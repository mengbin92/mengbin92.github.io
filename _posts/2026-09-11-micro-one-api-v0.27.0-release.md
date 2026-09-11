---
title: "Micro-One-API v0.27.0 发布：Lite 一键部署收口与可审计账务工具"
date: 2026-09-11T10:00:00+08:00
description: "micro-one-api v0.27.0 修复 SQLite Lite 从空环境到首个聊天请求的结算死锁与方言 schema 缺口，补齐可重复部署 Quickstart 与只读历史账务审计入口，并固化 K3 canonical charge 的验收 SQL 口径与安全依赖基线。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

v0.27.0 是 `micro-one-api` 项目面向个人部署者与运维审计场景的一个收口版本。本版修复了 SQLite Lite 从空环境到首个聊天请求之间的结算死锁与方言 schema 缺口，补齐了可重复验证的部署 Quickstart，新增只读的历史账务审计工具，并把 K3 canonical charge 灰度的验收 SQL 口径与安全依赖基线彻底固化。

**关键特点**：无公共 API / proto 破坏性变更。MySQL 生产 schema 不变（仍为 `089`）；SQLite / PostgreSQL 通过增量迁移 `011` / `090` 安全升级旧库。Lite 示例要求部署者自行生成 `CHANNEL_ENCRYPTION_KEY`，初始管理员密码写入卷内 `0600` 文件而非服务日志。

## 核心亮点

### 1. Lite 部署从空环境直达首个请求

Lite（SQLite 单连接）此前存在一个隐蔽的结算死锁：chat 结算事务中的账户、订阅组和定价读取逃出了事务，动态定价又在连接被占用后才加载——单连接自等待，最终表现为 chat 502。同时 SQLite/PostgreSQL 基线遗漏部分渠道字段，账务时间列沿用整数声明，与 GORM `time.Time` 映射不兼容，旧库无法安全升级。

v0.27.0 的修复：

- 结算事务改用事务绑定的账户、订阅组和动态定价快照读取；SQLite 单连接下钱包与订阅双轨结算可完成、重试幂等，余额与账务守恒，并有真实 SQLite 回归测试覆盖。
- 新增 `011_add_channel_oneapi_fields.sql`（补齐 `channels.model_mapping` / `channels.system_prompt`）与 `090_fix_billing_timestamp_types.sql`（账务时间列修正为方言时间类型，旧数据 `0` 保持 NULL、Unix 秒自动转换）。
- Lite Compose 使用独立 project、随机本地端口、非 root 数据卷和私有 bootstrap 密码文件；后续启动只应用待执行增量迁移。

**收益**：个人部署者拿到一个从 clone 到首个聊天请求全流程可复现的 Lite 形态；旧 SQLite / PostgreSQL 库可就地升级，无需重建。

### 2. Lite Quickstart 与可重复 Smoke

新增 [docs/quickstart-lite.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/quickstart-lite.md)：覆盖空环境启动、私有初始密码、渠道 / 钱包 / Token / Chat 操作、停机备份恢复与升级边界。配套 `scripts/test-lite-smoke.py` 在独立临时目录、空卷、随机端口和本地 mock 上游下完整验证 bootstrap、登录、建渠道、充值、Token、models、chat、重复迁移和重启持久化。

同时更新了脱敏截图与 `lite-quickstart.mp4` 演示，让部署效果在动手前即可预览。

**收益**：个人部署从“翻源码猜配置”变成“照文档跑一遍 smoke”，部署正确性有了自动化防线。

### 3. 历史 Usage 只读审计工具

历史 consume ledger 只靠 token 算术无法证明当时的解析口径、订阅归属、定价快照和实扣金额，人工导出难以重复复核，而任何写式修复都会放大账务风险。

v0.27.0 新增 `scripts/reconcile/history-audit`：

