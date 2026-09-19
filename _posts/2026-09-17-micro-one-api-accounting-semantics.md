---
title: "订阅账务：续费、退款、冲正，以及“已售出的套餐被改了”怎么办"
date: 2026-09-17T12:00:00+08:00
description: "用户买了一个月的套餐，付了 20 块。用了 10 天，要求退款。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个看起来很简单的问题，答案不简单

用户买了一个月的套餐，付了 20 块。用了 10 天，要求退款。

**退多少钱？**

- 退 20？那他用掉的 10 天白用了。
- 退 10？按剩余时间比例退。
- 不退？那"退款"这个功能就没有意义。

而这只是开始。继续问：

- 退款之后，他的**订阅怎么处理**？立即失效？保留到月底？
- 如果他这 10 天里消耗的额度**已经超过**了剩余 10 天的价值，怎么办？
- 他**续费**过一次（比如买了两个月，用了 40 天），先退哪个？
- 退款是**支付渠道那边**发起的（用户走了平台仲裁），我怎么记录？
- 这笔退款在**账本**上怎么写？它和"消费退款"是同一类吗？

这篇讲我怎么处理这些。核心是三个操作——**续费、退款、冲正**——以及一个跨所有操作的机制：**购买时的套餐快照**。

---

## 1. 先定账本的形状：append-only

在讲这三个操作之前，先说我给账本定的规矩。

`billing_ledgers` 是**只追加**的。任何账务变动都是一条新记录，没有 `UPDATE`。

类型的枚举：

```go
LedgerTypeConsume      = "consume"
LedgerTypeRecharge     = "recharge"
LedgerTypeRefund       = "refund"
LedgerTypeRedeem       = "redeem"
LedgerTypeSubscription = "subscription"
```

**为什么不像钱包余额那样直接改一个数？**

因为余额只能回答"现在是多少"，而账本能回答"**为什么会是这个数**"。

一个用户说"我的钱不对"，如果只有一个余额字段，我只能说"系统显示是 37.5"。如果有账本，我可以列给他看：充值 100、消费 52.3、退款 20、兑换码 10——每一笔都有时间、有原因、有关联的订单号。

**这是"可解释性"的价值，而它在出问题的时候才体现出来。**

而 append-only 的一个直接后果是：**修正不能是"改一条旧记录"，而必须是"加一条反向记录"。** 这就是"冲正"这个概念的来源。

---

## 2. 续费：两个容易写错的地方

### 2.1 剩余时间必须累加，不能被覆盖

第一版的逻辑大概是：

```go
// 错的
newExpiresAt = now + duration
```

看起来没问题。但如果用户在一个还没到期的订阅上续费，比如还剩 20 天，买 30 天——按这个公式，新的到期时间是"从现在起 30 天"，**等于用户损失了那 20 天。**

我在代码注释里记了这次修复：

```go
// Extension always accumulates remaining time (review H3 fix): the new
// expires_at is max(active.ExpiresAt, now) + requestedDuration. The
// previous code dropped remaining time when the renewal duration was
// shorter than the remaining window (the common "renew close to expiry"
// case), truncating the user's entitlement. Centralizing the accumulation
// here makes the payment-callback path and the admin issuance path use
```

正确的公式是：

```
newExpiresAt = max(active.ExpiresAt, now) + duration
```

两个细节：

**用 `max(active.ExpiresAt, now)` 而不是直接用 `active.ExpiresAt`。** 如果订阅已经过期了（`active.ExpiresAt` 在过去），从这个时间点加时长会得到一个新的过期时间，可能还在过去。所以要和 `now` 取大值。

**这个累加逻辑要集中在一处。** 注释里强调的是 "Centralizing the accumulation here makes the payment-callback path and the admin issuance path use [the same rule]"。

**因为续费有两条入口：支付回调，和后台管理员手动发放。** 如果两处各写一遍，迟早会不一致——而用户会看到"后台给我加的天数比我自己买的多/少"。

我在第 8 篇里说过"检查额度和记录用量必须用同一个倍率"，这里是同一个道理：**同一个业务规则有多个执行路径时，规则必须只有一份实现。**

