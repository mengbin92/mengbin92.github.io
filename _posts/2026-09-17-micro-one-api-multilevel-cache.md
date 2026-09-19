---
title: "三级缓存：缓存鉴权不等于授权，以及两个失效函数的真实代价"
date: 2026-09-17T12:00:00+08:00
description: "第 1 篇里算过一笔账：relay-gateway 处理一个请求，要打四次下游 gRPC——identity 鉴权、channel 选路、billing 预扣、billing 结算，外加写日志。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个数字让我决定加缓存

第 1 篇里算过一笔账：relay-gateway 处理一个请求，要打四次下游 gRPC——identity 鉴权、channel 选路、billing 预扣、billing 结算，外加写日志。

按 1000 req/s 估算，光身份和选路这两个查询就是 2000 次 gRPC/s 起步。而这些数据有什么共同点？

**它们的变更频率是"每分钟几次"，而读取频率是"每秒上千次"。**

用户 token 一天不会变几次，渠道配置一天不会变几次，但每个请求都要查一遍。这是缓存最经典的适用场景。

这篇讲我怎么搭这个缓存的，其中有一个我一开始想错的地方——**我一度把"缓存命中"当成了"授权通过"**。

---

## 1. 为什么是三级，不是两级

三级指的是：

```
L1  进程内（ristretto）   → 零网络，纳秒级
L2  Redis                → 一次 RTT，毫秒级
源  identity / channel 服务 → 一次 gRPC，几毫秒到几十毫秒
```

"三级"里的第三级其实是**回源**，不是一个存储层。但在 `Get` 的实现里它是同一段逻辑的一部分：

```go
// Get retrieves from L1 → L2 → source, populating upstream caches.
func (c *MultiLevelCache[T]) Get(ctx context.Context, key string) (*T, error) {
```

分开说 L1 和 L2 的理由是它们的失败模式完全不同：

| | L1 | L2 |
|---|---|---|
| 位置 | 进程内存 | Redis |
| 每个副本 | 各一份 | 共享 |
| Redis 挂了 | 照常工作 | 不可用 |
| 容量 | 有界（按 cost 算） | 大 |
| 一致性 | 各副本独立 | 单一视图 |

**L1 是"Redis 挂了还能撑住"的那一层。** 这是我做两级的核心动机，不是"再快一点"。

L1 用的是 ristretto：

```go
l1, err := ristretto.NewCache(&ristretto.Config{
    NumCounters: int64(float64(cfg.L1CacheSize) * 10),
    MaxCost:     cfg.L1CacheSize,
    BufferItems: 64,
})
```

选它而不是 `map + mutex`，是因为它有准入策略和命中率统计。`NumCounters` 设成容量的 10 倍是 ristretto 文档推荐的经验值——它用 Count-Min Sketch 估算访问频率，计数器太少会让热点判断失真。

代价是 **ristretto 的写入是异步的**，`Set` 之后立刻 `Get` 不保证能拿到。所以 L1 的语义是"尽力而为的加速层"，不是"刚写就一定能读到"。这个特性后面第 5 节会引出一个具体的坑。

---

## 2. 完整的读路径

```go
func (c *MultiLevelCache[T]) Get(ctx context.Context, key string) (*T, error) {
    start := time.Now()
    cacheKey := c.prefix + key

    // L1 check
    if val, ok := c.l1.Get(cacheKey); ok {
        entry, ok := val.(*entry[T])
        if ok && !entry.expired() {
            c.metrics.recordL1Hit()
            metrics.CacheHits.WithLabelValues(c.metrics.cacheName, "l1").Inc()
            metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "l1").Observe(time.Since(start).Seconds())
            return entry.data, nil
        }
        // Entry expired or invalid type, remove it
        c.l1.Del(cacheKey)
    }

    // L2 check
    if c.l2 != nil {
        data, err := c.l2.Get(ctx, cacheKey).Bytes()
        if err == nil && len(data) > 0 {
            c.metrics.recordL2Hit()
            // ...
            var val T
            if err := c.unmarshal(data, &val); err == nil {
                c.populateL1(cacheKey, &val)
                return &val, nil
            }
        }
    }

    // Cache miss - use singleflight to prevent thundering herd
    c.metrics.recordMiss()
    result, err, _ := c.sf.Do(key, func() (any, error) {
        val, err := c.loader(ctx, key)
        if err != nil {
            return nil, err
        }
        _ = c.populate(ctx, cacheKey, val)
        return val, nil
    })
    // ...
}
```

