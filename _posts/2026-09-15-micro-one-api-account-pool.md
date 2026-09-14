---
title: "订阅账号池：把一个账号“用满”和“用坏”分开处理"
date: 2026-09-15T11:00:00+08:00
description: "拆解 micro-one-api 的订阅账号池调度：用 Redis ZSet 租约实现跨副本并发槽与续租、RPM 滚动窗口限流、按状态码分档的运行时冷却，以及“健康但忙”与“故障”在封禁、熔断、指标、重试预算五个层面上的区分。包含 Redis 故障时 fail-open 的取舍及其被测试钉住的原因。"
tags: ["Micro-One-API", "AI 网关", "Go", "架构", "可靠性"]
categories: ["architecture"]
draft: false
mermaid: true
---

## 摘要

并发一上来，上游返回 429，而我当时的逻辑把 429 当失败，重试几次就把一个完全健康的账号标记成不健康、从候选里摘掉。这就是"用满"和"用坏"没分开的后果。这篇讲我最后怎么在限流器、冷却时长、重试策略、健康记录、指标标签每一处把它们分开。

---

## 0. 一个把我绕进去的问题

接订阅账号（Claude Pro、Codex 这类用 OAuth 登录的上游）的时候，我按渠道的思路先写了一版：选账号 → 请求 → 失败就换一个 → 连续失败就把它标记成不健康。

跑起来之后发现不对。

并发上来的时候，账号开始返回 429。我的逻辑把 429 当失败，重试几次之后把这个账号标记成不健康、从候选里摘掉。结果就是**一个完全健康的账号，因为我并发打太猛被上游限流，就被我自己停用了**。如果池子里只有一个账号，接下来整个池子都会返回"没有可用渠道"。

这就是我所谓的"用满"和"用坏"没分开：**账号被限流说明它还能用，只是现在忙；账号一直 5xx 才是真的坏了。**

这篇讲我最后是怎么把这两个状态在所有层面上分开的——限流器、冷却时长、重试策略、健康记录、指标标签，每一处都要分开。

---

## 1. 为什么要自己做并发限制

先说清楚为什么需要这个。

上游订阅账号的额度是按账号算的，而且它们的限流往往很粗暴：短时间打太猛就直接 429，甚至 529（Overloaded）。这类账号不像 API Key 可以随便开新的，一个账号废掉就是真的少了容量。

所以我希望**把限流的判断前移到我这一侧**：给账号配一个并发上限，达到了就在本地排队/换账号，而不是打过去等上游来拒绝我。

`SubscriptionAccount` 上因此有三个限制字段：

```go
// Concurrency is the maximum number of in-flight relay requests this account
// will serve at once. 0 means unlimited. Enforced by the relay gateway
// (memory or Redis-backed AccountConcurrencyLimiter) so a single
// subscription account is not saturated into upstream 429s.
Concurrency int32
// RPMLimit is the maximum number of relay dispatch attempts this account
// will serve per rolling minute. 0 means unlimited.
RPMLimit              int32
SessionWindowLimitUSD float64
```

三个字段都是 0 表示不限。

---

## 2. 并发槽：一个账号一个信号量

### 2.1 接口只有一个方法

```go
// AccountConcurrencyLimiter caps the number of in-flight relay requests per
// subscription account. It is the enforcement side of
// SubscriptionAccount.Concurrency: channel-service owns the configured limit,
// the gateway holds a slot for the lifetime of each upstream call (including the
// full duration of a streamed response) so a single account is never saturated
// into upstream 429/529s.
type AccountConcurrencyLimiter interface {
    TryAcquire(ctx context.Context, accountID int64, limit int32) (func(), bool)
}
```

返回一个 release 函数。这个形态是被流式逼出来的：**槽位必须持有到流式响应彻底写完为止**，不能只在"发起请求"那段持有，否则并发限制对长连接毫无意义。

"limit ≤ 0 表示不限"这个约定我写在注释里，是为了让调用方不用处理无限的分支：

