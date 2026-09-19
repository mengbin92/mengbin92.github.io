---
title: "订阅账号治理：多副本同时跑定时任务，怎么保证不出错"
date: 2026-09-16T12:00:00+08:00
description: "订阅账号会有各种“暂时不能用”的情况：被上游限流了、额度用完了、凭据过期了、上游在抖动。这些状态都要有退出机制——总不能因为一次 429 就永远不再用这个账号。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个迟早要面对的问题

订阅账号会有各种"暂时不能用"的情况：被上游限流了、额度用完了、凭据过期了、上游在抖动。这些状态都要有退出机制——**总不能因为一次 429 就永远不再用这个账号。**

最自然的做法是定时扫一遍，把该恢复的恢复。

问题是：**channel-service 会有多个副本。**

那么"扫一遍"就有四个副本同时在扫。于是：

- 两个副本同时看到"这个账号的日窗口跨天了"，同时执行重置 → **额度被重置两次**（如果重置是"清零"，那没事；但如果重置动作包含"把窗口起点往前推"，重复执行就会推错）。
- 两个副本同时看到"这个账号的限流 TTL 到了"，同时清除标记 → 通常无害，但如果清除动作里有副作用（写审计、发通知）就会重复。
- 两个副本同时判定"这个账号额度用完了"，同时标记 → 无意义的工作量。

我在写这两个 sweeper 的时候，把"多副本并发"当成了默认前提，而不是事后补的考虑。这篇讲我处理它的方式，其中有一个我觉得挺通用的技巧。

---

## 1. 恢复策略：五种分类，而不是一个 TTL

第一版的恢复逻辑很简单：记一个 `rate_limited_until`，时间到了就清除。

问题很快暴露：**不是所有"不能用"都该自动恢复。**

- 被上游 429，等 5 秒就好了 → 应该自动恢复。
- 凭据失效（401），等多久都没用 → 自动恢复只会让它反复失败。
- 额度用完，要等窗口重置 → 不应该按固定 TTL 恢复，因为窗口重置时间不是固定的。
- 本地额度耗尽和上游快照耗尽，重置条件也不一样。

所以我把"为什么不能调度"变成了一个显式的策略字段：

```go
// Recovery policy classifications for unschedulable subscription accounts.
//
// The recovery sweeper uses these to decide whether an account may be
// auto-recovered: temporary upstream errors (429/5xx/529) auto-recover once
// their TTL expires; authorization errors (401/403) never auto-recover and
// require OAuth rebind or manual confirmation; local quota exhaustion waits
// for a window reset or manual reset; codex snapshot exhaustion waits for the
// upstream snapshot to reset.
const (
    RecoveryPolicyAuto    = "auto"    // temporary upstream error: auto-clear once TTL elapses
    RecoveryPolicyManual  = "manual"  // authorization error: never auto-recover
    RecoveryPolicyQuota   = "quota"   // local quota exhausted: wait for window reset
    RecoveryPolicyCodex   = "codex"   // codex snapshot exhausted: wait for snapshot reset
    RecoveryPolicyRolling = "rolling" // default when no marker is set
)
```

策略是从状态码推出来的：

```go
func recoveryPolicyForStatus(statusCode int) string {
    switch {
    case statusCode == 401 || statusCode == 403:
        return RecoveryPolicyManual
    case statusCode == 429 || statusCode == 529 || statusCode >= 500:
        return RecoveryPolicyAuto
    default:
        return RecoveryPolicyRolling
    }
}
```

`RecoveryPolicyRolling` 是"没有明确标记时的默认值"，它的意思是"按本地状态检查决定"——主要给滚动窗口的额度恢复用。

这些标记存在账号的 `metadata` JSON 里：

```go
const (
    metaKeyLastError           = "last_error"
    metaKeyRecoveryPolicy      = "recovery_policy"
    metaKeyUnschedulableReason = "unschedulable_reason"
    metaKeyUnschedulableSince  = "unschedulable_since"
    metaKeyUnschedulableUntil  = "unschedulable_until"
    metaKeyExpectedRecoveryAt  = "expected_recovery_at"
    metaKeyLastQuotaAlertAt    = "last_quota_alert_at"
    metaKeyLastQuotaAlertKind  = "last_quota_alert_kind"
)
```