关于"剩余时间比新买时长短"这个场景，设计文档里还专门写了：

> 若新订单的 `expires_at` 落在当前 `expires_at` 之前，则按"叠加"语义处理，避免续费反而缩短有效期。

**"续费"这个动作的语义是"增加"，所以它在任何情况下都不该减少有效期。** 这个判断我认为是定义层面的，不是实现细节。

### 2.2 续费"策略"要能看出来

数据库里有一个字段叫 `renewal_strategy`：

```go
// RenewalStrategy records how a user's subscription came to be active, so the
// "expired but not revoked" renewal policy is explicit and observable rather
// than drifting with the hourly expiry scan (code-review M2). The behaviour is
// fixed: an unexpired subscription is extended in place (extend); a user with
// no active subscription — including one whose expires_at has passed and is
// therefore no longer "active" — gets a brand-new subscription (new). The
// column lets operators and reconciliation tell the two apart.
const (
    RenewalStrategyExtend = "extend" // renewed while active: remaining time + duration
    RenewalStrategyNew    = "new"    // granted when no active subscription existed
)
```

这个字段**不影响行为**——它只是记录"这次是怎么来的"。

为什么值得加一个字段？注释里那句 "rather than drifting with the hourly expiry scan" 是原因：

**一个订阅的"续费历史"不能被事后重建，因为它依赖当时的状态。** 用户是先过期了再买，还是在有效期内续的？这两个在结果上（都有一条 active 订阅）可能看起来一样，但对账和客服的意义不同。

**如果不记录，我就只能靠 `expires_at` 和时间戳去推测。** 而那个推测会随着定时任务的执行时刻漂移（因为"过期"这个状态是每小时扫一次标记的，不是精确到秒的）。

---

## 3. 设计文档和代码不一致的地方

这一节讲一个我在写这篇时核实出来的事，因为它本身就是一条教训。

设计文档 `subscription-renewal-semantics.md` 里有一节写"已过期订阅的重新激活策略"：

> 已过期但未撤销（`status=expired`，非 `revoked`）的订阅，策略固定为：
>
> **重新激活（reactivate）而非新建。**
>
> - 续费时若 active 订阅不存在但存在同组 `expired` 订阅，则把该 expired 订阅重新置为 active 并延长 `expires_at`。
> - 这保证同一用户在同一分组始终只有一条订阅记录……

但我看代码的时候发现不是这样。`assignOrExtend` 的逻辑是：

```go
if active == nil {
    var sub *UserSubscription
    var sErr error
    if tx != nil {
        sub, sErr = uc.AssignInTx(ctx, tx, req)
    } else {
        sub, sErr = uc.Assign(ctx, req)
    }
    return sub, false, sErr
}
```

**`active == nil` 时直接新建，没有"查同组的 expired 订阅"这个分支。**

而文档自己在末尾有一句注：

> 注：当前 `AssignOrExtend` 通过 `GetActiveSubscriptionByUser` 判断；expired→active 的重新激活由 expiry_checker 将过期 active 标记为 expired 后，下一次 `Assign`（无 active 时）新建。两种路径都保证用户唯一 active 订阅。若未来需要严格复用 expired 行，可在 `Assign` 中增加 expired 查找分支。

**"当前"这两个字救了这份文档。** 它说明作者（我）知道正文描述的是目标而不是现状，并且把差异写在了注里。

但这不是一个好形态。原因是：

**正文的措辞是"策略固定为：重新激活"，注里说"当前是新建"。** 一个读者只读正文就会得到一个错误的结论，而注释是最后一句话，很容易被跳过。

我认为正确的写法有两种：

**方案一：** 正文写"当前行为是新建，原因是 X；若需要重新激活，需要在 `Assign` 中加分支"。

**方案二：** 如果决定要做，就把它实现掉，然后文档不用改。

**我选了第三种（最差的一种）：正文写目标，注里写现状。** 这是"设计文档"和"实现说明"混在一起的结果——它读起来像在描述已经做到的事。

**这个例子让我对"文档和代码不一致"多了一种认识：它往往不是因为改了代码忘了改文档，而是因为写文档的时候就在写"打算这么做"。**

