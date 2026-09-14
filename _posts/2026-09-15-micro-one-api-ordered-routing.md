---
title: "一次请求该走哪个渠道：我的选路与重试是怎么长出来的"
date: 2026-09-15T10:00:00+08:00
description: "拆解 micro-one-api 网关的选路与重试：优先级只分层、权重管层内分流的双维度设计，平滑加权轮询加健康/延迟/负载三因子动态降权，熔断器的三处返工（错误率语义、最小样本、半开探测），以及从整层跳过改为逐候选排除的 failover 重写、用复合 key 区分渠道与订阅账号命名空间、重试前重新授权等取舍。"
tags: ["Micro-One-API", "AI 网关", "Go", "架构", "可靠性"]
categories: ["architecture"]
draft: false
mermaid: true
---

## 摘要

选路这件事比我想的难。优先级相同的渠道怎么分流量、重试该换谁、换的时候会不会误伤别的渠道、授权要不要再验一次、一个渠道坏到什么程度该被摘掉——这篇按我实际动手的顺序讲，中间有两次返工，还有一个后来 review 时自己揪出来的、后果比较严重的 bug。

---

## 0. 选路这件事比我想的难

写网关之前我觉得选路很简单：给渠道配个优先级，取最高的那个。

真写起来才发现，一个"该走谁"的问题下面压着一串别的问题：

- 优先级相同的渠道之间怎么分流量？
- 第一次选的渠道失败了，重试换谁？
- 换渠道的时候，原来的排除逻辑会不会误伤别的渠道？
- 授权在第一次选路时校验过了，重试还要不要再校验？
- 渠道连续失败到什么程度该被摘掉？摘掉之后什么时候放回来？
- 这些判断散布在两个进程里，状态怎么同步？

这篇就按我实际动手的顺序讲。中间有两个地方我返工了，还有一个是后来 review 时自己揪出来的、后果比较严重的 bug。

---

## 1. 第一版：优先级 + 加权

### 1.1 优先级只负责分层，不负责分流

我最初把 `Priority` 同时当成"谁优先"和"谁分多少"，后来发现这是两个正交的维度，混在一起会非常难调。

现在的约定写在 `app/channel/internal/biz/channel.go` 的结构体注释里：

```go
Priority int64 // layering only (higher = preferred tier); NOT a within-tier weight
// Weight is the explicit within-tier selection weight for smooth WRR. 0
// ... layering, Weight is for intra-tier distribution, so configured ratios
```

**优先级只分层，权重只管层内分流。** 这个区分是为了让两件事可以分开调：想改"先走便宜的再走贵的"就调优先级，想改"同价位这三家按 3:2:1 分"就调权重。如果只有一个字段，改一个必然影响另一个。

选路的骨架是先按优先级降序排，然后在同一层里做加权选择：

```go
sort.Slice(abilities, func(i, j int) bool {
    return abilities[i].Priority > abilities[j].Priority
})

for i := 0; i < len(abilities); {
    priority := abilities[i].Priority
    tier := make([]*Channel, 0)
    for i < len(abilities) && abilities[i].Priority == priority {
        // ...把这一层里所有可用的渠道收进 tier
    }
    if len(tier) == 0 {
        continue          // 这一层一个可用的都没有 → 落到下一层
    }
    selected, err := uc.selector.Select(ctx, group, tier)
    // ...
}
```

注意 `continue` 那一行：**如果最高优先级这一层全是不可用的，会继续往下找，而不是直接失败。** 这是"降级"最自然的形态——不需要额外的兜底配置。

### 1.2 层内用的是平滑加权轮询

`WeightedSelector` 我选的是 nginx 那套 smooth WRR，而不是按权重随机。原因是随机在样本少的时候抖动很明显：权重 3:1 的两个渠道，前 10 个请求可能全落在权重 1 的那个上。

