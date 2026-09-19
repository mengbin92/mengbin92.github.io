---
title: "不用消息队列也能做事件驱动：路由失效的 Outbox 实践"
date: 2026-09-17T12:00:00+08:00
description: "第 12 篇讲了三层缓存，但留了一个尾巴没讲：缓存什么时候该失效。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 问题：缓存怎么知道该失效了

第 12 篇讲了三层缓存，但留了一个尾巴没讲：**缓存什么时候该失效。**

最省事的方案是纯 TTL。我一开始就是这么做的，注释里还留着当时的推算：`max(L1TTL, L2TTL)`，对鉴权是 5 分钟，对渠道是 10 分钟。

也就是说：**一个被禁用的 token，最多还能用 5 分钟。**

对大多数系统这也许可以接受，但我不太能接受。因为这不是"数据有点旧"，这是"我已经撤销了权限，而系统还在放行"。

所以要主动失效。而主动失效需要跨进程通知——relay-gateway 有多个副本，每个副本都有一份 L1；identity-service 改了用户的访问权，得让所有副本都知道。

我面临的选择是：

1. 引一个消息队列（Kafka / NATS / RabbitMQ）；
2. 用 Redis 的 pub/sub；
3. 用 Redis Streams；
4. 自己写一张表 + 轮询。

我选了最后一个，加上第 3 个。这篇讲为什么，以及这条路踩到的坑。

---

## 1. 为什么不上消息队列

先说清楚：**这不是"消息队列不好"，而是我这里的场景还不需要它。**

我的需求非常窄：

- 事件量极小。路由配置变更、用户权限变更，一天可能几百次。
- 只有一个消费语义：**让缓存失效**。
- 消费者和生产者都在同一套服务里，共享同一个数据库。
- 不需要重放、不需要分片、不需要事件溯源。

而引入消息队列要付的代价是：多一个中间件要部署和监控、多一套凭证和网络配置、多一个故障点，以及最实际的——**我要在文档里多写一章"怎么部署 Kafka"**。

对一个还没上线的项目，这是过度设计。

但我也不能什么都不用。纯 pub/sub 的问题是**不持久**：Redis 重启期间的失效消息直接丢了，没有补偿。

所以我用了一张表来补这个洞。

---

## 2. Outbox：把"要通知"和"改数据"写进同一个事务

### 2.1 事件长什么样

```go
// Package routingoutbox persists routing invalidations in the owning service's
// transaction. Events contain identifiers and revisions only, never credentials.
package routingoutbox

type Change struct {
    Owner       string `json:"owner"`
    Kind        string `json:"kind"`
    AggregateID int64  `json:"aggregate_id"`
    Revision    int64  `json:"revision"`
}
```

**包注释里那句话是我给这个包定的最重要的一条规矩：只带标识和版本号，绝不带凭证。**

事件里没有 access token、没有渠道的 key、没有用户邮箱。理由很直接：事件会落到表里、会进 Redis Stream、会被日志打出来。一旦带了敏感数据，这些地方全都变成泄露面。

消费者拿到 `Owner + Kind + AggregateID` 之后自己去重新查——**事件是"失效信号"，不是"数据载体"。**

第二种写法（把新数据一起发过去，消费者直接写入缓存）看起来更高效，但它有一个我很不喜欢的性质：**事件里的数据一旦过期，你会把一个陈旧的快照灌进缓存，而且看起来像是"刚更新的"。** 失效信号没这个问题——失效永远安全，最多多查一次。

### 2.2 写入必须在同一个事务里

```go
// Enqueue must receive the same transaction that writes the authoritative row.
func Enqueue(tx *gorm.DB, owner, kind string, id, revision int64) error {
    return tx.Create(&record{
        ID:          fmt.Sprintf("%s:%s:%d:%d", owner, kind, id, revision),
        Owner:       owner,
        Kind:        kind,
        AggregateID: id,
        Revision:    revision,
        CreatedAt:   time.Now().Unix(),
    }).Error
}
```

函数签名里第一个参数就是 `*gorm.DB`，而且变量名就叫 `tx`。这不是巧合——**参数名叫 tx 是为了让调用方一眼看到"这里要传事务"。**

实际调用点确实都传的是事务：

```go
err := tx.WithContext(ctx).Transaction(func(db *gorm.DB) error {
    // ...写权威数据
    return routingoutbox.Enqueue(db, "subscription", "subscription", model.ID, 1)
})
```

