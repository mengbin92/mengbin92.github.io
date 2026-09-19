---
title: "96 个迁移文件、三个 SQL 方言：迁移治理是怎么被逼出来的"
date: 2026-09-17T12:00:00+08:00
description: "我第一版迁移就是一个编号序列：001_xxx.sql、002_xxx.sql……每个文件一个号，跑的时候按号排序。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个编号，两种假设

我第一版迁移就是一个编号序列：`001_xxx.sql`、`002_xxx.sql`……每个文件一个号，跑的时候按号排序。

这个模型默认了一件事：**编号是唯一的，而且递增一次就代表一个新版本。**

后来我加了 Lite 部署模式（SQLite），于是同一个逻辑变更需要三个方言的实现。这时候编号就出问题了：

```
migrations/057_add_plan_snapshot_to_payment_orders.sql
migrations/057_create_subscription_account_quota_reset_runs.sql
```

**两个文件都是 057。**

这不是我手滑——是两条开发线在合并的时候各自用了下一个可用编号。在只看前缀的模型里，这是一个必须修复的冲突。

但真正让我停下思考的是：**这两个文件真的冲突吗？**

答案是不冲突，因为迁移的执行器根本不用前缀做版本号：

```yaml
# The runner versions migrations by FULL basename (schema_migrations.version
# is the file name without .sql), so two files sharing a prefix do not
# collide. The prefixes are nevertheless confusing and any NEW duplicate
# prefix is a hard error (checked by cmd/migrate-check).
```

**`schema_migrations.version` 存的是完整文件名（去掉 `.sql`），不是那个数字前缀。**

所以"057 冲突"在技术上根本不存在。冲突存在于我的脑子里——因为我把编号当成了版本号。

这个发现改变了我对整件事的处理方式：**既然编号只是排序提示、真正的版本是文件名，那我的治理规则就应该围绕文件名，而不是围绕那个数字。**

---

## 1. 治理变成了三个可检查的命题

想清楚之后，我把迁移治理收敛成三条规则，全部可以由一个静态检查器判断：

### 规则一：新增的重复编号是错误，历史的允许保留

```yaml
# Historical duplicate numeric prefixes that are allowed to stay.
#
# The runner versions migrations by FULL basename (schema_migrations.version
# is the file name without .sql), so two files sharing a prefix do not
# collide. The prefixes are nevertheless confusing and any NEW duplicate
# prefix is a hard error (checked by cmd/migrate-check).
duplicate_prefix_allowlist:
  mysql:
    - prefix: "057"
      files:
        - 057_add_plan_snapshot_to_payment_orders
        - 057_create_subscription_account_quota_reset_runs
  sqlite:
    - prefix: "009"
      files:
        - 009_add_per_bucket_cost
        - 009_clean_orphan_model_mappings
```

**允许列表 + 硬错误**这个组合是标准做法，但我特意把 `files` 列出来了——不只是"允许 057 重复"，而是"允许**这两个**文件用 057"。

因为只写 `prefix: "057"` 的话，以后有人再加一个 `057_xxx.sql` 也会被放过。而列出具体文件，任何**新的** 057 都会失败。

**治理规则要精确到"我批准了什么"，而不是"我批准了哪个编号"。**

### 规则二：新迁移必须三个方言都有

```yaml
# The numbered files >= auto_mirror_from_prefix MUST be mirrored into
# postgres/ and sqlite/ with the IDENTICAL basename.
auto_mirror_from_prefix: "072"
```

从 `072` 开始，每个根目录的 `.sql` 必须在 `migrations/postgres/` 和 `migrations/sqlite/` 里有同名文件。

为什么是 072 这个边界？因为**之前的历史已经乱了**：

```yaml
# Older files may use a different numbering or be consolidated into the
# dialect baseline; that historical coverage is documented (not enforced) in
# `historical_coverage`.
```

老的 Postgres/SQLite 是用一个 `000_create_full_schema.sql` 基线合并起来的，不是逐个镜像。这是合理的做法（新方言从完整基线开始），但它意味着**历史区间没法用"文件名镜像"来判断覆盖度**。