```go
effectiveWeight := channelEffectiveWeight(state)
state.currentWeight += effectiveWeight
if state.currentWeight > bestWeight {
    bestWeight = state.currentWeight
    best = state
}
// 选中的那个减去总权重
totalWeight := s.totalEffectiveWeight(candidates, now)
if totalWeight > 0 {
    best.currentWeight -= totalWeight
}
```

### 1.3 但"权重"不是配置里那个数字

真正参与计算的是四个因子的乘积：

```go
func channelEffectiveWeight(state *channelState) int64 {
    return int64(state.weight) *
        int64(state.healthFactor()) *
        int64(state.latencyFactor()) *
        int64(state.loadFactor())
}
```

三个动态因子都是 1~100 的定点数：

| 因子 | 依据 | 分档 |
|---|---|---|
| `healthFactor` | 近 60s 错误率 | <1% →100，<5% →80，<10% →50，<30% →20，否则 1 |
| `latencyFactor` | P95 延迟（近 100 次） | <500ms →100，<2s →80，<5s →50，否则 20 |
| `loadFactor` | 在途请求 / maxConcurrent | <40% →100，<60% →80，<75% →50，<90% →20，否则 1 |

用乘法而不是加权求和，是因为**这三个因子任何一个变差都应该独立地压低这个渠道的份额**，而不是被其他两个的好表现抵消掉。

这里有个细节我是刻意做的：用定点数（整数 1~100）而不是浮点。早期的实现里我如果用浮点相乘再取整，低权重渠道（比如权重 1）在三个因子都打折之后会全部落到同一个整数桶里，配置的 1:2 比例就消失了。定点化之后比例能保住。

### 1.4 在途计数：为什么渠道这一侧是"活的"

`loadFactor` 里我写过一段注释，对比了渠道选择器和账号选择器：

```go
// Unlike the subscription-account selector (which tracks load in the
// relay gateway, a different process), the channel WeightedSelector owns the
// full in-flight lifecycle in-process: Select increments inflight and
// RecordHealth decrements it, so this factor is live, not inert.
```

渠道选择器在 channel-service 进程里，`Select` 加一、`RecordHealth` 减一，闭环在同一个进程内，所以这个因子是真的在起作用。

而订阅账号的在途数在 relay-gateway 进程里，channel-service 看不到——这就是为什么账号选择器需要一个 `LoadOracle` 接口去问。这个不对称是被进程边界逼出来的，不是设计偏好。第 4 篇会专门讲账号池那一侧。

---

## 2. 熔断：我第一版写错了三处

这一段是我觉得最值得写的，因为三个错误都很典型。

### 2.1 错误一：把"每秒错误数"当成"错误率"

第一版我用一个计数器记录最近 60 秒的错误次数，然后拿它和阈值 0.5 比：

```go
if cs.recentErrors.Rate() > circuitBreakerErrorThreshold {  // 0.5
    // 打开熔断
}
```

问题在于 `Rate()` 当时返回的其实是**每秒错误数**，不是比例。结果就是：一个低流量渠道，60 秒里总共只有 5 个请求、错了 2 个，每秒错误数就可能超过 0.5，直接被熔断。而一个高流量渠道错误率 30%，每秒错误数很大但比例没到阈值，反而不熔断。

**语义错了，阈值就全是错的。** 现在的 `SlidingCounter` 同时记录总数和错误数：

```go
// Review channel-H1: the previous version recorded only errors and exposed
// them as errors-per-second, which made Rate()'s name a lie — callers compared
// it to a 0..1 threshold as if it were an error *ratio*, so low-traffic
// channels tripped on a handful of failures. It now tracks both errors and
// totals so Rate() returns a true error ratio (errors/total).
func (c *SlidingCounter) RecordOutcome(success bool) {
    c.totals[now]++
    if !success {
        c.errors[now]++
    }
}
```

### 2.2 错误二：没有最小样本量

即使 `Rate()` 语义对了，低流量渠道还是有问题：3 个请求错 2 个，错误率 66%，超阈值。但这 3 个样本什么都说明不了。

所以加了最小样本门槛：