```go
revision = current.EntitlementRevision + 1
if err := tx.Model(&subscriptionModel{}).Where("id = ?", s.ID).Update("entitlement_revision", revision).Error; err != nil {
    return err
}
if err := syncContractCoverage(tx, "subscription_routing_entitlements", "subscription_id", s.ID, s.Contract); err != nil {
    return err
}
return routingoutbox.Enqueue(tx, "subscription", "subscription", s.ID, revision)
```

**数据改了但事件没写** → 缓存不失效，权限变更不生效。
**事件写了但数据没改** → 缓存被无谓清掉，下一次又灌回旧数据。

两个方向都是 bug，而把它们放进一个事务就同时消除了。这是 Outbox 模式的全部价值，没有别的。

主键设计成 `owner:kind:id:revision` 的字符串，顺带带来两个好处：**同一个聚合的同一个版本不可能重复入队**（重复插入会被主键拒绝，事务回滚），而且这个 ID 在日志里可读。

### 2.3 表结构

```sql
CREATE TABLE IF NOT EXISTS routing_change_outbox (
  id VARCHAR(96) PRIMARY KEY,
  owner VARCHAR(16) NOT NULL,
  kind VARCHAR(16) NOT NULL,
  aggregate_id BIGINT NOT NULL,
  revision BIGINT NOT NULL,
  created_at BIGINT NOT NULL,
  delivered_at BIGINT NOT NULL DEFAULT 0
);
CREATE INDEX idx_routing_outbox_pending ON routing_change_outbox(owner, delivered_at, created_at);
```

索引是 `(owner, delivered_at, created_at)`，和投递查询的条件顺序完全一致：

```go
db.WithContext(ctx).Where("owner = ? AND delivered_at = 0", owner).Order("created_at, id").Limit(100).Find(&rows)
```

没投递的行 `delivered_at = 0`（不是 NULL），这样索引能用等值条件。**用 0 而不是 NULL，是为了避免 `WHERE delivered_at IS NULL` 那种在有些数据库上不走索引的写法。**

---

## 3. 投递：轮询 + 先发后确认

```go
// Dispatch acknowledges only successful durable publishes. A crash after publish
// may cause duplicates; consumers invalidate rather than installing event state.
func Dispatch(ctx context.Context, db *gorm.DB, owner string, publish func(context.Context, string, any) error) error {
    var rows []record
    if err := db.WithContext(ctx).Where("owner = ? AND delivered_at = 0", owner).Order("created_at, id").Limit(100).Find(&rows).Error; err != nil {
        return err
    }
    for _, row := range rows {
        if err := publish(ctx, Topic, Change{Owner: row.Owner, Kind: row.Kind, AggregateID: row.AggregateID, Revision: row.Revision}); err != nil {
            return err
        }
        if err := db.WithContext(ctx).Model(&record{}).Where("id = ? AND delivered_at = 0", row.ID).Update("delivered_at", time.Now().Unix()).Error; err != nil {
            return err
        }
    }
    return nil
}
```

顺序是**先 publish，成功了再标记 delivered**。

这个顺序意味着：进程在 publish 之后、标记之前崩溃，这条事件会被重发一次。

注释里把这件事说清楚了：

```go
// A crash after publish may cause duplicates; consumers invalidate rather than
// installing event state.
```

**"至少一次"配上"消费是幂等的失效"就变成安全的。** 如果消费是"把事件里的数据写进缓存"，重复消费虽然也无害（一样的值写两次），但如果事件顺序乱了，旧值可能覆盖新值。这就是我坚持事件只做失效的第二个理由。

驱动它的循环：

```go
ticker := time.NewTicker(time.Second)
defer ticker.Stop()
var gcCount int
for {
    runCtx, runCancel := context.WithTimeout(ctx, 5*time.Second)
    err := Dispatch(runCtx, db, owner, bus.Publish)
    // Delivered rows are dead weight once consumers have acked; sweep
    // them so the pending scan stays cheap on high-churn deployments.
    gcCount++
    if gcCount >= 300 {
        gcCount = 0
        cutoff := time.Now().Add(-24 * time.Hour).Unix()
        if gcErr := db.WithContext(runCtx).Where("delivered_at > 0 AND delivered_at < ?", cutoff).Delete(&record{}).Error; gcErr != nil && err == nil {
            err = gcErr
        }
    }
    runCancel()
    if err != nil && ctx.Err() == nil && report != nil {
        report(err)
    }
    select {
    case <-ctx.Done():
        return
    case <-ticker.C:
    }
}
```

