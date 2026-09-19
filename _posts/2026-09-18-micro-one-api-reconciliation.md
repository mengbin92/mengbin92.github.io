---
title: "对账：七类核对、五种容差，以及“只报告不修复”为什么是对的"
date: 2026-09-18T12:00:00+08:00
description: "我第一版的对账逻辑很简单：把钱包余额和账本净额比一下，不一致就报出来。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 第一版对账：全是误报

我第一版的对账逻辑很简单：**把钱包余额和账本净额比一下，不一致就报出来。**

跑起来之后，几乎每个用户都进了异常列表。

排查下来有两个原因，都是我没想清楚"余额"到底是什么：

**第一，预扣会把钱从余额挪到冻结，但不写账本。**

用户余额 100，请求预扣 5 元（在途），钱包变成 `balance = 95, frozen = 5`。而我拿去比对的"账本净额"还是 100——因为预扣不产生账本记录（它只是把钱冻起来）。

于是 `95 != 100`，报异常。

**第二，有些账户的期初余额没有账本记录。**

最早那批用户是直接写进数据库的，没有对应的 `billing_ledgers` 行。所以"账本净额"是 0，而余额是 500。这个差值永远存在，而且不是错误。

修正之后：

```go
for _, account := range accounts {
    ledgerBalance, found, err := uc.reconRepo.LatestLedgerBalanceAfter(ctx, account.UserID)
    if err != nil {
        continue
    }
    // An account with no ledger has no persisted opening-balance baseline;
    // do not manufacture a mismatch from an unknown initial value.
    if !found {
        continue
    }
    // Reserving quota moves funds from balance to frozen without writing a
    // ledger entry. Subtract the currently frozen amount from the latest
    // settled snapshot before comparing the available wallet balance.
    expectedBalance := ledgerBalance - account.FrozenAmount
    diff := account.Balance - expectedBalance
    if diff < 0 {
        diff = -diff
    }
    if diff > 100 {
        result.AccountInconsistencies = append(result.AccountInconsistencies, AccountInconsistency{...})
    }
}
```

两个关键改动：**减掉冻结额**、**没有账本记录就跳过（而不是当成 0）**。

第二点我想单独说，因为它是这一篇里最通用的一条：

```go
// An account with no ledger has no persisted opening-balance baseline;
// do not manufacture a mismatch from an unknown initial value.
```

**"我不知道初始值"和"初始值是 0"是两件事。** 我原来的代码把"查不到账本"当成了"账本是 0"，于是凭空制造了一堆差异。

注释里那句 "do not manufacture a mismatch from an unknown initial value"（不要用一个未知的初始值去制造差异）是我后来补的。一个对账系统最大的失败模式就是误报——**当异常列表里 99% 是噪音时，那个真的差异你就看不见了。**

---

## 1. 七类核对

现在的对账覆盖七个维度，每一类对应一种独立的账务关系：

```go
const (
    ReconciliationDiscrepancyTypeAccount       = "account_quota"
    ReconciliationDiscrepancyTypeChannel       = "channel_usage"
    ReconciliationDiscrepancyTypeLog           = "ledger_log_consume"
    ReconciliationDiscrepancyTypeSubscription  = "subscription_absorption"
    ReconciliationDiscrepancyTypeReceivable    = "receivable_mirror"
    ReconciliationDiscrepancyTypeRefund        = "refund_reversal"
    ReconciliationDiscrepancyTypeStuckIssuance = "stuck_issuance"
)
```

| 类型 | 核对的是 | 两侧 |
|---|---|---|
| `account_quota` | 钱包余额对不对 | 余额+冻结 ↔ 账本净额 |
| `channel_usage` | 渠道用量对不对 | 渠道 `used_quota` ↔ 按渠道汇总的消费账本 |
| `ledger_log_consume` | 账本和日志是否双写一致 | ledger 汇总 ↔ log 汇总 |
| `subscription_absorption` | 订阅额度消耗对不对 | 订阅窗口用量 ↔ 带倍率的账本成本 |
| `receivable_mirror` | 应收款和透支是否镜像 | 待收总额 ↔ 负余额总额 |
| `refund_reversal` | 退款/冲正是否配平 | — |
| `stuck_issuance` | 有没有卡住的发放 | — |