```go
const (
    circuitBreakerErrorThreshold = 0.5 // trip when >50% of requests fail
    circuitBreakerMinRequests    = 10  // but only after this many samples
    circuitBreakerOpenDuration   = 30 * time.Second
    circuitBreakerHalfOpenProbes = 1   // requests let through while half-open
)
```

```go
case circuitClosed:
    // Closed: trip only once we have enough samples AND a high ratio.
    if cs.recentErrors.Total() < circuitBreakerMinRequests {
        return
    }
    if cs.recentErrors.Rate() > circuitBreakerErrorThreshold {
        cs.circuitOpenUntil = now + circuitBreakerOpenDuration.Nanoseconds()
    }
```

### 2.3 错误三：恢复时把所有流量一次性放回去

第一版的恢复逻辑是"过了 30 秒就把熔断关掉"。问题是一个还没恢复的渠道，会在 30 秒后被瞬间灌满流量，然后再次失败，如此循环。

改成三态机之后好多了：

```go
type circuitState int

const (
    circuitClosed circuitState = iota
    circuitOpen
    circuitHalfOpen
)
```

半开状态的实现有点绕，我用了一个哨兵值：

```go
// halfOpenUntil is encoded inside circuitOpenUntil: when the open window
// elapses the channel flips to half-open by setting circuitOpenUntil to a
// sentinel far in the future and arming halfOpenProbes; a probe success closes
// the circuit, a probe failure re-opens it. This keeps the existing
// "circuitOpenUntil > now means skip" invariant in Select intact while adding
// a graduated recovery path.
const circuitHalfOpenSentinel = math.MaxInt64
```

为什么用哨兵而不是加一个状态字段？因为 `Select` 里现有的不变式是"`circuitOpenUntil > now` 就跳过"，把哨兵设成 `MaxInt64`，这个不变式不用改就继续成立。**恢复路径是增量加的，没有重写判断逻辑。**

半开时的行为：

```go
func (cs *channelState) recordBreakerOutcome(success bool) {
    now := time.Now().UnixNano()
    if cs.breakerState(now) != circuitHalfOpen {
        return
    }
    if success {
        cs.circuitOpenUntil = 0 // half-open → closed
    } else {
        cs.circuitOpenUntil = now + circuitBreakerOpenDuration.Nanoseconds() // 重新打开
    }
}
```

**一次探测决定结果**：成功就关闭，失败就再关 30 秒。这样病渠道的流量是一点点加上去的，不是一次性灌回去。

---

## 3. 重试：换谁，以及"什么算换过"

### 3.1 第一次返工：整层跳过 vs 逐个排除

最早的 failover 很简单：重试时把**最高优先级的整层**跳过。

```go
if excludeFirstPriority {
    skipPriority = abilities[0].Priority
}
```

然后我发现一个场景：P0 层有 3 个渠道，其中 1 个坏了。请求落到 P0 里那个坏渠道上失败，重试时整层 P0 被跳过，直接去了 P1。**P0 里另外两个健康渠道一次都不会被用到。**

当时的注释写的是"failover 路径排除最高优先级层"——逻辑上自洽，但它把"这一层有一个坏的"当成了"这一层不能用"。

所以加了 `SelectChannelExcluding`，按渠道 ID 逐个排除：

```go
// SelectChannelExcluding selects a channel for group+model while filtering out
// the given channel IDs individually (per candidate, not per tier), so
// request-scoped failover can walk past failed channels into any remaining
// tier — SelectChannel(excludeFirstPriority=true) skips the entire top tier
// and a post-hoc exclusion check would strand healthy lower tiers.
func (uc *ChannelUsecase) SelectChannelExcluding(ctx context.Context, group, model string, excluded map[int64]bool) (*Channel, error) {
```

这个注释里我特意写了"a post-hoc exclusion check would strand healthy lower tiers"——意思是如果我在选完之后再检查"这个是不是排除过的"，那就得重新选，而且可能一直在同一层里打转。**排除必须发生在选择之前，作为选择算法的一个输入。**

