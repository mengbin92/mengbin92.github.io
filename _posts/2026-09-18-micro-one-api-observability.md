---
title: "可观测性：一个指标记错了五次，以及很多次我加了指标却从来没看过"
date: 2026-09-18T12:00:00+08:00
description: "这段代码注释是我在 review 自己的时候发现的，编号 platform-L9：。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 差点发生的事：审计日志一条都没记

这段代码注释是我在 review 自己的时候发现的，编号 platform-L9：

```go
// The logger is resolved on EACH event rather than captured at construction
// time (platform-L9): NewAuditor is typically called during wire/DI setup,
// BEFORE applogger.Initialize has swapped the nop logger for the real one.
// Capturing applogger.Log.Named("audit") then pinned the nop logger forever
// and silently dropped every audit event.
type Auditor struct {
    enabled bool
}

// logger resolves the current audit sub-logger at call time (platform-L9).
func (a *Auditor) logger() *zap.Logger {
    return applogger.Current().Named("audit")
}
```

原来那版是在构造函数里把 logger 存下来的：

```go
// 旧版本（错的）
func NewAuditor(enabled bool) *Auditor {
    return &Auditor{enabled: enabled, logger: applogger.Log.Named("audit")}
}
```

`applogger.Log` 在程序启动时是一个 **nop logger**（什么都不做的空实现），真正的 logger 要等 `applogger.Initialize()` 之后才换上。而 `NewAuditor` 是 Wire 依赖注入的时候调用的——**在初始化之前。**

于是审计日志全部写进了一个黑洞。没有任何报错，因为 nop logger 的语义就是"什么都不做"。

这个 bug 的性质值得单独说：**它不是"日志写得不对"，而是"日志系统本身没接上"。** 而你无法通过看日志来发现这件事——因为日志里什么都没有，和"没有事件发生"完全一样。

**空手而归和从未出发，在观测上是一样的。** 这是我在这件事上学到的最重要的一条。

改正的方式是每次记事件的时候现取 logger，而不是构造时缓存。

---

## 1. 三套东西，三种用途

我现在把可观测性分成三类，它们的用途和保留期完全不同。

### 1.1 指标（Prometheus）

**回答"现在正常吗"，聚合、低基数、长期保留。**

```go
metrics.CircuitBreakerState.WithLabelValues(name).Set(stateToGauge(state))
metrics.CacheHits.WithLabelValues(c.metrics.cacheName, "l1").Inc()
metrics.SubscriptionAccountRecoveriesTotal.WithLabelValues(policy, "skipped").Inc()
```

指标的价值在于**趋势和对比**：这个小时比上个小时差了多少、P95 有没有超线、错误率是从哪一刻开始涨的。

### 1.2 审计（结构化日志）

**回答"谁在什么时候做了什么"，不聚合、高基数、按需查询。**

```go
type AuditEvent struct {
    Timestamp time.Time      `json:"timestamp"`
    EventType EventType      `json:"event_type"`
    Actor     ActorInfo      `json:"actor"`
    Resource  ResourceInfo   `json:"resource"`
    Action    string         `json:"action"`
    Result    string         `json:"result"`
    Details   map[string]any `json:"details,omitempty"`
    RequestID string         `json:"request_id,omitempty"`
    IPAddress string         `json:"ip_address,omitempty"`
    UserAgent string         `json:"user_agent,omitempty"`
}
```

类型枚举是**动作导向**的，不是资源导向的：

```go
const (
    EventTypeCreate     EventType = "create"
    EventTypeRead       EventType = "read"
    EventTypeUpdate     EventType = "update"
    EventTypeDelete     EventType = "delete"
    EventTypeLogin      EventType = "login"
    EventTypeLogout     EventType = "logout"
    EventTypePayment    EventType = "payment"
    EventTypeConfig     EventType = "config"
    EventTypePermission EventType = "permission"
)
```

`Payment`、`Permission`、`Config` 这三类我单独拎出来了，而不是笼统地叫 `update`。因为**"谁改了别人的余额"和"谁改了一个渠道描述"是完全不同量级的事**，混在一个 `update` 里就没法做告警规则了。

### 1.3 链路追踪（OpenTelemetry）

**回答"这个请求慢在哪一段"，接第三方、采样、短期保留。**