所以我划了一条线：**线的这边开始强制，线的那边只记录不强制。** 而那条线（072）不是推导出来的，是我决定"从这里开始我把规矩立起来"的时刻。

`historical_coverage` 那张表是纯文档：

```yaml
# Documented mirror coverage for the historical range (< auto_mirror_from_prefix).
# Keyed by root version; value is the dialect file that carries the change
# (or "(baseline)" when the change is folded into 000_create_full_schema).
# This table is documentation — the check script does NOT enforce it — but it
# makes drift in the historical range visible on review.
```

**注释里明确写了"the check script does NOT enforce it"。** 我把这句话写下来，是因为一张看起来像配置表的文档很容易被误以为是强制的。而它实际的作用是"让漂移在 review 时可见"。

### 规则三：每个可执行迁移必须被某个服务认领

```yaml
# When a backend service runs migrations against its own schema
# (IDENTITY_SCHEMA=oneapi_identity, BILLING_SCHEMA=oneapi_billing, …), it
# must only own the migrations for the tables it cares about.
```

```yaml
services:
  identity:
    # users / tokens / user_oauth_identities
    - 000_create_core_tables          # users, tokens (subset owned by identity)
    - 007_create_system_options       # also admin-owned; running on identity schema is harmless
    - 014_add_token_management_fields
    # ...
  channel:
    # ...
```

这个清单来自我在做 schema 隔离时遇到的一个问题：**一个服务对着自己的 schema 跑迁移时，不该跑别的服务的表。**

但清单很快就出现了两类"例外"，而这两类必须区别对待：

**第一类：这个迁移在某些方言下确实不存在。**

```yaml
# Root migrations that intentionally have NO postgres/sqlite counterpart.
# The check script requires every file listed here to exist in migrations/.
not_applicable:
  - version: 061_add_billing_schema_system_options
    reason: MySQL-only view DDL over the oneapi_billing schema (Phase 2.4 schema isolation). Postgres/SQLite deployments do not use the oneapi_* schema split.
```

**第二类：这个文件不是被某个服务执行的。**

```yaml
# Files that are intentionally NOT part of the per-service ownership model.
# They either run on the centralised shared schema or are reference DDL the
# runner skips. The ownership check requires every other runnable root
# migration to be claimed by exactly one service (or shared).
ownership_exempt:
  - file: phase1_indexes.sql
    reason: applied by the runner on the shared schema; no single service owns it
  - file: phase3_partitioning.sql
    reason: index for optional MySQL-only per-schema partition DDL, skipped by the runner
  - file: schema_split.sql
    reason: reference DDL for the Phase 2.4 cutover, executed manually, skipped by the runner
```

**我坚持给每个例外都写 `reason`。** 因为"豁免"很容易变成垃圾桶——加进去就再也没有人问为什么。

而这两个列表的语义必须分开：

| 列表 | 含义 | 检查器要求 |
|---|---|---|
| `not_applicable` | 这个迁移在某些方言下不存在 | **必须**在根目录存在 |
| `ownership_exempt` | 这个文件不归任何服务 | 其余文件必须**恰好被一个服务**认领 |

`not_applicable` 那条"必须存在"的检查我觉得挺重要：**它防止我写一个指向不存在文件的豁免**（比如我改了文件名但忘了改清单，或者我本来打算删这个文件）。如果没有这条检查，豁免列表会慢慢积累幽灵条目。

---

## 2. 静态检查：不需要数据库

整条治理的入口是一条命令：

```makefile
.PHONY: migration-check
# static migration governance gate (v0.19 P1.2): duplicate numeric prefixes
# (historical ones allowlisted in migrations/dialect-manifest.yaml), ownership
# coverage, and postgres/sqlite mirror coverage for new migrations. Pure file
# checks — no database required.
migration-check:
	go run ./cmd/migrate-check -dir ./migrations
```

**"Pure file checks — no database required"** 这半句是我特意写进注释的。

因为它决定了这条检查能放在哪里跑：

- 每个 PR 都能跑（不需要起 MySQL）；
- 本地改完立刻能跑（不用等容器）；
- CI 里不需要 service container。