### 3.2 第二次返工：用复合 key 记"谁失败了"

失败源的排除集合，key 不能是 `int64`：

```go
// RoutingSourceIdentity is a namespace-safe routing source key. Ordinary
// channel IDs and subscription-account IDs are allocated independently, so a
// bare int64 is never sufficient when excluding failed sources during
// cross-source fallback.
type RoutingSourceIdentity struct {
    Kind UpstreamRouteKind
    ID   int64
}
```

渠道 ID 和订阅账号 ID 来自两个独立的 ID 空间。如果只用 `int64`：请求在渠道 42 上失败，排除集合里记了 `42`；接着跨来源回退时，订阅账号 42 会被一起排除掉——**一个完全没被用过的账号，因为 ID 撞号被跳过了**。

这种 bug 只在两个空间刚好碰撞时出现，而且只会表现为"某个账号好像从来没被选中过"，没有任何报错。

### 3.3 候选列表：一次算好，重试时不再问

`Plan()` 已经把候选排好序了，重试直接走这个列表：

```go
type RoutingCandidateList struct {
    Group       string
    Model       string
    GlobalModel string
    Candidates  []RoutingCandidate
    Excluded    map[RoutingSourceIdentity]bool
    pos         int
}
```

好处有两个：重试不需要再发一次选择 RPC；**同一次请求里的顺序是稳定的**，不会因为重试时渠道的健康状态变了就跳到另一个渠道上去。

列表走完之后才降级到统一回退：

```go
// selectNextForRetry picks the next source for a retry attempt, in order:
//  1. walk the request-scoped precomputed candidate list with the accumulated
//     exclusion set (no selection RPC);
//  2. the unified cross-namespace fallback with per-candidate exclusion;
//  3. the legacy excludeFirstPriority tier-skip when no fallback selector is
//     wired.
```

### 3.4 一个自己揪出来的 bug：跨命名空间重试会带上空 key

这个是后来 review 的时候发现的，我给它起了个名字叫 HIGH-1。

HTTP 那几个 handler 的重试闭包里，是直接用 `ch.Key` 建上游 provider 的：

```go
provider, provErr := s.providerFactory.CreateProviderWithConfig(ch.Type, ch.BaseURL, ch.Key, ...)
```

而订阅账号投影出来的 `Channel`，`Key` 是**故意留空**的——凭证要通过适配器/凭证存储去取，而 HTTP 闭包不走那条路。

所以如果重试从 API-key 渠道跨到了订阅账号投影上，就会拿着一个空 key 去请求上游，拿回一个 401。而 401 不在可重试状态码里（默认只有 429/500/502/503），于是**这个 401 会直接透传给客户端**。

修复是把重试锁在初始来源所在的命名空间里：

```go
// HIGH-1 fix: ... Lock retry to the INITIAL source namespace: an API-key plan
// only ever fails over to other API-key channels, and a subscription plan only
// to other subscription accounts. This lock applies only to the candidate-list
// path (ExecuteWithCandidates, used by the 4 HTTP handlers); the legacy
// ExecuteWithInitialChannel path (candidates == nil) keeps cross-namespace
// behaviour for its existing callers and tests. WS/Responses transport is
// unaffected — it routes through SelectFallbackRoutingSource directly
// (credential-resolving path).
var initialKind UpstreamRouteKind
if candidates != nil {
    initialKind = UpstreamRouteChannel
    if initialChannel != nil && initialChannel.SubscriptionAccountID > 0 {
        initialKind = UpstreamRouteSubscription
    }
}
```

这个 bug 让我意识到一件事：**"凭证放在哪个结构体里"这个看似洁癖的决定，会反过来决定重试能怎么走。** `RelayPlan` 里我特意不让 access token 进 `Channel.Key`（为了不被日志和管理接口序列化出去），代价就是跨命名空间的重试失去了凭证来源。两个决定是耦合的，我当初做第一个决定时没意识到。

