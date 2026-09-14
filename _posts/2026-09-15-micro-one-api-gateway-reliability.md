---
title: "熔断、超时和降级：跨服务调用的那些保护，以及我接错了的地方"
date: 2026-09-15T12:00:00+08:00
description: "从一次“用户传错模型名把整个网关打挂”的 incident 讲起，拆解 micro-one-api 跨服务调用的保护：按 gRPC code 分档的熔断失败判定、为什么 Unknown 必须归到“不算上游故障”、降级 fallback 绝不伪造成功的硬约束、不同下游 fail-close 与 best-effort 的分工、超时上限夹取，以及缓存失效的 fan-out 语义。"
tags: ["Micro-One-API", "Go", "Kratos", "架构", "可靠性"]
categories: ["architecture"]
draft: false
mermaid: true
---

## 摘要

有一批请求要的模型在所有渠道上都没配置，channel-service 全部返回"没有可用渠道"。这个错误跨 gRPC 回来是 codes.Unknown，而我的熔断器把它算作失败——于是用户传错一个模型名，整个网关的流量都被熔断器拒了。这篇讲这次之后我怎么重排错误分类，以及跨服务降级的其他几处取舍。

---

## 0. 从一次"所有请求都被拒绝"说起

有个 incident 记录被我写在了代码注释里，日期是 2026-08-16：

```go
// Application-level errors from our own services historically cross
// gRPC as codes.Unknown (e.g. "no available channel" routing
// dead-ends). They are not upstream-health signals: counting them let
// a storm of unroutable-model requests trip the breaker and reject
// ALL traffic to the service (2026-08-16 incident).
```

那次的现象是：一批请求要的模型在所有渠道上都没有配置，channel-service 全部返回"没有可用渠道"。这个错误经过 gRPC 传回来是 `codes.Unknown`。

而我当时的熔断器把 `Unknown` 算作失败。于是：

1. 一批"模型没配"的请求打进 channel-service；
2. 每个都返回 Unknown；
3. 熔断器数到阈值，跳闸；
4. 接下来**所有**请求——包括那些模型配置完全正常的——都被熔断器直接拒绝。

**用户传错模型名，把整个网关打挂了。**

这就是这篇要讲的事：跨服务调用的保护措施，如果错误分类错了，保护本身会变成故障源。

---

## 1. 熔断器的配置和它踩过的三个坑

### 1.1 基本参数

```go
func DefaultBreakerConfig(name string) *BreakerConfig {
    return &BreakerConfig{
        Name:             name,
        MaxRequests:      3,                 // 半开状态下放几个探测请求
        Interval:         60 * time.Second,  // 关闭状态下的统计周期
        Timeout:          30 * time.Second,  // 打开后多久转半开
        ReadyToTrip:      DefaultReadyToTrip,
        FallbackStrategy: FallbackCache,
    }
}

// DefaultReadyToTrip trips the breaker after 5 consecutive failures.
func DefaultReadyToTrip(counts gobreaker.Counts) bool {
    failureRatio := float64(counts.TotalFailures) / float64(counts.Requests)
    return counts.Requests >= 5 && failureRatio >= 0.6
}
```

60 秒窗口内至少 5 个请求、失败率 ≥60% 就跳闸；打开 30 秒后进半开，放 3 个探测请求。

这套参数目前是硬编码的，四个下游服务共用同一份。这一点我在最后一节会算作欠账。

### 1.2 坑一：客户端错误不该算上游故障

第一个错误是：一个无效的 token、一个不存在的资源，返回 `InvalidArgument` 或 `NotFound`，我把它们都算成熔断失败。

结果和开头那个 incident 是同一类：**一批坏 API Key 打进来，identity 的熔断器跳闸，然后所有流量都被拒。**

修法是给 gobreaker 加一个判断：