**如果一个检查需要外部依赖，它就会变成"CI 里那个偶尔失败的任务"，而不会变成"我提交前顺手跑一下的东西"。**

而真正需要数据库的检查是另一条命令：

```makefile
.PHONY: migration-smoke-mysql
# v0.21 P1: execute all MySQL migrations against a scratch database, verify a
# repeat apply is a no-op, audit schema_migrations, and prove an invalid SQL
# migration fails. Requires a healthy MySQL at MIGRATIONS_DSN (CI provides a
# service container; see scripts/test-migration-smoke.sh for the default DSN).
migration-smoke-mysql:
	./scripts/test-migration-smoke.sh mysql
```

这条做了三件事，第三件我觉得最有意思：

1. 把所有迁移跑一遍；
2. **再跑一遍，验证是 no-op**（幂等）；
3. **验证一个非法的 SQL 迁移会失败。**

第三件事是"检查器自身的检查"——**我在验证这个检查器真的有失败能力。** 一个只会通过的检查等于没有检查，而这类"检查器能不能红"的验证很少有人做。

---

## 3. 两个都进了 `make verify`

```makefile
	@echo "== make verify: architecture =="
	@./scripts/check-architecture.sh
	@echo "== make verify: migration-check =="
	@make migration-check
	@echo "== make verify: frontend (lint/test/build) =="
	@cd web && npm run lint && npm test -- --run && npm run build
	@echo "== make verify: all gates passed =="
```

`make verify` 是一个总闸，里面串了架构检查、迁移检查、前端三件套。**它的价值在于"所有门禁在一个命令里"，而不是要记住五条命令。**

这也解释了为什么 `migration-check` 必须是纯文件的——`make verify` 是要在日常开发里反复跑的，如果它需要起 MySQL，就不会有人跑它。

---

## 4. 方言：三个树，一个是规范

```yaml
# Three dialect trees coexist:
#   migrations/            MySQL-canonical sequence (the source of truth)
#   migrations/postgres/   Postgres deployment mode. Consolidated
#                          000_create_full_schema.sql baseline + numbered
#                          mirrors of recent MySQL changes.
#   migrations/sqlite/     SQLite Lite deployment mode. Same layout
#                          strategy as Postgres.
strategy:
  mysql: canonical
  postgres: consolidated-baseline
  sqlite: consolidated-baseline
```

**明确指定 MySQL 是规范源（source of truth），另外两个是派生。** 这条声明解决了一个很实际的问题：当两个方言对同一个变更需要不同的写法时，先写哪个？

答案是先写 MySQL，然后逐个方言适配。而"适配"不一定是改 SQL——可能是改类型（`VARCHAR` → `TEXT`）、改语法（`IF()` → `CASE WHEN`），甚至改设计（比如 MySQL 的分区在 SQLite 上直接不支持，见下一节）。

当前规模：根目录 96 个 `.sql`，`postgres/` 41 个，`sqlite/` 42 个，`manual/` 2 个。

**Postgres 和 SQLite 的数量几乎相同（41 vs 42），但都不到根目录的一半**——这正是"合并基线 + 只镜像近期"这个策略的体现。

---

## 5. 分区：只支持 MySQL，而且要优雅降级

大表（日志、账本）我做的是 MySQL 的 range 分区。这个能力**只有 MySQL 有**：

```go
// PartitionManager handles table partition operations.
//
// MySQL is the only supported backend: native range partitioning,
// REORGANIZE PARTITION and information_schema.PARTITIONS are MySQL-only.
// On any other dialector (e.g. SQLite used by the Lite deployment) the
// manager reports Supported=false and all maintenance calls become
// no-ops so the cron tickers can keep running without error.
type PartitionManager struct {
    db        *gorm.DB
    Supported bool
}
```

最后半句是关键：**"so the cron tickers can keep running without error"**。

因为分区维护是挂在一个定时任务里的。如果 SQLite 部署下这个任务直接报错，日志里就会有一堆"no such table: information_schema"——**一个"这个功能不适用"的情况被表现成了"一个错误"。**