### 3.5 同源重试不是 failover

`execute` 循环里有一段我写得很小心：

```go
// If no alternative found, lastChannel stays the same —
// this is a same-source retry, NOT a fallback.
```

```go
if !SameRoutingSource(ch, previous) && firstErr == nil {
    firstErr = lastErr
    switched = true
}
```

只有真正换到不同来源才置 `switched`。这个区分影响两个东西：

**指标**：`routing_fallback_total` 只统计真正换源的请求。如果同源重试也算进去，这个指标会虚高。

**健康记录**：同一个渠道在一个请求里的多次尝试，合并成**一次**逻辑结果：

```go
if pendingHealth != nil && SameRoutingSource(pendingHealth.channel, ch) {
    // Same-source retries are one logical channel outcome. Accumulate only
    // upstream time (backoff is intentionally excluded) and let the latest
    // attempt determine the terminal result.
    pendingHealth.responseTime += responseTime
    return
}
```

`responseTime` 累加时**不含退避时间**——退避是我自己选的等待，不该算成渠道的响应时间，否则渠道的 P95 会被我自己的重试策略污染。

---

## 4. 什么错误该重试，什么错误该"算账"

这套判断我改了最多次。核心是把三类东西分开：

### 4.1 该不该重试

```go
func (p *RetryPolicy) IsRetryable(err error) bool {
    if err == nil {
        return false
    }
    if IsPostForwardError(err) {
        return false
    }
    // Protocol capability mismatches are not malformed client requests. Another
    // channel may support Responses natively or preserve the required reasoning
    // history, so they remain retryable even with an older custom status list.
    if IsProtocolCapabilityMismatch(err) {
        return true
    }
    if status := UpstreamStatus(err); status > 0 {
        return p.RetryableStatus[status]
    }
    return isRetryableNetworkError(err)
}
```

`PostForwardError` 最先判：**上游已经返回了，本地才失败的，绝不重试**。重试会重复上游请求、付两次钱。

`ProtocolCapabilityError` 走反方向：这不是客户端请求错了，是**这个渠道不支持这个能力**。换一个渠道就有戏，所以即使状态码是 400 也要重试。但 400 的匹配我写得很窄：

```go
// Keep the 400 match deliberately narrow: other bad requests must still fail
// immediately.
func IsProtocolCapabilityMismatch(err error) bool {
    if _, ok := errors.AsType[*ProtocolCapabilityError](err); ok {
        return true
    }
    status := UpstreamStatus(err)
    if status != 400 {
        return false
    }
    return strings.Contains(strings.ToLower(err.Error()), "reasoning_content in the thinking mode must be passed back")
}
```

只认一条具体的报错文案。因为**如果把所有 400 都当成"能力不匹配"去重试，客户端的真实参数错误会被重试 N 次，白白花 N 次钱。**

### 4.2 该不该算"渠道不健康"

这个判断和"该不该重试"是两件事，我一开始混在一起了。分开之后的逻辑是：

```go
// upstreamAttemptHealthy distinguishes channel failures from request/local
// failures. A 4xx response proves the channel is reachable and must release
// selector inflight state without advancing its circuit breaker. Rate limits,
// 5xx responses, timeouts, and transport failures still count as unhealthy.
func upstreamAttemptHealthy(err error) bool {
    if err == nil {
        return true
    }
    if IsPostForwardError(err) {
        return true
    }
    // A model-specific outage proves the channel itself is reachable. Keep
    // fallback enabled, but do not let one unavailable model open the
    // channel-wide circuit and remove unrelated models from routing.
    if isUpstreamModelUnavailable(err) {
        return true
    }
    // Some upstreams encode request-specific policy rejection as HTTP 500.
    // The source is reachable and may still be useful for other prompts, so
    // keep failover enabled without poisoning channel health.
    if isUpstreamPolicyRejection(err) {
        return true
    }
    status := UpstreamStatus(err)
    if status > 0 {
        return status < 500 && status != 429
    }
    // 转换、计费等本地失败也不是渠道健康的证据
    return true
}
```