几个细节：

**一秒一次轮询，每批 100 条。** 对每天几百次变更的量级，这个频率绰绰有余；对突发场景，一秒 100 条的上限也够。轮询而不是 LISTEN/NOTIFY，是因为后者要额外维护连接，而且 MySQL 的实现不如 PostgreSQL 好用。

**每次 Dispatch 包一个 5 秒的超时。** 卡住的查询不该让整个循环停了。

**清理是每 300 次轮询做一次（约 5 分钟），删 24 小时前的已投递行。** 用计数器而不是单独的 ticker，是为了少一个 goroutine。不删的话，`delivered_at = 0` 的扫描虽然走索引，但表会一直涨。

**清理失败不会覆盖掉投递失败。** 看那段 `if gcErr != nil && err == nil`——只有投递成功的情况下才报清理的错误。这个细节的意思是"投递问题优先"。

### 3.1 一个刻意的选择：即使内存总线可用也用 Redis Streams

```go
// Start deliberately uses Redis Streams even when the optional general event bus
// uses memory. Without Redis the durable rows remain pending for a later restart.
func Start(db *gorm.DB, redisClient *redis.Client, owner string, report func(error)) func() {
    if db == nil || redisClient == nil {
        return func() {}
    }
    bus := events.NewStreamEventBus(redisClient, owner+"-routing-outbox")
    // ...
}
```

项目的通用事件总线有一个开关，可以用内存实现（`NewConfiguredEventBus` 在 `EVENT_BUS_BACKEND` 不是 `redis-streams` 时返回 `MemoryEventBus`）。但**路由失效这条线不用那个开关，它硬依赖 Redis Streams。**

因为内存总线的"跨进程通知"根本不存在——它只在同一个进程里传递。用内存总线做失效广播，等于多副本部署时只有收到变更的那个副本会失效，其余的照旧。

`if db == nil || redisClient == nil { return func() {} }`：没有 Redis 的时候，投递器**不启动**，但已经入队的行还留在表里。等 Redis 恢复了重启进程，它们会被一起投出去。**这是"延迟送达"而不是"丢失"**，也是我选 Outbox 而不是纯 pub/sub 的关键收益。

---

## 4. 消费端：为什么每个副本要一个 consumer group

```go
const DefaultConsumerGroup = "micro-one-api"
```

```go
// deriveConsumerGroup returns the per-service consumer group name. The consumerID
// is already service-specific (passed by NewConfiguredEventBus from each service),
// so embedding it in the group name gives each service its own copy of every
// event (platform-M1). We keep the "micro-one-api:" namespace prefix for
// discoverability in XINFO GROUPS output.
func deriveConsumerGroup(consumerID string) string {
    if consumerID == "" {
        consumerID = "default"
    }
    return DefaultConsumerGroup + ":" + consumerID
}
```

这段注释里的 "platform-M1" 是一次 review 的编号，说明这里改过。

Redis Streams 的 consumer group 语义是**竞争消费**：同一个 group 里的多个 consumer，每条消息只会被其中一个拿到。

我最初给所有服务用了同一个 group，结果就是：identity 发了一个事件，只有其中一个订阅者收到。**跨服务的事件被静默丢弃了。**

现在每个服务（其实每个副本）一个 group，语义变成广播：

```go
routingEvents = events.NewStreamEventBus(redisClient, fmt.Sprintf("relay-routing-%s-%d", host, os.Getpid()))
```

`relay-routing-<hostname>-<pid>`——注意是**每进程**一个，不是每服务一个。第 15 篇里我提过这一点，这里的理由是同样的：失效必须广播到每个 L1 缓存，不能负载均衡。

**用 Streams 的时候就顺手写一个共享 group，是这类问题的常见来源。** 你要先想清楚这条消息的语义是"谁处理都行"还是"每个都要处理"。

---

## 5. 版本号：处理乱序和重复

失效消息可能乱序到达（两个不同的事件被不同副本投递），也可能重复（投递崩溃重发）。

消费端的处理：