检测方式：

```go
func NewPartitionManager(db *gorm.DB) *PartitionManager {
    pm := &PartitionManager{db: db, Supported: true}
    if db != nil && db.Dialector != nil {
        name := strings.ToLower(db.Dialector.Name())
        if name != "mysql" {
            pm.Supported = false
        }
    }
    return pm
}
```

然后每个操作入口先查这个标志：

```go
func (pm *PartitionManager) PartitionMaintenance(ctx context.Context) error {
    if !pm.Supported {
        // ...
    }
```

**"不支持"要变成一个正常状态，而不是一条错误日志。** 这个原则我在第 2 篇（明确不支持的 OpenAI 接口返回结构化响应）和第 12 篇（不支持的操作返回明确错误）都用到过，这里是第三次。

### 5.1 分区维护做什么

能做的操作不多，都是 MySQL 特有的：

| 操作 | 说明 |
|---|---|
| `GetPartitionStatus` | 查 `information_schema.PARTITIONS` |
| `AddLogsPartition` / `AddBillingLedgersPartition` | 加一个未来分区 |
| `DropOldPartition` | 删一个过期分区 |
| `DropPartitionsOlderThan` | 按保留期批量删 |
| `EnsureFuturePartitions` | 保证未来 N 个月的分区都在 |

加分区用的是 `REORGANIZE PARTITION pmax INTO (...)`——**把一个 `pmax`（catch-all）分区拆成"新分区 + 新的 pmax"。** 这也是 MySQL 特有的语法。

`EnsureFuturePartitions(ctx, tableName, monthsAhead)` 是那个定时任务真正调用的：**每次跑都保证未来几个月有分区存在**，这样数据永远有地方落。

### 5.2 删除是分表的，而且账本表的删除在代码里被显式关掉

这一条我原本以为"没有自动删除"，核对之后发现不是——是**两张表策略不同**。

日志表的维护带保留期：

```go
// app/log/cmd/log/partition.go
func startPartitionMaintenance(ctx context.Context, db *gorm.DB, cfg *logconf.Partition, retentionDays int) func() {
    if cfg == nil || !cfg.Enabled || db == nil {
        return func() {}
    }
    // ...
    retention := time.Duration(retentionDays) * 24 * time.Hour
    if retention <= 0 {
        retention = 30 * 24 * time.Hour
    }
    runMaintenance := func() {
        if err := pm.PartitionMaintenanceForTableWithRetention(maintenanceCtx, appdb.LogTable, retention); err != nil {
            applogger.Log.Warn("partition maintenance failed", zap.String("table", appdb.LogTable), zap.Error(err))
        }
    }
    // ...
}
```

而账本表走的是另一个入口：

```go
// app/billing/cmd/billing/billing_helpers.go
err := pm.PartitionMaintenanceForTable(maintenanceCtx, appdb.BillingLedgersTable)
```

两个入口的分歧在中间这层：

```go
func (pm *PartitionManager) PartitionMaintenanceForTable(ctx context.Context, tableName string) error {
    retention := time.Duration(0)
    if tableName == LogTable {
        retention = 6 * 30 * 24 * time.Hour
    }
    return pm.PartitionMaintenanceForTableWithRetention(ctx, tableName, retention)
}

// PartitionMaintenanceForTableWithRetention performs routine partition
// maintenance for one table. A non-positive retention disables partition
// deletion, which is mandatory for billing_ledgers unless a separately
// approved archival/retention policy is introduced.
```

**账本表的 `retention` 是 0，也就是"不删"。** 而方法注释里那句 "which is mandatory for billing_ledgers" 说明这不是"我还没配"，而是**在代码里明确写死的决定**。

日志表是 180 天（`6 * 30` 天），而且那个默认值只在配置没给的时候生效。

两者共同的部分是 `EnsureFuturePartitions(ctx, tableName, 12)`——**无论哪张表，都保证未来 12 个月的分区存在。**

这个策略我认为是对的：

- **日志是可再生数据**，180 天之后没有保留价值，删掉是安全的；
- **账本是不可再生数据**，删掉就等于销毁财务记录。要删的话必须先有一个经过批准的归档方案。

