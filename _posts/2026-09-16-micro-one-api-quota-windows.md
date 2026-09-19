---
title: "订阅额度：为什么我要同时维护两套完全不同的账"
date: 2026-09-16T12:00:00+08:00
description: "做订阅功能的时候，我脑子里只有一个“额度”概念：用户买了套餐，每个月能用 20 美元，超过就停。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个把我绕进去的概念冲突

做订阅功能的时候，我脑子里只有一个"额度"概念：用户买了套餐，每个月能用 20 美元，超过就停。

写下去才发现这个模型和真实情况对不上。因为**上游也在算额度，而且它算的跟我不一样。**

以 Claude Pro / Codex 这类订阅账号为例：

- 我这边想知道的是：**这个用户这个月花掉多少钱了。** 按美元算，日/周/月三个窗口，我自己记。
- 上游告诉我的是：**这个账号现在还剩多少额度。** 它返回的是百分比，比如"5 小时窗口已用 87%，7 天窗口已用 40%"。

这两个数字回答的是不同的问题：

| | 我本地记的 | 上游报的 |
|---|---|---|
| 单位 | 美元 | 百分比 |
| 归属 | 消费它的用户 | 出借额度的账号 |
| 窗口 | 日 / 周 / 月 | 上游自己定的（常见 5h / 7d） |
| 重置 | 由我决定 | 由上游决定，我只知道还剩多久 |
| 可靠性 | 我自己写的账，确定 | 上游想报才报，不报我就不知道 |

而且它们**都不是"真实花费"**。我本地记的是"我按我的价格算，这个用户该付多少"；上游报的是"这个账号还能被我用多少"。中间隔着我的定价、我的倍率、上游自己的限流策略。

这篇讲我最后怎么维护这两套账，以及它们各自最容易出错的地方。

先说清楚两套东西分别存在哪。

**账号侧的本地额度**（`SubscriptionAccount`，channel-service 拥有）：

```go
QuotaLimitUSD          float64   // 总量
QuotaUsedUSD           float64
Quota5hLimitUSD        float64   // 5 小时窗口
QuotaDailyLimitUSD     float64   // 日
QuotaDailyUsedUSD      float64
QuotaWeeklyLimitUSD    float64   // 周
QuotaWeeklyUsedUSD     float64
QuotaResetStrategy     string    // rolling | fixed
QuotaTimezone          string
```

**用户侧的订阅额度**（`SubscriptionGroup`，`domain/subscription` 拥有）：

```go
DailyLimitUSD   *float64 `json:"daily_limit_usd"`
WeeklyLimitUSD  *float64 `json:"weekly_limit_usd"`
MonthlyLimitUSD *float64 `json:"monthly_limit_usd"`
// RateMultiplier scales quota-window consumption, after routing-group pricing.
RateMultiplier float64 `json:"rate_multiplier"`
```

注意用户侧那三个是**指针**，账号侧是值。这个差别是有意的，后面第 6 节会说。

**上游侧的快照**（解析出来存进账号记录）：

```go
type CodexSnapshot struct {
    PrimaryUsedPercent          *float64
    PrimaryResetAfterSeconds    *int
    PrimaryWindowMinutes        *int
    SecondaryUsedPercent        *float64
    SecondaryResetAfterSeconds  *int
    SecondaryWindowMinutes      *int
    PrimaryOverSecondaryPercent *float64
    UpdatedAt                   time.Time
}
```

三套数据放在一起，才是"这个账号现在能不能接活"和"这个用户还能不能花钱"的完整答案。

---

## 1. 本地额度：为什么明知道上游会拒绝，还要自己记一份

最容易被问的问题是：上游自己会拒绝，为什么还要本地记？

三个理由，按重要性排：

**第一，上游不总是会拒绝，它会先降速。** 打太猛的时候，上游可能不是拒绝，而是把你的请求变慢、或者返回一个部分结果。等它明确拒绝的时候，我的账号已经被消耗得差不多了。本地额度是**提前刹车**。