四个细节：

**L1 里存的是 `*entry[T]`，L2 里存的是 JSON 字节。** L1 需要自己判断过期（因为 ristretto 的 TTL 和我的 TTL 是两套），所以包了一层带过期时间的 envelope；L2 直接用 Redis 的 TTL。

**L1 命中后发现过期要主动 `Del`。** 不然这个键会一直占着容量，每次命中都白走一遍过期判断。

**L2 反序列化失败会静默落到回源。** 不返回错误，因为"缓存里的数据坏了"不该让请求失败，回源重新拿一份就好。代价是坏数据会一直躺在 Redis 里直到 TTL 到期——如果能做到的话，这里应该顺手删掉它，我没做。

**回源用 singleflight 合并。** 这一段是关键的：

```go
result, err, _ := c.sf.Do(key, func() (any, error) {
```

一个热点 key 过期的那一瞬间，可能有几百个并发请求同时发现未命中。如果没有 singleflight，这几百个请求会一起去打 identity-service——**这就是缓存击穿，而且它专挑最热的那一刻发生。**

`sf.Do` 保证同一个 key 同时只有一个真正回源，其余等待并共享结果。

注意 `sf.Do` 的第三个返回值（是否共享）被丢弃了。我不需要区分"我是发起者"还是"我蹭了别人的结果"。

### 2.1 写缓存失败不能让请求失败

```go
// Populate L1 and L2; a cache-write failure must not fail the source load.
_ = c.populate(ctx, cacheKey, val)
```

两个 `_ =` 都是刻意的。**回源成功了，这个请求就该成功**；缓存写失败只影响下一个请求要不要再回源一次。

这个取舍在缓存系统里是标准做法，但很容易写错——写成 `if err := c.populate(...); err != nil { return nil, err }` 的话，Redis 一抖动，所有请求都会失败，哪怕数据已经拿到了。

---

## 3. 最重要的那条规则：缓存命中不是授权

这是我一开始想错的地方。

最初的实现很简单：缓存里有这个 token 的快照，就直接用它。写完之后我意识到一个问题：

**缓存里的"允许"是一个过去的判断。**

`GetAuthSnapshot` 返回的快照包含了 token 是否有效、用户是否被禁用、属于哪个分组、能访问哪些模型。这些都是**某个时刻的事实**。如果在这之后管理员禁用了这个 token，而缓存还没失效，我就会继续放行。

更严重的是渠道缓存。它缓存的是"这个 group+model 应该走哪个渠道"，我一开始直接从缓存里取渠道就开始转发。但**选路结果里隐含了授权**——能选中这个渠道，意味着这个用户对这个模型有访问权。

渠道配置变更、分组映射调整、账号被禁用，都可能让这个判断失效。

所以现在渠道缓存多了这一步：

```go
channels, err := c.cache.Get(ctx, group, model)
if err == nil && len(channels) > 0 {
    // A cached selection is not an authorization grant. Mapping/group
    // changes must take effect even if an invalidation event was missed.
    permission, checkErr := checkRoute(ctx, c.ChannelServiceClient, group, model, routing.Source{Kind: routing.Channel, ID: channels[0].GetId()})
    if checkErr != nil {
        return nil, checkErr
    }
    if permission.Allowed {
        ch := proto.Clone(channels[0]).(*commonv1.ChannelInfo)
        ch.UpstreamModelId = permission.UpstreamModelID
        return &channelv1.SelectChannelReply{Channel: ch}, nil
    }
}
```

注释那句就是我当时想通的那句话：**"A cached selection is not an authorization grant."**

注意它的几个行为：

**缓存命中之后还是要问一次授权。** 这次问的是一个更轻的接口（`checkRoute`），不是完整的选路，所以还是有节省。但它是一次网络调用——也就是说**我的渠道缓存省掉的是"选路计算"，不是"鉴权"**。