```go
// platform-H1: a non-retryable error (invalid token, not found, bad
// request) is a client problem, not an upstream-health signal. Counting
// it as a breaker failure lets a wave of bad API keys trip the identity
// breaker and reject ALL traffic. gobreaker's IsSuccessful gates its own
// afterRequest(onFailure) — returning true for non-retryable errors means
// only retryable failures (network, deadline, unavailable) move the
// breaker toward open.
IsSuccessful: func(err error) bool {
    return err == nil || !isRetryableError(err)
},
```

### 1.3 分档表：哪些 gRPC code 算"上游不健康"

```go
func isRetryableError(err error) bool {
    if err == nil {
        return false
    }
    st, ok := status.FromError(err)
    if !ok {
        // Non-gRPC errors are considered retryable
        return true
    }
    switch st.Code() {
    case codes.OK, codes.Canceled, codes.InvalidArgument, codes.NotFound,
         codes.AlreadyExists, codes.PermissionDenied, codes.Unauthenticated,
         codes.ResourceExhausted, codes.FailedPrecondition, codes.OutOfRange,
         codes.Unimplemented, codes.DataLoss, codes.Unknown:
        return false
    case codes.DeadlineExceeded, codes.Aborted, codes.Unavailable:
        return true
    default:
        return true
    }
}
```

真正能跳闸的只有三个 code：`DeadlineExceeded`、`Aborted`、`Unavailable`——也就是**传输层的失败**。

`ResourceExhausted` 被放在"不算"这一侧，注释里写的理由是 "Rate limiting is retryable"。这里我其实偷懒了，注释和代码有点对不上：按分类逻辑它不该跳闸，但注释写的是"可重试"。这两件事在这个函数里被混在一起了——函数名问的是"这个错误该不该算熔断失败"，但 `ResourceExhausted` 那行的注释回答的是另一个问题。这是个我还没来得及清理的表述问题。

### 1.4 坑二：`Unknown` 为什么这么难处理

`Unknown` 是最麻烦的一个。

一方面，它确实可能是真的故障。另一方面，**它更多是我自己的业务错误跨 gRPC 之后的表现**。Kratos 的 `errors.New` 加 reason 那套，在没做 code 映射的时候就会落到 `Unknown`。

我一开始把它归到"可重试"（也就是会跳闸）那一侧，就是开头那个 incident 的来源。现在归到"不算"这一侧，但注释里留了很重的警告：

```go
case codes.Unknown:
    // Application-level errors from our own services historically cross
    // gRPC as codes.Unknown (e.g. "no available channel" routing
    // dead-ends). They are not upstream-health signals: counting them let
    // a storm of unroutable-model requests trip the breaker and reject
    // ALL traffic to the service (2026-08-16 incident). Genuine transport
    // failures arrive as Unavailable/DeadlineExceeded, which stay
    // retryable below.
    //
    // NOTE: this is a GLOBAL semantic change, not channel-service-only.
    // Every service whose errors cross gRPC as Unknown (identity, billing,
    // config, ...) is now treated as "not an upstream-health signal" and
    // never trips the breaker. That matches platform-H1's intent (client-
    // side problems must not trip breakers); real transport failures still
    // surface as Unavailable/DeadlineExceeded and remain protected. Do not
    // flip this back to retryable without auditing every Unknown producer.
    return false
```

最后那句 "Do not flip this back to retryable without auditing every Unknown producer"（不要在没审计所有 Unknown 生产者之前把它翻回去）是我写给未来的自己的。

代价我也清楚：**现在如果某个服务真的崩了、但错误恰好以 `Unknown` 形式返回，熔断器不会跳闸。** 我选择接受这个代价，因为一侧是"用户错误打挂整个网关"，另一侧是"真实故障时熔断晚一点生效"——传输层真正的失败还是会以 `Unavailable` 出现，那一个仍然会被接住。

### 1.5 坑三：跳闸指标被算成了拒绝次数

```go
OnStateChange: func(name string, from gobreaker.State, to gobreaker.State) {
    state := stateToGauge(to)
    metrics.CircuitBreakerState.WithLabelValues(name).Set(state)
    // platform-L5: a trip is a transition INTO open, not every request
    // rejected while open (which inflated the metric hugely).
    if to == gobreaker.StateOpen {
        metrics.CircuitBreakerTrips.WithLabelValues(name).Inc()
    }
    // ...
},
```