**第二，上游的百分比是"它想报的时候才报"。** 它有快照我就有信息，没有快照我就两眼一抹黑。本地额度是我唯一能保证 100% 拿到的数。

**第三，运营上我需要一个自己能调的数字。** 上游给了 100% 的额度，我可能只想让这个账号用到 80%——留出余量给别的用途，或者避免在临近上限时被限流。本地额度给了我这个旋钮。

所以本地额度不是"复刻上游"，而是一个**我可以独立调节的保守上限**。

---

## 2. 两种窗口语义：滚动 vs 固定

这是我做的第一层设计决定，也是我认为最容易踩坑的一层。

### 2.1 默认是滚动窗口

用户侧订阅的窗口是从 `starts_at` 锚定的滚动窗：

```go
const (
    quotaDailyWindow   = 24 * time.Hour
    quotaWeeklyWindow  = 7 * 24 * time.Hour
    quotaMonthlyWindow = 30 * 24 * time.Hour
)
```

```go
func alignedWindowStart(anchor, now, periodSec int64) int64 {
    if now <= anchor {
        return anchor
    }
    return anchor + ((now-anchor)/periodSec)*periodSec
}
```

`anchor` 是订阅的 `starts_at`。所以一个在 14:30 买的日额度订阅，它的"一天"是每天 14:30 到次日 14:30。

**为什么不做成自然日？** 因为自然日要处理时区和夏令时，而且"今天 23:50 买、明天 00:10 就能用新一天"会让短期套餐被绕过。锚定在购买时间上，规避了这两个问题。

### 2.2 但账号侧可以选固定窗口

上游账号有另一个选项：

```go
const (
    QuotaResetStrategyRolling = "rolling"
    QuotaResetStrategyFixed   = "fixed"
    DefaultQuotaTimezone      = "UTC"
)
```

```go
func (a *SubscriptionAccount) FixedQuotaWindowStart(now time.Time, scope string) int64 {
    loc, err := time.LoadLocation(a.EffectiveQuotaTimezone())
    if err != nil {
        loc = time.UTC
    }
    local := now.In(loc)
    start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
    if scope == "weekly" {
        daysSinceMonday := (int(local.Weekday()) + 6) % 7
        start = start.AddDate(0, 0, -daysSinceMonday)
    }
    // ...
}
```

固定窗口是**当地时间自然日 / 自然周（周一开始）**，时区可配。

为什么账号侧需要这个选项？因为**运营对账要看自然日**。如果上游账号的用量是从"某台机器上次重启时间"开始滚的，我拿它跟任何人讲都讲不清楚。很多订阅套餐的上游限流本身也是按自然日算的，我按滚动窗去估，反而对不上。

时区那块有个我改过的细节：

```go
func (a *SubscriptionAccount) EffectiveQuotaTimezone() string {
    tz := strings.TrimSpace(a.QuotaTimezone)
    if tz == "" {
        return DefaultQuotaTimezone
    }
    if _, err := time.LoadLocation(tz); err != nil {
        // Review L1 fix: log the invalid timezone so operators can locate the
        // misconfigured account instead of silently falling back to UTC.
        fmt.Fprintf(os.Stderr, "subscription account %d: invalid quota_timezone %q, falling back to UTC: %v\n", a.ID, tz, err)
        return DefaultQuotaTimezone
    }
    return tz
}
```

**时区配错要打出来。** 之前是静默回退到 UTC，于是"我配了 Asia/Shanghai 但窗口还是按 UTC 重置"这种事，除了对不上账之外没有任何线索。现在至少有一行 stderr。

### 2.3 两种语义混用的后果

我一开始让账号侧也统一用滚动窗，因为代码复用最省事。后来发现一个具体的坏处：

**按滚动窗，永远没有一个"新的一天开始了"的时刻。** 运营想看"昨天这个账号花了多少"，滚动窗给不出这个数——因为昨天的窗口和今天的窗口有重叠。固定窗口能直接回答。