**`checkErr != nil` 时直接返回错误，不回退到"那就从缓存拿吧"。** 授权查不通就是不放行。和第 3 篇讲的重试授权一样，这里是 fail-closed。

**授权通过后把 `UpstreamModelID` 覆盖上去。** 因为这个字段是授权结果的一部分（模型可能被映射到不同的上游名字），不能沿用缓存里的旧值。

**缓存未命中或者渠道列表是空的，走完整回源。** 空列表也当未命中，因为"这个模型没有任何渠道"往往是一个需要重新确认的状态。

### 3.1 什么时候干脆不用缓存

```go
// SelectChannel consults the channel cache before calling the upstream
// channel service. Failover requests bypass the cache so retries do not replay
// a failed channel:
//   - ExcludeFirstPriority=true skips the whole top tier (legacy tier-skip);
//   - ExcludedChannelIds is non-empty (Phase C #2 request-level exclusion) and
//     the cached first candidate is very likely one of those just-failed IDs,
//     so serving from cache would silently defeat the exclusion set.
func (c *CachedChannelClient) SelectChannel(ctx context.Context, req *channelv1.SelectChannelRequest, opts ...grpc.CallOption) (*channelv1.SelectChannelReply, error) {
    if relaybiz.RoutingContextV2Enabled() || c.cache == nil || req.GetExcludeFirstPriority() || len(req.GetExcludedChannelIds()) > 0 {
        return c.ChannelServiceClient.SelectChannel(ctx, req, opts...)
    }
```

三个绕过条件里，后两个是我读了第 3 篇那段代码之后补的：

**`ExcludeFirstPriority=true`**：这是整层跳过的重试路径，缓存里的"首选渠道"正是刚失败的那个，从缓存返回等于原地打转。

**`ExcludedChannelIds` 非空**：请求级排除集。缓存里存的只有 `channels[0]` 一个候选，如果它恰好在排除集里，从缓存返回就会**静默地破坏排除语义**——重试会再次打到刚失败的渠道上。

这个问题我觉得挺典型的：**缓存的 key 里没有包含"排除集"这个维度**，所以对不同的排除集它给同一个答案。要么把排除集并进 key（组合爆炸），要么在有排除集时绕过缓存。我选了后者。

**`RoutingContextV2Enabled()`**：这是另一个更大的问题，下一节讲。

### 3.2 V2 路由下鉴权缓存被整体绕过

```go
func (c *CachedIdentityClient) GetAuthSnapshot(ctx context.Context, req *identityv1.GetAuthSnapshotRequest, opts ...grpc.CallOption) (*identityv1.GetAuthSnapshotReply, error) {
    if relaybiz.RoutingContextV2Enabled() || c.cache == nil {
        return c.IdentityServiceClient.GetAuthSnapshot(ctx, req, opts...)
    }
    return c.cache.Get(ctx, req.GetToken())
}
```

**只要 `RELAY_ROUTING_CONTEXT_V2=true`，鉴权缓存就完全不生效。**

我在读这段的时候愣了一下，因为这等于"我花了很大力气做的缓存，在一种路由模式下是死的"。

想清楚之后我认为这个判断是对的：V2 路由上下文带了版本号和摘要（第 2 篇里讲过那个三方哈希比对），它的正确性依赖于**每次都能拿到当前版本的上下文**。一个"token → 快照"的朴素缓存如果返回了旧版本的快照，会让摘要校验失败或者更糟——用旧版本的信息去做新版本的决策。

但这也意味着：**V2 路由模式下，relay 对 identity 的调用会退化成每请求一次。** 如果以后 V2 要成为默认，这个缓存必须重新设计成"版本感知"的，而不是简单地绕过。

这是我这套缓存里最大的一个已知缺口，我记在这里。

---

## 4. 失效：两个函数都在整片清

### 4.1 为什么做不到精确失效

理想情况下，"用户 X 改了密码"应该只失效 X 的 token 缓存。但我做不到，原因很具体：