`CircuitBreakerTrips` 现在只在**状态从非 open 变成 open 的那一刻**加一。

之前我是在 `Execute` 的失败分支里加的，也就是熔断打开期间**每一个被拒绝的请求**都会加一。熔断一旦跳闸，这个指标会在几十秒内涨到几万，看起来像"疯狂跳闸"，实际上只跳了一次。**指标的名字和它统计的东西不一致，这种错误比没有指标更糟。**

---

## 2. Fallback：四个工厂里我埋过一颗雷

### 2.1 三种降级策略

`platform/grpc/fallback.go` 里定义了几个 fallback 实现，对应"熔断打开时怎么办"：

```go
const (
    FallbackCache  FallbackStrategy = "cache"  // 用缓存数据
    FallbackAsync  FallbackStrategy = "async"  // 转异步处理
    FallbackNoOp   FallbackStrategy = "noop"   // 什么都不做
    FallbackReject FallbackStrategy = "reject" // 直接拒绝
)
```

`AuthCacheFallback` 的设计意图是：identity 熔断打开时，用本地/Redis 缓存里的鉴权快照继续服务。

它有一个非常关键的约束：

```go
// ExecuteFallback returns cached auth data or an error. It never fabricates a
// success: without a configured lookup the request is rejected, preventing
// unauthorized access during an identity-service outage.
func (f *AuthCacheFallback) ExecuteFallback(ctx context.Context, token string) (*identityv1.GetAuthSnapshotReply, error) {
    if f == nil || f.lookup == nil {
        return nil, fmt.Errorf("auth cache fallback unavailable: no lookup configured")
    }
    snap, err := f.lookup.Lookup(ctx, token)
    if err != nil {
        return nil, fmt.Errorf("auth cache fallback miss for token: %w", err)
    }
    // ...
}
```

**它绝不伪造成功。** 没有配置 lookup、或者缓存没命中，一律返回错误。

这条约束是被上一版教出来的。文件里有段注释记录了旧实现的问题：

```go
// REVIEW_v1 P1-1 flagged the previous implementation as "假装成功但不扣费"
// (fake success, no charge). It now requires a real AsyncBillingQueue: if none
// is configured the fallback returns an error so the request is rejected
// rather than served for free.
```

计费的那个 fallback 早期版本写成了"假装成功"——熔断打开时直接返回一个成功的响应，**于是请求被免费服务了**。这是我这套架构里出现过的最危险的一个 bug 类型：降级路径上伪造成功。

现在的规则是：**所有 fallback 要么返回真实数据，要么返回错误。没有第三种。**

```go
// ChannelCacheFallback ... Without a lookup the request is rejected rather
// than routed to an arbitrary channel.
```

### 2.2 类型化拒绝：让调用方能分支

现在真正接在生产路径上的 fallback 是这一个：

```go
// ErrCircuitBreakerOpen is the sentinel returned by RejectFallback when the
// circuit breaker for a downstream service is open. Callers can branch on it
// with errors.Is to degrade gracefully instead of receiving a wrapped,
// message-bearing "circuit breaker open for <svc>" error (relay-H1: the four
// production ResilientClients previously passed nil as the fallback, so the
// only signal was an opaque formatted string).
var ErrCircuitBreakerOpen = errors.New("circuit breaker open")

func TypedRejectFallback[T any]() FallbackFunc[T] {
    return func(ctx context.Context, err error) (T, error) {
        var zero T
        return zero, errors.Join(ErrCircuitBreakerOpen, err)
    }
}
```

`errors.Join` 让两个信息都留着：调用方用 `errors.Is(err, ErrCircuitBreakerOpen)` 判断"这是熔断导致的"，同时原始的熔断器错误还在链上可以打日志。