**七类而不是一类，是因为"账不平"这个结论太笼统了。** 到底是钱包算错了、渠道统计错了、还是日志丢了？三种情况的处理方式完全不同。

从 `ReconciliationResult` 的结构也能看出来，它不是一个布尔值而是一组分片结果：

```go
type ReconciliationResult struct {
    RunID                        int64
    RunAt                        time.Time
    ExpiredCleaned               int
    AccountInconsistencies       []AccountInconsistency
    ChannelInconsistencies       []ChannelInconsistency
    LogInconsistencies           []LogInconsistency
    SubscriptionInconsistencies  []SubscriptionInconsistency
    ReceivableInconsistencies    []ReceivableInconsistency
    RefundInconsistencies        []RefundInconsistency
    StuckIssuanceInconsistencies []StuckIssuanceInconsistency
    TotalAccounts                int
    TotalChannels                int
    TotalReservations            int
    TotalSubscriptions           int
}
```

带上了各个维度的总量。**没有总量的差异数字是没有意义的**——"3 个账户不一致"，在总共 10 个账户和总共 10 万个账户下，是完全不同的严重程度。

---

## 2. 顺手清理：过期预约

对账的第一个动作不是"检查"，而是"修正在途状态"：

```go
// Step 1: Clean up expired reservations via the unified release
// path so the wallet refund + ledger + status transition are in
// one transaction. The legacy UpdateReservationStatus +
// UpdateFrozenAmount + UpdateBalance sequence is gone.
expired, err := uc.reservationRepo.GetExpiredReservations(ctx)
```

一个预扣如果永远不被提交或释放，那笔冻结的钱就永远冻着。所以对账顺带做一次超时释放。

这段代码里有个我觉得值得单独讲的 bug 修复：

```go
// Atomic path: CAS reserved -> releasing -> expired in one
// transaction, refunding the wallet-side BalanceAmount
// (not the full Amount) and writing the dedupe-keyed refund
// ledger. This is the same pipeline used by explicit
// ReleaseQuota and CommitQuota success=false, so a dual-track
// reservation whose cost was fully absorbed by the
// subscription (BalanceAmount == 0) refunds zero to the
// wallet instead of minting the full Amount.
if err := uc.releaser.ReleaseReservation(ctx, res.ReservationID, "reconciliation: reservation expired", ReservationStatusExpired); err != nil {
```

**一个预约有两个金额：`Amount`（这笔调用应付多少）和 `BalanceAmount`（其中由钱包出的部分）。**

在一笔订阅全额抵扣的调用里，`Amount = 0.05` 而 `BalanceAmount = 0`——钱该由订阅额度出，钱包一分不动。

如果释放时退的是 `Amount`，那么：

1. 预扣时钱包冻结 0（因为 `BalanceAmount = 0`）；
2. 释放时钱包收到 0.05；
3. **凭空多出 0.05。**

这就是注释里 "instead of minting the full Amount"（而不是凭空造出整个 Amount）的意思。

而 legacy 的降级路径里还留着正确的写法：

```go
} else {
    // Legacy fallback when no billing usecase is wired (tests).
    // Refund the wallet-side BalanceAmount so a fully
    // subscription-absorbed reservation does not mint money.
    refundAmount := res.BalanceAmount
    if refundAmount > 0 {
        _ = uc.accountRepo.UpdateFrozenAmount(ctx, res.UserID, -refundAmount)
        _, _ = uc.accountRepo.UpdateBalance(ctx, res.UserID, refundAmount, LedgerTypeRefund)
    }
```