所以两种语义都存在，各有各的用途。代价是**每个消费窗口的地方都必须先问一句"这个账号用哪种重置"**：

```go
dailyUsed := effectiveWindowUsedUSD(a.QuotaDailyUsedUSD, a.QuotaDailyWindowStart, nowUnix, 24*time.Hour)
weeklyUsed := effectiveWindowUsedUSD(a.QuotaWeeklyUsedUSD, a.QuotaWeeklyWindowStart, nowUnix, 7*24*time.Hour)
if a.UsesFixedQuotaReset() {
    dailyUsed = a.EffectiveFixedQuotaWindowUsedUSD(a.QuotaDailyUsedUSD, a.QuotaDailyWindowStart, now, "daily")
    weeklyUsed = a.EffectiveFixedQuotaWindowUsedUSD(a.QuotaWeeklyUsedUSD, a.QuotaWeeklyWindowStart, now, "weekly")
}
```

这段"先按滚动算，如果是固定模式就重算"的写法我重复写了两遍（账号侧一处、别处一处），一直没抽出统一函数。是我留的一个小债。

---

## 3. 窗口滚动是个纯函数，而且必须共用一份

### 3.1 为什么是纯函数

```go
// RollUsageWindows returns a copy of subscription with any usage window that has
// aged past its period reset to zero, relative to now (unix seconds). It is a
// pure function so both the usecase and the data layer's atomic AddUsage can
// share one definition of the rolling rules.
func RollUsageWindows(subscription *UserSubscription, now int64) *UserSubscription {
    if subscription == nil {
        return nil
    }
    cloned := *subscription
    cloned.DailyUsageUSD, cloned.DailyWindowStart = rollUsageWindow(cloned.DailyUsageUSD, cloned.DailyWindowStart, cloned.StartsAt, now, quotaDailyWindow)
    // ...周、月同理
    return &cloned
}
```

注释里那句 "so both the usecase and the data layer's atomic AddUsage can share one definition" 是重点。

不共用的后果很具体：**读路径（查额度）和写路径（记用量）对"窗口什么时候重置"的理解不一致**，就会出现"查询显示还有额度，但写入时按另一个窗口算，直接记到已经过期的窗口上"。

把规则做成纯函数，两边调同一个实现，这个分歧就不可能发生。

### 3.2 `rollUsageWindow` 的三个分支

```go
func rollUsageWindow(used float64, windowStart, anchor, now int64, period time.Duration) (float64, int64) {
    periodSec := int64(period.Seconds())
    if periodSec <= 0 {
        return used, windowStart
    }
    if anchor <= 0 {
        anchor = windowStart
    }
    if anchor <= 0 {
        anchor = now
    }
    currentStart := alignedWindowStart(anchor, now, periodSec)
    if windowStart <= 0 {
        return used, currentStart          // 从来没有窗口 → 只补上起点，用量保留
    }
    if windowStart < currentStart {
        return 0, currentStart             // 窗口过期 → 用量清零
    }
    if windowStart != currentStart {
        return used, currentStart          // 窗口起点在未来 → 只修正起点
    }
    return used, windowStart               // 同一个窗口 → 原样返回
}
```

四个返回点各有含义。我特别说一下第三个：`windowStart != currentStart` 且 `windowStart > currentStart` 时会走到这里——**窗口起点被设成了未来**。这不该发生，但如果数据被人手动改过或者时钟出问题，我选择"纠正起点但不清用量"。因为清用量等于白送额度，宁可多算一点。

第一个分支 `windowStart <= 0` 保留用量，也是同一个思路：**数据缺失时，宁可认为用户已经用掉了，也不要认为他没花。**

---

## 4. 倍率：两套价格体系叠在一起

### 4.1 `RateMultiplier` 和 `GroupRatio` 是两回事

这一段是我在文档里特意澄清过的，因为它们太容易混：