```go
// Invalidator serializes revision checks with eviction. Failed evictions remain
// retryable; delayed/duplicate events cannot replace a newer cached snapshot.
// The versions map is a bounded guard only: dropping an entry at worst causes a
// redundant cache reload, never stale state, so it is randomly pruned at cap.
func Invalidator(evict func(context.Context, Change) error) events.Handler {
    var mu sync.Mutex
    versions := map[string]int64{}
    return func(ctx context.Context, event events.Event) error {
        // ...反序列化并校验
        key := fmt.Sprintf("%s:%s:%d", change.Owner, change.Kind, change.AggregateID)
        mu.Lock()
        defer mu.Unlock()
        if versions[key] >= change.Revision {
            return nil
        }
        if err := evict(ctx, change); err != nil {
            return err
        }
        versions[key] = change.Revision
        // ...容量裁剪
        return nil
    }
}
```

核心是那三行：

```go
if versions[key] >= change.Revision {
    return nil          // 已经处理过更新的版本，跳过
}
if err := evict(ctx, change); err != nil {
    return err          // 失效失败 → 不记版本，允许重试
}
versions[key] = change.Revision
```

**顺序很重要：先失效，成功了才记版本。** 如果反过来（先记版本再失效），失效失败时版本已经推进了，重试会被"版本不够新"挡掉——**一次失败的失效会被永久静默。**

这个模式我认为是消费端幂等处理的一个通用要点：**"已处理"的标记必须写在副作用成功之后。**

### 5.1 版本表的裁剪策略是有理由的

```go
if len(versions) > invalidatorVersionCap {
    for k := range versions {
        delete(versions, k)
        if len(versions) <= invalidatorVersionCap/2 {
            break
        }
    }
}
```

```go
const invalidatorVersionCap = 65536
```

超了就从 map 里随机删（Go 的 map 遍历顺序是随机的），删到剩一半。

**为什么可以随机删？** 因为注释里写了：

```go
// The versions map is a bounded guard only: dropping an entry at worst causes a
// redundant cache reload, never stale state, so it is randomly pruned at cap.
```

丢掉一个版本记录，最坏情况是这个聚合的下一条事件会被"重新处理"一次——也就是多失效一次、多回源一次。**代价是多一次查询，收益是不会因为内存无限增长把进程搞死。**

如果丢记录会带来正确性问题（比如用来去重计费），那这个策略就不能用。**判断标准是"丢掉它会不会导致状态不一致"，而不是"丢掉它有没有代价"。**

### 5.2 校验不是走过场

```go
if change.AggregateID <= 0 || change.Revision <= 0 || (change.Owner != "identity" && change.Owner != "channel" && change.Owner != "subscription") {
    return fmt.Errorf("invalid routing event")
}
```

三个域的白名单、聚合 ID 和版本号必须为正。

因为 `evict` 的实现是按 owner 分支的（第 15 篇那段）：

```go
if change.Owner == "identity" || change.Owner == "subscription" {
    return authCache.InvalidateAll(ctx)
}
if routingChannelCache != nil {
    return routingChannelCache.InvalidateByChannel(ctx, 0)
}
```

一个未知的 owner 会**走到最后那个 channel 分支**——清掉全部渠道缓存。一个畸形或者恶意构造的事件就能引发全量缓存击穿。所以白名单校验在这里不只是防御性编程，它挡住了一个具体的放大攻击。

---

## 6. 这条链路保证什么、不保证什么

写到这里我觉得有必要把边界说清楚。

**保证：**

- **不丢。** 数据变更和事件在同一个事务里，数据库提交了就一定会有这条待投递记录。
- **顺序（同一聚合内）。** 同一聚合的 revision 单调递增，消费端按 revision 去重，旧事件不会覆盖新状态。
- **可重放。** 没有 Redis 的时候记录留在表里，Redis 恢复后继续投。清理只删 24 小时前的**已投递**行。

**不保证：**

- **及时性。** 最坏情况有 1 秒的轮询延迟；Redis 挂掉期间则完全没有失效，直到恢复。
- **恰好一次。** 崩溃可能重发。靠消费端幂等兜住。
- **跨聚合的顺序。** 两个不同聚合的变更顺序没有任何保证，也不需要。

### 6.1 最大的缺口：Redis 挂掉时失效完全停止

我想单独把这条拎出来，因为它是这个设计里最实际的风险。

