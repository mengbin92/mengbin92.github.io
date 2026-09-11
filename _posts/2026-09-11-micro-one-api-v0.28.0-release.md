---
title: "Micro-One-API v0.28.0 发布：模型健康被动监测与 Websocket 多轮计费修复"
date: 2026-09-11T11:00:00+08:00
description: "micro-one-api v0.28.0 新增按来源与上游模型粒度的被动模型健康监测与管理台看板，修复多轮 /v1/responses Websocket 连接按累计 usage 重复计费的问题，并把 404 模型不可用判定收窄到 API 形状响应体。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

v0.28.0 是 `micro-one-api` 项目在模型可观测性方向的一个重要版本。本版新增按来源与上游模型粒度的被动模型健康监测与管理台看板，修复了多轮 `/v1/responses` Websocket 连接按累计 usage 重复计费的问题，并把 404 模型不可用判定收窄到 API 形状响应体，避免误配 `base_url` 把整渠道模型标红。

**关键特点**：`channel.v1` proto 为 additive 变更（新增 `RecordModelHealth` / `ListModelHealth`），既有接口不变。数据库新增三方言迁移 `091`（`model_health_states` 表）。健康监测默认启用但只写观测表，不参与渠道路由与计费决策，不改变任何线上请求行为。

## 核心亮点

### 1. 模型健康被动监测 —— 不用探测流量看清每个模型

渠道级健康无法区分“某个模型故障”与“整个来源故障”，事故定位只能人工翻日志；而任何主动探测式巡检都会产生付费的合成流量。v0.28.0 选择了一条零成本路径：**只记录真实流量的终态结果**。

实现要点：

- relay 执行器在同源重试收敛后，把终态结果（成功 / 可归因上游失败）异步投递到独立队列持久化——**不在请求 goroutine 上写库**，不影响转发延迟。
- 健康状态按 `(source_kind, source_id, model_id, upstream_model_id)` 唯一键聚合，同时区分客户端可见模型与实际发往上游的模型，渠道 / 订阅来源和上游重写路由互不覆盖。
- 状态机在持久化事务内统一转移：成功即恢复 `healthy` 并清零连续失败；连续失败达到阈值（3 次）标记 `unavailable`，中间态为 `degraded`；MySQL / SQLite / PostgreSQL 与内存实现共享同一套 `ApplyModelHealthOutcome` 语义。
- 管理端新增模型健康页面：分页 / 关键字 / 来源类型 / 状态过滤，展示成功率、平均延迟、最近错误与最近成功 / 失败时间。
- 纯被动记录：不发送探测流量，不参与路由选择与计费。

**收益**：单模型故障第一次有了模型粒度的可观测信号，不再依赖人工翻日志；全程零合成流量成本。

### 2. Websocket 多轮连接按 Usage 增量计费

`/v1/responses` Websocket 连接存在一个会造成显著超扣的计费缺陷：relay usage 在全连接生命周期内累计，而每个终态轮次都拿着**累计快照**结算——第 N 轮被重复收取第 1..N 轮的费用，多轮对话严重超扣。同时终态事件只按事件名分类：`response.done` 携带 `status="failed"` 被记为成功并重置连续失败计数；客户端导致的内容策略 / 审核 / 敏感词失败被记为上游故障。

修复方案：

- 维护已计费 usage 基线，每轮只上报**增量**；即使某轮被跳过基线也会前进，重复的终态事件无法抬高下一轮账单。
- 终态分类改为读取 payload 结果而非事件名：`response.done` 失败按失败记录；`response.failed` 中客户端策略 / 校验类错误记为中性，与 HTTP 路径的排除规则一致；解析出的状态随轮次消费，不泄漏到下一轮。

**收益**：Websocket 多轮对话的账单与实际用量严格一致；历史已结算 ledger 不做原地修改，如有争议按既有对账流程处理。

### 3. 404 模型不可用判定收窄到 API 形状响应体

此前任何上游 404 都被记录为模型不可用。当渠道 `base_url` 误配、上游返回代理 / HTML 404 页面时，该渠道**所有模型**被标红，而渠道健康仍是绿色——信号自相矛盾，误导排障方向。

修复后，只有 API 形状的 404（JSON 错误体，或响应体点名了该模型）才证明该路由无法服务此模型；其余 404 回落到渠道中性分支，不再污染模型级健康。