```go
// A non-positive limit (or a nil limiter / non-positive accountID) means
// "unlimited": TryAcquire always succeeds and returns a no-op release so callers
// need not special-case the unlimited path.
```

### 2.2 release 必须幂等

```go
var once sync.Once
return func() {
    once.Do(func() {
        l.mu.Lock()
        if l.inflight[accountID] <= 1 {
            delete(l.inflight, accountID)
        } else {
            l.inflight[accountID]--
        }
        l.mu.Unlock()
    })
}, true
```

`sync.Once` 不是我多虑。流式那条路径上，release 既可能被 `defer` 调用，也可能在 `result.write` 里被调用（槽位转移给写响应的一方），两条路都可能走。没有 `once` 的话就会重复释放，把在途计数减成负数，然后**这个账号的并发上限就永远达不到、限制彻底失效**。

在途为 0 时顺手 `delete` 掉 map 条目，是为了避免账号被删之后 map 里还留着一堆 0 值。

### 2.3 内存版只解决了单进程

内存版的问题很明显：**并发限制只在单个 relay-gateway 进程里生效。** 起两个副本，同一个账号实际能承受的并发就是 `2 × limit`，恰好是我最不想要的结果——我以为限制住了，其实没有。

所以有了 Redis 版。

---

## 3. Redis 租约：让并发槽跨副本

### 3.1 用 ZSet 存槽位，用 score 当过期时间

```go
const redisAcquireConcurrencyScript = `
redis.call("ZREMRANGEBYSCORE", KEYS[1], "-inf", ARGV[1])
local current = redis.call("ZCARD", KEYS[1])
if current >= tonumber(ARGV[2]) then
	return 0
end
redis.call("ZADD", KEYS[1], ARGV[3], ARGV[4])
redis.call("PEXPIRE", KEYS[1], ARGV[5])
return 1
`
```

一个账号一个 key，每个在途请求是一个 ZSet member，**score 是租约到期时间**。抢占逻辑放在 Lua 里做成原子的：先清掉过期的成员，再数还剩几个，没到上限就加一个进去。

用 ZSet 而不是 `INCR`/`DECR` 计数，是因为**进程崩溃时计数不会自己恢复**。用租约，进程挂了之后成员到期自动被清掉，槽位就释放了。

member 的命名带实例标识和自增序号：

```go
func (l *RedisAccountConcurrencyLimiter) slotMember(accountID int64) string {
    id := l.nextID.Add(1)
    return l.instance + ":" + strconv.FormatInt(accountID, 10) + ":" + strconv.FormatUint(id, 10)
}
```

实例前缀是为了让同一进程的多个槽位互不冲突，序号是为了让同一账号在同一个进程里的多个并发请求各占一个 member——**如果 member 只按账号 ID 命名，同进程的第二个并发请求会覆盖第一个的 member，计数永远上不去。**

### 3.2 长请求要续租

一个流式请求可能跑好几分钟，而租约 TTL 只有 2 分钟。所以持槽期间要后台续租：

```go
func (l *RedisAccountConcurrencyLimiter) refreshLease(ctx context.Context, key, member string, done <-chan struct{}) {
    interval := l.leaseTTL / 2
    // ...
    ticker := time.NewTicker(interval)
    defer ticker.Stop()
    for {
        select {
        case <-done:
            return
        case <-ctx.Done():
            return
        case <-ticker.C:
            deadline := time.Now().Add(l.leaseTTL).UnixMilli()
            // ZADD 更新 score + PEXPIRE 刷新 key 过期
        }
    }
}
```

注意 `case <-ctx.Done(): return`。请求上下文被取消时续租就停了，但**槽位不会立刻释放**——它会在 TTL 到期后自然消失。这个取舍我觉得可以接受：唯一被取消时快速释放要靠额外的取消监听，代价和复杂度都不值当。

### 3.3 反过来说，查询要排除还没被清理的僵尸租约