`Start` 在 Redis 不可用时不启动投递器（正确），已入队的行留在表里（也是对的）。但**后果是：这段时间内所有副本的 L1 缓存都不会失效**。

回到第 12 篇那句：没有失效广播时，陈旧窗口是 `max(L1TTL, L2TTL)`——鉴权 5 分钟，渠道 10 分钟。

所以：

```
Redis 故障期间：权限变更最长 5 分钟不生效
```

而"Redis 挂了"和"你想马上撤销一个 token"这两件事，恰好有可能同时发生（比如你在应急处理）。这个组合我目前没有好的对策——要么用一个独立的通道（那就等于上消息队列），要么在接受 TTL 窗口的前提下把它写进运维文档。

我选了后者，并且把 5 分钟这个数字明确写在缓存层的注释里，而不是让它隐含在代码里。

**我认为重要的不是"消灭所有风险"，而是"每个风险都有一个明确的、被写下来的数字"。**

### 6.2 没有监控投递积压

这是第二个缺口，而且我觉得它比第一个更容易修，只是我还没修。

现在 `Start` 接受一个 `report func(error)` 回调，出错时会调用。但**我没有任何指标暴露"有多少行还没投递"**。

如果投递一直失败（比如表被锁、Redis 权限问题），表现是：行一直堆、缓存一直不失效、**但没有任何告警**。这和第 15 篇那个"没有日志就没有信号"是同一类问题。

至少该有一个 gauge：待投递行数。到阈值告警。这是我下一步要补的。

---

## 7. 这套东西的适用边界

最后说一下我认为什么情况下该抄这个做法、什么情况下不该。

**适用：**

- 事件量不大（每秒几十以内）。
- 生产者和消费者共享数据库。
- 消费语义是"失效/通知"，不是"数据同步"。
- 你不想为了这个功能引入一个中间件。

**不适用：**

- 事件量大。轮询表和 Redis Stream 都撑不住高吞吐，这时该上 Kafka。
- 消费者在另一个数据库边界之外。Outbox 的原子性依赖"同一个事务"，跨库就不成立了。
- 需要历史重放/事件溯源。Outbox 表会被清理，它不是账本。
- 需要严格顺序。这里只保证同聚合单调，不保证全局。

还有一个我从这次实践里得到的、比技术更泛的结论：

**"先想清楚消费端能不能幂等，再决定要不要引入投递保证。"**

如果消费端天生幂等（比如"清掉这个 key"），那"至少一次"就够了，一套很轻的机制就能做到。如果消费端不幂等（比如"给用户加 1 块钱"），那不管用什么传输层，你都得在消费端加去重——**传输层的保证解决不了业务层的不幂等。**

我一开始以为 Outbox 是个"可靠投递"问题，做下来才发现它其实是个"让消费端变幂等"的问题。

---

## 8. 现在的状态

**已经能用的：**

- 变更与事件同事务写入，主键天然去重
- 一秒轮询、每批 100 条、5 秒单次超时
- 先发布后确认，崩溃可重发，靠消费端幂等兜住
- 每进程独立 consumer group，失效真广播
- 按 revision 去重，失效成功才记版本
- 版本表有界，随机裁剪且不损害正确性
- 24 小时已投递行清理，清理失败不遮蔽投递失败
- 事件只带标识与版本号，不带任何凭证

**欠账：**

- 投递积压没有指标和告警（第 6.2 节）
- Redis 故障期间失效完全停止，陈旧窗口 5/10 分钟，只有文档没有机制
- 轮询是固定 1 秒，没有按积压量自适应
- 没有"死信"处理：一条毒事件（比如反序列化一直失败）会卡住整个批次

最后那条我想展开一句：现在 `Dispatch` 里 publish 失败就 `return err`，**当前批次剩下的行都不会被处理**。如果某条事件因为数据问题永远发不出去（不过校验那一关是在消费端，所以生产端不太可能出现），它会一直排在队首。这个风险不大，但严格说需要一个"跳过 N 次后移到队尾或标记死信"的机制。

---

## 9. 下一篇

下一篇讲订阅账号的治理：账号的恢复探测怎么做、多副本同时执行治理任务怎么保证幂等、以及为什么"单用户单 active 订阅"这个约束在并发下需要额外处理。

[《订阅账号治理：多副本同时跑定时任务，怎么保证不出错》](/2026-09-16-micro-one-api-account-governance/)