```go
// InvalidateByUser invalidates tokens for a specific user.
//
// Because the token→snapshot keys are hashed from the raw token, there is no
// cheap reverse index from userID to its token keys. Rather than silently
// no-op (which would leave stale snapshots in the cache), we clear the L1
// cache entirely for this prefix and rely on the short L1 TTL (30s) plus the
// L2 Redis TTL to bound staleness.
func (c *AuthCache) InvalidateByUser(ctx context.Context, userID int64) error {
    c.cache.ClearAll()
    return nil
}
```

**缓存 key 是 token 的哈希，我没有 userID → token 的反向索引。** 一个用户可能有几十个 token，要精确失效就得先查"这个用户有哪些 token"，那又要一次数据库查询——为了省一次查询而做一次查询，没意义。

渠道缓存是一样的处境：

```go
// The channel cache is keyed by "group:model" and a single key may resolve to a
// list of candidate channels, so there is no reverse index from channelID
// to the keys that contain it. We therefore clear the L1 cache entirely
// (bounded by the short L1 TTL) and invalidate the whole channel prefix in L2
// via a SCAN. This is safe — channel config changes are infrequent — and
// avoids the silent no-op the previous TODO represented.
func (c *ChannelCache) InvalidateByChannel(ctx context.Context, channelID int64) error {
    c.cache.ClearAll()
    return c.cache.InvalidateByPattern(ctx, "*")
}
```

注释里 "avoids the silent no-op the previous TODO represented" 说的是我之前的版本：这个函数什么都不做，只是留了个 TODO。**一个静默 no-op 的失效函数比没有更危险**，因为调用方以为失效过了。

现在我选的是"整片清"，代价明确写在注释里。

### 4.2 `ClearAll` 和 `InvalidateByPattern` 清的不是同一层

这两个函数名字很像，但清的东西完全不同：

```go
// InvalidateByPattern invalidates all L2 keys whose Redis key matches the
// given glob pattern (prefixed with the cache's prefix).
//
// L1 (ristretto) does not expose pattern-based deletion, so matching L1
// entries are NOT removed here; callers that need a full L1 wipe should use
// ClearAll. This is acceptable because L1 entries have a short TTL and are
// bounded, so a stale L1 hit is time-limited.
```

```go
// ClearAll removes every entry from L1. L2 is left untouched (use
// InvalidateByPattern for targeted L2 eviction). This is the brute-force
// fallback when a reverse index (user→tokens, channel→groups) is not
// maintained.
func (c *MultiLevelCache[T]) ClearAll() {
    if c.l1 != nil {
        c.l1.Clear()
    }
}
```

**必须两个一起调，才是一次完整的失效。**

`InvalidateAll` 就是两个都调：

```go
func (c *AuthCache) InvalidateAll(ctx context.Context) error {
    c.cache.ClearAll()
    return c.cache.InvalidateByPattern(ctx, "*")
}
```

我第一次写 `InvalidateByUser` 的时候只调了 `ClearAll`，以为"清掉了"。实际上 L2 里那份还在，下一个请求会从 L2 读到旧数据再灌回 L1——**失效看起来生效了，实际上没有。**

这个坑给我留下一条规矩：**分层的失效函数必须让调用方清楚它清了哪几层。** 名字里如果体现不出来，注释必须写死。

### 4.3 失效是整片清，所以集群会有一次小击穿

结合第 15 篇讲过的广播机制：

```go
routingEvents.Subscribe(routingoutbox.Topic, routingoutbox.Invalidator(func(ctx context.Context, change routingoutbox.Change) error {
    if change.Owner == "identity" || change.Owner == "subscription" {
        return authCache.InvalidateAll(ctx)
    }
    if routingChannelCache != nil {
        return routingChannelCache.InvalidateByChannel(ctx, 0)
    }
    return nil
}))
```

一次用户改密码，会导致**所有副本的鉴权缓存清空、L2 整片清掉**，接下来一小段时间所有请求都要回源。

我知道这个代价，也接受它，两个理由：

- 这类变更频率极低（一个用户改密码不会每秒发生）；
- 精确失效需要维护反向索引，那个索引本身的一致性问题比这个击穿更难。

但如果流量规模上来了，这里会是一个需要重新设计的点：至少应该给 L2 的 `SCAN` 加个上限，避免键数量很大时扫太久。

---

## 5. 两个缓存的 TTL 差一个数量级