读路径有个坑。写路径的 Lua 只在**有人来抢槽**的时候才清理过期成员，所以如果一段时间没有新请求，一个崩溃副本留下的过期租约不会被清掉，`ZCARD` 会把它算进去。

```go
// L1 fix: count only members whose lease score is still in the future.
// The acquire Lua only reaps expired members on the write path, so ZCARD
// would include dead leases from crashed replicas for up to one leaseTTL.
// ZCOUNT key now +inf excludes expired-but-unreaped members, matching the
// channel-side LoadOracle semantics.
now := strconv.FormatInt(time.Now().UnixMilli(), 10)
n, err := l.rdb.ZCount(rCtx, l.key(accountID), now, "+inf").Result()
```

用 `ZCOUNT key now +inf` 而不是 `ZCARD`。

**这个 bug 的表现会很误导**：一个副本 OOM 崩了，接下来 2 分钟内这个账号的"在途数"一直虚高，选择器以为它很忙，持续给它降权。看起来像"账号突然变慢了"。

---

## 4. Redis 挂了会怎样：我选了 fail-open

这是我觉得最有必要写清楚的一段，因为**它违反直觉，而且我到现在也不完全确定选对了**。

### 4.1 我的选择

```go
// Redis command failures fail open to the memory limiter so a Redis outage
// degrades to the pre-Redis behaviour instead of blocking all requests.
if err != nil {
    metrics.RelayAccountConcurrencyFallbackTotal.WithLabelValues("acquire_error").Inc()
    return l.fallback.TryAcquire(ctx, accountID, limit)
}
```

Redis 出错时退回到进程内的内存限流器。**请求不会被拒绝。**

### 4.2 代价是明确的

```go
// Fail-open trade-off (code-review H11/M9): the fallback is PER-REPLICA, so
// during a Redis outage each replica enforces the configured limit locally and
// the global cap degrades to N × limit (N = replica count). This is a
// deliberate availability-over-strictness choice — an outage must not block
// traffic — and the exact behaviour is pinned by
// TestRedisAccountConcurrencyLimiter_MultiReplicaFailOpenExceedsCap, so a
// future replica-count-aware weighted cap (limit / N via a registry) or a
// fail-closed policy must update that assertion intentionally.
```

三个副本时，一个上限 5 的账号实际能被打到 15。这正好是会触发上游 429 的量级——**我为了解决一个可用性问题，换来了一个会触发限流的问题。**

### 4.3 为什么我还是写了这个测试

`TestRedisAccountConcurrencyLimiter_MultiReplicaFailOpenExceedsCap` 这个名字是故意的。测试不是验证"行为正确"，而是**把这个错误行为钉住**：

```go
// ... the exact behaviour is pinned by
// TestRedisAccountConcurrencyLimiter_MultiReplicaFailOpenExceedsCap, so a
// future replica-count-aware weighted cap (limit / N via a registry) or a
// fail-closed policy must update that assertion intentionally.
```

以后谁想改成 fail-close、或者做按副本数分摊（`limit / N`），就必须先来改这个测试。**我不想让这个取舍被无声地改掉——它值得一个有意识的决定。**

同样的 fail-open 我也用在了会话窗口上：

```go
// The in-memory maps are the fail-open fallback (code-review M8): when Redis is
// unreachable the window is enforced per-replica, so a multi-replica deployment
// can temporarily overspend the session window (N × the single-replica view)
// until Redis recovers. Availability over strict enforcement; the same
// trade-off as the account concurrency limiter (H11).
```

### 4.4 折中方案：写路由不写限制

写到这里我想补一句：还有第三种选择我没做，就是**观测 fail-open、限制 fail-close**——Redis 挂了之后不阻止请求，但要打告警，让人知道现在限制是失效的。

所以我在失败路径上都挂了指标：

```go
metrics.RelayAccountConcurrencyFallbackTotal.WithLabelValues("acquire_error").Inc()
```

