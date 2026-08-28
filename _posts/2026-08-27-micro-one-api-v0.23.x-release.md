---
title: "Micro-One-API v0.23.x 发布：Executor 灰度架构落地与全链路可靠性加固"
date: 2026-08-27T09:00:00+08:00
description: "micro-one-api v0.23.x 系列为 relay-gateway 引入 transport-neutral executor 执行层，通过 token allowlist 灰度门禁完成新旧路径验证，并持续加固渠道健康、用量日志安全、协议兼容与失败边界。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

`micro-one-api` v0.23.x 系列（v0.23.0 / v0.23.1 / v0.23.2）是项目在 relay-gateway 执行架构上的一个重要里程碑。这个系列为 `/v1/chat/completions` 与 `/v1/responses` 引入了一套 **transport-neutral 的 executor 执行层**，并通过 token allowlist 灰度门禁、失败矩阵测试和生产 canary 观察，在小流量、可回滚的前提下完成了新旧路径的验证与切换准备。与此同时，三个补丁版本持续加固了渠道健康、用量日志安全、协议兼容和失败边界。

**关键特点**：executor 灰度默认关闭（`RELAY_ORCHESTRATOR_ENABLED=false`），未命中 allowlist、关闭开关或未覆盖的传输仍走旧 handler，行为零变更。全系列 **无数据库迁移、无公共 API / proto 破坏性变更**。

## 核心亮点

### 1. Transport-Neutral Executor —— 拆开 relay handler 的“一肩挑”

在 v0.22 及更早的架构中，relay handler 同时承担 HTTP 传输、上游转发和 quota 结算编排三件事，任何小改动都会牵动整条提交链路，也无法在不复制扣费请求的前提下做小流量验证。v0.23.0 引入了一组传输无关的执行端口：

- `Executor` / `Planner`：编排一次请求的执行计划
- `QuotaPort`：金额预扣、Release、Commit 的生命周期
- `Forwarder`：经 adaptor registry 统一处理 API-key 与订阅凭据的上游转发
- `EventLogger`：用量日志写入边界

`/v1/chat/completions`（v0.23.0 非流式）与 `/v1/responses`（v0.23.2 流式）通过 adaptor registry 路由到 executor，staging 路径由两道门禁保护：

```bash
# 默认关闭
RELAY_ORCHESTRATOR_ENABLED=false
# 只保存 bearer token 的 SHA-256 摘要，不保存原始 token
RELAY_ORCHESTRATOR_TOKEN_SHA256=<sha256-of-staging-token>
```

```bash
# 在安全环境计算摘要，只把输出写进配置
printf %s "$STAGING_TOKEN" | sha256sum
```

关闭开关或清空 allowlist 即回退旧 handler，回滚不需要动数据。

**收益**：结算编排与传输解耦，新路径可以只放行内部 allowlist token 的小流量，与旧路径逐指标对照；v0.23.2 的生产 canary 已累计 106 个 Responses 成功样本，quota 生命周期闭合。

### 2. Failover 与 Quota 生命周期 —— 不让任何一次扣费处于不确定状态

executor 首切片补齐了完整的失败候选结算语义：

- 失败候选执行 Release，成功候选只 Commit / Log 一次，重试请求使用独立 request ID 保证幂等
- 上游已成功后的结算错误（post-forward failure）标记为终态，**不污染渠道健康**，也不继承网络重试语义
- 上游错误体映射为 client-safe 消息并限制大小，内部错误不再直接透传给客户端
- 补齐 reserve 失败、context cancel、无候选、commit 失败、健康回写失败、日志写入失败的黄金路径 / failover 测试矩阵

**收益**：金额预扣在任何失败路径上都有确定的 Release 或 Commit 归属，从架构层面消除重复结算与悬挂预留的风险。

### 3. 渠道健康隔离 —— 单模型故障不再拖垮整个渠道

v0.23.1 修复了一个生产中真实踩到的坑：同一请求的多次 retry 按 attempt 重复记录渠道健康失败，上游只对单个模型返回“无健康节点”时，渠道级熔断阈值被重试快速打满，同渠道其他模型也被路由排除。

修复后：

- 同一请求内同一来源的多次 retry 合并为一次终态健康结算
- 明确识别模型范围故障并保留 fallback，不推进渠道级熔断
- 修复重复减少选择器 `inflight` 的问题
- monitor-worker 的 `/models` 主动探测要求响应为包含数组形态 `data` 或 `models` 字段的 JSON，上游返回 HTML 200（如被劫持页）时记为 `invalid_response` 失败，不再误判健康

**收益**：健康反馈链路按“请求 × 终态”粒度结算，模型级故障与渠道级故障清晰分层。

### 4. 凭证隔离 —— Authorization 永远进不了用量日志

v0.23.1 关闭了 CodeQL #277 指出的风险：transport-neutral executor 曾把包含 headers、body 和 bearer token 的完整请求传入用量日志接口。现在日志边界只传递模型、端点、请求 ID 和流式标记，event logger adapter 再加一道二次过滤，并有回归测试锁定 `Authorization` 等敏感字段不会进入日志钩子。

**收益**：请求凭证在架构边界上被物理隔离，而不是依赖“记得别打日志”。

### 5. Responses → Anthropic 协议桥 —— 修复本地误报 502

v0.23.2 修复了 staged executor 的一个协议兼容问题：`/v1/responses` 请求经 orchestrator 选择 Anthropic API-key 渠道（如 StepFun `step-explore`）时，adaptor 只接受原生 Messages，请求尚未发往上游就在本地转换阶段失败，被统一映射为 HTTP 502。

