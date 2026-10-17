---
title: "模型调用慢在哪一段：我给网关做了一套计时观测"
date: 2026-10-17T20:00:00+08:00
description: "拆解 micro-one-api v0.36.0 的请求计时观测：摘要存 log-service、瀑布存 Jaeger、观测身份独立于追踪开关，HTTP/SSE/WebSocket/gRPC 三条入口的生命周期插桩，异步结算的金融边界，以及上线评审修掉的九个边界问题。"
tags: ["Micro-One-API", "Go", "可观测性", "OpenTelemetry", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个我答不上来的问题

日志页里躺着一条记录：状态 200，耗时 28 秒，token 数正常。然后有人问了一个特别自然的问题——**这 28 秒花在哪了？**

我答不上来。

我能翻出来的全部证据是 `logs` 表里的一个 `elapsed_time`。这个字段的口径还是漂移的：legacy 非流式路径在 commit、写日志、writeJSON 之前取值，流式路径在输出结束后取值。同一个字段，两种含义。至于这 28 秒里，多少是路由选源、多少是排队准入、多少是上游首字节、多少是流传输——没有数据，只能猜。

更尴尬的是，Jaeger 我其实早就部署了，OTLP 导出也通，但打开一看，每个请求只有 HTTP 入口一根光秃秃的根 span。它告诉你"这个请求存在过"，仅此而已。

还有第三个问题，是管理端账单详情教我的。页面上的"调用日志"来自账务 ledger，`ReferenceId` 被直接暴露成 `request_id`——而消费账单的引用可以是 **reservation ID**。也就是说，账单根本不是请求的索引，从一条账单出发，我甚至找不到"产生它的那次模型调用"。

三个问题指向同一件事：网关有日志、有指标、有追踪壳子，但**没有"一次调用的时间都花在哪"的账本**。v0.36.0 我做的就是把这本账建起来。方案文档是 `docs/design/llm-request-timing-observability-plan.md`，这一篇讲它从纸面到上线的过程，尤其是上线前评审修掉的那一圈边界问题——那部分比功能本身更有意思。

---

## 1. 先分层，再谈插桩

第 17 篇里我把可观测性分成指标、审计、追踪三套。这次的第一决定是延续这个分层，不发明第四套：

- **Prometheus** 继续管总体趋势，只加有限阶段标签的 histogram，request、trace、用户这些高基数字段一概不进标签；
- **摘要存 log-service**，每个逻辑请求一条结构化摘要，跟着日志的 ingestion、去重和保留走；
- **详细 span 存 Jaeger**，沿用 48 小时 TTL，不另建逐 span 的 SQL 明细表。

真正花心思的决定是第二个：**观测身份不寄生于追踪开关。**

```go
// domain/requesttrace/recorder.go
func StartObservation(parent context.Context, kind, endpoint, protocol, path string, sampled bool) (context.Context, *Recorder) {
```

每次 HTTP 请求、每个 WS 回合、每次 gRPC RPC，由服务端独立生成一个 `observation_id`（UUID），它是摘要的主键和去重键。OTel 启用与否只影响详情能不能展开成瀑布，不影响摘要存在。OTel 没启用时详情标 `not_recorded`，而不是把空 trace ID 拼成所有请求共用的去重键——那种键一旦进唯一索引，全站的请求会互相挤掉。

我为什么这么坚持：追踪系统是可以降级、可以关的，摘要不行。客服问"那条账单卡在哪"的时候，我不能回答"不好意思那小时 Jaeger 在重启"。

第三个决定是**身份边界**。公网传进来的 trace 上下文不作为授权依据，也不直接续用：网关为每次逻辑请求建内部 trace，必要时用 link 关联外部 trace。这样既不受外部 sampled 标记控制，也避免把多个用户的请求拼成一条可以被整体读出来的 trace。内部服务之间传播 `traceparent`/`tracestate`，兼容保留 `X-Trace-ID`，但普通用户不能覆写服务间的可信关联。

---

## 2. 三条入口，三种生命周期

方案评审时标注的第一条现状就是：执行路径根本不统一。`internal/server/routes.go` 注册 legacy、raw、proxy 好几个入口，orchestrator 受开关控制，WS 和 gRPC 还有独立执行路径。**只给新 executor 插桩等于漏掉大半流量。** 所以插桩必须落在传输边界上。

### 2.1 HTTP：writer 包装器的分寸

HTTP 侧的核心是 `internal/server/request_timing.go` 里的 `timingResponseWriter`。它包装 `ResponseWriter`，在 `Write`/`WriteHeader`/`FlushError` 处记录里程碑。这类包装器有个经典翻车点——下游 handler 会做类型断言拿 `http.Flusher`、`http.Hijacker`，包装器一旦少了能力，流式就废了。所以 `Flush`、`Hijack`、`Unwrap` 一个都不能少：

```go
func (w *timingResponseWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }
func (w *timingResponseWriter) Flush() { _ = w.FlushError() }
```

另一个分寸是"首内容"的定义。SSE 流里心跳（`: ping`）和只有 role 的帧会先到，把它们当首内容，"上游首有效输出"就成了"上游心跳到达"——一个毫无排查价值的数字。所以 `domain/requesttrace/content.go` 的 `ContentProbe` 明确：role-only 帧、ping、`response.created` 都不算内容；probe 只保留一个有界帧（64 KiB），绝不缓存完整响应体。

协议判定也在这里：`Write` 时看响应的 `Content-Type` 是不是 `text/event-stream`，是才把 summary 的 protocol 改成 `sse`。这个"看实际响应"的原则后面救了我一次，第 6 节讲。

### 2.2 WebSocket：连接是连接，轮是轮

WS 是三种入口里最容易做错的，因为它有**两种生命周期**。连接/握手是一个，每个 `response.create` 入站帧是一个完整的"轮"。方案里定了几条硬规矩：

- 每个完整的入站帧读到后**立即**建独立 trace 和 observation，不能等上游响应 ID 出现才建；
- 首轮在 forwarder 里就已经做了 Plan/RPM/预占，握手（`ws.accept`）和首帧等待（`ws.first_frame`）必须作为回溯阶段记入首轮；
- 后续轮绑定该轮实际使用的身份和 attempt，不能沿用首轮的计时根；
- 每轮输出及同步处理结束就独立结束 span 并提交摘要，不等整条连接关闭。

最绕的是输出结束的判定。`openai_ws_relay.go` 在 `writeClient` 之前调用 `finishTurn`，而这个回调会**同步**执行结算和写日志。如果把回调完成当作"输出结束"，那结算耗时就被吞进了输出耗时；如果把终帧写出当作结束，又会把写出前发生的结算标成"响应后的后台阶段"。方案的回答是拆成三个里程碑：`upstream terminal`、终帧写出完成、turn 同步处理完成，各记各的。

连接池也要诚实：`ws.pool.acquire` 包裹池获取并用 `ws.pool.reused` 区分复用/新建，`ws.upstream.dial` 只在真实拨号时记录——复用连接时不重复计拨号，不然瀑布上每一轮都顶着一段假的"拨号耗时"。

### 2.3 gRPC：transport 层建根，不伪造里程碑

改造前 gRPC 只传兼容性的 `x-trace-id`，没有分布式 span 树。这次在 `platform/grpc/xgrpc` 挂接 `stats.Handler`，靠 TagRPC/Begin/End 事件完成上下文传播和 client/server span。一个容易踩的坑是 stats handler 和拦截器各建一份根 span，方案明确：同一 RPC 的根 span 只由 transport instrumentation 创建。

另一条规矩我喜欢：**unary RPC 测不准的里程碑就让它缺着。** Relay 的 RPC 是 unary，"首内容时间"无法精确测量，那就保持字段缺失，不允许用 service 返回时刻伪造。观测系统撒谎比没有数据更糟——没有数据你会继续查，假数据你会停下来。

---

## 3. 异步不断链，金融不动账

响应结束后还有一堆活：commit 计费、写日志、健康反馈。这批异步任务会把 context 搞断，之前代码里就有响应后日志退化成 `Background` 的地方。同进程任务用 `context.WithoutCancel(parent)` 保留 span context 另起超时；HTTP 根 span 在 handler 完成时结束，后台任务单独列示，持续时间不并入应用输出耗时。

跨进程的结算 outbox 更麻烦。`settlement_task_repo` 原来只从 payload 还原 SettleTask，trace 关联根本穿不过"持久化 → claim → 反序列化 → worker → RPC"这条链。这次的解法是迁移 138：给 `billing_settlement_tasks` 加五个遥测信封列（`observation_id`、`trace_parent`、`trace_state`、接受/排队时间），worker 恢复上下文再建处理 span。

这里有一条不可越过的线：**金融 payload 和 digest 一个字节都不能动。** `domain/execution/event.go` 对事件 JSON 求摘要，遥测字段如果混进 payload，金融证据和幂等语义就变了。所以遥测走独立列和任务外壳；首次接受的原始关联永远不改，幂等重放不重写 parent；carrier 损坏只让追踪失联并计数，不拒绝结算、不重发金融事件。账是账，观测是观测，观测坏了不能碰账。

log 批写是另一个共享场景：一条 flush 可能装多个请求的日志。每条队列项保留自己的 SpanContext 和 enqueue 时间，共享 flush span 用 links 关联各请求并标明共享批次。管理查询只返回匹配关联的安全片段——不能假设 Jaeger 支持按 links 反查，更不能把批次里别人请求的数据带出来。

---

## 4. 查得到，也要查得安全

观测数据再全，查得不安全就是事故温床。这层的规矩：

- 新增的 `ListRequestTraces`/`GetRequestTrace`/`ResolveLedgerRequest`/`GetSettlementStatus` 四个 RPC 全部登记 `platform/security/serviceidentity/registry.go`，`UserCallers` 仅 admin、无 SystemCallers；admin 转发 operator credential，log/billing owner 再做一次范围校验。用户 ID、trace ID 只是定位条件，不替代授权。
- 浏览器**不直连 Jaeger**，也不提供"传任意 trace ID 就返回"的代理。所有瀑布都走 owner API。
- Jaeger 查询整体 5 秒、累计最多 2 MiB/2000 spans、最多跟随 8 个明确关联，撞限就返回 `partial` 加原因，不静默截断后宣称完整。
- span 属性过白名单（`app/log/internal/data/trace_safety.go`）：`cache.name` 只放行 `auth`/`channel`，`http.response.status_code` 必须是合法状态码整数……不透传 Jaeger 原始 tags、URL query、凭证、prompt 或响应正文。

还有一个隐蔽的坑：摘要复用了 logs 表（迁移 137 加 `request_timing_json`、`observation_id` 等观测列），而数据库和内存里的用户列表/用量聚合原来只排除 `routing-selection` 这一个 source。新的 `relay-request-timing` source 不排除掉，**每条摘要都会被当成一次调用计入调用次数、token 和费用统计**。为此专门加了回归断言：同一调用新增摘要后，统计和用户日志列表必须不变。

---

## 5. 上线：门槛、实测和一次诚实的 canary

发布门槛我定的是：受控基线下网关额外 P95 开销不超过 5%，验收流量无丢弃。实测结果（固定 50ms 假上游、并发 8）：

| 指标 | 关闭采集 | 开启采集 |
| --- | --- | --- |
| 响应 P95 | 53.185542 ms | 53.933708 ms |
| 每请求分配 | 56,906.5 B | 277,417.25 B |
| 每请求 CPU | 592.9 μs | 822.5 μs |
| 摘要导出/丢弃 | 0 / 0 | 168 / 0 |

P95 增量 1.4067%，过了 5% 的门槛。但分配涨了近 5 倍、CPU 涨了 39%，这两个数字我原样写进了验收记录——短时基线过了门槛不代表长流和高峰没事，这属于明确欠着的账（第 7 节）。

生产是低流量 canary：近 24h 约 0.00526 RPS。部署后我用无凭据 POST 打了一个 401，摘要如实落库为 `rejected`、unknown user，Jaeger 里能查到 `relay.request`、`request.parse`、`usage.log` 四根 span。写这篇文章时我顺手查了库，`observation_id` 非空的记录已经写到五百多条，最新一条就在几分钟前。Jaeger 容器 RSS 36 MiB，按保守模型估 48h 原始数据约 45 MiB——以当前流量，512 MiB 的容器限制和 48h TTL 是够的，但公网拒绝请求和峰值增长要继续盯，所以 Prometheus 加了 `request-timing` 告警组：摘要导出丢弃、OTel 队列丢弃、OTLP 导出失败、异步 carrier 失效，四个"观测静默丢失"的信号全覆盖。

---

## 6. 上线评审：修掉的九个边界

功能合并后、发布前，我按方案把七个功能提交分模块复审了一遍，工作方式是**先写会失败的回归测试，再修到通过**。这一轮捞出来九个真问题，每一个都值得说。

### 6.1 stream 请求的"协议假象"

`serveObservedRelay` 在 handler 入口看到请求带 `stream: true` 就把 summary 标成 `sse`。问题来了：上游拒绝的时候返回的是 JSON 错误——客户端请求了流，但实际的响应传输是 HTTP。于是"一次被拒绝的流式请求"在摘要里变成"一条不完整的 SSE 流"，排查方向直接带偏。修法就是把协议判定收敛到 `timingResponseWriter`，以实际响应的 `Content-Type` 为准。**请求想要什么不算数，实际发生了什么才算数。**

### 6.2 一个回合，两条观测

WS 故障转移会重放第一个 `response.create` 帧。重放走的还是 `Send()`，于是同一个客户端回合开了两条 observation——数据直接翻倍。修法是加 `SendFirst()`：重放复用那个还挂着的 turn，结束掉上一次尝试残留的 `response.stream` 阶段，并把重试的 attempt 序号带过去。附带还有一个更细的坑：录制的 context 跨故障转移存活，但 I/O 必须服从当前这次 relay 尝试的取消信号，所以 `writeUpstream` 里用 `context.AfterFunc` 把当前 relayCtx 的取消桥接到回合 context 上——不然一次已取消的重试会把 recorder 晾在那里。

### 6.3 终态塌缩

`ContentProbe` 原来只有一个 `Failed bool`：`response.failed`、`response.incomplete`、`error` 全压成"失败"。但设计方案要求瀑布区分 success/rejected/failed/cancelled/incomplete——被取消的流和推理失败的流是完全不同的排查入口。现在 probe 保留 `outcome`，`Recorder.TerminalOutcome` 原样导出，顺带把 legacy completion 的 `text` 字段也认作内容（老协议响应没有 delta.content）。

### 6.4 "完整"的假象——本期我最在意的一个

`ReadRequestTrace` 原来判断瀑布完整性靠的是数阶段：根 span 在、阶段数够，就算完整。但 OTel 导出是会丢的——摘要里明明白白记录着 `output.finished` 发生过，Jaeger 里这条 milestone 事件却可能永远没来。旧逻辑会把这样一棵缺了关键事件的树标成"完整"。

第 17 篇里我写过一句话：**空手而归和从未出发，在观测上是一样的。** 这次是同一个问题的另一面：摘要是独立于 OTel 导出落库的，它知道哪些里程碑"一定发生过"。所以修法是把摘要当成完整性判据——`output.finished`、`handler.finished`、`turn.finished`、`rpc.finished`、`output.first_content`，摘要证明发生过的，瀑布里找不到就如实标 `missing_*`，详情降级为 partial。观测系统自己的完整性，必须用一个不依赖被观测通道的证据来校验。

同批还修了：长流的根 span 开始时间可能是几小时前，用它算"过期年龄"会把刚导出完的 trace 误判成过期（现在用最晚的完成里程碑算）；截断首页没有根 span 时不再报 `trace_not_found`，而是 partial 加真实预算原因（`response_limit` 和 `span_limit` 分开）。

### 6.5 账单关联的分页死锁

`/api/log/{id}/trace` 把 `page_token` 吃掉了——一个预留关联超过 200 条观测时，第 201 条永远翻不到。更 subtle 的是 admin service 每次调用都重新生成 `EndTimeMs`，而 owner 存储的分页摘要是按第一页的时间上界算的，第二页带上新上界，游标校验直接失败。现在是透传游标，第一页的上界由 owner 从游标里恢复，整个分页期间看同一个预留快照。

### 6.6 panic 的"成功" span

结算 worker 有 panic 防护：recover 后记日志继续下一个任务。问题在于 defer 是 LIFO——`endTask(taskErr)` 的 defer 后注册先执行，panic 发生时它带着 nil 的 `taskErr` 把 span 收成了 `success`，recover 的 defer 之后才轮到。**一次 panic 的提交，在追踪里是一次完美的成功。** 修法是合成一个 defer：先 recover、记录失败，再结束 span，防护范围不变。

### 6.7 卡死任务的"reserved"假象

`settlement_current` 把 outbox 里 `invalid`（载荷损坏、已停止处理）的任务映射成 `reserved`——只要预留行还是 unknown，一个永远不会再被执行的结算在管理端看起来"活着且正常排队"。现在 `invalid` 一律显示 `failed`，已落账/已释放的仍然优先。

### 6.8 L1 缓存挂错位置

`MultiLevelCache.get` 的 L1 探测用 `requesttrace.Phase(ctx, "cache.l1")` 开了阶段，却把属性打到 `trace.SpanFromContext(ctx)`——父 span 上。结果是 L1 命中时请求在瀑布上看不到自己的鉴权/选路阶段。一行的事：用 Phase 返回的 `l1Ctx` 取 span。评审能抓出这个，靠的就是瀑布测试里"这个属性应该挂在哪根 span 上"的断言。

### 6.9 前端的四个边界

管理端瀑布也有四个展示 bug：取消和未完整输出与成功无法区分（现在如实显示输出终态）；"结束后处理"标记拿单轮结束时间比，WS 回合里把正常输出工作误标（改成按输出结束比）；多次观测选中一条后没有返回列表的路；候选已过期读不出来时死在报错页。最后两个用同一个"返回观测列表"动作收掉，观测列表顺带补了 `next_page_token` 翻页。

这一轮修完，每个问题都有一个"修之前红、修之后绿"的测试守着。我把它们和功能提交分成四个 fix 提交，根因和影响写进 commit body——半年后回看，这些比"fix bugs"四个字有用得多。

---

## 7. 现状与欠账

**现在看得见的：** 任意一次模型调用（HTTP/SSE/WS 轮/gRPC），从解析、鉴权、路由、准入、预占、上游、首内容、输出终态到提交/释放、日志的分阶段耗时；拒绝和提前返回同样有摘要；账单能翻到关联观测和当前结算状态；观测系统自身的丢失有四个告警盯着。

**明确看不见的：** 供应商内部排队和推理耗时（网关只能给实测等待）；客户端真正收到内容的时间；CDN/反代那段；48 小时后的完整瀑布（摘要还在，详情随 Jaeger TTL 过期）。

**欠着的账：**

第一，**容量实测只做完了低流量基线。** 分配和 CPU 的涨幅摆在那里，高峰和长 WS 连接的持续观测方案定了（对比开关前后的 P95/CPU/分配、按日记 Jaeger Badger 和 SQL 增长），但要等真实流量窗口，我不打算假装做完了。

第二，**观测覆盖有边界。** gRPC 在 RPC 归属建立前被连接层拒绝的事件只有连接级观测；进程崩溃不承诺追踪零丢失；共享批次只返回安全片段。

第三，部署后我注意到 admin-api 日志里有个每分钟一次的既有告警（`unpriced routed metric evaluation failed: PermissionDenied`）。排查结论：那个后台 worker 以无用户上下文调用一个策略要求 `UserCallers: ["admin"]` 的 RPC，注册表和 worker 都早于本次功能，与计时观测无关——但它确实是"后台调用方如何过 owner 授权"的一个遗留坑，记在这里，单独立项修。

---

## 8. 下一篇

这次从方案、实现、验收、部署到发布走完了完整一圈，中间还夹着两次工程插曲：pre-push 的 gosec 新版规则把已验证的 `client.Do` 标成 SSRF，CI 的 RBAC 矩阵因为源文件摘要漂移挡了一次发布。下一篇我想聊聊这个项目的发布流水线本身——一个个人项目为什么值得配一套带着迁移冒烟、矩阵契约、安全扫描和 E2E 门禁的 release 通道，以及这套通道真正拦住过的那些东西。