注释里 "unless a separately approved archival/retention policy is introduced" 就是那个门槛——**它把"要不要删账本"从一个配置项变成了一个需要走审批的设计决定。**

### 5.3 两个都默认关闭

两个 `startPartitionMaintenance` 的开门条件是一样的：

```go
if cfg == nil || !cfg.Enabled || db == nil {
    return nil
}
```

**分区维护默认是关的**（`cfg.Enabled` 来自配置的特性开关）。所以即使代码齐全，默认部署下这些逻辑也不会运行。

而且它是个 no-op 降级：`db == nil`（内存存储）时直接返回一个空函数，不报错。

运行逻辑本身有两点我觉着挺好：

```go
go func() {
    ticker := time.NewTicker(interval)
    defer ticker.Stop()
    // Run once immediately so newly-enabled services don't wait a full
    // interval before their first partition is created.
    runMaintenance()
    // ...
}()
```

**启动时立刻跑一次**，而不是等第一个 tick。否则刚打开开关的服务要等 24 小时才会建第一张未来分区。

间隔默认 24 小时，而 `EnsureFuturePartitions` 保证 12 个月——**这个余量足够大，偶尔几次维护失败不会导致分区用完。**

---

## 6. 现在的状态和欠账

**已经能用的：**

- 96 个根迁移，MySQL 为规范源，Postgres/SQLite 走"基线 + 近期镜像"
- 三条可静态检查的治理规则：重复编号、方言镜像、服务归属
- 豁免列表都带 `reason`，且 `not_applicable` 的条目必须在根目录真实存在
- `make migration-check` 纯文件检查，进 `make verify`
- `migration-smoke-mysql` 起真库跑迁移，并验证"重复执行是 no-op"和"非法迁移会失败"
- 分区维护只在 MySQL 生效，其他方言优雅降级为 no-op
- 分区自动往前铺 12 个月；日志表按 180 天保留期删旧分区；账本表在代码里显式禁用删除
- 分区维护默认关闭（特性开关），且启动时立刻跑一次而非等首个 tick

**还没解决的：**

**第一，历史区间的方言覆盖只记录不强制。** `historical_coverage` 是一张文档表，82 个老迁移在 Postgres/SQLite 里到底覆盖没覆盖，只有 review 时人眼能发现漂移。没有测试能证明它。

**第二，分区维护默认关闭，所以「有自动删除」这件事默认不成立。** 逻辑是齐的（日志删、账本不删），但 `cfg.Enabled` 默认 false。一个默认关闭的维护任务，效果等于没有——这一点和我在第 15 篇说的熔断默认关闭是同一类欠账。

**第三，`auto_mirror_from_prefix: "072"` 这个边界是我拍的。** 我没有验证过 072 之前的每个变更在 Postgres/SQLite 上是否真的可用——只验证了"文件名在不在"。**文件名存在不等于 SQL 能在那个方言上跑通。**

**第四，Postgres 和 SQLite 的镜像只有最近的在 CI 里跑过真机。** `migration-smoke-mysql` 只跑 MySQL。另外两个方言的 smoke 我没做，所以它们目前只是"文件在"，不是"能跑"。

**第五，`manual/` 目录只有 2 个文件，没有治理。** 那两个是需要人工执行的 DDL（比如 `schema_split.sql`），它们不在编号序列里，也没有被任何检查覆盖。

**第六，ownership 清单是我手工维护的。** 加了新迁移就要回来加一行，忘了就会被 `migration-check` 拦住（这是设计意图），但"拦住"的代价是我得知道该归给谁——而有些表确实横跨多个服务（`000_create_core_tables` 那行注释里就写了 "subset owned by identity"）。

---

## 7. 下一篇

下一篇讲代码质量：298 个测试文件是怎么组织的、兼容性矩阵和 fixture 怎么用、以及那个确定性 mock upstream 是怎么让性能基线可复现的。

[《313 个测试文件，以及一次「测试自己坏了」的排查》](/2026-09-19-micro-one-api-testing-strategy/)