- 在只读、可重复读事务中 SELECT billing ledger、pricing snapshot 和 reservation 三表，输出确定性 JSON 或 CSV。
- 报告将请求分为 `verified` / `candidate` / `unknown`：只有完整一致的 v1 usage 证据、来源和 SHA-256 校验通过的冻结价格快照才复算 canonical 差额；证据不足不反推价格、不自动分摊、不输出冲正指令。
- 订阅 / 钱包双轨 ledger 按请求合并原始实扣，保留每条 ledger 证据；差额只出现在请求层。
- 工具不提供 billing RPC、apply、退款或 reversal 路径；实库模式仅要求三表 SELECT 权限。

**收益**：历史账务争议第一次有了可重复、可归档、零写入风险的证据报告。

### 4. Canonical Charge 灰度验收与回滚口径固化

K3 限定来源 canonical charge 的 72 小时灰度窗口（2026-09-06 至 2026-09-09）以 scoped PASS 收官：1166 条 allowlisted K3 请求与 canonical 重建完全一致，无正向差额、无用户超扣。过程中修复了两个验收 SQL 口径问题：

- **float64 舍入复刻**：门禁 SQL 原先按 DECIMAL `ROUND` 重建逐桶成本，而生产 Go 代码是 float64 左结合乘法加 `math.Round`，十进制 `.5` 边界低 1 ULP 时产生“少扣 1 quota”的假差异。修复后按 `FLOOR(x)+(x-FLOOR(x)>=0.5)` 位级复刻 `roundScaled`，5279 个边界 / 随机用例与生产零偏差。
- **PromptExclusive 语义重建**：legacy 成本重建原先按 `usage_semantics` 推断是否扣除 cache-read，但生产实际由订阅平台（claude/zhipu/minimax/kimi）或渠道类型判定。修复后按行 LEFT JOIN 订阅账号与渠道推导，消除了回滚演练暴露的 17 条口径不一致样本。

2026-09-10 还完成了配置-only 回滚演练：切换 `BILLING_CANONICAL_USAGE_MODE=observe` 并重建 billing-service 即完成回滚，无 schema 变更、allowlist 不动；observe 阶段 19 条 K3 全部按 legacy 实扣，切回 charge 后 2 条按 canonical 实扣，幂等与多重集一致性双向验证通过。

**收益**：canonical charge 的扩面决策第一次建立在“门禁口径与生产位级一致”的证据之上，回滚路径有了实测背书。

### 5. 安全与依赖基线

- gRPC 升级到 1.83.2 并同步 `golang.org/x/net` 0.58.0，修复 Dependabot / Trivy 报告的 CVE-2026-84445。
- Web 依赖更新：`hono` 4.13.7、`js-yaml` 4.3.2、`@vitest/mocker` 5.0.0。
- Lite `.env` 示例的 `CHANNEL_ENCRYPTION_KEY` 改为空必填（Quickstart 引导生成唯一 32 字节 ASCII key），杜绝示例密钥被直接复制进真实部署；仅历史占位指纹加入 Gitleaks allowlist。
- CI 部署检查为 Lite 静态校验生成一次性随机密钥，示例保持留空，空密钥的 Lite Compose 仍拒绝渲染。

**收益**：`npm audit` 0 漏洞、Trivy 无 high/critical、govulncheck 无受影响代码；Lite 默认配置不再携带可复用秘密。

### 6. 维护者文档：计费链路与协议转换

新增两份面向维护者的单一入口文档：