之前四个 resilient client 传的是 `nil` fallback，于是熔断打开时只有一个格式化字符串 `"circuit breaker open for identity: ..."`。调用方只能去匹配字符串——这种东西一旦文案改了就会静默失效。

### 2.3 一个我留下的矛盾

`DefaultBreakerConfig` 里写的是 `FallbackStrategy: FallbackCache`，但四个生产 client 用的都是 `TypedRejectFallback`：

```go
breaker: appgrpc.NewResilientClient[identityv1.IdentityServiceClient](
    client,
    appgrpc.DefaultBreakerConfig("identity"),
    timeout,
    appgrpc.TypedRejectFallback[identityv1.IdentityServiceClient](),
),
```

也就是说这个配置字段目前只影响**指标标签**，不影响实际行为：

```go
func (rc *ResilientClient[T]) fallbackStrategyLabel() FallbackStrategy {
    if rc.fallbackStrategy != "" {
        return rc.fallbackStrategy
    }
    return FallbackReject
}
```

结果就是我指标上看 `FallbackActivation{strategy="cache"}`，但实际执行的是拒绝。**这是一个会误导排障的命名问题**，要么把默认值改成 `FallbackReject`，要么真的把缓存 fallback 接上去。我倾向后者，但还没做。

---

## 3. 不同下游，失败方式不一样

第 1 篇里我讲过一条判断边界的线：**能不能拒绝服务**。落到实现上就是"熔断打开时这个调用怎么办"。

| 下游 | 挂了会怎样 | 现在的行为 |
|---|---|---|
| identity | 无法鉴权 | 拒绝（fail-close） |
| channel | 无法选路 | 拒绝（fail-close） |
| billing | 无法预扣 | 拒绝（fail-close） |
| log | 日志丢失 | **请求照常返回** |

前三个接的是 `TypedRejectFallback`，第四个虽然也接了同样的 fallback，但**调用点本身不阻断请求**：

```go
logUpstreamUsage(logInput)
s.ingestUsageLog(ctx, logInput)
s.writeJSON(w, http.StatusOK, resp)
```

`ingestUsageLog` 的返回值没有参与任何判断。日志写失败只记 Warn：

```go
func (s *HTTPServer) logPostResponseCommitError(err error) {
    if err != nil {
        applogger.Log.Warn("failed to commit quota after response was written", zap.Error(err))
    }
}
```

所以 log 这个服务的熔断打开时，你会在指标上看到它跳闸了，但**用户侧完全感知不到**。这是设计意图：观测数据允许最终一致，对账任务会在事后发现 ledger 和 log 的差异。

**同一个 fallback 实现，接在不同调用点上，语义完全不同。** 这一点我认为是跨服务降级设计里最容易搞混的地方——`ResilientClient` 只负责"熔断打开时返回什么错误"，"这个错误要不要影响请求"是调用点的事。

---

## 4. 超时：我更喜欢那个上限保护

`pkg/timeout` 是一组简单的超时工具，默认值是这样：

```go
const (
    DefaultHTTPTimeout     = 30 * time.Second
    DefaultGRPCTimeout     = 10 * time.Second
    DefaultDBQueryTimeout  = 5 * time.Second
    DefaultUpstreamTimeout = 60 * time.Second

    MaxHTTPTimeout = 5 * time.Minute
    MaxGRPCTimeout = 1 * time.Minute
)
```

读取的时候有个上限夹取：

```go
// GetTimeout returns a timeout value from environment variable or default
func GetTimeout(envVar string, defaultValue time.Duration, maxValue time.Duration) time.Duration {
    if timeoutStr := os.Getenv(envVar); timeoutStr != "" {
        if duration, err := time.ParseDuration(timeoutStr); err == nil {
            if maxValue > 0 && duration > maxValue {
                return maxValue
            }
            return duration
        }
    }
    return defaultValue
}
```

**配置写错了不会生效成"超大超时"，而是被夹到上限。** 这个保护我挺喜欢的：`GRPC_TIMEOUT=10h` 这种手误，如果直接生效，一次下游卡死就能把连接池耗光。