---

## 4. 支付回调的幂等：靠行锁，不靠应用逻辑

续费有一个绕不开的问题：**支付平台可能重复回调。**

同一笔订单的回调可能因为超时重试、用户刷新页面、或者平台自己的重试机制而到达多次。如果每次都执行续费，用户就白拿了很多时间。

处理方式在 `MarkOrderPaid` 里：

> 续费的支付回调幂等由 `MarkOrderPaid` 的事务守卫保证：
> - `MarkOrderPaid` 在事务内对订单加行锁（`SELECT ... FOR UPDATE`）。
> - 若订单已是 `paid`，直接返回 `changed=false`，**不重新执行 issue 回调**（不重复调用 assigner）。
> - 因此同一订单多次回调（重放、多副本、重复 notify）只产生一次续费效果，`expires_at` 只延长一次。

三个要点：

**第一，判断状态和改变状态在同一个事务里，而且加了行锁。** 如果没有行锁，两个并发的回调会同时读到 `pending`，然后都执行续费。

**第二，`changed=false` 是一个显式的返回值，而不是"什么都没做"。** 调用方可以据此判断"这次回调是重放"。

**第三，返回 `changed=false` 时不再调用 assigner。** 这一条是关键——**如果继续调用 assigner，而 assigner 自己是幂等的，那也没问题；但如果它不幂等，就出事了。** 在边界上多做一次判断，比依赖下游的幂等性可靠。

我在第 9 篇讲过"单用户单 active 订阅"用生成列 + 唯一索引来保证。**这里是同一个问题的另一层：在数据库约束之外，还需要一个事务级的守卫来避免"读到旧状态然后重复执行"。**

---

## 5. 退款/冲正：四个决定

### 5.1 决定一：给退款加一个终态

```go
const (
    // PaymentOrderStatusRefunded marks an order whose purchase has been
    // reversed. It is terminal.
    PaymentOrderStatusRefunded = "refunded"
)
```

订单状态从三个变四个：

| 状态 | 含义 | 终态 |
|---|---|---|
| `pending` | 待支付 | 否 |
| `paid` | 已支付并已发放权益 | 是 |
| `closed` | 已关闭（未支付） | 是 |
| `refunded` | 已退款/冲正 | 是 |

规则是：

> - 只有 `paid` 订单可以退款。`pending` 订单应走关闭（`closed`），`closed` 订单没有钱包变动可冲正。
> - 退款是终态：退款后的订单不能再次支付、关闭或退款。

**"只有 paid 可以退款"这条把两个不该退的情况排除掉了**：

- `pending`：还没付钱，退款这个动作没有对象。用户想取消应该走"关闭订单"；
- `closed`：已经关闭的订单，钱包里没有对应的变动，冲正会变成凭空加钱。

第二条（退款是终态）防的是"退款之后再退款"。有了这个状态，第二次退款会因为订单不是 `paid` 而被拒。

### 5.2 决定二：冲正和消费退款是不同的 cost_source

账本里加了一个维度：

| 字段 | 值 | 说明 |
|---|---|---|
| `type` | `refund` | 复用既有退款类型 |
| `cost_source` | `reversal` | 新增冲正维度，与 `balance`（消费退款）区分 |
| `ledger_dedupe_key` | `{trade_no}:refund:reversal` | 幂等键 |

`type` 是 `refund`，但 `cost_source` 是 `reversal`。

**为什么不直接用一个新 type？** 因为从"这笔钱的流向"看，两者是一样的——都是钱进用户账户。用同一个 `type` 让汇总查询不需要改。

**那为什么还要区分？** 因为从"为什么退"看，两者完全不同：

```go
// CostSourceReversal marks ledger entries that reverse a prior purchase.
// It is distinct from CostSourceBalance so reconciliation can separate
// consumption refunds (CostSourceBalance) from purchase reversals.
CostSourceReversal = "reversal"
```

- **消费退款**：一次调用失败了，预扣的钱退回去。每日可能几千笔，金额小。
- **购买冲正**：用户退了一个套餐。每月可能几笔，金额大。