这里有三个"看起来像渠道故障、其实不是"的情况被我单独挑出来了：

1. **模型不可用**（404 且响应体是 API 形状）。这个渠道只是没有这个模型，它服务别的模型可能完全正常。如果按渠道整体故障处理，一个模型的问题会让这个渠道上的所有模型都被摘掉。
2. **内容策略拒绝**（有的上游用 500 返回 `sensitive_words_detected`）。这是这个 prompt 的问题，不是渠道的问题。
3. **本地失败**（协议转换、计费出错）。根本没到上游，凭什么算渠道的账。

而 404 的判定我写得很小心，因为它同时是"模型不可用"和"base_url 配错了"的表征：

```go
// A concrete API-shaped upstream 404 means this route cannot serve the
// requested model. Only an API error body (JSON, or a body naming the
// model) counts: a proxy/HTML 404 from a misconfigured base_url is
// channel-level breakage, and recording it as model unavailability would
// mark every model on the channel red while channel health stays green.
func upstream404IndicatesModel(body []byte) bool {
    trimmed := bytes.TrimSpace(body)
    if len(trimmed) == 0 {
        return false
    }
    if jsonx.Valid(trimmed) {
        return true
    }
    return strings.Contains(strings.ToLower(string(trimmed)), "model")
}
```

**同一层里的渠道和其上的模型，健康状态是两个粒度。** 这是我在做被动模型健康监测那次改动里才彻底理清的（对应 v0.28.0）。现在的记录函数把两者分开写：

```go
func (e *RetryExecutor) recordHealth(ctx, modelID, baseModel string, ch *Channel, channelOK, modelRecord, modelOK bool, message string, responseTime int64) {
    if ch.ID > 0 && ch.SubscriptionAccountID <= 0 {
        _ = e.selector.RecordChannelHealth(ctx, ch.ID, channelOK, channelMessage, responseTime)
    }
    if !modelRecord {
        return
    }
    // 按 (source_kind, source_id, model_id, upstream_model_id) 记模型级健康
    _ = recorder.RecordModelHealth(ctx, sourceKind, sourceID, RelayModelName(modelID), ResolveChannelModel(ch, baseModel), modelOK, message, responseTime)
}
```

### 4.3 回退原因是给指标看的

`ClassifyRetryFallbackReason` 把第一次失败映射成一个低基数标签：

```go
func ClassifyRetryFallbackReason(firstErr error) string {
    if firstErr == nil {
        return ""
    }
    status := UpstreamStatus(firstErr)
    switch {
    case IsProtocolCapabilityMismatch(firstErr):
        return "capability_mismatch"
    case isUpstreamModelUnavailable(firstErr):
        return "model_unavailable"
    case isUpstreamPolicyRejection(firstErr):
        return "policy_rejection"
    case status == 429:
        return "rate_limited"
    case status >= 500:
        return "upstream_5xx"
    case status == 0 && (errors.Is(firstErr, context.DeadlineExceeded) || isTimeoutError(firstErr)):
        return "timeout"
    case status == 0:
        return "network"
    default:
        return "other"
    }
}
```

用 `firstErr` 而不是终态 error，是刻意的：**我要的是"为什么发生了切换"，不是"最后怎么失败的"。** 一个请求可能 5xx 切了一次、429 又切了一次最后成功——这个请求应该记成 `upstream_5xx` 的 failover，而不是"成功所以没有 failover"。

另外注意这些标签里**没有 channel id、没有 model 名**。model 是基数极高的维度，放进 Prometheus 标签会直接把时序库打爆。真正需要渠道和模型信息的地方是结构化日志/trace：

```go
// channel/account/model identifiers stay OUT of Prometheus labels
// (cardinality) and go only into the structured event/log.
```

---

## 5. 重试之前为什么必须重新授权

这是我很坚持的一条。

