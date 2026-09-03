---
title: "Micro-One-API v0.24.0 ~ v0.26.5 发布：从双语控制台到可审计计费"
date: 2026-09-02T10:00:00+08:00
description: "micro-one-api v0.24.0 到 v0.26.5 完成双语控制台、用户协议和隐私协议、模型定价注册表、五桶用量语义、定价快照、Go 1.27 工具链、Relay 路由、控制台性能与 Responses 来源归因的持续演进。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

## 摘要

本文整理 `micro-one-api` 从 v0.24.0 到 v0.26.5 共 8 个版本的发布内容。这个周期先完成控制台可用性、双语界面与用户协议和隐私协议基础，随后补齐模型模态与每 1M tokens 定价注册表，再进入用量语义与计费审计的核心建设，最后收口 Go 1.27 工具链、Relay 路由、控制台性能和 Responses 来源归因。范围覆盖 `v0.23.3..v0.26.5`，共 436 个文件变更、+18.1k/-5.7k 行。

整个周期没有公共 API / proto 破坏性变更，但包含 `083`–`089` 数据库迁移、Go 1.27 工具链要求、canonical usage 灰度开关以及多个 executor / canonical observe 观察窗口约束。v0.26.2 tag 未产出完整 Release 制品，实际部署应使用包含同等修复的 v0.26.3 或更新版本。

## 版本总览