另一个函数处理的是嵌套超时：

```go
// WithTimeout creates a context with a timeout
func WithTimeout(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
    // If parent already has a deadline, use the remaining time
    if deadline, ok := parent.Deadline(); ok {
        remaining := time.Until(deadline)
        if remaining < timeout {
            timeout = remaining
        }
    }
    return context.WithTimeout(parent, timeout)
}
```

**子超时不延长父超时。** 上层给了 2 秒的预算，下层想要 10 秒，实际拿到的是 2 秒。这条如果不写，就会出现"外层已经超时返回 504 了，内层还在跑"的情形。

### 4.1 但超时和重试是乘起来的

这是我到现在还不太满意的地方。relay-gateway 调下游时，超时是这么配的：

```yaml
resilience:
  enabled: ${RELAY_RESILIENCE_ENABLED:-false}
  timeout: ${RELAY_RESILIENCE_TIMEOUT:-3s}
```

```go
resilienceTimeout := parseDurationOrDefault(cfg.Bootstrap.Resilience.Timeout, 3*time.Second)
if cfg.Bootstrap.Resilience.Enabled {
    identityClient = relaydata.NewResilientIdentityClient(identityClient, resilienceTimeout)
    // ...
}
```

每次调用 3 秒上限。但**重试策略是 3 次，退避 500ms → 1s**。所以最坏情况是：

```
3s + 0.5s + 3s + 1s + 3s = 10.5s
```

一个"3 秒超时"的下游调用，在这个请求里实际可能占用 10 秒以上的预算。

这两层是在不同地方配置的（一个在 `resilience.timeout`，一个在 `retry.max_attempts` / `initial_interval`），**没有任何机制保证它们的乘积落在一个可接受的范围内**。我现在的处理方式是"知道这件事，先这样"，但正确的做法应该是给整个请求一个有名字的预算，然后让重试自己判断"我还能不能再试一次"。

### 4.2 请求体大小限制：同样是分层夹取

`platform/middleware/bodylimit.go` 把入站请求按端点分了三档：

```go
const (
    // DefaultMaxBodySize is the fallback maximum request body size (10MB).
    DefaultMaxBodySize = 10 * 1024 * 1024
    // JSONRequestBodyLimit bounds chat-like JSON requests. These requests are
    // buffered for model extraction and should fail before allocation grows.
    JSONRequestBodyLimit = 8 * 1024 * 1024
    // LargeRequestBodyLimit is reserved for raw proxy and multipart audio/image
    // payloads that can legitimately be larger than JSON while still having a hard cap.
    LargeRequestBodyLimit = 64 * 1024 * 1024
)
```

8MB 给 JSON 类请求，64MB 给音频/图片这类本来就大的，其他 10MB。

两个检查点：`Content-Length` 能提前拒绝，chunked 请求交给 `http.MaxBytesReader` 在真正读的时候拒绝。

```go
func RequestBodyLimitByPath(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        maxSize := RequestBodyLimitForPath(r.URL.Path)
        if r.ContentLength > maxSize {
            WriteRequestBodyTooLarge(w, r.URL.Path)
            return
        }
        r.Body = http.MaxBytesReader(w, r.Body, maxSize)
        next.ServeHTTP(w, r)
    })
}
```

**Content-Length 是客户端说了算的，所以它只适合"提前拒绝明显超大的"，不能当唯一防线**——chunked 编码可以完全不带这个头。

这个文件还有一个特殊的例外，我写在了文件头：

```go
// Keep encoding/json for ValidateJSONBody: it needs Decoder.DisallowUnknownFields()
// and custom error type checking (json.SyntaxError, json.UnmarshalTypeError) that sonic
// doesn't expose the same way. Body parsing is not the hot path for serialization.
//
// NOTE (dual-parser boundary): this middleware validates the body with stdlib
// encoding/json, while downstream handlers parse the same body via pkg/jsonx
// (sonic.ConfigStd). Both parsers are encoding/json-compatible, but accept/reject
// behavior may differ on edge inputs (unknown fields, number precision, escapes).
// That is intentional: this layer fails closed (rejects) before the handler sees
// the body, so a divergence would surface as a rejected request, never as a
// silently different parse downstream.
```