**为什么要存 `unschedulable_since`、`unschedulable_until` 和 `expected_recovery_at` 三个时间？**

- `since`：什么时候开始不能用的（用于告警"这个账号已经坏了 2 小时"）。
- `until`：冷却什么时候结束（运行时封禁，第 4 篇讲过）。
- `expected_recovery_at`：**预计什么时候能恢复**（额度窗口的重置时间）。

前两个是事实，第三个是预测。运营最想看的是第三个——"这个账号还要多久才能用"。如果是 429 冷却，答案是 5 秒；如果是日额度用完，答案是"今天几点重置"。

因为存了明确的策略和预测时间，第 8 篇那四种配额告警才能分出来。

### 1.1 `Manual` 是唯一不自动恢复的

```go
// Authorization errors are never auto-recovered.
if policy == RecoveryPolicyManual {
    metrics.SubscriptionAccountRecoveriesTotal.WithLabelValues(policy, "skipped").Inc()
    return
}
```

**401/403 一定需要人工介入**：要么重新走一遍 OAuth 绑定，要么确认这个账号是不是被封了。自动恢复只会让它每 5 分钟失败一次，把日志刷满，而且掩盖真正的问题。

`skipped` 这个指标标签让它可见——运维能看到"有 3 个账号因为策略是 manual 而没有被恢复"，而不是"这些账号好像被人忘了"。

---

## 2. 恢复前探测：不要只看本地时钟

这是我觉得这一段里最实在的一个设计。

`auto` 策略的恢复条件是"TTL 到了"。但**TTL 到了不代表上游真的恢复了**。一个账号被限流 5 秒，5 秒后我再去重试，可能还是 429——因为上游的限流窗口比 5 秒长。

所以加了一层可选的探测：

```go
// RecoveryProber performs a lightweight upstream probe to verify an account is
// actually serving again before the recovery sweeper clears its unschedulable
// markers (roadmap §1.2 "增加恢复前探测策略, 只对可安全探测的平台执行轻量
// 请求"). Implementations MUST be safe to leave nil (no probe available): the
// sweeper then falls back to its existing local-state check. Only platforms the
// prober explicitly supports are probed; others recover via the local path.
type RecoveryProber interface {
    // ProbeRecovery performs a lightweight upstream check for the account. It
    // returns ok=true when the upstream confirms the account is healthy
    // (e.g. a 1-token request succeeds), ok=false when the upstream still
    // rejects it, and err!=nil when the probe could not be run (network,
    // unsupported platform). A nil prober means "no probe configured" and the
    // sweeper treats every account as probe-eligible via its local checks.
    ProbeRecovery(ctx context.Context, account *SubscriptionAccount) (ok bool, err error)
}
```

注意接口注释里的两个约束：

**"MUST be safe to leave nil"**：没有探测实现时，退回纯本地状态判断。这样加这个功能不需要一次到位。

**"Only platforms the prober explicitly supports are probed"**：不是每个平台都能安全探测。有的平台发一个 1-token 请求也会消耗额度，或者会污染会话。所以探测是按平台选择加入的，不是默认全开。

调用点：

```go
probeGate := func(resultLabel string) bool {
    if s.prober == nil || (policy != RecoveryPolicyAuto && policy != RecoveryPolicyRolling) {
        return true
    }
    ok, perr := s.prober.ProbeRecovery(ctx, account)
    if perr != nil {
        // Probe unavailable (unsupported platform / network): fall back to
        // local-state recovery so we do not strand accounts on platforms the
        // probe does not cover.
        metrics.SubscriptionAccountRecoveriesTotal.WithLabelValues(policy, "probe_unavailable").Inc()
        return true
    }
    if !ok {
        metrics.SubscriptionAccountRecoveriesTotal.WithLabelValues(policy, "probe_negative").Inc()
        return false
    }
    metrics.SubscriptionAccountRecoveriesTotal.WithLabelValues(policy, "probe_confirmed").Inc()
    return true
}
```

三个分支的处理不一样，这是我想清楚之后才定的：

