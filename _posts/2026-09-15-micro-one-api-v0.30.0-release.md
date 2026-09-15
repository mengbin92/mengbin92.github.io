---
title: "Micro-One-API v0.30.0 发布：分组 v2 生产启用收口 —— 部署接线、可观测性、迁移预检与操作解释"
date: 2026-09-15T10:00:00+08:00
description: "micro-one-api v0.30.0 完成分组 v2 生产启用收口：部署模板接线并通过 MySQL / SQLite 真实链路验收，补齐路由与 outbox 可观测性及九项告警，管理台汇总 P95 由 380ms 降至 109ms 并诚实降级，迁移 runner 增加旧元数据表预检，管理台补齐分组操作与扣费解释链路。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

v0.30.0 是 v0.29.0 之后的 **MINOR 启用与稳定性收口版本**。v0.29.0 交付的分组重设计 v2（阶段 A–F）全部能力默认关闭、未经真实链路验收；本版按 [v0.30 阶段路线图](https://github.com/mengbin92/micro-one-api/blob/main/docs/design/v0.30-roadmap.md)完成 P0 / P1 / P2 三个优先级共 7 项任务：接通部署开关并完成 MySQL / SQLite 真实服务验收，补齐路由 / outbox 可观测性与告警，收口管理台汇总性能与降级语义，为迁移 runner 增加旧元数据表预检，并补齐分组日常操作与账务解释链路。

发布时生产 B–F 开关已全部开启，见[生产只读基线](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-baseline-2026-09-13.md)。

**关键特点**：无 proto 变更、无新增数据库迁移、无新增必填配置；新增配置断言与指标 / 告警均为 additive。唯一语义变化：`/api/admin/summary` 分项失败时由伪造零值改为返回 `null` 并携带 `partial` / `sections` / `alerts_complete` 状态（响应键保持稳定，前端已同步改造）。逐项根因、修复与影响服务的工程细节见 [release-v0.30.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.30.0.md)。

## 核心亮点

### 1. P0：部署接线与真实链路验收 —— 让分组 v2 可以真正跑起来

v0.29.0 只交付了代码，三种 Compose 与 Kubernetes 模板都没有注入分组 v2 开关，identity / billing 缺 channel RPC 地址，Lite / PostgreSQL relay 缺订阅数据库连接——照模板部署出来的环境根本用不了新能力。本版补齐了整条部署链路：

- 三种 Compose、Kubernetes 与示例环境变量完成 `ROUTING_*` / `BILLING_REQUEST_SNAPSHOT_V2` / `SUBSCRIPTION_ENTITLEMENTS_V2` 开关与依赖接线，新增配置渲染断言与分阶段 SELECT / RPC 只读预检；生产阶段 F 预检 43 项通过。
- ordered Responses 恢复时直接重新校验会话绑定组，不再被较早候选覆盖或阻断。
- channel 旧能力查询同时兼容 PostgreSQL BOOLEAN 与历史整数 enabled 字段。
- 新增隔离 MySQL / SQLite 真实服务验收：创建组到扣费、三种结算模式、会话、撤权、Redis 故障恢复与创建入口回退，接入共享 nightly / release E2E workflow。

**收益**：新环境按模板部署即得到分组 v2 全部依赖；真实服务链路（而非单测桩）验证了从建组到扣费的完整闭环。

### 2. P1-1：路由 / outbox 可观测性与告警 —— 失效第一次可见

路由失效事件此前只持久化，队列年龄、投递失败与扫描过时都不可见；订阅 worker 丢弃投递错误；能力拒绝与账务快照校验失败没有有界的定位信号。本版补齐观测面：

- 三个 outbox owner（identity / channel / subscription）统一暴露积压、最老消息年龄、投递成功 / 失败与扫描时间；未配置 Redis 仍可观察积压；订阅 outbox 补齐错误回调与 owner / operation / event_id 结构化日志。
- 权威 RPC 客户端错误计数、准入 reason 标签、快照内容 / 解析 / 绑定失败分别计数。
- 九项 Prometheus 告警与 Routing and Outbox Operations 看板（十个面板）；规则测试（故障触发 / 恢复 / 空闲 / 采集失效）接入共享 E2E 入口。
- MySQL / SQLite 验收断言真实 Prometheus 在 Redis 故障期间 firing、恢复后清除，且撤权 / 重新授权与结算断言保持正确。

**收益**：分组 v2 的运行状态有了生产级可观测性；出问题时先看告警和看板，而不是翻数据库猜。运行与处置见[可观测性 runbook](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-observability-runbook.md)。

### 3. P1-2：管理台汇总性能与降级语义 —— P95 从 380ms 到 109ms

`handleAdminSummary` 串行执行约 20 次独立 RPC，延迟逐个累加；聚合挂在入口请求 context 上，尾部调用继承临近过期的 deadline，健康后端也报 `DeadlineExceeded`；分项失败被替换为零值 / 空集，前端把「不可用」显示成真实的「零」。本版重做了聚合编排：

- 聚合下沉到 service 层 `LoadSummary`，受限并发执行：每请求最多 4 路、总预算 8 秒、分项预算 2 秒；客户端取消向下传播，失败分项不取消健康兄弟任务，无后台工作逃逸请求。
- 每个分项返回 `available` / `reason` 状态；失败字段编码为 `null` 并置 `partial` / `sections` / `alerts_complete`，不再伪造零值。
- 前端区分「暂无数据」与「数据暂不可用」：部分失败显示可重试横幅与失败分项名称。
- 同负载（每次 RPC 固定 20ms、12 次请求）P95 由 380.5ms 降至 109.3ms，单请求 RPC 峰值并发 1 → 4。

**收益**：管理台概览快了 3 倍以上，且降级路径诚实——坏掉的分项明说坏掉，不再用零值冒充数据。

### 4. P1-3：旧迁移记录表升级预检 —— 把半完成迁移挡在业务 DDL 之前

旧 `schema_migrations` 表可能将 `applied_at` 定义为 `NOT NULL` 且无默认值，而 runner 执行完每个迁移后仅插入 `version`；MySQL 上可能先提交业务 DDL 再在元数据插入处失败，留下未记账的半完成迁移。本版把这类风险前置拦截：

- `Runner.Apply` 在 brownfield 标记和首个业务 DDL 之前，用事务内插入 / 回滚探针验证 `schema_migrations (version)` 写法；不兼容的旧表得到可操作的 `preflight schema_migrations` 错误，并提示半完成迁移的人工恢复步骤。
- `Runner.Status` 改为严格只读：元数据表不存在时全部报告 pending，不再初始化元数据表。
- MySQL / PostgreSQL migration smoke 与 SQLite 单测覆盖阻断、修复后升级、重复执行 no-op 与半完成显式恢复；runner 不根据同名对象自动补录。

**收益**：brownfield 环境升级迁移时，元数据表问题在改库之前暴露并给出修复指引，不再产生「DDL 已提交但没记账」的暗伤。

### 5. P2：分组日常操作与账务解释 —— 把「为什么这么扣费」讲清楚

试用反馈显示新组接线、有效价格和冻结扣费证据难以从现有页面解释。本版补齐解释链路：

- 分组详情补齐新组启用检查：资源成员、价格解析、能力版本与价格闸门、启用后的授权要求；资源为空仅提示操作风险，不替代后端权威闸门。
- 新增管理员只读接口 `GET /api/v1/admin/routing-access/{user}/available`（additive），返回目标用户当前有效访问来源、模型、有效倍率、价格来源 / 版本、结算模式与订阅覆盖状态。
- 用户授权弹窗展示授权来源（admin / migration / subscription / public）、有效倍率、用户专属价格与订阅覆盖；Token 页面同步展示有效倍率与用户专属标识。
- 调用日志详情解析 v2 冻结请求快照，展示路由选择、策略版本、有效倍率、计价方式、订阅证据与订阅 / 钱包分账；无快照的历史账单明确不可反推，不反造证据。

**收益**：运营和客服可以在管理台自助回答「这个用户为什么走这个组、为什么按这个价格扣费」，不用再查库对账。

## v0.30 任务总览

| 优先级 | 任务 | 状态 |
|--------|------|------|
| P0 | 部署接线与真实链路验收 | ✅ |
| P1-1 | 路由 / outbox 可观测性与告警 | ✅ |
| P1-2 | 管理台汇总性能与降级语义 | ✅ |
| P1-3 | 旧迁移记录表升级预检 | ✅ |
| P2 | 分组日常操作与账务解释 | ✅ |

验收记录与脱敏证据见 [p1-acceptance-2026-09-15](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/p1-acceptance-2026-09-15.md) 与 [routing-ops-experience-2026-09-15](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-ops-experience-2026-09-15.md)。

## 升级步骤

```bash
# 拉取版本
git fetch --tags
git checkout v0.30.0
```

1. **无需执行新迁移**。如环境存在历史 `schema_migrations` 旧表，先运行 `migrate -status`（现为严格只读）核对 pending；runner 预检会在业务 DDL 前阻断不兼容表并给出修复指引。
2. 本地交叉构建 `linux/amd64` 镜像（**不在资源受限服务器上构建**）：本次涉及 `relay-gateway`、`identity-service`、`channel-service`、`billing-service`、`admin-api`，可用 `scripts/deploy-update.sh relay-gateway identity-service channel-service billing-service admin-api` 一次完成。
3. 重新构建并同步前端 `web/dist`（前端经 `/opt/web/dist` 挂载提供，重建镜像不会更新前端）。
4. 部署新增的 Prometheus 告警规则（`deploy/prometheus/alerts/alerts.yml`）与 Grafana 看板（`deploy/grafana/dashboards/routing-operations.json`），按[可观测性 runbook](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-observability-runbook.md) 验证告警链路。

## 兼容性说明

- **API / proto**：无 proto 变更；新增唯一 HTTP 端点 `GET /api/v1/admin/routing-access/{user}/available` 为 additive 只读接口。
- **数据库**：无新增迁移。迁移 runner 行为变化：旧的不兼容 `schema_migrations` 表会在业务 DDL 前被预检阻断并给出修复指引，需按提示为 `applied_at` 补默认值后继续。
- **配置**：无新增必填配置；三种 Compose / Kubernetes 模板现在注入分组 v2 相关开关，默认值保持关闭，行为与 v0.29.0 默认路径一致。
- **可观测性**：新增指标、告警规则与 Grafana 看板均为 additive；无外部 Alertmanager 链路变更。
- **admin summary 语义**：分项失败由零值改为 `null` + 状态字段，响应键保持稳定；依赖旧零值行为的消费方需同步调整（仓库内前端已改造）。
- **回滚**：镜像回滚前为线上镜像打 `rollback-<ts>` 标签即可；无迁移需要回退。已按 runbook 打开的开关须先反向关闭再回滚镜像。

## 适合哪些场景

v0.30.0 特别适合以下团队：

- **正在或计划启用分组 v2**：部署模板开箱即接线，真实链路验收背书
- **生产运维需要可观测性**：outbox 积压、投递失败、路由准入拒绝都有指标和告警
- **管理台数据量大**：汇总接口 P95 3 倍以上提速，降级语义诚实
- **brownfield 老库升级**：迁移预检把元数据表问题挡在业务 DDL 之前
- **需要解释扣费依据**：管理台自助展示路由选择、有效价格与冻结快照证据

## 完整变更日志

- docs(runbooks): merge the three P1 acceptance records
- feat(admin): explain routing operations and charges
- fix(migrate): preflight legacy metadata before DDL
- perf(admin): bound admin summary fan-out and surface partial failures
- feat(observability): complete v0.30 routing and outbox operations
- fix(routing): close P0 deployment and acceptance gaps

## 项目简介

`micro-one-api` 是一个基于 Go Kratos 的多服务 AI API 网关与管理系统。它参考了 one-api 的多渠道 OpenAI API 分发思路，也借鉴了 sub2api 在订阅额度窗口、账号池、限流和用量管理上的场景经验，将用户鉴权、渠道管理、钱包账务、日志监控和管理后台拆分成清晰的微服务。

如果你正在维护多个上游模型渠道，希望统一 API 入口、统一用户 Token、统一钱包余额和用量记录，并且希望系统后续具备更强的可维护性与扩展性，这个项目可以作为一个参考实现。

- GitHub 仓库：[mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
- 本次发布：[v0.30.0 Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.30.0)
- 详细发布公告：[release-v0.30.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.30.0.md)