**"退多少钱"这个判断，两个金额字段选错一个就会造钱。** 这类 bug 不会报错、不会崩，只会让账目慢慢偏。

---

## 3. 五种容差，而且不能统一

这是我做对账时最花心思的部分。

七类核对用了五种不同的容差：

| 核对 | 容差 | 单位 |
|---|---|---|
| 钱包余额 | `> 100` | 最小金额单位（1 = 0.0001 USD） |
| 渠道用量 | `diffAbs(...) > 100` | 同上 |
| 订阅窗口 | `> 0.0001001` | USD（浮点） |
| 账本 ↔ 日志 | **`> 0`**（零容差） | 计数和金额 |
| 应收镜像 | 精确相等 | — |

### 3.1 为什么钱包是 100 而不是 0

`100` 个最小单位 = 0.01 USD。

留这 0.01 不是偷懒，是因为**账本和余额的写入路径不完全相同**。余额是一个累加的整数列，账本是一行行的流水，两者在并发下的可见时机可能有微小差异。

我用一个分币级的容差换掉"因为一个单位的四舍五入就报异常"。

**这个 100 不是理论推导出来的，是试出来的**：我先把容差设成 0，看到了大量 1-2 个单位的差异；设成 100 之后归零。如果以后看到 150 的差异，那大概率是真的。

### 3.2 为什么订阅用浮点容差

```go
// The subscription columns store four decimal places. Permit one
// fixed-point unit plus a small float representation epsilon.
if math.Abs(difference) > 0.0001001 {
```

订阅的用量是 `float64` 存的美元（第 8 篇讲过原因），四位小数。

所以容差是 `0.0001`（一个最小单位）加上 `0.0000001` 的浮点表示误差。**这个多出来的小数尾巴不是凑数，是必需的**——`0.1 + 0.2 != 0.3` 的问题在这里会真实触发。

### 3.3 为什么账本和日志是零容差

```go
countDiff := ledgerSummary.Count - logSummary.Count
quotaDiff := ledgerSummary.Quota - logSummary.Quota
// ...取绝对值
if countDiff > 0 || quotaDiff > 0 {
    result.LogInconsistencies = append(result.LogInconsistencies, LogInconsistency{...})
}
```

注意注释里那句：

```go
// Step 4: Log<->ledger consume summary. The legacy
// duplicate-write path is still in place, so the existing
// tolerance check stays.
```

这段代码是我准备讨论的一个矛盾点：**其余核对都留了容差，为什么这一对是零？**

我的理由是：**账本和日志是"同一次写入的两个输出"，不是"两个独立计算的量"。** 如果双写正确，它们的数量和金额应该逐位相等；任何差异都说明写漏了一次或写重了一次，没有任何"合理的舍入空间"。

而钱包余额和账本是两个不同路径算出来的东西，容差是给"路径差异"留的。

**判断该不该留容差的标准是：这两个数是不是同源的。**

- 同源（一次操作的两种记录）→ 零容差。
- 不同源（两条独立路径）→ 允许路径差异带来的小误差。

如果反过来——该零的地方留了容差，真差异会被吃掉；不该零的地方零容差，会淹没在误报里。

---

## 4. "只报告不修复"：我为什么坚持这条

这个决定是我在对账上最坚持的一条，代码里在四个地方重复写了同一句话：

```go
// not auto-repair (code-review M1).
```

```go
// The reconciliation job reports it but does not auto-repair.
```

```go
// track ledger entries. We report but do not auto-repair.
```

```go
// these so an operator can re-trigger completion; it does not auto-repair
```

四个地方写四遍，是因为我担心以后有人（包括我自己）觉得"反正知道正确值了，顺手改一下吧"。

### 4.1 为什么不自动修

**第一，对账算出来的"正确值"可能才是错的。**

回到第 0 节那个例子：我第一版的"期望余额"是错的（没减冻结），如果它还能自动"修正"钱包，它会把所有用户的余额都改错。