- [LLM 计费实现讲解](https://github.com/mengbin92/micro-one-api/blob/main/docs/design/llm-billing-explained.md)：用项目实现讲清 token 桶、定价模式、预留、订阅抵扣与上游成本如何共同决定一笔账单，含可验算的定价示例。
- [协议转换指南](https://github.com/mengbin92/micro-one-api/blob/main/docs/design/protocol-conversion.md)（405 行）：Chat / Responses / Messages 三协议的请求响应映射、adaptor 路由矩阵、流式状态机与兼容性边界。

**收益**：计费排查和协议适配不再需要在兼容层、adaptor 和路由代码之间来回翻找。

## 升级步骤

```bash
# 拉取版本
git fetch --tags
git checkout v0.27.0
```

1. 阅读目标方言发布说明并完成备份。MySQL 从 v0.26.6 起无新增迁移；SQLite / PostgreSQL 会依次应用 `011` 和 `090`。
2. Lite 部署按 Quickstart 生成并持久保存 `CHANNEL_ENCRYPTION_KEY`；不要复用历史示例值，也不要在升级时重新生成已有库的密钥。
3. Lite / PostgreSQL 升级采用停机窗口：停止服务并备份数据卷，串行构建镜像，运行 `migrate`，确认退出码 0 后启动全部服务。
4. 全量 Compose 建议先更新 `migrate`、`billing-service`、`channel-service`、`identity-service`，再按依赖更新其余服务；避免在资源受限服务器上构建镜像。
5. 历史审计使用仅具备三表 SELECT 权限的账号通过 `HISTORY_AUDIT_DSN` 执行，报告留在受控环境，不要提交到仓库。
6. 保持 canonical usage 现有 mode 与 K3 allowlist 不变；本版本发布 tag 与镜像不要求重启当前生产 billing / relay 容器。

## 兼容性说明

- **API / proto**：无新增或破坏性公共 API、HTTP 路由或 proto 变更。
- **数据库**：MySQL 无新增迁移，仍是 `089`。SQLite / PostgreSQL 新增 `011` 与 `090`；`090` 在事务内重建相关表，保留金额、ID、自增序列、索引和可解析时间值，升级前必须停机备份并预留表空间。
- **配置**：Lite `CHANNEL_ENCRYPTION_KEY` 不能为空，必须由部署者生成并保存；初始管理员密码默认写入 SQLite 卷内 `initial-admin-password.txt`（0600），不再打印到服务日志。
- **运行时**：Lite chat 结算、重复迁移和重启持久化修复；MySQL 结算语义不变。历史审计与 72h 门禁均为只读，不修改 ledger。
- **回滚**：canonical charge 保持仅切 `BILLING_CANONICAL_USAGE_MODE=observe` 并重建 billing-service；迁移回滚采用一致的停机备份恢复。

## 适合哪些场景

v0.27.0 特别适合以下团队与个人：

- **个人 / 小团队自部署**：Lite + SQLite 一键起站，Quickstart 与 smoke 保证路径可复现
- **有历史账务争议需要复核**：只读审计工具输出确定性证据，零账务风险
- **关注 canonical charge 扩面的运维**：验收 SQL 口径与生产位级一致，回滚路径经过实测
- **安全合规敏感**：依赖基线清零高危漏洞，Lite 默认配置无内嵌秘密

## 完整变更日志

- docs: explain LLM billing with project implementation
- docs: sync project progress after v0.26.6 release
- docs(v0.27): close out K3 canonical charge 72h window with scoped PASS
- feat(reconcile): add read-only historical usage audit
- fix(lite): restore SQLite settlement and complete deployment quickstart
- docs(roadmap): close personal deployment documentation milestone
- build(deps): bump hono (#19)
- build(deps): bump the npm_and_yarn group across 1 directory with 2 updates (#20)
- fix(security): patch gRPC and require generated Lite encryption keys
- docs(design): add protocol conversion guide for Chat/Responses/Messages
- fix(reconcile): replicate production float64 rounding in charge gate SQL
- fix(reconcile): rebuild legacy cost with PromptExclusive semantics
- fix(ci): generate an ephemeral key for Lite manifest validation

## 项目简介

`micro-one-api` 是一个基于 Go Kratos 的多服务 AI API 网关与管理系统。它参考了 one-api 的多渠道 OpenAI API 分发思路，也借鉴了 sub2api 在订阅额度窗口、账号池、限流和用量管理上的场景经验，将用户鉴权、渠道管理、钱包账务、日志监控和管理后台拆分成清晰的微服务。

如果你正在维护多个上游模型渠道，希望统一 API 入口、统一用户 Token、统一钱包余额和用量记录，并且希望系统后续具备更强的可维护性与扩展性，这个项目可以作为一个参考实现。

- GitHub 仓库：[mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
- 本次发布：[v0.27.0 Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.27.0)
- 详细发布公告：[release-v0.27.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.27.0.md)