如果混在一起，对账和对成本分析都会失真——**"今天退了 2000 块"这个数字里，1990 块可能是几十万次调用失败的小额退款，10 块才是真的有人退套餐。** 两者的运营含义完全不同。

这个设计和第 16 篇里"对账分七类"是同一个思路：**汇总口径和归因口径要分开，一个字段承担一个语义。**

### 5.3 决定三：幂等键包含 cost_source

```go
// Idempotency: the reversal ledger dedupe key is
//   "{trade_no}:refund:{cost_source}" (mirroring the consume dedupe key
// format). The global ledger dedupe claim primary key guarantees at most
// one reversal row per trade_no, so a replayed refund callback is a no-op.
```

`trade_no` 是订单号，所以这个 key 保证"**一笔订单最多冲正一次**"。

而它和消费的幂等键共享同一个格式：

```go
// is "{reservation_id}:{type}:{cost_source}" so retries from the CAS
```

**两种账本记录用同一种键格式**，所以那个全局的 dedupe claim 主键（第 16 篇提到的 `billing_ledger_dedupe_claims`）能统一处理。

**共享格式的价值在于"一个约束覆盖两种场景"。** 如果两者的键格式不同，就需要两套去重机制——而两套机制意味着两处可能出错的地方。

### 5.4 决定四：退款之后订阅怎么办，是三个选项

这一条我认为是整个退款设计里最需要"想清楚业务"的地方。文档里写的是：

> * "prorate"：按剩余时间比例退款，并相应缩短 `refunded` 套餐的有效期。用于用户已经消耗了部分订阅、退款按剩余时间折算的场景。
> * "keep"：不动订阅。用于退款是善意补偿、不收回权益的场景。

（加上"收回全部有效期"就是三种。）

**"退多少钱"和"权益怎么处理"是两个独立的决定**，而它们可以组合出三种以上合理的业务策略：

| 策略 | 钱 | 权益 | 适用场景 |
|---|---|---|---|
| 按比例 | 退剩余时间的钱 | 缩短到剩余时间（或立即失效） | 用户主动退订 |
| 全退但保留 | 退全款 | 不动 | 善意补偿、平台过失 |
| 全退且收回 | 退全款 | 立即失效 | 走仲裁、欺诈订单 |

**如果把这两件事绑在一起（"退款"就等于"收回权益"），那"善意补偿"这个场景就实现不了。**

这里没有"正确答案"，只有"哪个场景支持哪个策略"。所以我做的是**把两个决定分开**，让调用方显式指定策略。

---

## 6. 套餐快照：解决"已售出的套餐被改了"

这是跨所有操作的一个机制，也是我认为这一篇最重要的部分。

### 6.1 问题

用户 1 月 1 日买了一个套餐：日额度 10 美元、月额度 300 美元。

1 月 15 日，我调整了这个套餐：日额度降到 5 美元。

**那这个用户 1 月 16 日的日额度是多少？**

- 按新配置 → 5 美元。他把套餐改小了，用户吃亏。
- 按旧配置 → 10 美元。他改了价格，但对已购用户无效。

这两种都可能是我想要的（取决于改配置的原因），但**默认行为必须明确，不能是"看代码怎么写的"**。

### 6.2 做法：购买时冻结

我的选择是**默认按购买时的快照**：

```go
// PlanSnapshotter captures the immutable purchase-time view of a plan into a
// PaymentOrder. The interface is kept separate from SubscriptionPlanGetter so
// the payment usecase can depend on a narrow capability instead of the full
// plan repo.
type PlanSnapshotter interface {
    CapturePlanSnapshot(ctx context.Context, planID int64) (PlanSnapshot, error)
}
```

```go
// paymentPlanSnapshotter is the default implementation backed by the
// subscription plan repository. It reads the live plan row once and copies the
// fulfilment-relevant fields into a PlanSnapshot via the canonical
// SubscriptionPlan.ToPlanSnapshot helper (shared with the admin plan-snapshot
// completion path). The snapshot is then frozen on the payment order; later
// edits to the plan do not retroactively change the order.
```

**"later edits to the plan do not retroactively change the order"** —— 这是整个机制的目标。