至少让"限制正在失效"这件事可见。

---

## 5. RPM：同样的形状，更简单的语义

RPM 限制和并发槽是两套东西，虽然都用 ZSet。

并发是"同时在跑多少"，是**状态**；RPM 是"一分钟内发起过多少次"，是**事件流**。RPM 的槽位用完就没了，不需要续租：

```go
const redisAcquireRPMScript = `
redis.call("ZREMRANGEBYSCORE", KEYS[1], "-inf", ARGV[1])
local current = redis.call("ZCARD", KEYS[1])
if current >= tonumber(ARGV[2]) then
	return 0
end
redis.call("ZADD", KEYS[1], ARGV[3], ARGV[4])
redis.call("PEXPIRE", KEYS[1], ARGV[5])
return 1
`
```

脚本长得几乎一样，区别在参数：RPM 的 score 是"这次请求发生的时间"，清理阈值是"一分钟前"。

```go
func (l *MemoryAccountRPMLimiter) TryAcquire(_ context.Context, accountID int64, limit int32) bool {
    // ...
    cutoff := now.Add(-time.Minute).UnixMilli()
    kept := pruneRPMEvents(l.events[accountID], cutoff)
    if len(kept) >= int(limit) {
        l.events[accountID] = kept
        return false
    }
    kept = append(kept, nowMs)
    l.events[accountID] = kept
    return true
}
```

同样的 fail-open 取舍，注释里也指向了那个被钉住的测试。

有意思的是这套 RPM 限流器被复用了两次——按账号限（`subscription_account:rpm:`）和按用户限（`user:rpm:`），只是换了 key 前缀：

```go
func NewRedisAccountRPMLimiter(rdb *redis.Client) *RedisAccountRPMLimiter {
    return newRedisRPMLimiter(rdb, accountRPMKeyPrefix, "")
}

func NewRedisUserRPMLimiter(rdb *redis.Client) *RedisAccountRPMLimiter {
    return newRedisRPMLimiter(rdb, userRPMKeyPrefix, "")
}
```

---

## 6. 运行时封禁：把失败分档冷却

前面说的都是"主动限制"。运行时封禁是"被动反应"：上游告诉我这个账号现在不能用了，我记下来冷却一段时间。

### 6.1 冷却时长按状态码分档

```go
// runtimeBlockDuration returns how long to cool an account down for a given
// upstream status, honouring the configured overrides (SetRuntimeBlockDurations)
// and falling back to the built-in defaults (429=5s, 401=2m, 5xx=2m). Other
// statuses are not blocked.
func (s *HTTPServer) runtimeBlockDuration(statusCode int) time.Duration {
    switch {
    case statusCode == http.StatusTooManyRequests:
        return 5 * time.Second        // 限流：很短暂
    case statusCode == passthrough.StatusOverloaded:
        return 30 * time.Second       // 529 过载：比 429 长，比 5xx 短
    case statusCode == http.StatusUnauthorized:
        return 2 * time.Minute        // 401：凭据问题，要人工介入
    case statusCode >= 500:
        return 2 * time.Minute        // 5xx：上游故障
    }
    return 0                          // 其他状态不封禁
}
```

这四档的排序是我想清楚"这个错误的本质是什么"之后定的：

| 状态 | 本质 | 冷却 | 理由 |
|---|---|---|---|
| 429 | 我打太快 | 5s | 等一小会儿就好，封久了白损失容量 |
| 529 | 上游自己过载 | 30s | 不是我的错也不是账号的错，但需要更长一点 |
| 401 | 凭据失效 | 2m | 短时间重试没意义，同时给告警留出时间 |
| 5xx | 上游故障 | 2m | 同上 |

**529 单独分一档是我特意加的。** 它和 429 在语义上完全不同——429 是"你的配额/速率超了"，529 是"我现在整体过载"。混在一起用一个值，要么对 429 太狠，要么对 529 太松。