```go
tp := sdktrace.NewTracerProvider(
    sdktrace.WithBatcher(exporter),
    sdktrace.WithResource(res),
    sdktrace.WithSampler(sdktrace.TraceIDRatioBased(cfg.SampleRate)),
)

otel.SetTracerProvider(tp)
otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
    propagation.TraceContext{},
    propagation.Baggage{},
))
```

三套东西的分工我认为是清楚的，混用会出问题：把高基数的模型名放进指标会打爆时序库；把聚合数字写进审计日志等于什么都没记。

---

## 2. `X-Trace-ID`：为什么我在 OTel 之外自己做了一个

这是我觉得值得单独讲的一个设计。

项目接了完整的 OTel，但**仍然有一个自己的 trace ID**：

```go
// TraceIDHeader is the HTTP header used to propagate trace IDs.
const TraceIDHeader = "X-Trace-ID"

func Middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        traceID := r.Header.Get(TraceIDHeader)
        if traceID == "" {
            traceID = GenerateTraceID()
        }
        ctx := WithTraceID(r.Context(), traceID)
        w.Header().Set(TraceIDHeader, traceID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

有 OTel 了为什么还要这个？三个具体理由：

**第一，OTel 是采样的。** `TraceIDRatioBased(cfg.SampleRate)` 意味着大部分 trace 不会被导出。但**每一个请求都需要一个可关联的 ID**，用来把"用户报的问题"和"日志里的记录"对上。用户说"我 10:23 那次的请求失败了"，我需要一个他也能看到的 ID。

**第二，用户可见。** `w.Header().Set(TraceIDHeader, traceID)` 把这个 ID 写回响应头。用户可以在反馈里带上它。OTel 的 trace ID 虽然也是标准格式，但用户拿不到——它藏在 SDK 内部。

**第三，格式不一样。** 我这个是 16 字节随机数的 hex（32 字符），和 W3C trace context 的格式兼容，但独立生成。

所以两个 ID 并存：**OTel 的用于跨服务追踪，`X-Trace-ID` 的用于用户支持和日志关联。**

代价是它们不互通——我在日志里看到 `X-Trace-ID`，不能在 Jaeger 里直接搜到对应的 trace。这一条我到现在也没解决，属于"知道但没修"。

---

## 3. 一版记错了五次的指标

`CircuitBreakerTrips` 这个指标我改过好几轮，每一轮都是因为"它的名字和它统计的东西不一致"。

### 3.1 我踩过的坑

**第一版**：在 `Execute` 的失败分支里加。结果熔断打开期间每个被拒绝的请求都加一，指标在几十秒内从 0 涨到几万。名字叫 trips（跳闸次数），实际统计的是拒绝次数。

**第二版**：改成只在状态是 open 时加。还是每次请求都加——因为 open 期间每个请求都会看到 open。

**第三版**：试图在 fallback 里加。但 fallback 可能没配置（第 15 篇讲过有段时间四个 client 传的是 nil），于是永远不加。

现在这版是挂在状态变更回调上：

```go
OnStateChange: func(name string, from gobreaker.State, to gobreaker.State) {
    // Update metrics
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

**"跳闸"是一个状态转移，不是一个请求属性。** 这个区分我花了三次才写对。

### 3.2 同一个地方还有一个失败分类问题

```go
if err != nil {
    // platform-L5: distinguish client (non-retryable) errors from real
    // upstream failures so the "failure" outcome only reflects breaker-
    // relevant failures.
    if !isRetryableError(err) {
        metrics.CircuitBreakerRequests.WithLabelValues(rc.serviceName, "client_error").Inc()
    } else {
        metrics.CircuitBreakerRequests.WithLabelValues(rc.serviceName, "failure").Inc()
        metrics.CircuitBreakerFailures.WithLabelValues(rc.serviceName).Inc()
    }
    // ...
}
```

`client_error` 和 `failure` 分开统计。这和第 15 篇讲的那个 incident 是同一条线索：**用户的参数错误不是上游的健康信号，也不该被算成"上游失败"。**

如果这个标签不分开，我会看到一张"identity 服务失败率 30%"的图，然后去查 identity 的容量，而实际上那 30% 全是用户传了错的 token。**错误的分类会把排查引向错误的方向。**

### 3.3 分层缓存的命中率

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

```go
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "l1").Observe(time.Since(start).Seconds())
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "l2").Observe(time.Since(start).Seconds())
metrics.CacheLatency.WithLabelValues(c.metrics.cacheName, "get", "source").Observe(time.Since(start).Seconds())
```

前面几篇讲过这个理由，这里只补充一句：**"总命中率 95%" 和 "L1 命中率 95%" 指向完全不同的优化动作。** 只看总数的话，你不知道该加内存还是改 key 设计。

---

## 4. 高基数：为什么指标里没有模型名

这是我在做指标时定的一条硬规则，写在 selection event 的类型注释里：

```go
// The roadmap requires structured records at the selection and execution
// boundaries: candidate sources, the final source, sticky hit, priority tier,
// fallback reason, execution result and latency. These feed the Prometheus
// metrics (§3.5, low-cardinality labels) and the admin operations view (§3.6,
// full detail in structured logs / traces). channel/account/model identifiers
// stay OUT of Prometheus labels (cardinality) and go only into the structured
// event/log.
```

关键那句：**"channel/account/model identifiers stay OUT of Prometheus labels (cardinality)"。**

模型名是**极高基数**的维度。一个网关对接几十家上游、每家几十个模型，再加上用户自定义的别名——**模型名的基数可以是几千甚至几万**。

如果把它做成 Prometheus 标签：

- 每个"模型 × 渠道 × 结果"的组合都是一个独立时间序列；
- 每个序列都要单独存储、单独计算；
- 时序数据库的内存和磁盘会爆炸。

所以指标里只用低基数的粗粒度维度：

```go
metrics.RoutingSelectionTotal.WithLabelValues(sourceKind, result, providerFamily)
```

`providerFamily` 是从模型名推出来的**粗分类**：

```go
func ProviderFamilyForModel(model string) string {
    switch {
    case strings.HasPrefix(lower, "claude-"):
        return "anthropic"
    case strings.HasPrefix(lower, "gpt-"), strings.HasPrefix(lower, "o1"):
        return "openai"
    // ...
    }
}
```

而**具体的渠道 ID、账号 ID、模型名走结构化日志**：

```go
type SelectionEvent struct {
    RequestID string
    // ...
    // FinalSourceID is the selected channel or account id (structured log only).
    FinalSourceID int64
    // Model is the canonical public model id (HIGH cardinality — labels only
    // use a coarse provider_family derived from it, never the raw model).
    Model string
    // PriorityTier is the priority value of the winning tier (structured log).
    PriorityTier int64
    // ...
}
```

**同一个事件，字段级地区分"能进标签"和"只能进日志"，并且把这条规则写在字段注释里。** 我认为这比写在一份《指标规范》文档里有效得多——因为写代码的人一定会看结构体定义，未必会去看规范文档。

---

## 5. 错误路径的日志必须"有界"

第 2 篇和第 15 篇都提过这条，这里从可观测性的角度再说一次，因为它同时是隐私问题。

修复那次 4xx 被改写成 502 的 incident 时，我加了一个日志函数：

```go
// internal/server/responses_upstream_error.go
// logResponsesUpstreamFailure records only bounded, low-cardinality failure
// metadata. In particular, it never logs request headers/body or the upstream
// response body carried by UpstreamHTTPError.
func logResponsesUpstreamFailure(ctx context.Context, endpoint string, stream bool, phase string, err error) {
    status := relaybiz.UpstreamStatus(err)
    // ...
    applogger.Log.Warn("responses upstream request failed",
        zap.Int("upstream_status", status),
        zap.String("endpoint", endpoint),
        zap.Bool("stream", stream),
        zap.String("execution_path", executionPath),
        zap.String("phase", phase),
        zap.String("error_category", responsesUpstreamErrorCategory(status)),
    )
}
```

不记 header、不记请求体、不记上游响应体。

同一件事在 adaptor 层也做了一次：

```go
// truncateBody returns a size-capped copy of body for inclusion in error
// messages. Upstream error bodies may leak internal account identifiers (the
// upstream's own view of the subscription, request ids, etc.), so callers
// should never forward them verbatim to the client. We cap at 512 bytes and
// mark truncation.
func truncateBody(body []byte) string {
    const max = 512
    if len(body) <= max {
        return string(body)
    }
    return string(body[:max]) + "...(truncated)"
}
```

**上游的错误响应体里可能有上游侧的账号标识、请求 ID、内部错误细节。** 原样透传给客户端，等于把上游的内部结构暴露出去。

所以：**错误路径要记日志，但要记的是低基数、可聚合、不含内容的元数据。**

### 5.1 这条规则和"排查需要信息"是矛盾的

说实话，这两者确实是矛盾的——最想看的往往就是请求体和上游响应体。

我的处理是分环境：**默认不记内容；需要排查时，用具体请求的 `X-Trace-ID` 去捞那一条**（如果开了请求体采样日志，那也是一个独立的、有保留期的通道）。

但我必须承认：**我现在没有那个"独立通道"。** 所以实际排查时如果日志里没有我需要的信息，我只能去复现。这是当前的缺口。

---

## 6. 一次基线采集告诉我的事

我按季度做一次观察基线，输出到 `docs/observability/`。第一份是 2026 Q3 的。

做这件事的时候我以为只是"例行记录"，但实际发现了好几个只有拉长周期才看得出来的事。

### 6.1 小样本会让比率指标完全失去意义

报告里有一条 502 ratio：

> 2026-08-14 01:00 UTC 出现 502 ratio = 50%。该小时样本量极小，分母为 2 个请求、其中 1 个 502；不是持续性压力信号。

**50% 的 502 听起来是重大故障，实际是 2 个请求里有 1 个失败。**

如果我的告警规则是"502 ratio > 1% 就报警"，这个小时会疯狂报警。而真实情况是那天那个小时只有 2 个请求。

所以比率类指标**必须配一个最小样本量**。这个原则我在熔断器的实现里用过（`circuitBreakerMinRequests = 10`，第 3 篇），但在告警规则里我一开始没加。

报告里把这一类现象叫 "异常点归因"，我认为这是个好习惯：**每个异常点都要写清楚它的样本量，否则这个数字会被后来的人当成真信号。**

### 6.2 直方图的 bucket 上界会被当成真实值

> `/v1/responses` 当前 P95 恰好落在 10s bucket，受 histogram bucket 上界影响，应继续观察而不是推断为 10s 精确值。

Prometheus 直方图算分位数是**插值估算**。如果 P95 落在最高的 bucket 边界上，你看到的是 bucket 的上界，不是真实值。

**但看板不会告诉你这件事**——它就是显示 "10s"。

我在报告里明确写了"不应推断为精确值"，因为我知道三个月后的自己会直接相信那个数字。

### 6.3 指标覆盖不到的地方，用 SQL 兜

报告的第三节叫 "Dedupe claim 观察（SQL）"。为什么用 SQL 而不是指标？

因为**我没有为"去重声明冲突"设计指标**。报告里写得很直白：

> 结论：正常。当前仍没有应用级 dedupe conflict / claim-created counter，本值只能说明新增 ledger 与新增 claim 一一对应，不能区分并发重试被正确拒绝、业务重复请求或回滚残留。

我能从 SQL 里知道 `billing_ledger_dedupe_claims` 有 27,400 行、`ledgers` 有 27,401 行，两者一一对应。但我**不能**区分以下三种情况：

1. 并发重试被正确拒绝了（好事）；
2. 业务上真的有重复请求（可能有问题）；
3. 事务回滚留下了残留（坏事）。

三者都表现为"claim 和 ledger 数量一致"。

**指标的缺失会让一个看起来很正常的数字承载不了任何结论。** 报告里把改进项写进了待办：实现一个低基数的 dedupe counter。

这个发现我认为比那张表本身更有价值：**做基线的时候，你不仅会发现"指标数值不好"，更会发现"某些问题根本没有指标能回答"。**

### 6.4 保留窗口会限制能得出的结论

报告里还有一条：

> 受 Prometheus 保留窗口与 1h step 限制，本快照不能可靠统计完整打开次数与最长持续时间；下一季度需要保留原始 15s 序列或至少 5m step。

熔断打开过 3 次，但**"最长持续了多久"这个数我算不出来**——因为我是按 1 小时为步长取的点，而熔断持续了 30 秒还是 50 分钟，在 1h 粒度下看不出区别。

这就是"先有指标，后有采样策略"的典型后果：指标定义好了，但采集粒度定得太粗，事后再想补数据已经来不及。

---

## 7. 我加了但从来没看过的指标

这一节是自我批评。

我刚才数了一下项目里注册的指标，有几个我从来没在任何一个看板或告警里用过：

- `CacheEvictions`——我加了按层（l1/l2）的驱逐计数，但驱逐多少算正常？没有基线，看了也不知道好坏。
- `SubscriptionAccountRecoveryScanDuration`——扫一遍的耗时。这个其实有用（能发现账号表变大导致扫描变慢），但我没配告警。
- `FallbackActivation`——按策略标签统计 fallback 激活次数。因为第 15 篇讲过那个"配置写的是 cache 实际是 reject"的问题，这个指标现在其实是误导的。
- 各种 `...Total` 计数器只计了数，没有配套的"速率"看板。

**加了指标不等于有了可观测性。** 一个没人看的指标和没有这个指标是一样的，区别只是多占了一点存储。

我现在给"要加一个指标"设了一个门槛：**先想清楚它的告警规则或者它要看板上的位置。** 想不出来的就先不加——因为一个看不懂的数字比没有数字更容易误导人（第 6.3 节那个例子就是这个道理）。

---

## 8. 跨服务的关联

最后说一下跨服务怎么串起来。

现在的关系是：

```
客户端请求
  → X-Trace-ID（网关生成，写回响应头）
  → RequestID（网关生成，用于计费幂等）
  → OTel trace（采样导出）
  → 审计日志的 request_id 字段
```

`RequestID` 是另一个独立的 ID，它承担的是**幂等键**的职责（第 2 篇讲过计费和预扣用它去重）。它和 `X-Trace-ID` 不是一回事：

| ID | 谁生成 | 用途 | 是否用户可见 |
|---|---|---|---|
| `X-Trace-ID` | 网关 HTTP 中间件 | 日志关联、用户报障 | 是（响应头） |
| `RequestID` | 网关业务层 | 计费幂等、扣费归属 | 否 |
| OTel trace ID | SDK | 跨服务调用链 | 否（采样） |

**三个 ID 存在是因为它们解决三个不同的问题**：用户能报出来的、能保证钱不重复扣的、能画出调用链的。

我没有把它们统一，因为统一意味着要在某一方面妥协——比如让 OTel 的采样决定计费幂等键是否唯一，那是不能接受的。

代价是排查时需要多跳几次：从用户给的 `X-Trace-ID` 找到日志里的 `RequestID`，再从日志里找到账本记录。这一跳目前靠 `RequestID` 在两边都记录来打通，但不是自动的。

---

## 9. 现在的状态

**已经能用的：**

- 指标 / 审计 / 追踪三套分工，各自有明确的用途和保留策略
- 用户可见的 `X-Trace-ID`，与 OTel 追踪并存
- 按 gRPC code 分档的熔断失败分类（`client_error` vs `failure`）
- 缓存命中率与延迟按层拆分
- 高基数字段不进 Prometheus 标签，规则写在字段注释里
- 错误路径的"有界日志"，不记 header / body / 上游错误体
- 季度观察基线，含异常点样本量归因和指标盲区记录

**还没解决的：**

**第一，`X-Trace-ID` 和 OTel trace 不互通。** 拿到用户给的 ID 不能直接跳到调用链。

**第二，审计日志只有一个出口。** 写进结构化日志，没有独立的存储和查询界面；要查"谁改了谁的钱"得靠日志检索。

**第三，我有一批没人看的指标。** 见第 7 节，该删或者该配上看板。

**第四，去重冲突没有低基数指标。** 只能靠 SQL 数行数，无法区分"正常拒绝并发重试"和"业务真的重复了"。

**第五，请求内容的排查通道缺失。** 默认不记内容是对的，但没有一个"按 trace ID 临时开启"的机制，导致有些问题只能复现。

**第六，基线是手写的。** `docs/observability/` 下的报告是人工采集整理的，不是自动生成的。季度做一次还好，频率再高就不可持续。

---

## 10. 下一篇

下一篇换个方向，讲前端：管理后台的 Apple 风格重设计。那一篇的实现过程比较特殊——它有一份罕见的量化基线（多少处硬编码颜色、对比度是多少、字号多小），我会讲清楚"先量再改"这套流程是怎么走的，以及过程中哪些东西我说服自己放弃了。

[《先量再改：一次有审计底稿的 UI 重设计》](/2026-09-18-micro-one-api-web-redesign/)