现在在 adaptor 边界补齐了三段转换：

- Responses 请求 → Anthropic Messages 请求
- Anthropic 非流式响应 → Responses 响应
- Anthropic SSE → Responses SSE

并继续裁剪第三方 Messages 端点不普遍支持的 `thinking`、`output_config` 和 server-tool `type` 扩展。生产 canary 已获得 14 个 StepFun Responses 成功样本，旧的 25–70ms 本地 502 未再复现。

### 6. Relay Playground —— 不写盘的在线调试入口

v0.23.2 在管理后台发布了受控的 Relay Playground：内存态 token（不写入 localStorage、sessionStorage 或 URL）、模型发现、Chat Completions 调用、SSE 解析、请求检查、取消与错误映射。Relay 路由配套安装无凭证 CORS 和 request tracing，生产环境 CORS 默认 **fail closed**，启用时需显式配置可信来源。

**收益**：管理员和用户可以在控制台直接验证 Relay 链路，不必再为调试拼 curl。

## 适合哪些场景

v0.23.x 特别适合以下团队：

- **计划重构 relay 转发层**：executor 端口 + allowlist 灰度提供了可复制的“新旧路径对照切换”范式
- **对账务正确性敏感**：quota 生命周期在每个失败分支都有确定语义，且有测试矩阵背书
- **多渠道多模型运营**：模型级故障隔离 + 主动探测响应校验，渠道健康信号更可信
- **合规与日志审计要求高**：凭证在日志边界物理隔离，CORS 生产默认 fail closed
- **接入 Anthropic 系兼容渠道**：Responses → Messages 协议桥覆盖 StepFun 等 API-key 渠道

## 兼容性说明

- **API / proto**：无公共 API 或 proto 破坏性变更；旧 handler 与 WebSocket 路径保留
- **数据库**：全系列无新增迁移，无需执行 `make migrate`
- **配置**：新增 `RELAY_ORCHESTRATOR_ENABLED`（默认 `false`）、`RELAY_ORCHESTRATOR_TOKEN_SHA256`（默认空 allowlist，仅存 SHA-256 摘要）与可选 `RELAY_GRPC_ADDR`；全部默认值保持旧行为
- **路由行为**：只有开关开启且 token 命中 allowlist 的请求进入 executor；其余继续走旧路径
- **部署范围**：v0.23.1 需更新 `relay-gateway` 与 `monitor-worker`；v0.23.2 需更新 `relay-gateway`，使用 Playground 时同步发布 `web/dist`

## 升级步骤

```bash
git fetch --tags
git checkout v0.23.2
```

1. 备份当前 relay 镜像与 `web/dist`；确认数据库无需迁移。
2. 按既有跨平台构建流程部署 `relay-gateway`（以及 v0.23.1 涉及的 `monitor-worker`），不要在生产主机上构建镜像。
3. 保持 `RELAY_ORCHESTRATOR_ENABLED=false` 完成基础健康检查。
4. 如启动 executor 灰度，在安全环境计算 token 摘要并写入 allowlist，仅对内部 token 开启，按 endpoint / stream 分组对照 success、5xx、P95、quota outcome 和 failover 指标，连续观察至少 7 天。
5. 回滚时关闭开关或清空 allowlist 后重建 relay 容器；全系列不涉及数据库回滚。

## 验证与测试

- `make verify`（unit、race、architecture、migration-check、frontend lint/test/build）通过
- Web Playwright：35 passed、1 skipped
- executor staging 失败矩阵覆盖 reserve 失败、context cancel、无候选、commit 失败等全部分支；allowlist 清空回滚有回归测试
- 生产 canary：Responses 累计 106 success / 2 error；StepFun Responses 14 success，单次 502 后连续约 47 分钟无复现；P95 收敛至约 59.7s，quota 生命周期闭合且无 failover

## 完整变更日志

### v0.23.2

- feat(relay): add streaming executor staging
- fix(relay): bridge responses through anthropic api-key channels
- fix: harden relay failure boundaries
- fix(config): make relay gRPC address configurable
- feat(web): add relay playground
- fix(relay): resolve playground issues after launch

### v0.23.1

- fix(security): keep request credentials out of usage logs
- fix(relay): isolate model outages from channel health
- test(config): avoid secret scanner false positive

### v0.23.0

- feat(relay): gate executor staging by token allowlist
- refactor(relay): add transport-neutral executor ports
- refactor(relay): route executor through adaptor registry
- feat(relay): add executor failover settlement
- fix(relay): sanitize executor error responses
- fix(admin): prevent cost chart label overlap

## 项目简介

`micro-one-api` 是一个基于 Go Kratos 的多服务 AI API 网关与管理系统。它参考了 one-api 的多渠道 OpenAI API 分发思路，也借鉴了 sub2api 在订阅额度窗口、账号池、限流和用量管理上的场景经验，将用户鉴权、渠道管理、钱包账务、日志监控和管理后台拆分成清晰的微服务。

如果你正在维护多个上游模型渠道，希望统一 API 入口、统一用户 Token、统一钱包余额和用量记录，并且希望系统后续具备更强的可维护性与扩展性，这个项目可以作为一个参考实现。

## 下一步

后续版本计划包括：

- 扩大 executor 灰度范围，完成新旧路径全量对照后切换默认路径
- 完善渠道健康检查和自动熔断
- 强化用量统计、成本分析和对账能力
- 增加 Codex 场景下 Anthropic `/v1/messages` 代理适配的完整性
- 完善前端运营体验和可观测性面板
- 加强生产部署文档、安全基线和高可用方案

欢迎关注、试用和参与改进：[github.com/mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