| 探测结果 | 处理 | 理由 |
|---|---|---|
| `ok = true` | 放行恢复 | 上游确认好了 |
| `ok = false` | **不恢复** | 本地 TTL 到了但上游还在拒 |
| `err != nil` | **放行恢复**（退回本地判断） | 探测本身失败了，不能因此把账号困住 |

第三行是我改过的一次。最初我让"探测失败"也阻止恢复——想法是"探测不了就别动"。结果是**凡是探测不支持的平台，账号一旦不可调度就再也不会恢复**，因为每次探测都返回 err。

现在的原则是：**探测失败只影响"我能不能更保守"，不影响"这个账号能不能恢复"。** 探测的作用是在"本地判断说可以了"的时候多拦一道，而不是变成一个新的前置条件。

---

## 3. 第一个多副本问题：窗口重置的幂等

### 3.1 问题是什么

固定窗口策略的账号，需要有人在跨天/跨周的时候把用量清零。这是 `QuotaResetSweeper` 干的活。

四个副本同时扫，同一个账号会被四个副本同时判定"跨天了"。如果直接执行"清零"，重复清零本身无害。但真正的重置动作不只是清零，还要**推进窗口起点**：

```go
// Idempotency: a reset is only applied when the stored window_start is older
// than the current fixed window start. After the reset the window_start is
// advanced to the current fixed window start, so a repeated worker tick within
// the same boundary observes no drift and performs no work. A durable record
// is written to subscription_account_quota_reset_runs whose (account, scope,
// window_start) unique key prevents duplicate resets even across replicas.
```

这是 `QuotaResetSweeper` 的文档注释，它把两层防护都写了。

### 3.2 第一层：状态自查

```go
func (s *QuotaResetSweeper) resetIfCrossedBoundary(ctx context.Context, account *SubscriptionAccount, now time.Time, scope string) {
    fixedStart := account.FixedQuotaWindowStart(now, scope)
    var storedStart int64
    switch scope {
    case "daily":
        storedStart = account.QuotaDailyWindowStart
    case "weekly":
        storedStart = account.QuotaWeeklyWindowStart
    default:
        return
    }
    // No usage yet, or already aligned to the current fixed window: nothing to do.
    if storedStart <= 0 || storedStart >= fixedStart {
        return
    }
    // ...
}
```

`storedStart >= fixedStart` 就返回。**第一次重置把 `window_start` 推到了当前窗口起点，第二次扫描就会命中这个条件直接返回。**

这一层在单副本下就够了。但多副本下不够——两个副本可能**同时**读到旧的 `storedStart`，都通过了这个检查。

### 3.3 第二层：数据库唯一键

真正的兜底在数据库：

```sql
CREATE TABLE IF NOT EXISTS `subscription_account_quota_reset_runs` (
  ...
  UNIQUE KEY `idx_subscription_account_quota_reset_runs_dedupe` (`subscription_account_id`, `scope`, `window_start`),
  KEY `idx_subscription_account_quota_reset_runs_account_time` (`subscription_account_id`, `reset_at`)
);
```

唯一键是 `(账号, 作用域, 窗口起点)`。

**为什么包含 `window_start`？** 因为同一个账号的"日"和"周"是两个独立的 scope，而且要允许**下一个窗口**再重置一次。如果唯一键只是 `(账号, scope)`，那这个账号这辈子只能重置一次。

调用方式：

```go
if applier, ok := s.recorder.(QuotaResetRunApplier); ok {
    if err := applier.RecordQuotaResetAndReset(ctx, run); err != nil {
        if err == ErrQuotaResetRunDuplicate {
            metrics.SubscriptionAccountQuotaResetsTotal.WithLabelValues(scope, "duplicate").Inc()
        } else {
            metrics.SubscriptionAccountQuotaResetsTotal.WithLabelValues(scope, "error").Inc()
        }
        return
    }
    metrics.SubscriptionAccountQuotaResetsTotal.WithLabelValues(scope, "success").Inc()
    return
}
```

`RecordQuotaResetAndReset` 把"记录这次重置"和"执行重置"放在一个事务里。唯一键冲突时返回 `ErrQuotaResetRunDuplicate`，于是**只有一个副本会真正执行重置，其余的走 duplicate 分支什么都不做。**