- **路由分组的 `GroupRatio`** 是**价格**：这个分组的上游贵不贵，决定扣钱包扣多少。
- **订阅策略的 `RateMultiplier`** 是**额度消耗倍率**：这个套餐消耗订阅额度的速度。

结构体注释写得很直白：

```go
// RateMultiplier scales quota-window consumption, after routing-group pricing.
RateMultiplier float64 `json:"rate_multiplier"`
```

"after routing-group pricing" 是关键：先按路由分组的价格算出这笔消费是多少美元，再乘上订阅策略的倍率，才是从这个用户订阅额度里扣掉的数。

举例：一笔调用按分组价格算下来 0.10 美元，用户买的是 `RateMultiplier = 1.5` 的套餐，那么他的日额度里扣 0.15 美元。

**为什么要有这个倍率？** 因为不同档位的套餐可以给出不同的"额度性价比"。高价套餐倍率低（额度更耐用），低价套餐倍率高。如果只有价格没有倍率，那就只能靠改价格来区分档位，而价格是全局的。

### 4.2 检查额度和记录用量必须用同一个倍率

这是这一节最重要的一条，我写在了注释里：

```go
// domain-M5: apply the group's billing multiplier so recorded spend matches
// what the quota check charges. The group lookup MUST NOT silently fall back
// to 1.0x on a transient DB error: that would permanently under-record usage
// (quota is charged at the multiplier via CheckQuota), letting users exceed
// their paid window. Propagate the error so the usage write fails and can be
// retried. A zero/unset multiplier legitimately means "no scaling" (1.0).
group, gerr := uc.GetGroupForSubscription(ctx, subscription)
if gerr != nil {
    return fmt.Errorf("lookup billing group %d for usage recording: %w", subscription.GroupID, gerr)
}
effectiveCost := costUSD
if group != nil && group.RateMultiplier > 0 {
    effectiveCost = costUSD * group.RateMultiplier
}
```

两个方向都会出错，而且方向相反：

**如果检查时不乘倍率、记录时乘**：用户被少扣，实际能花掉超过套餐的钱。
**如果检查时乘、记录时不乘**：用户被多扣，套餐还没用完就不能用了。

而且这两个错误的表现完全不同：前者是"用户占便宜"，后者是"用户投诉额度不对"。前者往往几个月都没人发现。

所以两边都用同一个倍率，并且**查不到分组时必须报错，不能默认 1.0**。注释里那句 "MUST NOT silently fall back to 1.0x" 就是针对这个：一次数据库抖动回退成 1.0，会让那批请求的用量被永久少记。

---

## 5. 预扣的用量记在哪：冻结额度

### 5.1 问题

订阅的用量记录有个时序问题：

1. 请求进来，检查额度（通过）；
2. 转发上游，可能跑 30 秒；
3. 结算，记录实际用量。

如果第 3 步发生在窗口边界之后，用量会被记到**新窗口**上。但用户实际是在旧窗口里消耗的。

后果：用户可以卡在窗口切换的瞬间发一批长请求，让它们在旧窗口检查通过、却记在新窗口上——**两个窗口都不吃亏，他多用了。**

### 5.2 我的做法：记录预扣时的窗口

```go
// FrozenWindowCharge records settlement against the exact pre-deduction
// windows. Its accounting amount is already multiplied by the captured Q.
type FrozenWindowCharge struct {
    ReservationID      string
    SubscriptionID     int64
    QuotaPolicyID      int64
    DailyWindowStart   int64
    WeeklyWindowStart  int64
    MonthlyWindowStart int64
    AccountingUSD      float64
    CreatedAt          int64
}
```

**结算时用的不是"当前窗口"，而是预扣时捕获的那组窗口起点。** 请求跨过边界，也归到它开始的那一个窗口。

字段注释里那句 "Its accounting amount is already multiplied by the captured Q" 说明倍率也是预扣时固定的——这样即使管理员在请求飞行过程中改了套餐倍率，这笔账也不会被改。

写入走的是和钱包同一个事务：

