---
title: "Micro-One-API v0.29.0 发布：路由分组重设计 v2 —— 分组实体、订阅合约与有序候选组"
date: 2026-09-13T10:00:00+08:00
description: "micro-one-api v0.29.0 交付路由分组重设计 v2 的全部实施阶段：分组从散落各处的字符串升级为有稳定 ID、生命周期与使用权限的路由分组实体，其上交付订阅合约、按组结算模式、有序候选组与用户专属倍率；全部能力默认关闭，proto 与三方言迁移 092–100 均为 additive。"
tags: ["Micro-One-API", "Go", "Kratos", "AI 网关", "发布", "微服务"]
categories: ["release-notes"]
draft: false
---

v0.29.0 是 `micro-one-api` 的 **MINOR 路由分组重设计版本**，交付分组重设计 v2 的全部实施阶段（A–F）。

在此之前，「分组」只是散落在用户、渠道、账号和倍率配置里的字符串：删除一个倍率覆盖并不会撤销组的访问，页面无法准确表达组是否存在、可用或被引用，用户切组会影响其全部 Key。v0.29.0 把分组升级为有稳定 ID、生命周期、资源成员和使用权限的**路由分组实体**，并在此之上交付订阅合约（contracts / entitlements）、按组结算模式、有序候选组（ordered / Auto）和用户专属倍率。

**关键特点**：全部能力由分阶段开关控制、默认关闭——「新代码 + 旧行为」。不打开任何开关时，系统行为与 v0.28.1 完全一致（所有用户走服务端默认组、legacy 订阅合同、inherit 模式）。proto 仅 additive，MySQL / SQLite / PostgreSQL 三方言新增迁移 `092`–`100`（全部为新表 / 加列 / 可空列，无回填型改写）。逐项根因、修复与影响服务的工程细节见 [release-v0.29.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.29.0.md)。

## 核心亮点

### 1. 路由分组实体 —— 分组第一次有了事实源（阶段 A–B）

旧模型里没有组的事实源：用户、渠道、账号、模型映射和倍率配置各自携带组名字符串，互相之间没有任何一致性保证。v0.29.0 先以只读审计拆清跨服务 schema 的存量数据，再交付分组实体：

- `routing_groups` 实体：稳定 ID、`key` 精确唯一、状态、资格模式、revision，以及 channel / account 成员关系表；随既有 CSV 配置双写回填（迁移 `092`）。
- 用户资格与 Key 选组分离：用户有默认组 + 零到多个显式授权组，授权记录携带来源（migration / grant / subscription）与有效期。
- 管理台「分组」页面：列表展示名称/键、状态、资格、结算方式、倍率、模型数、资源数、有效套餐数，并支持**显式新建分组**（`POST /api/v1/admin/routing-groups`）。新建组固定停用、资格模式可选，避免半成品组立即可路由。

**收益**：组的存在、可用性与引用关系可被准确表达和治理；用户切组不再影响其全部 Key；页面上的分组状态第一次与后端权威数据一致。

### 2. 请求快照与 identity 路由事实 —— 冻结在途请求的计费上下文（阶段 C，默认关）

`ReserveQuotaRequest` 原本没有实际路由组，预扣与结算按 `account.Group` 取价；请求中途改价或换组也没有快照语义。阶段 C 补齐了这条链路：

- billing 请求快照（迁移 `093`）：reservation 携带冻结的价格与路由上下文，在途改价 / 换组不影响已预扣请求；`LedgerEntry` 记录 `routing_group_id/key` 与 `request_snapshot_hash/json` 证据。
- identity 路由事实（迁移 `094`）：用户与 Token 携带默认组、授权、revision，鉴权返回 `routing_context_version=2`；`common.v1` 新增 `ResolvedRoutingContext` / `RoutingSubjectFacts` / `UserRoutingGroupGrant`。

**收益**：Key 选组前先补齐上下文，不再错组计费；账单自带证据链，计费一致性可审计。

### 3. fixed 组 Key、多组授权与 outbox —— 授权变更可靠投递（阶段 D，默认关）

- Token 支持 `inherit`（跟随默认组）与 `fixed`（固定组）两种模式，每次调用重新确认资格。
- 授权与生命周期变更经 `routing_change_outbox` 投递，identity / channel / billing 三个 schema 各建一份（迁移 `095`），不再依赖调用方轮询。
- 用户可用组目录 API 与前端选组入口。

**收益**：授权的发放与撤销跨服务最终一致；fixed Key 绑定的组失去资格时会被立即重新校验，而不是继续放行。

### 4. 订阅合约与按组结算模式 —— 表达「只覆盖某个组」的套餐（阶段 E，默认关）