授权在 `Plan()` 里做过一次，但重试发生在几百毫秒之后。这段时间里管理员完全可能撤销了某个分组的访问权。如果重试直接复用第一次的授权结果，就会在一次已经失去授权的请求上继续花钱。

所以 `RetryExecutor` 里挂了这么一个钩子：

```go
// WithRouteAuthorization rechecks persisted candidates and same-source retries
// immediately before a new upstream attempt. Normal attempt zero was selected
// by the channel authority; a retry may outlive the grant that selected it.
func (e *RetryExecutor) WithRouteAuthorization(check func(context.Context, string, string, string, *Channel) error) *RetryExecutor {
```

调用点：

```go
if attempt > 0 && e.authorize != nil {
    if err := e.authorize(ctx, group, clientModel, model, lastChannel); err != nil {
        flushHealth()
        return &ExecuteResult{Channel: lastChannel, Err: err, Attempt: attempt, ...}
    }
}
```

实现要向渠道权威再问一次：

```go
func (uc *RelayUsecase) authorizeRetry(ctx context.Context, group, clientModel, resolvedModel string, channel *Channel) error {
    if channel == nil {
        return fmt.Errorf("retry routing source unavailable")
    }
    source := routing.Source{Kind: routing.Channel, ID: channel.ID}
    if channel.SubscriptionAccountID > 0 {
        source = routing.Source{Kind: routing.Subscription, ID: channel.SubscriptionAccountID}
    }
    permission, err := uc.CanRoute(ctx, group, clientModel, resolvedModel, source)
    if err != nil {
        return err
    }
    if !permission.Allowed {
        return fmt.Errorf("retry routing permission revoked")
    }
    channel.UpstreamModelID = permission.UpstreamModelID
    return nil
}
```

`Source` 这个结构体本身就是第 3.2 节那个命名空间问题的产物：

```go
// Source keeps channel IDs and subscription-account IDs in separate namespaces.
type Source struct {
    Kind string `json:"kind"`
    ID   int64  `json:"id"`
}
```

授权查询失败时是 **fail-closed** 的：

```go
// RoutingAuthorizationClient is implemented by both production channel
// adapters. A missing authorizer or an RPC failure must never approve reuse.
```

**权威连不上不等于"允许"。** 这条如果不写死，一次 channel-service 的抖动就会变成一次批量越权。

还有个小细节：`CanRoute` 会先用客户端模型名问一次，不允许的话再用解析后的模型名问一次：

```go
permission, err := authorizer.CanRoute(ctx, group, clientModel, source)
if err != nil || permission.Allowed {
    return permission, err
}
if resolvedModel != "" && resolvedModel != clientModel {
    return authorizer.CanRoute(ctx, group, resolvedModel, source)
}
```

因为授权可能配在别名上，也可能配在真实模型名上，两边都要认。

---

## 6. 有序路由：另一种模式，我到现在还在犹豫

除了"继承用户默认分组"和"固定到某个分组"，我做了第三种 token 模式：**ordered**，也就是 token 上带一个显式有序的分组列表，按用户给的顺序依次尝试。

它的推进规则和普通选路完全不同，注释里我把边界写死了：

```go
// resolveOrderedRouting walks the token's explicit ordered candidate list in
// user order. Advancement to the next candidate happens ONLY here — before
// the first upstream send, before reservation. Disabled/archived groups and
// groups without candidate resources advance; missing access, failed
// settlement qualification and an exhausted list terminate (never falling
// back to the global group list).
```

**推进只发生在一个地方：第一次上游请求发出之前、预扣之前。**

为什么强调这个？因为一旦已经发出请求、已经预扣了钱，再"换一个分组"就意味着要在另一个分组的定价体系下重新计费，账会变得非常难对。所以我宁可让请求失败，也不在事后跳分组。

区分也很细：**没有资源可以往下走，没有权限必须停。**