配置里可以覆盖这几个默认值：

```yaml
runtime_block:
  rate_limited_duration: 5s
  unauthorized_duration: 2m
  server_error_duration: 2m
  overloaded_duration: 30s
```

### 6.2 "健康但忙"不封禁

这是整篇最关键的一段判断：

```go
result := s.runSubscriptionAttempt(...)
if result.retryable {
    accountID := subscriptionAccountIDFromPlan(current)
    if accountID > 0 {
        failedAccounts[accountID] = true
        // Local relay limits mean the account is healthy, just currently
        // unavailable: fail over to a sibling but never cool it down.
        // Rate-limit outcomes (429/423/529) are likewise transient "account
        // busy" states, NOT faults: the same-account retry in
        // runSubscriptionAttempt already backed off before we got here, and
        // cooling the account down would make a single-account pool surface
        // 503 "no available channel" for the whole cool-down window. So
        // rate-limited accounts are excluded for THIS request (failover)
        // but never cooled.
        if !result.concurrencyFull && !result.rpmFull && !result.sessionWindowFull &&
            !isSubscriptionRateLimitStatus(result.statusCode) {
            s.blockRuntimeAccount(r.Context(), accountID, result.statusCode, result.err)
        }
    }
    // ...换下一个账号
}
```

注意 `failedAccounts[accountID] = true` 在封禁判断**之前**，无条件执行。这两件事是两个不同的作用域：

| | `failedAccounts` | `runtimeBlocker` |
|---|---|---|
| 作用域 | 这**一个**请求 | 整个进程（或整个集群） |
| 目的 | 别再把请求发给它 | 别再用它 |
| 触发条件 | 任何失败 | 只有真正故障 |

**"这个请求别用它"和"全局别再让它接活"必须分开。** 前者是请求级的排除，后者才是状态变更。我一开始把两者合成一个动作，就出现了开头说的那种"账号因为被限流而被停用"的问题。

### 6.3 429/423/529 在健康记录里也要被排除

同一件事在另一处也要处理：

```go
// Feed a real upstream outcome into the account circuit breaker — but never
// a rate-limit (429/423/529) outcome. Rate limits mean "the account is busy",
// not "the account is broken": under concurrency (which the config model
// intentionally does not gate locally) a burst of requests naturally trips
// upstream rate limits, and counting those as breaker errors would open the
// circuit on a healthy account, surfacing as "no available channel" for
// every concurrent request until the open window expires.
if result.upstreamAttempted && !isSubscriptionRateLimitStatus(result.statusCode) {
    _ = s.relayUsecase.RecordSubscriptionAccountHealth(ctx, subscriptionAccountIDFromPlan(current), result.upstreamSucceeded)
}
```

熔断器（决定长期不健康）和运行时封禁（决定短期冷却）是两套机制，**但限流这个信号对两者都不构成"故障证据"**，要在两个地方分别排除掉。

---

## 7. 同账号重试：先原地等，别急着换人

上游返回 409/423 这类"暂时性冲突"时，我最早的做法是直接换账号。

问题是：账号池里的每个账号都可能有这种瞬时抖动。一次抖动就换人，会让"好账号"被频繁地轮换掉，而且换过去的新账号可能也刚好在抖动。

所以现在的顺序是：**先在同一个账号上原地重试几次，还不行才换人。**

```go
const (
    // subscriptionSameAccountMaxRetries bounds how many times a transient
    // same-account error (409/423) is retried in place before escalating to
    // cross-account failover.
    subscriptionSameAccountMaxRetries = 3
    // subscriptionSameAccountRetryDelay is the fixed pause between same-account
    // retries.
    subscriptionSameAccountRetryDelay = 500 * time.Millisecond
)
```