一个请求体会被两个解析器读：中间件用标准库（因为它需要 `DisallowUnknownFields` 和那两个具体的错误类型），业务用 `jsonx`。我在注释里把"这两者可能对边界输入判断不一致"这件事写明了，并说明为什么可接受——**这一层是先拒绝，所以分歧只会表现成"请求被拒"，不会表现成"下游解析出另一个东西"**。往坏的方向偏，而不是往静默错误的方向偏。

---

## 5. 缓存：它同时是降级手段和风险源

`platform/cache` 里的两级缓存本来是为性能做的（第 12 篇会单独讲），但它和这一篇的关系是：**它是熔断降级的候选手段，也是一个把风险往后拖的机制。**

缓存的默认参数：

```go
func DefaultConfig() *Config {
    return &Config{
        L1CacheSize: 10_000,
        L1TTL:       30 * time.Second,
        L2TTL:       5 * time.Minute,
        Prefix:      "cache",
    }
}
```

L1 在进程内 30 秒，L2 在 Redis 5 分钟。

### 5.1 失效是整片清的

渠道配置和鉴权快照的失效，是通过路由变更事件广播的：

```go
// Each process owns a distinct consumer group: invalidations must broadcast
// to every L1 cache, not load-balance across gateway replicas.
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

注意 "Each process owns a distinct consumer group" 那句：consumer group 的名字里带了主机名和进程 ID，

```go
routingEvents = events.NewStreamEventBus(redisClient, fmt.Sprintf("relay-routing-%s-%d", host, os.Getpid()))
```

**失效消息必须广播到每个副本，不能负载均衡。** 如果多个副本共用一个 consumer group，Redis Stream 只会把消息投给其中一个，其余副本的 L1 缓存就会一直保留旧值,直到 TTL 到期。这是我踩过的一个很典型的坑：用了 stream 就顺手写了 consumer group，忘了失效语义要求的是 fan-out 而不是竞争消费。

失效的粒度我选得比较粗：

```go
func (c *AuthCache) InvalidateAll(ctx context.Context) error {
    c.cache.ClearAll()
    return c.cache.InvalidateByPattern(ctx, "*")
}
```

`identity` 或 `subscription` 域的任何变更，直接把**整个鉴权缓存**清掉。这是一个很粗暴的做法，代价是每次有用户改密码、改 token，所有副本的鉴权缓存全空，接下来一小段时间所有请求都要回源。

精确失效（按 `InvalidateByUser`）的接口是有的，但我在路由事件里没走那条路——因为事件里带的是变更对象的标识，要映射到"哪些 token 受影响"需要额外查询。整片清是最简单且绝对不会漏的方案，我先用了它。

代价我也说清楚：**热点集群下，一次用户资料修改会造成一次小规模的缓存击穿。**

### 5.2 这里有个注释已经过期了

`NewMultiLevelCache` 上面有一段注释：

```go
// The eventBus parameter is retained for API compatibility but is intentionally
// unused: event-driven invalidation was never wired (relay-gateway passes nil
// and no code path calls AuthCache.Invalidate / ChannelCache.Invalidate*).
// Cache freshness is therefore bounded EXCLUSIVELY by TTL expiry — the
// contract callers must respect is: a revoked/invalidated entry remains
// potentially stale for up to max(L1TTL, L2TTL) after the underlying source of
// truth changes.
```

**这段话现在是错的。** `relay-gateway/wire.go` 里确实订阅了 `routing.changed`，并且会调 `InvalidateAll`。写这段注释的时候失效还没接，后来接上了，但注释没跟着改。

我把这条列在这里是因为它本身就是一个教训：**注释里描述"现状"的句子，是最容易过期的。** 描述"为什么"的注释（比如为什么要 fan-out 消费）不会过期，描述"现在有没有接"的注释会。我现在尽量把前者写清楚，后者要么不写，要么标日期。

顺带说一句那段注释里唯一还有效的部分：**如果失效没接，陈旧窗口就是 `max(L1TTL, L2TTL)` = 5 分钟。** 这个数字对鉴权意味着"一个被撤销的 token 最多还能用 5 分钟"。这是我当初决定接失效广播的直接原因。

---

## 6. 现在的状态

### 已经能用的

- 四个下游都有熔断器，按 gRPC code 分档，只有传输层失败会跳闸
- 类型化 sentinel `ErrCircuitBreakerOpen`，调用方可以 `errors.Is` 分支
- Fallback 的硬约束：不伪造成功，要么真数据要么错误
- log 降级不阻断请求，计费/鉴权/选路 fail-close
- 超时上限夹取，子超时不延长父超时
- 请求体按端点三档限制，Content-Length 预热拒绝 + MaxBytesReader 兜底
- 缓存失效走事件广播 + 每副本独立 consumer group

### 还没解决的

**第一，熔断整体是默认关闭的。**

```yaml
resilience:
  enabled: ${RELAY_RESILIENCE_ENABLED:-false}
  timeout: ${RELAY_RESILIENCE_TIMEOUT:-3s}