```go
// AuthCache
cfg := &Config{
    L1CacheSize: 10_000,
    L1TTL:       30 * time.Second, // Short TTL for auth data
    L2TTL:       5 * time.Minute,
    Prefix:      "auth",
}
```

```go
// ChannelCache
cfg := &Config{
    L1CacheSize: 5_000,
    L1TTL:       60 * time.Second, // Longer TTL for channel data
    L2TTL:       10 * time.Minute,
    Prefix:      "channel",
}
```

| | L1 | L1 容量 | L2 |
|---|---|---|---|
| 鉴权快照 | 30s | 10,000 | 5min |
| 渠道选择 | 60s | 5,000 | 10min |

差别的理由：

**鉴权的时效性要求更高。** 一个被禁用的 token 还能用 30 秒，和还能用 60 秒，业务上的严重程度不同。所以它 L1 只有 30 秒。

**鉴权的 key 更多。** 每个活跃 token 一条，所以容量给了 10,000。渠道缓存的 key 是 `group:model` 组合，通常只有几百到几千个，5,000 够用。

**渠道配置变更频率更低。** 改一个渠道配置是管理操作，一天可能几次；token 的创建/禁用可能是用户在自助操作，频率高得多。

**陈旧窗口的实际含义**（假设失效广播漏了）：

- 鉴权：最长 5 分钟（`max(L1TTL, L2TTL)`）。一个被禁用的 token 最多还能用 5 分钟。
- 渠道：最长 10 分钟。

这就是我当初决定接失效广播的直接原因——5 分钟对一个被撤销的凭证来说太长了。

现在失效广播接上了（在 `RELAY_ROUTING_CONTEXT_V2` 打开时），但**如果这个开关是关的，那失效广播也不生效**，陈旧窗口就真的回到 5/10 分钟。

我在 `NewMultiLevelCache` 上面写过一段注释说"事件失效从未接线"，现在已经不准了——wire.go 里接了。这类**描述"现状"的注释会过期**，我在第 15 篇里把这条当成教训写过，这里就不重复了。

---

## 6. 我埋的一个坑：`InvalidateByChannel(ctx, 0)`

失效广播里这行：

```go
if routingChannelCache != nil {
    return routingChannelCache.InvalidateByChannel(ctx, 0)
}
```

注意参数是 `0`，而这个函数的签名是 `InvalidateByChannel(ctx context.Context, channelID int64)`。

`channelID` 这个参数**在函数体里根本没被使用**——因为它实现的是"整片清"，跟具体是哪个渠道无关：

```go
func (c *ChannelCache) InvalidateByChannel(ctx context.Context, channelID int64) error {
    // Clear L1 entirely.
    c.cache.ClearAll()
    // Invalidate the entire channel L2 namespace.
    return c.cache.InvalidateByPattern(ctx, "*")
}
```

所以调用方传 0 碰巧是对的，传真实的 channelID 也得到同样的结果。

我数了一下这几个精确失效函数的实际调用点，结果不太好看：

| 函数 | 签名表达的意思 | 调用点 |
|---|---|---|
| `AuthCache.Invalidate(ctx, token)` | 失效一个 token | **0 处** |
| `AuthCache.InvalidateByUser(ctx, userID)` | 失效一个用户的 token | **0 处** |
| `ChannelCache.Invalidate(ctx, group, model)` | 失效一个 group+model | **0 处** |
| `ChannelCache.InvalidateByGroup(ctx, group)` | 失效一个分组 | **0 处** |
| `ChannelCache.InvalidateByChannel(ctx, channelID)` | 按渠道失效 | 1 处（失效广播，传 0） |

真正被用到的只有 `InvalidateAll`（整片清 L1+L2）和那个传 0 的 `InvalidateByChannel`。

也就是说**我设计了四种精确失效的接口，一种都没用上，而实际生效的是两处"整片清"**。这些函数不是"能工作但难看"，而是**没人调用的死代码**——它们唯一的作用是让读代码的人以为系统有精确失效能力。

这是我的一个真实教训：**在还没有反向索引的时候就先把"看起来更精细"的接口设计出来，是很自然的冲动，但它会制造一个错误的心智模型。** 正确做法是当时只暴露 `InvalidateAll`，等真的做出反向索引再加精确方法。