而且这个冲突是**被当作正常路径**处理的（`duplicate` 指标，不是 error）。这一点我认为很重要：**在并发场景下，"我抢输了"是预期行为，不是异常。** 如果把它记成 error，指标会被正常的竞争刷满，真正的错误反而看不见。

### 3.4 降级路径

```go
if s.recorder != nil {
    if err := s.recorder.RecordQuotaResetRun(ctx, run); err != nil {
        // Already recorded by another replica/tick — skip the write.
        metrics.SubscriptionAccountQuotaResetsTotal.WithLabelValues(scope, "duplicate").Inc()
        return
    }
}
if err := s.repo.ResetSubscriptionAccountQuota(ctx, account.ID, scope); err != nil {
    // ...
}
```

如果 recorder 不支持原子的 `RecordQuotaResetAndReset`，就退回"先记录再重置"两步。

**这两步之间有一个窗口**：记录成功、重置失败，那么这条重置记录存在但重置没发生，之后所有副本都会认为"这个窗口已经重置过了"从而跳过——**额度就永远不会被重置了。**

这是降级路径的已知代价。它比"两个副本同时重置导致窗口起点推错"要好，但仍然不理想。我在"还没有更好的办法"和"至少标记了它"之间选了前者，把 `error` 标签留在指标上。

---

## 4. 第二个多副本问题：单用户单 active 订阅

这个约束不在账号治理里，但它是同一类问题的最典型例子，我觉得放在这篇讲最合适。

### 4.1 业务需求

一个用户同时只能有一个 active 订阅。为什么？

- 额度是"这个用户这个月能用多少"，两个 active 订阅就有两套额度，用户等于白拿一份。
- 续费语义会变得歧义：延长哪个？
- 计费侧拆分"这笔消耗算哪个订阅"会变成多对多。

### 4.2 用应用层保证必然失败

自然的写法是：购买前先查有没有 active 订阅，没有就创建。

**这个写法在并发下必然是错的。** 两个支付回调（或者用户双击、或者重试的新购和续费）会同时查到"没有 active"，然后各自创建一个。

所以我把这个约束下沉到了数据库：

```sql
-- Phase 2 review H10: enforce a single active subscription per user at the DB
-- level. A generated column exposes user_id only for active rows (NULL
-- otherwise) so a UNIQUE index on it permits multiple non-active rows per
-- user (expired/revoked) while forbidding two concurrent active rows.
-- Concurrent payment callbacks / new-purchase vs renewal races that both
-- read "no active" and CreateSubscription will now collide on this index
-- instead of producing two active subscriptions.

ALTER TABLE `user_subscriptions`
  ADD COLUMN `active_user_id` bigint GENERATED ALWAYS AS
    (IF(`status` = 'active', `user_id`, NULL)) VIRTUAL,
  ADD UNIQUE INDEX `uniq_user_subs_active_user_id` (`active_user_id`);
```

这段我觉得设计得很巧，值得展开讲：

**生成列 `active_user_id`**：只有当 `status = 'active'` 时才等于 `user_id`，否则是 `NULL`。

**在它上面加唯一索引**：于是同一个 `user_id` 最多只能有一行非 NULL。而 `NULL` 在唯一索引里是可以重复的（SQL 标准行为），所以一个用户可以有任意多个 expired / revoked 的历史订阅。

**结果**：数据库层面保证"每个用户最多一个 active 订阅"，同时不限制历史记录。

而不用 `UNIQUE(user_id, status)` 的原因也很清楚：那会限制"一个用户只能有一个 revoked 订阅"，这显然不对。

### 4.3 冲突了之后怎么办

数据库拦住之后，应用层要处理这个冲突：

```go
if err != nil {
    if isDuplicateKeyErr(err) {
        return biz.ErrSubscriptionAlreadyAssigned
    }
    return err
}
```

**把主键冲突翻译成一个业务错误。** 这是分层契约的一个标准动作：driver 的错误不能往上冒（第 1 篇的分层约定），data 层负责翻译成 biz 层的类型化错误。