**一个会写账的检查器，它的 bug 就是事故。** 一个只读的检查器，它的 bug 只是一个烦人的报告。

**第二，账本是 append-only 的。**

第 8 篇讲过预扣时会冻结窗口和倍率，就是为了让账本可追溯。在一个 append-only 的账本上，"修正"不该是一次 `UPDATE`，而该是**一条新的、记录了原因的反向记录**。

如果对账直接 `UPDATE` 了余额或删了账本行，那**"为什么变了"这个问题就永远没有答案了**。

**第三，差异本身就是信息。**

一个账户差 0.05 元，可能的原因有很多种：双写漏了、并发丢了、有人手工改了库、或者是一个我还没意识到的代码 bug。

自动修复会把这个信息变成"已解决"，然后你就可以永远不知道真正的原因。**报告会保留这个疑问，而疑问是修 bug 的起点。**

### 4.2 那什么时候才修

我的流程是：**先看报告，定位到具体原因，然后用一次显式的、带原因的操作去修正。**

从 `docs/runbooks/historical-ledger-audit.md` 这个文件名也能看出来这个思路——历史账本的审计是一个单独的动作，产物是 `.tsv` / `.csv` / `.json` 报告文件，不是自动执行。

而报告里的判断标准我也写在文档里了：**没有证据不冲正，原账本保持 append-only。**

"没有证据"这四个字是关键。差异存在不等于知道该往哪个方向修——少了 0.05 可能是少记了一笔收入，也可能是多记了一笔支出。**在没有确定原因之前动手，有 50% 的概率把它改得更糟。**

---

## 5. 运行记录与指标

每次对账都会留下结果，而且状态分了三种：

```go
defer func() {
    status := "success"
    if err != nil {
        status = "error"
    } else if result.DiscrepancyCount() > 0 {
        status = "discrepancy"
    }
    metrics.ReconciliationRunsTotal.WithLabelValues(status).Inc()
    metrics.ReconciliationRunDuration.WithLabelValues(status).Observe(time.Since(startedAt).Seconds())
    // 按类型分别计数
    metrics.ReconciliationDiscrepanciesTotal.WithLabelValues(ReconciliationDiscrepancyTypeAccount).Add(float64(len(result.AccountInconsistencies)))
    // ...
}()
```

三种状态的区别很重要：

| 状态 | 含义 | 该做什么 |
|---|---|---|
| `success` | 跑通了，没发现差异 | 没事 |
| `discrepancy` | 跑通了，发现差异 | 去看报告 |
| `error` | **对账本身失败了** | 先修对账，因为它现在是瞎的 |

**`error` 和 `discrepancy` 必须分开。** 如果对账执行失败也记成"有差异"，你会去查账；如果记成"成功"，你会以为账是平的——而实际上是**这次根本没检查**。

这和第 17 篇那条是同一条：**空手而归和从未出发，在观测上必须能区分。**

而 `ReconciliationDiscrepanciesTotal` 按类型分开计，是为了回答"哪一类问题在变多"。总数不变但 `channel_usage` 在涨，说明系统某处正在变坏。

---

## 6. 一个我特意保留的检查

第 3.3 节提到的账本↔日志核对，注释里我写了 "The legacy duplicate-write path is still in place, so the existing tolerance check stays"。

这句话值得展开：**这个检查之所以还需要，是因为我知道系统里还有一条我不信任的路径。**

账本和日志是双写的。双写意味着两次写入可能不一致，而我又没有把它们放进一个事务（日志服务是独立服务，第 2 篇讲过它是 best-effort 的）。所以这个检查是对"我知道这里可能出问题"的一种兜底。

**对账不是"证明系统正确"，而是"为我已知的薄弱环节装一个探测器"。**