旧订阅按用户查唯一有效订阅，额度策略的 `Platform` 只是描述字段，无法表达「只覆盖 Claude 组」；购买权益也没有快照。阶段 E 引入合约模型：

- 订阅合约（迁移 `096`）：套餐声明覆盖组与访问权益，用户订阅冻结购买时的合同快照；权益带版本号，到期按来源撤销访问，不改写默认组与其他授权。
- 按组计费策略（迁移 `097`）：`routing_billing_policies` 版本化价格 / 模式，支持 `wallet_only` / `subscription_first` / `subscription_only` 三种结算模式，与合同引用互斥。
- 订阅购买全流程事务化（单连接 SQLite 不再自等待），含幂等回执。

**收益**：商业化运营可以按组售卖订阅、按组选择结算顺序；购买即冻结合同，后续改价不影响已购权益。

### 5. 有序候选组、用户倍率与关系覆盖 —— 按序兜底与按人定价（阶段 F，默认关）

- Token 可携带显式有序候选组列表（迁移 `098`）：按顺序尝试，仅在前置组无可用资源时切换到下一组；绑定组失效（掉出候选、失去资格、被停用）时要求客户端重新发起，不静默漂移。
- 用户专属组倍率（迁移 `099`）：heads + history 版本化，替换组基础倍率。
- 组内成员关系 priority / weight 覆盖（迁移 `100`，可空列）。

**收益**：高价值流量固定在首选组、失败时按序兜底；同一组内可以按用户定价、按成员调优先级，路由策略的表达力大幅增强。

## 分阶段启用路线图

v0.29.0 落地的分组重设计 v2 各阶段：

| 阶段 | 内容 | 状态 |
|------|------|------|
| A | 拆分路由成员关系与订阅额度策略、统一授权、只读审计基线 | ✅ |
| B | 路由分组实体、成员关系与双写回填 | ✅ |
| C | 请求快照 + identity 路由事实 | ✅ |
| D | fixed 组 Key / 多组授权 / outbox | ✅ |
| E | 订阅合约 / 覆盖组 / 结算模式 | ✅ |
| F | 有序候选组 / 用户倍率 / 关系覆盖 | ✅ |

完整设计与各阶段完成记录见 [group-redesign-v2.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/design/group-redesign-v2.md)；生产启用路径见[路由分组运维 runbook](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-groups-runbook.md)——逐阶段、可灰度、可回退，不要在同一窗口内跳阶段全开。

## 安全与稳定性改进

本版一并发布了跨服务代码审查发现的修复：

### 路由失效处理 fail-closed

- **relay**：有序路由此前把非 NotFound 的组读取错误当作「组不存在」静默跳到下一候选；现在真实读取错误会中止本次尝试，仅 NotFound 穿透。
- **channel**：`HasRoutingCandidates` 在注册表读取失败时落入无限制回退路径、并在探测资源时吞掉非 NotFound 错误；现在注册表拒绝不再放宽访问，意外错误向上传播。

### 计费一致性

- **billing**：订阅覆盖判定统一为滚动窗口 + 最严格限额，与 reserve 一致；无订阅的钱包用户查价不再误报 `ErrSubscriptionNotFound`；订阅购买事务内的 plan / group / billing policy 读取全部留在事务连接上，修复单连接 SQLite 死锁。

### 授权与前端

- **identity**：v2 默认组命令不再改写 migration 授权，避免把临时 / 订阅访问变成永久访问；只改偏好，迁移授权的改写保留在 legacy 路径。
- **web**：有序组选择器不再丢弃不可用候选 ID（序号不再静默重排）；管理台覆盖解析接受小数优先级。
- **deploy**：`deploy-update.sh` 在任何构建或远程调用之前先校验完整服务列表，拼错服务名不会部分部署，附 `scripts/test-deploy-update.py` 回归。

## 升级步骤

```bash
# 拉取版本
git fetch --tags
git checkout v0.29.0
```