| 版本 | 日期 | 类型 | 关键词 |
|------|------|------|--------|
| [v0.24.0](#v0240) | 2026-08-31 | MINOR | 双语控制台、用户协议和隐私协议、可访问性重构 |
| [v0.25.0](#v0250) | 2026-08-31 | MINOR | 模型模态、cache-read 定价、每 1M tokens |
| [v0.26.0](#v0260) | 2026-08-31 | MINOR | 五桶用量语义、定价快照、可审计计费 |
| [v0.26.1](#v0261) | 2026-08-31 | PATCH | Go 1.27、全服务工具链现代化 |
| [v0.26.2](#v0262) | 2026-08-31 | PATCH | 未完成发布，由 v0.26.3 替代 |
| [v0.26.3](#v0263) | 2026-09-01 | PATCH | Relay 模型路由、双语文案、发布门禁 |
| [v0.26.4](#v0264) | 2026-09-01 | PATCH | 页面切换性能、静态缓存、索引 089 |
| [v0.26.5](#v0265) | 2026-09-02 | PATCH | Responses 来源归因、observe 保窗 |

---

## v0.24.0

> 2026-08-31 · 上一版：[v0.23.3](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.23.3.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.24.0)

v0.24.0 是 **MINOR Web 体验与运营基础版本**。它重构用户端与管理端的设计基础，新增全局中英文界面、响应式登录 / Playground 流程和语义化图表，并为中国大陆部署补齐用户协议、隐私政策、注册显式同意与运营主体配置。

本版本无数据库迁移、无公共 API / proto 破坏性变更，也不新增 relay 运行时行为。受影响运行时仅为 `admin-api` 与 `web/dist`。

### 亮点

- **可访问性设计重构**：统一字体、颜色、间距、阴影、动效、焦点态、加载 / 空状态和表格 / 卡片模式，覆盖用户控制台与管理后台主要页面。
- **全局中英文界面**：新增持久化 locale 状态、语言切换、英文长尾文案与数字 / 日期本地化；默认语言仍为 `zh-CN`。
- **用户协议和隐私协议**：新增公开 `/terms`、`/privacy`，注册流程要求显式同意；`/api/status` 公开运营者名称、注册地址和隐私联系邮箱三项可选字段。
- **Claude 工具链回归**：将 Anthropic native SSE 测试升级为分片 `Edit` 工具调用，验证 `file_path`、`old_string`、`new_string` 的跨分片顺序与完整性。

### 兼容性与部署

- 无新增迁移；法律主体配置复用系统选项存储。
- 对外开放注册前，必须在系统设置填写真实运营主体与专用联系邮箱，不得使用发布测试占位值。
- executor observation 期间不要构建、加载、重建或重启 `relay-gateway`。
- 升级范围：`admin-api` 与 `web/dist`。

### 完整变更日志

- feat(web): establish accessible design foundation
- feat(web): migrate console surfaces and status details
- feat(web): refine dashboards and semantic charts
- feat(web): redesign authentication and playground workflows
- docs: document completed web redesign
- feat(web): refresh Micro-One API logo
- feat(web): enable bilingual interface
- feat(web): add China legal agreements
- fix(web): complete bilingual legal consent
- test(relay): cover fragmented edit tool input
- docs: prepare v0.24 release candidate

---

## v0.25.0

> 2026-08-31 · 上一版：[v0.24.0](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.24.0.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.25.0)

v0.25.0 是 **MINOR 模型能力与定价注册版本**。模型管理和导入导出支持输入 / 输出模态与 cache-read 价格，注册表价格统一为每 1M tokens，并为 MySQL、PostgreSQL、SQLite 提供迁移与旧 MySQL 默认值兼容。

本版本包含兼容性新增的公共 channel API 字段，以及数据库迁移 `083`、`084`。影响 `channel-service`、`admin-api`、`web/dist` 与数据库。

### 亮点

- **模型模态与 cache-read 定价**：模型详情、摘要、创建 / 更新请求和导入导出新增 `input_modalities`、`output_modalities`、`pricing_cache_read`。
- **统一价格单位**：历史非零 `pricing_input` / `pricing_output` 从每 1K tokens 换算为每 1M tokens，扩大价格列精度并新增 cache-read 列。
- **三数据库迁移兼容**：`083` 增加模态列，`084` 处理价格列与历史数据转换，并兼容旧 MySQL 默认值路径。
- **上游成本展示修复**：成本页统一 provider key 归一化，稳定匹配不同大小写和分隔格式。

### 兼容性与部署

- 新增 API 字段均为可选字段，旧客户端可继续工作。
- 迁移必须按 `083 → 084` 执行；`084` 会改写历史价格，重复执行或手工重复换算会造成错误。
- 升级前备份数据库，并记录迁移版本与现有模型价格。
- 部署顺序：数据库迁移 → `channel-service` → `admin-api` → `web/dist`。

### 完整变更日志

- fix(models): link pricing and multimodal metadata
- fix(migrations): support legacy mysql defaults
- feat(models): align modalities and registry pricing
- fix(web): update user pricing modalities
- fix(web): render upstream cost key formats correctly

---

## v0.26.0

> 2026-08-31 · 上一版：[v0.25.0](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.25.0.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.0)

v0.26.0 是本周期最核心的 **MINOR 用量语义与计费审计版本**。它把上游 reported usage 与规范五桶计费值分离，为 ambiguous 语义增加隔离和候选成本审计，冻结每笔消费的定价证据，并在管理端展示完整证据链。

本版本包含数据库迁移 `085`–`088`，影响 `relay-gateway`、`billing-service`、`log-service`、`channel-service`、`admin-api`、`web/dist` 与部署配置。

### 亮点

- **统一五桶用量语义**：解析层按协议证据输出互斥的 `uncached_input`、`cache_read`、`cache_creation_5m`、`cache_creation_1h`、`output`，并标记 verified / estimated / ambiguous；无法证明语义时保留候选，不用算术关系静默推断。
- **语义隔离与账本证据**：billing ledger 与 usage log 保存 reported / billable totals、五桶、protocol、field shape、parse status、contract version、decision reason 与候选成本；channel-service 支持按执行来源、上游模型和 adapter 协议隔离连续 ambiguous 来源。
- **定价快照**：新增 `billing_pricing_snapshots` 和 `billing_ledgers.pricing_config_hash`，同事务记录当时的输入、输出、cache-read、cache-creation 单价、倍率与计费模式，相同 hash 幂等复用。
- **五桶审计界面**：管理端用量详情展示五桶 token / 单价 / 成本、双口径 total、语义状态、候选成本、pricing hash、倍率与 cache-creation mode；历史行明确标记 legacy。
- **灰度门禁**：`BILLING_CANONICAL_USAGE_MODE` 支持 `legacy`、`observe`、`charge`，`RELAY_CANONICAL_USAGE_PRODUCER` 默认关闭，避免 producer / consumer 不匹配。

### 兼容性与部署

- 公共 API 变更均为兼容性新增；展示口径可能从单一 total 变为 reported / billable 双口径。
- 迁移必须按 `085 → 086 → 087 → 088` 顺序执行。
- 历史数据默认 `usage_parse_status=legacy`，不会根据旧 token 数字关系自动回填语义。
- `088` 只冻结定价证据，不改变当时计费金额；billable total 不能继续简单等同于 reported total。
- 先保持 canonical usage observe 且 relay producer 关闭，核对分布、候选成本、隔离来源和 snapshot hash 后再按审批推进。
- executor observation 期间不要部署或重启 `relay-gateway`。

### 完整变更日志

- feat(billing): enforce parser-proven usage semantics and auditable five-bucket billing
- refactor(usage): unify inclusive usage projection behind pkg/usage
- feat(billing): freeze per-request pricing snapshots on consume ledgers (088)
- feat(admin): five-bucket usage audit view with frozen pricing evidence
- docs(design): record usage-semantics phase 2 implementation status
- fix(billing): harden usage audit remediation
- fix(deploy): pass canonical usage producer gate

---

## v0.26.1

> 2026-08-31 · 上一版：[v0.26.0](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.0.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.1)

v0.26.1 是 **PATCH Go 1.27 工具链与仓库现代化版本**。项目统一到 Go 1.27，采用 `any`、整数 range、`min` / `max`、slices/maps 辅助函数等语法，升级兼容依赖，并修复 middleware 测试的 goroutine 清理问题。

本版本无公共 API / proto 变更、无数据库迁移。由于工具链改动覆盖所有 Go 服务，除 relay 观察约束外，其余服务镜像需要整体滚动更新。

### 亮点

- **统一 Go 1.27**：`go.mod`、Dockerfile、CI 与代码风格对齐 Go 1.27。
- **现代化 Go 实现**：减少旧式 `interface{}`、手写集合处理和可替代循环，同时保持 provider JSON `omitempty` 契约。
- **测试与文档收口**：修复 middleware idempotency 测试 goroutine 清理，同步运行时和依赖文档。

### 兼容性与部署

- 本地 / CI 必须使用 Go 1.27，并继续交叉构建 `linux/amd64` 镜像。
- 按显式服务列表滚动更新 `admin-api`、`identity-service`、`channel-service`、`billing-service`、`config-service`、`log-service`、`monitor-worker`、`notify-worker`。
- 不使用宽泛 Compose 命令，不在资源受限生产服务器构建镜像。
- executor observation 期间不部署或重启 `relay-gateway`。

### 完整变更日志

- refactor: modernize Go codebase for Go 1.27 toolchain
- docs: align runtime and dependency references
- test: clean up Go 1.27 middleware goroutine
- docs(observation): record executor window restart
- docs(observation): record canary restart interruption
- docs(observation): record executor observation snapshot after restart
- docs(observation): record second canary day
- docs(observation): record first chat canary samples
- docs(observation): record manual executor review

---

## v0.26.2

> 2026-08-31 · 上一版：[v0.26.1](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.1.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.2)

v0.26.2 是 **PATCH Relay 路由与 Web 界面修复版本**，包含模型标识归一化、显式渠道映射优先级和中英文文案同步。但该 tag 的 Release workflow 未完成，未产出完整 GitHub Release 和多架构镜像。

**部署提示**：不要移动或复用 v0.26.2 tag；请直接部署完整包含其变更的 [v0.26.3](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.3.md) 或更新版本。

### 亮点

- 在 Relay 边界剥离末尾 `[1M]` 标记，模型精确映射、白名单和能力检查大小写不敏感。
- 渠道显式 `model_mapping` 优先于 `upstream_model_id` 和渠道模型列表 fallback。
- 导航、分页、Token、用量、渠道、日志、法律页面等文案统一接入共享翻译目录。
- 无公共 API / proto 变更、无数据库迁移。

---

## v0.26.3

> 2026-09-01 · 上一版：[v0.26.2](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.2.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.3)

v0.26.3 是替代未完成 v0.26.2 的 **PATCH 修复版本**。它完整包含 Relay 模型标识归一化、显式渠道模型映射优先级和中英文界面同步，并修复生成 API 类型与本地化 E2E 定位器导致的 Release 门禁失败。

本版本无公共 API / proto 变更、无数据库迁移。运行时影响为 `relay-gateway` 与 `web/dist`；若前端由 `admin-api` 托管，则还需更新对应托管方式。

### 亮点

- **统一 Relay 模型标识**：`[1M]` 不再泄漏到路由、计费或上游请求；大小写差异不再导致模型权限、渠道选择、重试 / failover、WebSocket sticky route、OneAPI proxy 或 gRPC 路径失配。
- **恢复显式映射优先级**：先应用渠道显式 `model_mapping`，再使用 `upstream_model_id` 与渠道模型列表，保证渠道配置的上游模型拼写被保留。
- **完整双语界面**：补齐硬编码中英文文案、无障碍标签和动态消息，并使用完整句子占位符避免翻译片段粘连。
- **Release 门禁修复**：重新生成并提交 36 个 canonical usage Web 类型字段；E2E 关键定位器改为中英文兼容表达式。

### 兼容性与部署

- 已有大小写不同的模型映射和白名单可以统一命中；显式 `model_mapping` 按文档优先。
- 客户端末尾 `[1M]` 仅作为扩展上下文提示，不会发送给上游或作为计费模型名。
- v0.26.2 未产出完整制品；从 v0.26.1 或 v0.26.2 直接升级到 v0.26.3。
- 更新 `relay-gateway` 与 `web/dist`；主机静态目录挂载 `/opt/web/dist:/web:ro` 时，前端更新无需重启容器。

### 完整变更日志

- fix(web): align generated types and localized E2E
- fix(relay): honor explicit channel model mapping
- fix(relay): normalize model routing identifiers
- fix(web): synchronize bilingual interface copy

---

## v0.26.4

> 2026-09-01 · 上一版：[v0.26.3](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.3.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.4)

v0.26.4 是 **PATCH 控制台性能修复版本**。诊断确认服务端响应并不慢，页面打开约 1 秒延迟主要来自前端资源加载与请求瀑布：懒加载页面先下载 JS 再请求 API、图表公共包被非图表页面预加载、哈希资源缺少长期缓存与压缩、导航与页面重复请求账户数据。

本版本包含数据库迁移 `089`（仅新增联合索引），需要配套更新 `admin-api`、`web/dist` 并应用迁移；`relay-gateway` 及其余服务无变更。

### 亮点

- **静态资源缓存与 gzip**：带哈希 `/assets/*` 返回一年 `immutable` 缓存；文本资源按 `Accept-Encoding` 协商 gzip，同时保留 `gzip;q=0`、Range、WOFF2 与 404 边界语义。
- **图表依赖隔离**：移除 `charts` 与兜底 `vendor` 公共分包，recharts/d3 只随实际图表页动态加载，登录首屏图表资源为 0。
- **路由预取与查询复用**：导航悬停 / 聚焦预加载目标路由模块；导航、Dashboard、个人资料、充值、兑换共享 `/user/self` 与账户概览缓存；登录 / 退出清空 React Query 缓存。
- **权限闪现修复**：`AdminRoute` 不再信任 `localStorage.userRole`，以共享 `/user/self` 查询作为权限唯一来源。
- **Dashboard 聚合索引**：迁移 `089` 为 `billing_ledgers` 新增 `(user_id, type, created_at)` 联合索引，覆盖 MySQL / PostgreSQL / SQLite。

### 兼容性与部署

- 无公共 API / proto 变更；`089` 仅新增索引，无数据改写。
- `admin-api`、`web/dist`、迁移 `089` 需要配套发布。
- 哈希资源改为一年 immutable 后，前端回滚场景可能需要强制刷新；正常内容哈希升级不受影响。
- executor observation 期间仍不要重启 `relay-gateway`。

### 完整变更日志

- perf(web): eliminate page-switch latency from asset waterfalls

---

## v0.26.5

> 2026-09-02 · 上一版：[v0.26.4](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.26.4.md) · [GitHub Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.26.5)

v0.26.5 是 **PATCH Relay 计费归因修复版本**。它修复 legacy `/v1/responses` 与显式 OneAPI 渠道成功结算时遗漏 `source_kind` / `upstream_model_id` 的问题，使 canonical usage observe 记录能够还原实际上游来源和定价模型；同时修正 release note 提交被 commit-body 门禁误报的 CI 规则。

本版本无公共 API / proto 变更、无新增迁移、无新增配置。从 v0.26.4 升级无需重复迁移；从更早版本升级需先应用至 `089`。

### 亮点

- **Responses 成功结算补齐来源**：12 个 legacy Responses 成功结算分支统一应用渠道输入，覆盖流式 / 非流式、直连 / fallback 和 previous-response stored-route。
- **显式 OneAPI 渠道归因**：成功结算写入 `source_kind=channel` 与渠道 `upstream_model_id`，不改变 Token 计数、价格、扣费模式、路由选择或对外响应。
- **Release CI 修复**：`docs(release)` 纳入 title-only 平凡提交豁免，非平凡代码提交仍必须带根因与影响说明。
- **observe 保窗**：生产已运行等价紧急修复镜像时，发布 tag 不要求替换镜像或重启容器，避免中断 48 小时 canonical observe。

### 兼容性与部署

- 未运行修复的环境仅更新 `relay-gateway`。
- 已运行 2026-09-02 紧急修复镜像的生产环境，在 observe 满窗前不为替换 tag 镜像而重启。
- 若回滚到 v0.26.4，应同时关闭 `RELAY_CANONICAL_USAGE_PRODUCER`，避免继续生成缺失来源的 observe 记录。
- 验证新 Responses / OneAPI 成功记录的来源字段、pricing hash、dedupe key，以及 billing / log 归因一致性。

### 完整变更日志

- fix(ci): exempt release-notes commits from body gate
- fix(relay): restore Responses source attribution

---

## 整体升级路径（v0.23.3 → v0.26.5）

如果从 v0.23.3 或更早版本直接升级，建议按版本链路理解变更，但可以以 v0.26.5 为最终目标执行一次配套升级。必须先完成备份和变更窗口评估，再按以下顺序操作。

### 1. 数据库迁移

迁移必须严格按序执行，不得跳版本或重复执行数据改写迁移：

```text
083 → 084 → 085 → 086 → 087 → 088 → 089
```

重点风险：

- `084` 会把历史每 1K tokens 价格换算为每 1M tokens；重复换算会导致价格错误。
- `085`–`088` 引入用量语义、隔离表和定价快照；历史数据保持 legacy，不做自动语义回填。
- `089` 仅新增 Dashboard 聚合索引；schema 拆分部署时需应用到 billing ownership。

### 2. 构建与服务更新

所有镜像应在本地或 CI 交叉构建 `linux/amd64`，不在资源受限生产服务器构建。建议顺序：

1. 备份数据库、当前镜像、配置和 `/opt/web/dist`。
2. 应用数据库迁移并记录迁移版本。
3. 更新 `channel-service`、`billing-service`、`log-service`。
4. 更新 `admin-api` 并同步发布 `web/dist`。
5. 更新 `identity-service`、`config-service`、`monitor-worker`、`notify-worker`。
6. 在满足 executor / canonical observe 约束后，最后评估并更新 `relay-gateway`。

每个服务使用显式列表执行 `docker compose up -d --no-deps <service>`，不要使用宽泛的 `docker compose up -d`。

### 3. 灰度与观察

- 初始保持 `BILLING_CANONICAL_USAGE_MODE=observe`。
- 初始保持 `RELAY_CANONICAL_USAGE_PRODUCER=false`。
- 核对 verified / estimated / ambiguous 分布、候选成本、隔离来源、snapshot hash、dedupe key 和 billing / log 一致性。
- 确认告警与审计证据稳定后，再按变更审批逐步开启 canonical producer / charge。
- 生产若已运行 v0.26.5 等价紧急修复镜像，canonical observe 满窗前不要为了替换 tag 镜像而重启 relay。

### 4. 版本替代关系

- v0.26.2 tag 未产出完整 Release 制品；实际部署使用 v0.26.3 或更新版本。
- v0.26.5 包含 v0.26.4 的全部前置迁移要求，且不新增迁移。

## 验证

各版本发布前已完成对应门禁。直接升级到 v0.26.5 后，建议至少复核以下内容：

```bash
make verify
./scripts/check-architecture.sh
make migration-check

cd web
npm run lint
npm test -- --run
npm run build
```

生产冒烟重点：

- 中英文登录 / 注册、法律页面、运营主体公示值。
- 模型列表、详情、创建 / 编辑、导入导出、模态图标和每 1M tokens 定价展示。
- 五桶用量、reported / billable 双口径、ambiguous 候选、隔离来源、pricing hash 与定价快照。
- Go 1.27 服务启动、内部 gRPC、JSON 序列化和 middleware idempotency。
- GLM / DeepSeek 大小写映射、显式 `model_mapping`、`[1M]` 请求、重试 / sticky 路由。
- 哈希资源 `immutable` 与 gzip 响应头，Dashboard / Usage / Logs 二次切换延迟。
- Responses / OneAPI 成功记录的 `source_kind`、`upstream_model_id`、pricing hash、dedupe key 与账本 / 日志归因一致性。

## 结语

v0.24.0 到 v0.26.5 是一次从界面体验到计费可信度的完整收敛：先把用户可见的控制台做到可访问、双语和合规提示清晰；再补齐模型能力与定价表达；随后把 usage 与 billing 的证据链拆解到五桶、语义状态和定价快照；最后用工具链、路由、性能和归因修复把发布质量收稳。

这个周期也明确了一个运维原则：数据库迁移、服务版本、前端产物、灰度开关和观察窗口必须作为同一证据链管理。尤其是 canonical usage 与 executor observation 相关约束，不能因为发布 tag 或依赖更新而随意重启或重建 relay。

如果你正在自托管多模型网关，或关注 Go Kratos 微服务中的可审计计费实践，欢迎试用并参与改进：[github.com/mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