### 6.3 三个设计点

**第一，快照挂在订单上，而不是订阅上。**

```go
// captures the immutable purchase-time view of a plan into a PaymentOrder
```

因为订单是"一次交易"的记录，而订阅是"一段时间的权益"。**一次续费会生成一个新订单、一个新快照。** 所以用户续费时的价格和额度，是那次续费时的配置。

**第二，接口是窄的（只读一个能力）。**

> The interface is kept separate from SubscriptionPlanGetter so the payment usecase can depend on a narrow capability instead of the full plan repo.

支付用例只需要"给我一个快照"，不需要"查套餐列表 / 改套餐 / 删套餐"。**依赖一个窄接口，意味着支付用例很难被误用来改套餐。**

这是第 1 篇那个依赖倒置的一个具体应用：**接口的宽度就是调用方的能力边界。**

**第三，快照捕获有两条路径共用同一个 helper。**

> via the canonical `SubscriptionPlan.ToPlanSnapshot` helper (shared with the admin plan-snapshot completion path)

和续费的累加逻辑一样：**同一个规则的两条路径，共用一个实现。**

### 6.4 快照带来的新问题

快照解决了"改配置影响已购用户"，但引入了新的问题：

**问题一：旧快照会一直存在。** 一个两年前的订单带着两年前的套餐配置。如果我要统计"现在所有 active 订阅的总额度"，我该按快照算还是按当前配置算？

**问题二：套餐要下线时，快照怎么处理？** 我把一个套餐标记为"停售"，但它的快照必须继续有效（否则已购用户的额度就没了）。

**问题三：如果快照里漏了一个字段怎么办？** 比如我新加了一个"并发上限"字段，但快照捕获是在它之前写的。那老订单的快照里就没有这个字段。

这三个我都没有完整的答案。第一个我目前的处理是"看场景"——给用户看额度用快照，做容量规划用当前配置。第二和第三靠"快照只增字段、不改语义"的纪律。

---

## 7. 现在的状态和欠账

**已经能用的：**

- 账本 append-only，五个 ledger type，修正靠反向记录
- 续费累加剩余时间（`max(expires_at, now) + duration`），逻辑集中在 `assignOrExtend` 一条路径
- `renewal_strategy` 记录 `extend` / `new`，让续费历史可观测
- 支付回调幂等靠 `MarkOrderPaid` 的事务行锁 + `changed=false`
- 退款是独立终态，只有 `paid` 可退
- 冲正用 `cost_source=reversal` 与消费退款区分
- 冲正幂等键 `{trade_no}:refund:{cost_source}`，与消费键格式一致
- 退款策略与权益处理解耦（prorate / keep 等）
- 套餐快照在购买时冻结，挂在订单上，两条路径共用 `ToPlanSnapshot`

**还没解决的：**

**第一，设计文档和代码不一致。** `subscription-renewal-semantics.md` 正文描述的是"重新激活 expired 订阅"，代码实现是"新建"。文档末尾的注说明了这点，但形态不好（第 3 节）。

**第二，快照的字段演化没有规则。** 新增一个影响履行的字段时，老订单的快照里没有它——那么老用户的这个维度按什么算？没有明确答案。

**第三，"按快照还是按当前配置"这个口径没有统一文档。** 给用户看、给运营看、给容量规划看，三处可能用不同的口径，而我没有把它们列在一起。**这是最容易产生"两个页面数字对不上"的地方。**

**第四，退款的部分退款没有支持。** 现在退款是整单退（终态 `refunded`）。如果用户要求退一半，我只能靠"退整单 + 手工补偿"。

**第五，`renewal_strategy` 只有两个值。** 如果以后有"降级续费""升级补差"这类操作，需要扩展这个枚举——而它已经落库了，扩展要处理历史数据。

---

## 8. 下一篇

下一篇讲数据库迁移与分区：96 个迁移文件怎么管、三个 SQL 方言怎么共存、大表怎么分区，以及一份 ownership 清单是怎么来的。

[《96 个迁移文件、三个 SQL 方言：迁移治理是怎么被逼出来的》](/2026-09-17-micro-one-api-migration-governance/)
