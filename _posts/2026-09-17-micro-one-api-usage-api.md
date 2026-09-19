---
title: "额度查询接口：为什么“没订阅”要返回 200 而不是 404"
date: 2026-09-17T12:00:00+08:00
description: "做这个接口的时候遇到的第一个问题不是技术问题，是语义问题。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个接口设计的取舍：用户没订阅，算不算错误

做这个接口的时候遇到的第一个问题不是技术问题，是语义问题。

`GET /v1/subscription/usage` 用来查用户订阅套餐的日/周/月用量。请求进来之后有三种可能：

1. 用户有活跃订阅 → 返回用量；
2. 用户没有订阅（纯钱包用户）→ **这算错误吗？**
3. 这个部署根本没启用订阅功能 → **这算错误吗？**

我的第一反应是 2 和 3 都返回 404 或者 400。但想清楚之后改了：

```go
if progress == nil {
    // No active subscription is a normal state for a wallet-only user; return
    // success:false instead of an error status so cc-switch-style tools render
    // "no subscription" rather than a failure banner.
    s.writeJSON(w, http.StatusOK, map[string]any{
        "success":   false,
        "isValid":   false,
        "is_active": false,
        "mode":      "subscription",
        "message":   "no active subscription",
        "user_id":   strconv.FormatInt(authSnapshot.UserId, 10),
    })
    return
}
```

**HTTP 200，但业务字段 `success: false`。**

理由写在注释里了：**调用方是 cc-switch 这类第三方工具。** 如果返回 404，工具会显示一个红色错误横幅，用户看到"查询失败"；而实际情况是"你没有订阅"——一个完全正常的状态。

**"我没有这个资源"和"这个请求失败了"是两件事，HTTP 状态码只有一个维度，装不下。** 所以状态码表达"这次 HTTP 交互成功了"，业务字段表达"业务上有没有这个资源"。

这个模式在 API 设计里不新鲜（GraphQL 就是这么干的），但在 REST 里容易被忽略——因为 REST 的惯例是用状态码表达资源存在性。

而第 3 种情况也做了同样的处理：

```go
if s.subscriptionUsecase == nil {
    // Subscriptions are not enabled on this deployment. Report a structured
    // success:false so tooling can surface "no subscription" rather than a
    // hard 5xx.
    s.writeJSON(w, http.StatusOK, map[string]any{
        "success":   false,
        "isValid":   false,
        "is_active": false,
        "mode":      "subscription",
        "message":   "subscription service not configured",
    })
    return
}
```

两种情况的差别只在 `message`：`no active subscription` 和 `subscription service not configured`。

**多这一个字段的价值是：用户能区分"我要去买订阅"还是"这个部署没这个功能"。** 如果两者返回同一个响应，用户会去研究怎么买订阅，而实际上买不了。

---

## 1. 为什么用 API Key 鉴权，而不是登录态

这个接口挂在 relay-gateway 上，用和 `/v1/chat/completions` 一样的 Bearer token 鉴权：

```go
authSnapshot, err := s.getAuthSnapshot(r.Context(), token)
if err != nil {
    s.handleIdentityError(w, err)
    return
}
if !authSnapshot.GetUserEnabled() || !authSnapshot.GetTokenEnabled() {
    s.writeError(w, http.StatusForbidden, "user or token disabled")
    return
}
```

设计文档里说明了原因：

> 为了方便在 `cc-switch` 这类工具中查询用户订阅套餐的使用情况（日/周/月限额、已用、剩余、下次刷新时间），新增一个 **API Key 鉴权** 的查询接口。

**因为这些工具手上只有 API Key，没有登录 JWT。** 用户在用命令行工具或者客户端的时候，能拿到的凭据就是那个 `sk-...`。让他去登录网页再看额度，那这个接口就没有意义了。

所以它和 `/v1/usage`（钱包余额查询）并列，都走 API Key。

而权限检查只有两条：用户启用、token 启用。**没有检查"这个 token 有没有权限查订阅"**——因为查自己的额度是个无害的只读操作，而且订阅是用户级的（不是 token 级的），用任何一个有效 token 查到的都是同一个答案。

### 1.1 它和 admin 接口的关系

代码注释里写清了这一层：

```go
// It is the API-key-authenticated counterpart to the admin
// /api/v1/subscriptions/progress endpoint, exposed on the relay gateway so
// external tools (e.g. cc-switch) can query a subscription plan's usage with
// the same API key they already use for /v1/chat/completions.
```

**同一个数据，两个入口，两套鉴权。** admin 接口给管理后台用（登录态、可能查任意用户），这个接口给工具用（API Key、只能查自己）。

这个复用是安全的，因为 `GetProgress` 的入参是 `authSnapshot.UserId`——**用户 ID 来自鉴权结果，不是请求参数。** 如果这个接口接受一个 `user_id` 查询参数，那它就成了一个越权接口。

---

## 2. 响应结构：为什么要有 `mode` 和 `unit`

完整响应长这样：