```go
func (s *HTTPServer) runSubscriptionAttempt(...) subscriptionAdaptorResult {
    result := s.executeAndMeter(...)
    for tries := 0; result.retryableSameAccount && tries < subscriptionSameAccountMaxRetries; tries++ {
        metrics.RelaySubscriptionFailoverTotal.WithLabelValues("same_account", "retried").Inc()
        if !sleepCtx(r.Context(), subscriptionSameAccountRetryDelay) {
            break // 客户端取消了，别白等
        }
        result = s.executeAndMeter(...)
    }
    if result.retryableSameAccount {
        // Same-account retries exhausted: escalate to cross-account failover.
        // 409/423 carry a zero runtime-block duration, so the caller excludes the
        // account for this request without cooling it down.
        result.retryable = true
    }
    return result
}
```

两个细节：

**这个重试不占跨账号的预算。** 3 次原地重试之后才升级成 `retryable`，交给外层去做跨账号 failover。如果原地重试也算进外层预算，一次抖动就会把 3 次 failover 机会用掉。

**409/423 的冷却时长是 0**（`runtimeBlockDuration` 的 default 返回 0），所以这类账号只被"这个请求"排除，不进全局封禁。跟 6.2 的原则一致。

`Classify` 里对应的分类：

```go
case statusCode == http.StatusConflict || statusCode == http.StatusLocked:
    err.Kind = KindRetryableOnSameAccount
```

---

## 8. 会话粘性：为了 prompt cache

订阅账号这块还有一个和"限制"无关、但和"账号池"强相关的功能：把会话固定到某个账号上。

原因很实际：上游的 prompt cache 是按账号维度命中的。同一个对话如果每次都换账号，缓存命中率基本是 0，成本和延迟都会明显变差。

```go
// SessionAccountStore resolves and refreshes the session -> subscription-account
// binding used for cross-session account stickiness (docs #7). It is satisfied
// by the server-layer sticky store (openAIWSStickyStore), which stores an int64
// account id keyed by group+sessionHash with a local hot cache + Redis. Lookup
// returns 0 on miss or backend error, so a Redis outage degrades to a normal
// (non-sticky) selection rather than failing the request.
type SessionAccountStore interface {
    LookupSessionChannel(ctx context.Context, group, sessionHash string) int64
    RefreshSessionTTL(ctx context.Context, group, sessionHash string, ttl time.Duration) bool
}
```

注意这里的第三处 fail-open：**Redis 查不到就当成没有绑定，走普通选路，而不是报错。** 粘性丢了只是缓存命中率下降，不值得让请求失败。

### 8.1 只在成功之后才绑定

```go
// Bind the conversation to the account that actually served it (success
// only), so the next turn reuses it for prompt-cache hits. A failover
// switch naturally rebinds to the sibling that succeeded.
if subscriptionAttemptSucceeded(result) {
    finalSuccess = true
    finalAccountID = subscriptionAccountIDFromPlan(current)
    s.bindSubscriptionSession(r.Context(), plan.Auth.Group, sessionHash, current)
}
```

```go
// subscriptionAttemptSucceeded reports whether a terminal adaptor result was a
// successful upstream response (2xx, not a retryable/failed attempt). Only these
// bind a session -> account stickiness record.
func subscriptionAttemptSucceeded(result subscriptionAdaptorResult) bool {
    return result.err == nil && !result.retryable && result.statusCode >= 200 && result.statusCode < 300
}
```

**失败的会话不绑定。** 否则一个刚好抖动的账号会被粘性记录锁住，后面整个对话的每一轮都会往它上面撞。绑定只在成功时发生，失败自动重绑到成功的那个账号。

绑定结果分了 "hit" 和 "rebind" 两类指标：

```go
prior := s.wsSticky.LookupSessionChannel(ctx, group, sessionHash)
s.wsSticky.BindSessionChannel(ctx, group, sessionHash, servedID, s.openAIWSStickyTTL())
result := "rebind"
if prior == servedID {
    result = "hit"
}
metrics.RelaySubscriptionStickyTotal.WithLabelValues(result, subscriptionMetricPlatform(served)).Inc()
```