1. **备份全部服务 schema**，然后按 runbook 逐 schema 执行迁移 `092`–`100`（本地交叉构建静态 `migrate` 二进制上传，经 `docker run` 执行；先 `-status` 核对 pending 只含本次新增编号）。
2. 本地交叉构建 `linux/amd64` 镜像（**不在资源受限服务器上构建**）：本次涉及 `identity-service`、`channel-service`、`billing-service`、`admin-api`、`relay-gateway`，可用 `scripts/deploy-update.sh identity-service channel-service billing-service admin-api relay-gateway` 一次完成（脚本会先校验完整服务列表）。
3. 重新构建并同步前端 `web/dist`（前端经 `/opt/web/dist` 挂载提供，重建镜像不会更新前端）。
4. 验证默认行为不变后，如需启用新能力，严格按[路由分组运维 runbook](https://github.com/mengbin92/micro-one-api/blob/main/docs/runbooks/routing-groups-runbook.md) 逐阶段打开开关：

```bash
# 阶段 B（channel-service，B 起必须保持 true）
CHANNEL_ROUTING_GROUP_DUAL_WRITE=true

# 阶段 C（billing / identity / relay，按序启用）
BILLING_REQUEST_SNAPSHOT_V2=true
IDENTITY_ROUTING_V2=true
RELAY_ROUTING_CONTEXT_V2=true

# 阶段 D（admin-api，只控制「新增」）
ADMIN_ROUTING_FIXED_KEYS=true

# 阶段 E（admin-api + billing-service + relay-gateway，三处必须一致开启）
SUBSCRIPTION_ENTITLEMENTS_V2=true

# 阶段 F（admin-api + relay-gateway）
ADMIN_ROUTING_ORDERED_KEYS=true
RELAY_ROUTING_ORDERED=true
```

## 兼容性说明

- **API / proto**：additive。新增 `common.v1` 路由上下文消息、`identity.v1` 路由事实与错误原因、`channel.v1` 错误原因、`LedgerEntry` 快照证据字段；无破坏性变更。
- **数据库**：迁移 `092`–`100`（三方言），全部 additive。生产 per-service schema 须逐 schema 带 `-ownership` 执行；执行前备份全部服务 schema，先 `-status` 核对 pending。
- **配置**：新增能力开关均默认关闭；不开关则行为与 v0.28.1 完全一致。
- **运行时**：默认路径的路由、计费与重试决策不变；新能力的启用须按 runbook 逐阶段灰度。
- **回滚**：镜像回滚前为线上现有镜像打 `rollback-<ts>` 标签即可；已应用的 additive 迁移无需回退（新表 / 新列不被旧代码引用）。已打开开关的环境须先按 runbook 反向关闭开关再回滚镜像。

## 适合哪些场景

v0.29.0 特别适合以下团队：

- **按组售卖订阅**：覆盖组 + 三种结算模式，表达「只覆盖某个组」的套餐
- **需要按人定价**：用户专属倍率 + 组内优先级 / 权重覆盖
- **对计费一致性要求高**：请求快照冻结价格，账本携带证据链
- **多渠道多分组运营**：分组实体治理组的生命周期与引用关系
- **希望灰度演进架构**：全部开关默认关闭，逐阶段启用、可回退

## 完整变更日志

- test(e2e): match the renamed channel group label in admin smoke
- fix(admin,billing): silence summary deadline and pricing-snapshot log noise
- fix(routing): close review findings across relay, billing, channel, identity, and web
- docs(routing): correct the new-group wiring order in the create form
- feat(routing): add explicit routing group creation
- docs(runbooks): add routing-groups operations runbook
- fix(deploy): honor service arguments in deploy-update.sh
- fix(docs): reject out-of-repo Markdown links and drop broken source links
- fix(groups): close code-review findings and enforce a gofmt quality gate
- feat(groups): deliver subscription contracts, entitlements, and settlement modes for redesign phase E
- feat(groups): freeze routing and billing context for redesign phase C
- feat(groups): establish routing group foundation for redesign v2
- docs(groups): record verified read-only audit baseline
- fix(groups): audit routing data across service schemas
- refactor(groups): unify routing authorization and add read-only audit
- refactor(groups): separate routing membership from subscription quota policies

## 项目简介

`micro-one-api` 是一个基于 Go Kratos 的多服务 AI API 网关与管理系统。它参考了 one-api 的多渠道 OpenAI API 分发思路，也借鉴了 sub2api 在订阅额度窗口、账号池、限流和用量管理上的场景经验，将用户鉴权、渠道管理、钱包账务、日志监控和管理后台拆分成清晰的微服务。

如果你正在维护多个上游模型渠道，希望统一 API 入口、统一用户 Token、统一钱包余额和用量记录，并且希望系统后续具备更强的可维护性与扩展性，这个项目可以作为一个参考实现。

- GitHub 仓库：[mengbin92/micro-one-api](https://github.com/mengbin92/micro-one-api)
- 本次发布：[v0.29.0 Release](https://github.com/mengbin92/micro-one-api/releases/tag/v0.29.0)
- 详细发布公告：[release-v0.29.0.md](https://github.com/mengbin92/micro-one-api/blob/main/docs/releases/release-v0.29.0.md)