我打算把它们删掉，只保留 `InvalidateAll` + 明确命名的整片清版本。删代码比留着"以后可能有用"更安全。

---

## 7. 可观测性：命中率要分层看

缓存最容易出的问题是"以为它在工作，其实没有"。所以每一层都有独立的指标：

```go
metrics.CacheHits.WithLabelValues(c.metrics.cacheName, "l1").Inc()
metrics.CacheHits.WithLabelValues(c.metrics.cacheName, "l2").Inc()
metrics.CacheMisses.WithLabelValues(c.metrics.cacheName).Inc()
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "l1").Observe(time.Since(start).Seconds())
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "l2").Observe(time.Since(start).Seconds())
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "source").Observe(time.Since(start).Seconds())
```

而且进程内还单独算了一份命中率：

```go
// HitRate returns the overall cache hit rate.
func (m *cacheMetrics) HitRate() float64 {
    l1, l2, miss := m.l1Hits.Load(), m.l2Hits.Load(), m.misses.Load()
    total := l1 + l2 + miss
    if total == 0 {
        return 0
    }
    return float64(l1+l2) / float64(total)
}

// L1HitRate returns the L1 cache hit rate.
func (m *cacheMetrics) L1HitRate() float64 {
    // ...
    return float64(l1) / float64(total)
}
```

**"总命中率 95%"和"L1 命中率 95%"是完全不同的两件事。**

- 如果 L1 命中率高：绝大多数请求零网络。
- 如果 L1 命中率低但总命中率高：每个请求都要打一次 Redis。这时候加 L1 容量或者调 TTL 才有用。
- 如果总命中率低：key 设计或者 TTL 有问题。

只看一个总数，这三种情况的处理方向完全不同。

`CacheLatency` 也按 `l1` / `l2` / `source` 分开观察。回源的延迟明显比 L1 高一个数量级，混在一起看会让 P95 失去意义。

---

## 8. 现在的状态和欠账

**已经能用的：**

- L1（ristretto）+ L2（Redis）+ 回源的三级读取，L1 与 L2 各自独立降级
- 回源走 singleflight，防止热点 key 过期时的缓存击穿
- 缓存写入失败不影响请求成功
- **缓存命中不等于授权**：渠道缓存命中后仍要复验 `checkRoute`，失败 fail-closed
- 重试路径（整层跳过 / 请求级排除集）绕过缓存，不破坏排除语义
- 失效走事件广播，每副本独立 consumer group 保证 fan-out
- L1/L2 命中率与延迟分层可观测

**还没解决的：**

**第一，V2 路由模式下鉴权缓存整体失效。** 这是我最大的一个缺口，前面说过。要做成版本感知的缓存才敢在 V2 下用。

**第二，失效只能整片清。** 没有反向索引（user→tokens、channel→keys），所以每次失效都是一次小击穿。键规模上来之后 `SCAN` 的开销也会成为问题。

**第三，`InvalidateByChannel` 的签名有误导性。** 参数没用，调用方传 0。属于"能工作但会误导下一个读代码的人"。

**第四，L2 反序列化失败后不清理坏数据。** 坏值会一直躺到 TTL 到期，期间每个请求都要"读出来、解析失败、回源"。

**第五，缓存层没有"预热"。** 进程刚启动、或者一次整片失效之后，冷启动期间所有请求都走回源。对一个副本数量会变化的部署来说，这是可观的尖峰。

**第六，四种精确失效的接口是没人调用的死代码。** 见第 6 节那张表。它们不只是没用，还会让读代码的人以为系统具备精确失效能力。我打算删到只剩 `InvalidateAll` 加一个明确命名的整片清方法。

---

## 9. 下一篇

网关可靠性那条线（第 3、4、15 篇）和这一篇到这里就结束了「请求链路」这个大主题。下一篇我想换一个方向，讲订阅的账务语义：续费、退款、冲正这三种操作在一个 append-only 的账本上分别该怎么记，以及"已售出的套餐配置被改了"这件事我是怎么处理的。

[《订阅账务：续费、退款、冲正，以及“已售出的套餐被改了”怎么办》](/2026-09-17-micro-one-api-accounting-semantics/)