这一点影响了我怎么决定核对哪些维度：我不是从"理论上该核对什么"出发的，而是从"哪里的写入路径不是原子的、哪里的数据有多份副本、哪里的计算有两条路径"出发的。

七类核对大致对应七处我认为可能出问题的地方：

- 钱包余额：余额是累加列，账本是流水 → 两条路径
- 渠道用量：`used_quota` 是异步累加的（第 2 篇的 `RecordChannelUsage` 是 fire-and-forget）
- 账本 ↔ 日志：双写，不在同一事务
- 订阅窗口：记账时有倍率、汇总时也要乘倍率 → 两处计算
- 应收镜像：负余额是钱包列，应收是独立表 → 两份数据
- 退款/冲正：反向记录的正确性
- 卡住的发放：状态机停在中间态

**每一类背后都有一个具体的、我能说出来的"为什么这里可能不平"。**

---

## 7. 现在的状态和欠账

**已经能用的：**

- 七类核对，各自独立报告，带总量
- 五种容差，按"是否同源"决定留不留
- 跑之前先清理过期预约，且退款按 `BalanceAmount` 而不是 `Amount`
- **只报告不修复**，四个地方都写明了
- 运行状态分三态（`success` / `discrepancy` / `error`）
- 差异按类型分别计数
- 历史审计是一次独立的只读动作，产物是报告文件

**还没解决的：**

**第一，对账是全量扫描，没有增量。** `ListAllAccounts` 把所有账户拉出来逐个比。账户规模上来之后，单次对账的时间和数据库压力会线性增长。

**第二，告警正文漏了两类差异。** 这个我是在写这篇的时候才核对出来的。

通知的开关是看总数：

```go
if j.notifier == nil || result.DiscrepancyCount() == 0 {
    return
}
```

`DiscrepancyCount()` 把**七类全算进去**，所以有差异就通知这一层是完整的。但通知正文 `buildAlertContent` 只展开了五类：账户、渠道、账本与日志、订阅、卡住的发放。

**没有展开的是应收镜像（`receivable_mirror`）和退款冲正（`refund_reversal`）。**

后果是一个很容易踩到的组合：如果某次对账**只**发现了应收镜像差异，你会收到一条标题写着 1 discrepancy 的告警，正文里却找不到这 1 条是什么。运维只能去看管理后台的对账页。

代码注释里写的意图是：

```go
// dispatchAlerts sends a single combined alert when discrepancies exist. We
// intentionally group all categories into one notification to avoid alert
// spam during partial outages; operators can drill down via the admin
// reconciliation page.
```

合并成一条通知避免告警风暴这个意图我认可，但**合并的前提是正文要完整**。合并加漏字段，等于一条让人看不懂的告警。

这类问题我觉得挺典型：**计数口径和展示口径是两套代码，改了其中一处不会提醒你另一处。** 修法很简单（把两类补进正文），但发现它需要专门去比对这两个函数。

**第三，没有"这个差异已经被人看过了"的状态。** 每次对账都是重新算的，同一个差异会一遍遍出现在报告里。缺少一个"确认/忽略"的标记，导致真正的新差异混在已知差异里。

**第四，容差是硬编码的。** `100`、`0.0001001` 这些值都写在代码里。不同环境的浮点行为或者不同业务的合理性可能不同，但我改不了。

**第五，`receivable_mirror` 是精确相等比较。** 这是我唯一没给容差的整数核对（因为两个数应该完全镜像）。但精确相等在有两个更新路径的系统里是很脆的，我还没有验证过它在并发下是否会稳定。

---

## 8. 下一篇

下一篇换方向讲前端：管理后台的 Apple 风格重设计。那一篇有一份罕见的量化基线（多少处硬编码颜色、对比度是多少、字号多小），我会讲"先量再改"这套流程怎么走，以及过程中哪些东西我说服自己放弃了。

[《先量再改：一次有审计底稿的 UI 重设计》](/2026-09-18-micro-one-api-web-redesign/)