看这两个值的比例，就知道粘性是不是真的在起作用。如果 hit 占比很低，说明会话哈希不稳定或者绑定被频繁覆盖。

---

## 9. 账号选择器里的负载因子：一条跨进程的链路

第 3 篇讲过渠道选择器的 `loadFactor` 是进程内闭环的（Select 加、RecordHealth 减）。账号选择器做不到这一点：它在 channel-service 进程里，而请求在 relay-gateway 进程里跑。

所以走了一条 Redis 中转：

**写侧**（relay-gateway）：抢到槽位就往 ZSet 里写一个带租约的 member，前面第 3 节讲的。

**读侧**（channel-service）：选账号之前把这些 ZSet 数出来。

```go
// InflightBatch pipelines a ZCOUNT per account in a single round-trip
// (MEDIUM-2), so selecting an N-account tier costs one Redis RTT instead of
// N serial ones. Absent accounts default to 0 (no live load).
func (o *redisLoadOracle) InflightBatch(ctx context.Context, accountIDs []int64) map[int64]int32 {
```

用 pipeline 把 N 次查询合成一次往返，是因为这个查询在选账号的热路径上。

两个我特意处理的细节：

**查询在锁外做。** 选账号时要遍历候选，如果每个候选都在选择器的锁里查一次 Redis，并发一上来所有 Select 会互相阻塞：

```go
// Phase D #12: refresh the cross-replica in-flight snapshot for each
// candidate BEFORE taking the lock. ... Querying outside the selector lock
// keeps per-candidate Redis RTTs off the hot-path critical section (MEDIUM-2):
// N candidates cost N lookups, but they no longer block every other
// concurrent Select in this process.
crossReplica := s.prefetchInflight(ctx, candidates)
```

**零值必须覆盖旧值。** 一个账号从忙变闲之后，如果只在有负载时才写快照，它会永远停留在峰值被降权：

```go
// Store the cross-replica snapshot unconditionally (MEDIUM-1): an idle
// account reads 0, which must overwrite a previously-high value so the
// account is no longer derated once it drains. Only writing on n>0
// would pin the snapshot at its peak forever.
state.crossReplicaInflight.Store(crossReplica[acct.ID])
```

而 pipeline 整体失败时会退化成逐个查询，而不是把所有账号都当成 0：

```go
// On pipeline failure, fall back to per-account reads so a transient
// Redis hiccup does not zero out every account (which would over-load
// saturated accounts). Individual errors still yield 0.
```

**"查不到负载" 和 "负载是 0" 是两个不同的意思。** 退化成 0 会导致所有账号的 `loadFactor` 都变成 100，把流量均匀地铺到已经饱和的账号上。

---

## 10. 三个限制的执行顺序

一个订阅账号请求进来，先后要过三道闸：

```go
// Enforce the account's concurrency limit before doing any work.
// A full account fails over to a sibling (concurrencyFull) rather than being
// cooled down: it is healthy, just busy.
releaseSlot, acquired := s.accountConcurrency.TryAcquire(ctx, accountID, concurrencyLimit)
if !acquired {
    result.statusCode = http.StatusServiceUnavailable
    result.err = fmt.Errorf("subscription account %d at concurrency limit %d", accountID, concurrencyLimit)
    result.retryable = true
    result.concurrencyFull = true
    result.write = func(w http.ResponseWriter) {
        s.writeError(w, http.StatusServiceUnavailable, "all subscription accounts busy")
    }
    return result
}
```

另外两道在 `AcquireRelayAttempt` 这个钩子里（第 2 篇提过）：