```go
s.writeJSON(w, http.StatusOK, map[string]any{
    "success":   true,
    "isValid":   progress.Status == subscriptionbiz.SubscriptionStatusActive,
    "is_active": progress.Status == subscriptionbiz.SubscriptionStatusActive,
    "status":    string(progress.Status),
    "mode":      "subscription",
    "planName":  planName,
    "unit":      "USD",
    "user_id":   strconv.FormatInt(authSnapshot.UserId, 10),
    "data":      progress,
})
```

`mode: "subscription"` 和 `unit: "USD"` 这两个字段看起来是冗余的（值固定），但它们承担了一个作用：**让调用方不必硬编码假设。**

- `mode` 让它和 `/v1/usage`（钱包）的响应可以共存于同一套解析逻辑里——工具可以按 `mode` 分支；
- `unit` 让金额的含义显式。

**我倾向于在 API 里显式声明那些"我现在恰好是固定值"的字段。** 因为固定的东西会变——如果以后支持按 Token 计数的套餐，`unit` 就不一定是 USD 了；如果以后有"混合模式"（钱包 + 订阅同时生效），`mode` 就不一定是单一值了。

而 `isValid` 和 `is_active` 两个字段表达同一个判断：

```go
"isValid":   progress.Status == subscriptionbiz.SubscriptionStatusActive,
"is_active": progress.Status == subscriptionbiz.SubscriptionStatusActive,
```

这两个字段重复了。它们的存在是因为**不同调用方用了不同的字段名**（有些工具查 `isValid`，有些查 `is_active`），为了兼容都留着了。这是一处我不太满意但暂时保留的冗余。

---

## 3. 一个防御性设计：过期判定不依赖定时任务

这是我觉得这个接口背后最值得讲的一段，虽然它不在这个 handler 里。

订阅过期是靠一个每小时跑一次的定时任务标记的：

```go
const (
    ExpiryCheckInterval = time.Hour
    ExpiryWarnBefore    = 24 * time.Hour
)
```

**每小时一次**，意味着一个刚过期的订阅最多还能"活跃"一小时。如果这个定时任务挂了或者延迟了，那就是永远。

而如果查询接口只按 `status = 'active'` 过滤，一个已经过期的订阅还会被返回，用户会看到"我还有额度"，然后请求照样能通过（因为额度检查也走同一个查询）——**免费额度可以无限领。**

所以查询里多加了一个条件：

```go
// Code-review 2026-07-30 domain-C1: defence-in-depth. The
// SubscriptionExpiryChecker is the primary mechanism that flips an active
// subscription to expired, but it is best-effort and hourly. A read path
// that only filters on status = 'active' would keep serving a subscription
// whose expires_at has already passed (free quota) for up to an hour after
// expiry, and forever if the checker is ever mis-wired or delayed. We
// therefore also require expires_at > now here so the active set is correct
// regardless of the checker. The dedicated expiry filter still runs in the
// checker to actually persist the status transition for reporting.
if err := r.db.WithContext(ctx).
    Where("user_id = ? AND status = ? AND expires_at > ?", userID, string(biz.SubscriptionStatusActive), time.Now().Unix()).
    Order("updated_at DESC, id DESC").
    First(&model).Error; err != nil {
```

**读路径自己判断过期，而不是信任那个状态字段。**

这段注释里有几个词值得注意：

- **"best-effort and hourly"**：定时任务是尽力而为的，而且粒度是一小时。
- **"forever if the checker is ever mis-wired or delayed"**：如果它坏了，状态就永远不翻。这是关键——**一个不可靠的机制不该成为正确性的唯一依赖。**
- **"The dedicated expiry filter still runs in the checker to actually persist the status transition for reporting"**：定时任务还是要跑的，因为它是**持久化状态变更**的地方（用于报表和审计）。读路径的过滤只保证"不误放行"，不负责改状态。

**职责分得很清楚：定时任务负责持久化状态，读路径负责正确性判断。** 两者都要有，但目的不同。

这个模式我认为可以推广：**当一个"状态字段"由异步任务维护时，不要把它的当前值当成事实，而是用可独立计算的谓词再判一次。**

---

## 4. "下次刷新时间"是怎么算的

这是响应的核心价值之一。用户最想知道的是"我还有多久能重新用满额度"。

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

```go
DailyUsed: makeDimension(rolled.DailyUsageUSD, dailyLimit, rolled.DailyWindowStart+int64(quotaDailyWindow.Seconds())),
WeeklyUsed: makeDimension(rolled.WeeklyUsageUSD, weeklyLimit, rolled.WeeklyWindowStart+int64(quotaWeeklyWindow.Seconds())),
MonthlyUsed: makeDimension(rolled.MonthlyUsageUSD, monthlyLimit, rolled.MonthlyWindowStart+int64(quotaMonthlyWindow.Seconds())),
```

```go
// NextRefresh is the moment the current window ends and usage resets.
// Windows are anchored to starts_at, so daily/weekly/monthly refresh
// countdowns stay aligned to the subscription success time.
```