```

`RESILIENCE_ENABLED` 默认 false。也就是说上面这一整套保护，在默认配置下一条都没有生效——relay-gateway 直接裸调四个下游。

我默认关着的理由是：这套东西我还没有在真实压力下验证过，包括它自己的失败模式（比如熔断器误跳闸之后怎么恢复、半开探测够不够）。**默认打开一个没验证过的保护机制，可能比没有它更危险。** 但我必须承认：现在的状态是"写了但没用上"，这是个需要尽快收掉的口子。

**第二，超时和重试的乘积没有统一预算。** 前面算过，3 秒超时 × 3 次重试 + 退避 = 10 秒以上。

**第三，熔断参数不可配。** 阈值 0.6、最小 5 个请求、打开 30 秒、半开 3 个探测，全是常量。不同下游的合理值明显不一样（billing 应该比 log 更保守），但我现在改不了。

**第四，缓存 fallback 没接，但指标标签说接了。** 第 2.3 节那个矛盾。

**第五，鉴权缓存失效是整片清。** 简单可靠，但会造成周期性击穿。

---

## 7. 这个系列的收尾

这是网关可靠性三篇的最后一篇（前两篇：[选路与重试](/2026-09-15-micro-one-api-ordered-routing/)、[订阅账号池](/2026-09-15-micro-one-api-account-pool/)）。三篇连起来是我在这条链路上做的三层保护：

| 层 | 问题 | 篇 |
|---|---|---|
| 选路 | 该走哪个来源，失败了换谁 | 第 3 篇 |
| 账号池 | 一个账号能承受多少，满了和坏了怎么区分 | 第 4 篇 |
| 跨服务 | 下游不可用时，这个请求该不该继续 | 第 15 篇 |

写这三篇的时候我反复碰到同一个问题：**同一个信号，在不同层里的含义不一样。**

- 一个 429，对选路来说是"换一个来源"，对账号池来说是"这个账号忙，别封禁"，对熔断来说是"上游不健康，但不算这个服务的故障"。
- 一个本地失败（比如协议转换错了），对选路来说是"别重试"，对账号健康来说是"跟渠道无关，别记它"，对熔断来说是"客户端问题，别跳闸"。
- 一个请求级排除，和一个进程级的封禁，是两件事。

我大部分返工都花在把这些含义拆开上。而拆开的代价是：同一类判断要在四五个地方分别写一遍，每一处都可能漏。**这大概是我这套代码里最容易复发的一类 bug。**

如果重来一次，我可能会给"失败"这个概念定义一个显式的分类结构，一次算清楚，然后各层只消费它的字段，而不是每层各自去猜状态码和错误类型。