```go
func (uc *SubscriptionUsecase) RecordFrozenUsageInTx(ctx context.Context, tx Tx, charge FrozenWindowCharge) error {
    if charge.ReservationID == "" || charge.SubscriptionID <= 0 || charge.QuotaPolicyID <= 0 ||
        charge.AccountingUSD < 0 || math.IsNaN(charge.AccountingUSD) || math.IsInf(charge.AccountingUSD, 0) {
        return fmt.Errorf("invalid frozen usage")
    }
    repo, ok := uc.repo.(FrozenUsageRepository)
    if !ok {
        return fmt.Errorf("frozen subscription usage capability unavailable")
    }
    return repo.AddFrozenUsageInTx(ctx, tx, charge)
}
```

入口先做了一轮参数校验。我第一次写的时候漏了 `ReservationID == ""` 这条，结果一条没有预约 ID 的记录写进去了，之后对账时完全无法归因——**没有预约 ID，这条用量就找不到对应的那笔请求。**

`IsNaN` / `IsInf` 的检查也是必要的：一个 NaN 进了账本，之后所有 `used >= limit` 的比较都会返回 false，这个用户的额度就再也拦不住了。

### 5.3 增量写入必须是原子的

```go
// Delegate the read-roll-increment to the repository so it happens atomically
// (single transaction / lock). Doing it here would be a lost-update race:
// concurrent requests read the same base row and clobber each other's
// increment, letting users blow past their quota.
return uc.repo.AddUsage(ctx, userID, effectiveCost, uc.now().Unix())
```

"读当前用量 → 加上这笔 → 写回去"如果在 biz 层做，两个并发请求会读到同一个基数然后互相覆盖。用户的实际用量会比账本上多，而账本上永远追不上额度，**他就可以无限用下去**。

所以这个"读-滚窗-加-写"必须在 data 层一条语句里完成。

---

## 6. 空值和零值的区别：为什么用户侧的限制是指针

回到第一节那个差异：`SubscriptionGroup` 的日/周/月限制是 `*float64`，而账号侧的额度字段是 `float64`。

```go
type SubscriptionGroup struct {
    DailyLimitUSD   *float64 `json:"daily_limit_usd"`
    WeeklyLimitUSD  *float64 `json:"weekly_limit_usd"`
    MonthlyLimitUSD *float64 `json:"monthly_limit_usd"`
}
```

因为用户侧的这三个限制要区分两种"没有值"：

| 值 | 含义 | 行为 |
|---|---|---|
| `nil` | 这个套餐**不设**这项限制 | 不检查，永远通过 |
| `0` | 限制是 0 | 一用就超 |

如果用 `float64` 加"0 表示不限"的约定，就区分不出"限制是 0"了。而"日额度为 0、但月额度有值"是一个完全合理的套餐配置（按周给额度但不按日限）。

检查逻辑体现了这个区分：

```go
result.Daily = makeDimension(subscription.DailyUsageUSD+estimated, group.DailyLimitUSD, 0)
// ...
if result.Daily.Limit != nil && result.Daily.Used > *result.Daily.Limit {
    result.Allowed = false
    result.Reasons = append(result.Reasons, "daily quota exceeded")
}
```

`Limit != nil` 才检查。三个维度分别判，任何一个超了都拒绝，而且**原因全部收集起来**：

```go
result.Reasons = make([]string, 0, 3)
// ...三个维度各自 append
```

**把三个原因都带上**，是因为用户看到"额度不足"时的第一反应是问"哪个额度"。一次告诉他是日额度还是周额度，能省掉一轮沟通。

账号侧那几个字段我用的是值类型，因为账号额度是"管理员填的配置"，空和 0 在实践中没有区别——不填就是不限。这个不对称我留着，但确实需要记住。

---

## 7. 账号耗尽和账号故障要分开

第 4 篇讲过"用满"和"用坏"要在限流器、封禁、熔断几处分开。额度这一层也要分开：