刷新时间 = 当前窗口起点 + 窗口长度。而窗口起点锚在 `starts_at` 上（第 8 篇讲过），所以：

**一个在 14:30 买的套餐，它的日额度每天 14:30 刷新，周额度每周同一天刷新，月额度每 30 天刷新。**

这个设计的实际后果是：**用户看到的是三个不同的倒计时，而不是"明天零点重置"。**

如果改成自然日/自然周，用户会更好理解（"每天零点刷新"），但会引入时区和夏令时问题。我选了锚定购买时间，代价是解释成本，收益是可预测性。

### 4.1 `limit` 是指针，`remaining` 不是

```go
Limit     *float64 `json:"limit"`
Remaining float64  `json:"remaining"`
```

`limit` 是 `*float64` 是因为要区分"不限制"和"限制为 0"（第 8 篇展开过）。

而 `remaining` 是值类型，于是**当 `limit` 为 nil 时它恒为 0**：

```go
func makeDimension(used float64, limit *float64, nextRefresh int64) *QuotaDimension {
    remaining := 0.0
    if limit != nil {
        remaining = *limit - used
    }
    return &QuotaDimension{
        Used:        used,
        Limit:       limit,
        Remaining:   remaining,
        NextRefresh: nextRefresh,
    }
}
```

这是我在第 8 篇里提到过的那个 bug 的残留痕迹：**"不限制"时 `remaining = 0`，而用户看到"剩余 0"会以为额度用完了。**

现在修的是"没把 group 的限制取出来"那个问题（所以 `limit` 能正常填上了），但 `limit` 本身为 nil 的场景——某些套餐确实不限某一维度——`remaining` 仍然是 0 而不是"无限"。

**接口层面把"我无限"表达成"我剩 0"，是一个还没解决的歧义。** 调用方可以通过 `limit == null` 判断，但这要求它知道这个约定。

---

## 5. 一个被 `isValid` 掩盖的事实

再看一眼那行：

```go
"isValid":   progress.Status == subscriptionbiz.SubscriptionStatusActive,
```

既然 `GetActiveSubscriptionByUser` 已经强制了 `status = 'active'`，这个比较**永远为 true**。

所以 `isValid` 实际上是常量。它的存在是为了兼容调用方，但它的计算是多余的。

这本身不是 bug，但我觉得它反映了一个模式：**"防御性代码"和"兼容性字段"容易堆积成永远不会取到第二个值的判断。**

如果一个字段永远只有一个值，那它传达的信息是零——但读代码的人会花时间去想"什么情况下它是 false"。**一个永远为真的判断，比没有这个判断更消耗注意力。**

---

## 6. 现在的状态和欠账

**已经能用的：**

- API Key 鉴权的 `/v1/subscription/usage`，与 admin 接口共用同一个 `GetProgress`
- 用户 ID 来自鉴权结果，不接受请求参数传入（不会越权）
- "没有订阅"和"部署未启用订阅"都返回 200 + `success:false`，用 `message` 区分
- 读路径独立判定 `expires_at > now`，不依赖小时级的过期定时任务
- 三个维度各带 `used` / `limit` / `remaining` / `next_refresh`
- `unit` 和 `mode` 显式声明，降低调用方的硬编码假设
- 刷新时间锚定购买时刻，日/周/月相位固定

**还没解决的：**

**第一，`limit` 为 nil 时 `remaining` 是 0 而不是"无限"。** 调用方要看 `limit == null` 才知道，这是个约定而不是显式表达。

**第二，`isValid` 永远为 true。** 要么去掉，要么说明它在什么情况下会是 false（现在没有）。

**第三，`isValid` 和 `is_active` 是重复字段。** 为了兼容不同工具留的，但我没有记录"哪个工具用哪个"——以后想删的时候会不敢删。

**第四，在途请求不计入已用。** 一个用户发了一批请求全都还在跑（预扣了但未结算），接口显示的 `used` 还不包含它们。所以用户可能看到"还剩 5 美元"，然后实际请求会失败（因为预扣时算上了）。**这个差值就是"已冻结但未结算"的金额。**

我在响应里**没有暴露这个数**。理论上它应该是 `used` 之外的一个独立字段，比如 `frozen`。用户看到 `used + frozen > limit` 才能理解为什么明明还有额度却失败了。

这是我认为这个接口目前最实际的一个缺口——**它是用户最容易困惑的地方**（"我明明还有额度"），而原因（在途预扣）在响应里完全不可见。

**第五，没有暴露"超额/降级"状态。** 如果用户已经超了额度（比如倍率调整导致），接口只会显示 `remaining` 为负数。调用方拿到一个负数要自己判断。

---

## 7. 下一篇

下一篇讲数据库迁移与分区：95 个迁移文件怎么管、多个 SQL 方言（MySQL / PostgreSQL / SQLite）怎么共存、大表怎么分区，以及我为什么给迁移写了一份 ownership 清单。

[《96 个迁移文件、三个 SQL 方言：迁移治理是怎么被逼出来的》](/2026-09-17-micro-one-api-migration-governance/)