```go
func (h httpRelayLifecycleHooks) AcquireRelayAttempt(ctx context.Context, plan *relaybiz.RelayPlan, req relaybiz.ExecutorRequest) (func(), error) {
    releaseSlot, acquired := h.s.accountConcurrency.TryAcquire(ctx, accountID, concurrencyLimit)
    if !acquired {
        return nil, &relaybiz.RetryableError{Status: http.StatusServiceUnavailable, Err: ...}
    }
    // ...
    if h.s.accountRPM != nil && !h.s.accountRPM.TryAcquire(ctx, accountID, rpmLimit) {
        release()
        return nil, &relaybiz.RetryableError{...}
    }
    if h.s.sessionWindow != nil && h.s.sessionWindow.Exceeded(ctx, plan.Auth.Group, req.SessionHash, accountID, sessionWindowLimitUSD) {
        release()
        return nil, &relaybiz.RetryableError{...}
    }
    return release, nil
}
```

顺序是：**并发槽 → RPM → 会话窗口**。三个都失败时都返回 `RetryableError` + 503，让上层去换账号。

注意 RPM 和会话窗口失败时都调了 `release()`——**并发槽是第一个拿的，后面任何一道没过都必须把它放掉**，否则这个账号的并发容量会被一个根本没发出去的请求占着。

`concurrencyFull` / `rpmFull` / `sessionWindowFull` 这三个标记的作用是让 6.2 节那段判断知道"这是本地限制导致的失败，不要封禁"。

指标上也能区分出来：

```go
func subscriptionRetryReason(result subscriptionAdaptorResult) string {
    if result.concurrencyFull {
        return "concurrency"
    }
    if result.rpmFull {
        return "rpm"
    }
    if result.sessionWindowFull {
        return "session_window"
    }
    if result.retryableSameAccount {
        return "same_account"
    }
    if result.statusCode == http.StatusTooManyRequests {
        return "429"
    }
    if result.statusCode == passthrough.StatusOverloaded {
        return "529"
    }
    // ...
}
```

**"换账号的原因"必须能区分出来。** 如果只有 `routing_fallback_total` 一个总数，我根本不知道是该加账号（并发不够）、还是该降 RPM、还是上游真的不稳。

---

## 11. 现在还没解决的

**第一，Redis 故障时的降级我选了可用性，代价写清楚了但没消除。** 多副本时全局上限会退化成 `N × limit`。我留了按副本数分摊的思路（`limit / N`），但需要服务注册信息，没做。

**第二，账号选择器的状态是 channel-service 进程内的。** 和渠道选择器同样的多副本问题。channel-service 多实例时，每个实例的加权轮询状态是独立的，而 `LoadOracle` 只能补上"在途数"这一个维度。

**第三，封禁原因的可观测性不够。** 现在有封禁总数和活跃数，但"这个账号现在因为什么被封、还有多久解封"要去翻结构化日志。运营排障时这一层缺失挺难受。

**第四，`maxAttempts = 8` 这个循环上限是拍出来的。** 在 `selectSchedulableSubscriptionAccount` 里，因为本地封禁的账号 channel-service 看不到，只能"选一个 → 发现被封 → 排除 → 再选"，循环 8 次。如果被封的账号超过 8 个，就会返回"找不到账号"，而池子里其实还有能用的。这个数我只是觉得"够大了"。

**第五，选择器的 `Acquire`/`Release` 是空转的。** 账号选择器里有一对 `Acquire`/`Release` 方法，注释里明确写着 relay 的派发路径不调用它：

```go
// v0.11.0 Phase 3 §3.2: this is an INERT reserved hook — production relay
// dispatch does not call it, so loadFactor stays neutral (100) and the
// selector never de-rates on in-flight saturation. It is retained so a future
// Redis-backed or async best-effort seam can populate it without changing the
// public API.
```

真实负载走的是 Redis 那条链路。这对方法是我早期设计的残留，一直没删——属于该清理的债。

---

## 12. 相关的一篇

账号池管的是单个账号能承受多少。再往外一层是跨服务调用的保护——熔断、超时、降级，以及一个曾经让用户传错模型名就能打挂整个网关的错误分类问题。

[《熔断、超时和降级：跨服务调用的那些保护，以及我接错了的地方》](/2026-09-15-micro-one-api-gateway-reliability/)。