```go
for i, gid := range candidates {
    g, err := load(gid)
    if err != nil {
        return err
    }
    if g == nil || g.Status != "enabled" {
        continue // 分组被禁用/归档/删除 → 推进
    }
    if len(routing.AccessSources(auth.RoutingFacts, g, now)) == 0 {
        return fmt.Errorf("routing group %d access denied", gid)  // 没有权限 → 终止
    }
    if !allowed {
        return fmt.Errorf("routing group %d settlement unavailable", gid)  // 结算不合格 → 终止
    }
    if !has {
        continue // 这个分组对该模型没有可用资源 → 推进
    }
    return uc.finishOrderedAttempt(...)
}
```

"没有权限"和"没有资源"看起来都是"用不了"，但含义完全不同：前者是授权问题，继续往下走等于跳过授权；后者是容量问题，往下走是正常的降级。**把它们当成同一种情况处理，就等于给了用户一个绕过授权的路径。**

还有一处我纠结了很久，最后选了"不迁移"：

```go
// A bound conversation stays on its original group. When that
// group can no longer serve it (access revoked, disabled), the
// client must start a new session instead of silently moving the
// conversation to another upstream.
```

一个已经绑定到某个分组的会话，如果这个分组不可用了，我**不会**静默把它挪到下一个分组，而是让请求失败、让客户端重新开一个会话。

理由是上下文一致性：这个会话之前的轮次是在分组 A 的上游上跑的，中途换到分组 B 的上游，等于把对话接到了另一个模型上。对用户来说这是"同一个会话里回答质量突然变了"，比直接报错更难排查。

### 6.1 这个功能默认关着

```go
// RoutingOrderedEnabled gates the Phase F ordered (auto) routing capability.
// Like the other relay routing gates it defaults off.
func RoutingOrderedEnabled() bool {
    return strings.EqualFold(strings.TrimSpace(os.Getenv("RELAY_ROUTING_ORDERED")), "true")
}
```

到现在我也没想清楚 ordered 模式该不该是默认能力。它给了用户很细的控制力，但也让"这个请求实际会走哪个分组"变得依赖 token 配置，运营排查时得多查一层。先关着。

---

## 7. 现在的状态和还没解决的事

### 已经能用的

- 优先级分层 + 层内平滑加权，四因子动态权重
- 三态熔断 + 最小样本门槛
- 逐候选排除式 failover，来源用复合 key 区分命名空间
- 重试前重新授权，权威不可达时 fail-closed
- 渠道级和模型级两套健康记录，都有明确的"不该记"清单
- 低基数指标 + 高基数信息走结构化日志

### 还没解决的

**第一，选择器的状态是进程内的。** `WeightedSelector` 的权重、错误率、在途数、熔断状态全在 channel-service 的内存里。如果 channel-service 起了多个实例，每个实例只看到自己那一份流量，权重分布会各自为政。要做多实例，这套状态得挪到 Redis 或者做成聚合视图，我还没做。

**第二，账号侧的负载数据要跨进程拿。** 渠道侧 `loadFactor` 是活的（Select/RecordHealth 同进程闭环），账号侧则要靠 relay-gateway 写进 Redis 的租约集合、channel-service 再去读。这条链路我接上了，但它比渠道侧多一个外部依赖，Redis 不可用时会退化。第 4 篇会展开这个退化行为。

**第三，`ordered` 模式的运营体验没做完。** 管理后台能看到 token 的分组列表，但看不到"最近这个 token 实际命中了哪个分组、跳过了哪些分组"。这层观测缺着，出问题时只能翻日志。

**第四，熔断参数是硬编码的。** 50% 阈值、10 次最小样本、30 秒打开时长都是常量。不同渠道的合理值不一样，但现在改不了。

---

## 8. 相关的一篇

选路决定了请求交给谁，但订阅账号那一侧还有另一套限制：并发槽、RPM、运行时封禁。它们要回答的是一个不同的问题——一个账号"满了"和"坏了"该怎么区别对待。

[《订阅账号池：把一个账号"用满"和"用坏"分开处理》](/2026-09-15-micro-one-api-account-pool/)。