```go
func (a *SubscriptionAccount) LocalQuotaExceededAt(now time.Time) bool {
    if a == nil {
        return true
    }
    nowUnix := now.Unix()
    if a.QuotaLimitUSD > 0 && a.QuotaUsedUSD >= a.QuotaLimitUSD {
        return true
    }
    if a.Quota5hLimitUSD > 0 && effectiveWindowUsedUSD(a.Quota5hUsedUSD, a.Quota5hWindowStart, nowUnix, 5*time.Hour) >= a.Quota5hLimitUSD {
        return true
    }
    // ...日、周
    return false
}
```

这个函数在选账号时被调用（第 4 篇的 `isSubscriptionAccountSchedulable`），返回 false 的账号**被跳过，而不是被封禁**。

区别在于：**额度耗尽是一个会自愈的状态，它随窗口滚动自己就恢复了。** 给它加运行时封禁是错的——封禁到期时间和窗口重置时间对不上，账号可能在封禁期结束之后被放出来，但额度还没恢复；或者反过来，额度已经恢复了但账号还被封着。

对照上游快照的判断：

```go
func (a *SubscriptionAccount) CodexSnapshotQuotaExceeded() bool {
    if a == nil {
        return false
    }
    if a.PrimaryQuotaUsedPercent != nil && *a.PrimaryUsedPercent >= 100 {
        return true
    }
    if a.SecondaryQuotaUsedPercent != nil && *a.SecondaryQuotaUsedPercent >= 100 {
        return true
    }
    if a.QuotaUsedPercent >= 100 {
        return true
    }
    return false
}
```

**两套额度，任何一个到顶都算耗尽。** 本地的到了，说明我给自己设的保守上限到了；上游的到了，说明真实上限到了。

### 7.1 四种告警形态

配额告警分了四类：

```go
func (e *QuotaAlertEvaluator) classify(account *SubscriptionAccount, now time.Time) string {
    // Exhausted: any local quota window at/over its limit.
    if account.LocalQuotaExceededAt(now) {
        return QuotaAlertExhausted
    }
    // Near-exhausted: upstream snapshot primary usage >= threshold.
    if account.PrimaryQuotaUsedPercent != nil && *account.PrimaryQuotaUsedPercent >= e.cfg.NearExhaustedPct {
        return QuotaAlertNearExhausted
    }
    if account.QuotaUsedPercent >= float32(e.cfg.NearExhaustedPct) && account.QuotaUsedPercent > 0 {
        return QuotaAlertNearExhausted
    }
    // Writeback down: snapshot paused indicates the recorder could not persist.
    if account.QuotaSnapshotPaused {
        return QuotaAlertWritebackDown
    }
    // Idle: no usage for the configured duration.
    if account.LastUsedAt > 0 && now.Unix()-account.LastUsedAt >= int64(e.cfg.IdleDuration.Seconds()) {
        return QuotaAlertIdle
    }
    return ""
}
```

四种对应四个不同的运营动作：

| 类型 | 含义 | 该做什么 |
|---|---|---|
| `Exhausted` | 本地额度真的用完了 | 加额度或换账号 |
| `NearExhausted` | 上游快照接近上限 | 提前准备备用账号 |
| `WritebackDown` | 快照**写不回去**了 | 查存储/权限，这是基础设施故障 |
| `Idle` | 很久没用了 | 可能是账号失效，或者没人用 |

四个判定是有顺序的，`Exhausted` 优先。因为如果同时"额度用完"和"很久没用"，真正要处理的是额度问题。

`WritebackDown` 这一类我觉得值得单独说：**它不是额度问题，是"我的记录能力坏了"。** 上游报了快照，但我存不下来。这种情况下本地账本和上游状态会开始漂移，越早发现越好。所以它有自己的告警类型，而不是混进"额度异常"里。

---

## 8. 用户看到的那三个数

额度最终要暴露给用户。接口返回的结构是：