**收益**：模型健康信号的信噪比大幅提升，误配基础设施不再造成整渠道误报。

### 4. Web 控制台布局与导航重组

- 重组 admin 工作区导航分组，新增模型健康入口；跨断点重排控制台布局。
- Overview 页面补齐加载失败等错误态；修复布局评审发现的交互问题。
- 新增 Playwright 布局回归用例（10 个浏览器场景），纳入回归基线。

**收益**：控制台体验一致性的回归第一次有了自动化防线。

### 5. 对账 Runbook 与工程化

- 新增 canonical usage 48 小时验收与历史账本审计两份 runbook，以及 `scripts/reconcile/historical_ledger_audit.sql` 只读审计 SQL 与 CSV/JSON 格式化脚本。
- 集成共享 `diagnosing-bugs` 调试 skill（`.agents/skills` / `.claude/skills`）。
- 部署文档补充 Lite Quickstart 索引，明确升级会应用模型健康迁移 `091`。

## 升级步骤

```bash
# 拉取版本
git fetch --tags
git checkout v0.28.0
```

1. 停机备份数据库（MySQL 生产备份 `model_health_states` 所在库即可，新表无历史数据）。
2. 运行 `migrate`，确认 `091` 应用成功、退出码 0。
3. 先更新 `channel-service`，再更新 `relay-gateway` 与 `admin-api`，最后更新 Web；避免在资源受限服务器上构建镜像。
4. 升级后打开管理台“模型健康”页面，确认真实流量开始累积记录（空表属正常现象，数据随请求产生）。
5. 历史已结算的 Websocket 账单不做追溯调整；如有争议按既有对账流程处理。

## 兼容性说明

- **API / proto**：additive。`channel.v1` 新增 `RecordModelHealth`、`ListModelHealth`；admin 新增模型健康查询端点；既有请求格式与路由不变。
- **数据库**：三方言新增 `091_create_model_health_states`（唯一键 `uk_model_health_route` + 两个查询索引）。MySQL 生产本次**需要执行迁移**；SQLite / PostgreSQL 升级时随 `migrate` 一并应用。旧库无数据回填需求。
- **配置**：无新增配置项；健康监测默认启用且只写观测表。
- **运行时**：渠道路由资格、重试策略、计费决策均不变；健康写路径异步化，失败不影响转发。
- **回滚**：代码回滚后 `model_health_states` 表可保留（无运行时依赖）；如需回退 schema，采用一致的停机备份恢复，本迁移无 down 脚本。

## 适合哪些场景

v0.28.0 特别适合以下团队：

- **多模型多来源运营**：模型粒度健康看板直接定位“哪个来源的哪个模型在故障”
- **使用 Codex 等 Websocket 长连接场景**：多轮计费修复消除重复扣费
- **曾因渠道误配被健康误报困扰**：404 收窄规则让模型健康信号可信
- **重视回归防线**：Playwright 布局用例为控制台体验兜底

## 完整变更日志

- feat: add passive model health monitoring
- refactor(web): reorganize admin workspace navigation
- feat(reconcile): add v0.27 observe audit materials
- docs(v0.27): record observe preparation status
- docs(release): include model health migration
- chore: integrate shared debugging skill
- fix: address model health review findings
- feat(web): rebalance console layout across breakpoints
- fix(relay): bill websocket turns on usage deltas and classify terminal payloads
- fix(biz): narrow 404 model-unavailable rule to API-shaped bodies
- perf(data): record model health off the request goroutine
- fix(channel): harden model-health persistence details
- fix(web): resolve layout review findings and overview error states
- feat: merge model health monitoring into develop

## 项目简介

`micro-one-api` 是一个基于 Go Kratos 的多服务 AI API 网关与管理系统。它参考了 one-api 的多渠道 OpenAI API 分发思路，也借鉴了 sub2api 在订阅额度窗口、账号池、限流和用量管理上的场景经验，将用户鉴权、渠道管理、钱包账务、日志监控和管理后台拆分成清晰的微服务。

如果你正在维护多个上游模型渠道，希望统一 API 入口、统一用户 Token、统一钱包余额和用量记录，并且希望系统后续具备更强的可维护性与扩展性，这个项目可以作为一个参考实现。

- GitHub 仓库：[mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
- 本次发布：[v0.28.0 Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.28.0)
- 详细发布公告：[release-v0.28.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.28.0.md)