于是支付回调拿到的是一个明确的 `ErrSubscriptionAlreadyAssigned`，可以据此决定"这单算已处理"（幂等成功）还是"报错给用户"。

### 4.4 这个模式的通用性

我认为这个技巧可以推广：**当一个业务约束是"某种状态下最多一条"时，用生成列把它变成一个数据库唯一约束。**

SQL Server / PostgreSQL 的部分索引（partial index）能更直接地表达它：

```sql
CREATE UNIQUE INDEX ... ON user_subscriptions(user_id) WHERE status = 'active';
```

MySQL 不支持部分索引，所以生造了一个生成列来模拟。**两者的思路是一样的：把"只在满足条件时才存在"变成一个可以被唯一索引覆盖的列值。**

比"应用层加锁"好在哪：不需要分布式锁、不需要序列化、不依赖任何中间件，而且**即使有人绕过应用层直接写数据库，约束依然成立。**

---

## 5. 这三层防护的分工

写到这里可以总结一下我在这件事上的分层：

| 层 | 手段 | 覆盖什么 | 覆盖不了什么 |
|---|---|---|---|
| 状态自查 | 读到的 `window_start >= 当前窗口起点` 就返回 | 同一副本的重复执行 | 多副本同时读到旧值 |
| 数据库唯一键 | `(account, scope, window_start)` | 跨副本的并发重置 | 记录成功但副作用失败 |
| 业务约束 | 生成列 + 唯一索引 | 并发创建 | 需要额外处理冲突错误 |

**关键是第一层不能替代第二层。** 状态自查是最便宜的（一次比较），但要靠它保证正确性就是错的——它只是一个"快速跳过无谓工作"的优化。

我见过不少项目在这一点上偷懒：查一下"这个状态已经是对的了吧"，是就跳过。**在单副本下能跑很多年，一旦扩到两个副本就开始偶发重复执行。** 而这类 bug 因为偶发、因为"看起来没造成什么问题"，通常拖很久才被发现。

我的原则是：**任何"扫描并修复"的定时任务，都要假设它会被多个副本同时执行，而且它们会同时读到同一份旧状态。**

---

## 6. 现在的状态

**已经能用的：**

- 五种恢复策略，401/403 永不自动恢复
- 恢复前轻量探测，探测失败不阻塞恢复
- 窗口重置：状态自查 + `(account, scope, window_start)` 唯一键双保险
- 重置记录落表，可审计
- 单用户单 active 订阅由数据库生成列 + 唯一索引保证
- 冲突被翻译成业务错误而不是 driver 错误
- 各种结果都有指标标签：`success` / `duplicate` / `error` / `skipped` / `waiting` / `probe_*`

**还没解决的：**

**第一，降级路径有一个窗口。** 不支持原子 `RecordQuotaResetAndReset` 时，"记录成功、重置失败"会让这个窗口永久不再重置。目前靠 `error` 指标暴露，没有自动补偿。

**第二，sweeper 是固定间隔全表扫描。** 5 分钟一次、每页 200 条。账号多了之后扫一遍的开销会线性增长，而且扫描间隔和恢复及时性绑定了——想让恢复更快就得扫得更勤。

**第三，探测的额度成本没有计量。** 探测会发真实的轻量请求，消耗一点额度。这部分消耗没有单独记账，也就无法评估"探测值不值"。

**第四，`expected_recovery_at` 是预测，可能不准。** 它根据策略算出来（TTL 到期时间 / 窗口重置时间），但上游的真实恢复时间可能不同。运营如果完全信任这个字段会误判。也许该把它明确标成"预计"——现在字段名里的 `expected` 承担了这个职责，但 UI 上未必体现。

**第五，`Manual` 策略的账号需要人处理，但没有"待处理清单"入口。** 运维得自己去查哪些账号策略是 manual、已经卡了多久。这是运营体验上的缺口。

---

## 7. 下一篇

下一篇讲可观测性：哪些指标真的有用、哪些是我加了之后从来没看过、trace 怎么贯穿跨服务的调用链，以及我为什么给请求打了一堆低基数标签而不是用模型名。

[《可观测性：一个指标记错了五次，以及很多次我加了指标却从来没看过》](/2026-09-18-micro-one-api-observability/)