```go
type QuotaDimension struct {
    Used      float64  `json:"used"`
    Limit     *float64 `json:"limit"`
    Remaining float64  `json:"remaining"`
    // NextRefresh is the unix timestamp at which this window resets and the
    // usage counter rolls back to zero. Zero when the window has already...
    NextRefresh int64
}
```

三个数：已用、上限、剩余，加上一个下次刷新时间。

这里有个我修过的 bug，注释里留着：

```go
// Surface the group's limits so Remaining is meaningful. Without them every
// dimension reported Remaining=0, indistinguishable from "quota exhausted".
var dailyLimit, weeklyLimit, monthlyLimit *float64
```

**之前我没把 group 的限制取出来，于是 `Remaining` 恒等于 0。** 用户看到"剩余 0"，第一反应是"我额度用完了"，但实际可能一分钱没用。

这个 bug 的性质值得记一下：**用 0 表示"未知"，和用 0 表示"真的没有"，是同一个数字。** 接口设计上我给 `Limit` 用了指针（区分 nil 和 0），却在 `Remaining` 上用了值类型，于是把一个已经解决的区分问题又引入了。

`NextRefresh` 的算法是基于窗口起点的：

```go
DailyUsed: makeDimension(rolled.DailyUsageUSD, dailyLimit, rolled.DailyWindowStart+int64(quotaDailyWindow.Seconds())),
```

注释里解释了为什么刷新时间要挂在 `starts_at` 上：

```go
// NextRefresh is the moment the current window ends and usage resets.
// Windows are anchored to starts_at, so daily/weekly/monthly refresh
// countdowns stay aligned to the subscription success time.
```

**三个窗口的刷新时间都锚在订阅开始时刻，所以它们之间的相位是固定的。** 如果日窗口锚在购买时间、周窗口锚在周一，用户会看到"每天都刷新但每周一还额外刷一次"这种难以理解的现象。

---

## 9. 现在的状态和欠账

**已经能用的：**

- 账号侧本地额度：总量 / 5h / 日 / 周，滚动或固定窗口可选，时区可配
- 用户侧订阅额度：日 / 周 / 月，锚定购买时间的滚动窗，`nil` 与 `0` 语义分开
- 上游快照解析（Codex 的 primary/secondary 窗口）
- 滚动窗口是纯函数，读写路径共用一份实现
- 预扣时固定窗口与倍率，结算按原窗口归属
- 倍率在检查和记录两侧一致，查不到分组时 fail-close
- 四种配额告警，含"快照写不回去"这种基础设施型告警

**还没解决的：**

**第一，账号侧没有"月"窗口。** 用户侧有日/周/月，账号侧只有总量/5h/日/周。要按自然月控制账号成本，现在只能靠总量。

**第二，"先按滚动算、固定模式再重算"的代码重复了两处。** 应该抽成一个统一的 `EffectiveWindowUsedUSD`，我一直没做。

**第三，本地额度和上游快照的换算关系是缺失的。** 现在两个数各管各的：本地记美元，上游记百分比，我没有一个"本地花了 X 美元，对应上游用了 Y%"的换算。这导致运营无法从上游百分比反推我还能给这个账号派多少流量。要做的话得按平台分别标定单价，工程量不小。

**第四，用户侧的月窗口是 30 天，不是自然月。** 这是滚动窗口的直接后果。对按自然月做预算的用户来说，这个口径会让月初月末对不上。我暂时接受，因为改成自然月要重新处理"一个用户跨月如何切分"的问题。

**第五，额度用尽的用户没有"排队/预约"能力。** 现在是直接拒绝，等窗口滚动。第 4 篇提过账号侧的负载感知排队我都没做，用户侧更靠后。

---

## 10. 下一篇

下一篇讲缓存：为什么鉴权快照和渠道配置要放在三级缓存里，哪些东西可以缓存、哪些绝对不能，以及失效广播里那个"consumer group 必须每个副本一个"的坑。

[《三级缓存：缓存鉴权不等于授权，以及两个失效函数的真实代价》](/2026-09-17-micro-one-api-multilevel-cache/)
