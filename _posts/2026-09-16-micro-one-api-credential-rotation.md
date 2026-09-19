---
title: "凭证轮转：refresh token 会被换掉，而我的内存和数据库可能对不上"
date: 2026-09-16T12:00:00+08:00
description: "我第一版的 token 刷新逻辑大概是这样的：。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个第一次写 OAuth 刷新很容易漏掉的事

我第一版的 token 刷新逻辑大概是这样的：

```
取缓存的 access_token
  → 快过期了？
    → 拿 refresh_token 去换新的
    → 存进数据库
    → 更新缓存
```

看起来没问题。但它默认了一个前提：**refresh token 是不变的。**

很多 OAuth 实现不是这样。它们在每次刷新时**把旧的 refresh token 作废，发一个新的**——这叫 refresh token rotation。用途是检测泄露：如果一个旧的 refresh token 被重复使用，服务端就知道它被偷过。

这带来一个我在第一版里完全没考虑的场景：

**刷新成功了，新 token 也拿到了，但存数据库失败了。**

这时：

- 上游已经作废了旧的 refresh token；
- 我手上的内存里是新的（可用的）；
- 数据库里还是旧的（已经失效的）；
- 进程一重启，内存没了 → 我去数据库读那个失效的 refresh token → 刷新失败 → **账号废了**。

这个 bug 不会立刻报错。它会在**下一次进程重启之后**才暴露，而那时你早已忘了之前那次存储失败。

这篇讲我怎么处理这一类"两份状态可能对不上"的问题，以及 OAuth 刷新这条链路上其他几个我踩到的点。

---

## 1. 五家平台，三种凭证形态

先交代背景。订阅账号支持五家平台，但它们的凭证形态只有三种：

```go
const (
    PlatformCodex   Platform = "codex"
    PlatformClaude  Platform = "claude"
    PlatformZhipu   Platform = "zhipu"   // GLM Coding Plan (static key)
    PlatformMinimax Platform = "minimax" // MiniMax Coding Plan (static key)
    PlatformKimi    Platform = "kimi"    // Kimi For Coding (OAuth refresh)
)
```

| 形态 | 平台 | 行为 |
|---|---|---|
| OAuth 可刷新 | codex、claude、kimi | 有 refresh token，临期主动换 |
| 静态密钥 | zhipu、minimax | 长期 API key，不过期、不刷新 |
| （未来） | — | — |

静态密钥那条路我单独做了一个实现，它的语义写得很清楚：

```go
// Semantics:
//   - GetAccessToken returns the access_token stored on the account (the
//     vendor-issued Coding Plan key). The stored key is assumed non-expiring,
//     so the provider neither caches nor refreshes; it reads from the
//     AccountLookup on every call.
//   - Refresh is a no-op: there is no refresh token to exchange. It returns
//     nil so callers that call Refresh defensively (e.g. after a transient
//     401) do not mark the account broken for a refresh failure.
//   - A persistent 401/403 from the upstream is the signal that the static
//     key is actually invalid; that path is handled by the relay's
//     runtime-blocker / SetSubscriptionAccountError chain keyed on the HTTP
//     status, not by this provider.
```

三点都值得注意，尤其是 `Refresh` 返回 nil 这一条：

**一个"防务性调用"不该导致账号被判死。** 如果某个调用方在收到 401 之后习惯性地调一次 `Refresh`，而静态 provider 在这里返回错误，账号就会被标记成刷新失败——但静态密钥根本没有"刷新失败"这回事，它只是过期或不合法。**这类错误的发生路径是"上游 401"，该由运行时封禁处理，不该由凭证层处理。**

而 `GetAccessToken` 每次都去查（不缓存）也不是偷懒：

```go
// Invalidate is a no-op: there is no in-process token cache to evict. The
// provider re-reads the stored key on every GetAccessToken, so an operator
// rotating the key via the channel-service admin RPC takes effect on the
// next request without any cache invalidation here.
```

**"不缓存"换来的是"改了就立刻生效"。** 对不过期、成本极低的静态密钥，这笔交易划算。

---

## 2. 双保险：请求时刷新 + 后台预刷新

刷新的触发有两个来源，注释里叫"double-safety"：

**第一层：请求时刷新。** 热路径上发现快过期就换。

```go
const RefreshSkew = 3 * time.Minute
```

3 分钟的 skew——**不是"过期了才换"，而是"还剩 3 分钟就换"。** 留这个余量是因为一次请求可能跑很久（流式响应几分钟很正常），如果等到过期才换，一个正在跑的流就会被中途掐断。

**第二层：后台预刷新。**

```go
func DefaultRefreshTaskConfig() RefreshTaskConfig {
    return RefreshTaskConfig{
        Interval:                  10 * time.Minute,
        Lookahead:                 24 * time.Hour,
        MaxRetries:                3,
        RetryBackoff:              2 * time.Second,
        TempUnschedulableDuration: 10 * time.Minute,
    }
}
```

每 10 分钟扫一遍，把**24 小时内将要过期**的账号提前换掉。

为什么要提前 24 小时？因为上游的 refresh 接口可能临时不可用。如果我等到还剩 3 分钟才去换，而那一刻上游正好抖动，这个账号就当场不可用了。**提前一天开始尝试，我就有一整天的重试窗口。**

这两层的关系不是"主备"，而是"一个负责正确，一个负责平稳"：

- 请求时刷新保证**正确性**——不管后台任务有没有跑，请求都不会因为 token 过期而失败；
- 后台预刷新保证**平稳**——避免所有账号的刷新都挤在请求路径上。

---

## 3. 核心问题：内存和持久化的两份状态

回到开头那个问题。现在的处理是这样的：

```go
newCreds, err := b.refresher.refresh(ctx, refreshURL, creds.RefreshToken)
if err != nil {
    return "", err
}
// Preserve the account id and client id from the stored record.
newCreds.AccountID = creds.AccountID
newCreds.ClientID = creds.ClientID
if newCreds.RefreshURL == "" {
    newCreds.RefreshURL = creds.RefreshURL
}
if storeErr := b.lookup.Store(ctx, accountID, newCreds); storeErr != nil {
    // domain-M1: persistence failed but we hold a fully-valid refreshed
    // credential set, including the ROTATED refresh token. Cache the whole
    // set in-process so (a) the current request succeeds with the new access
    // token and (b) the next resolve reuses the rotated refresh token instead
    // of the stale one the persistent lookup would return (which would brick
    // the account once the access token expires). Do NOT return the store
    // error: a typical caller does `if err != nil { return err }`, which would
    // fail a request that has a perfectly good token. Report the persist
    // failure via log/meter only.
    b.cache.setCreds(accountID, newCreds)
    logPersistFailure(accountID, storeErr)
    return newCreds.AccessToken, nil
}
b.cache.setCreds(accountID, newCreds)
return newCreds.AccessToken, nil
```

这段注释有点长，但它记录了两个独立的决定。

### 3.1 决定一：存储失败不返回错误

注释里那句是关键：

> *Do NOT return the store error: a typical caller does `if err != nil { return err }`, which would fail a request that has a perfectly good token.*

**我手上有一个完全可用的 access token，凭什么让这个请求失败？**

如果返回错误，调用方的典型写法会把这次的用户请求判失败，而实际上这次请求本来可以正常完成。**存储失败是运维问题，不该变成用户可见的故障。**

所以只记日志：

```go
func logPersistFailure(accountID int64, err error) {
    log.Printf("credential: account %d token refreshed but persist failed (will retry on next resolve): %v", accountID, err)
}
```

（这个用 `log.Printf` 而不是项目统一的结构化 logger，是我想改但还没改的一处不一致。）

### 3.2 决定二：把整套凭证存进内存缓存，而不只是 access token

这是真正解决开头那个 bug 的地方。缓存里存的不只是一个字符串：

```go
type cacheEntry struct {
    accessToken string
    expiresAt   time.Time
    // creds holds the full credential set (including a rotated refresh token)
    // when set. It lets resolve reuse a refreshed refresh token in-process even
    // if persistence (Store) failed, so the account does not brick on the next
    // refresh (domain-M1). Nil for cache entries seeded from an access-token-only
    // lookup.
    creds *AccountCredentials
}
```

然后 `resolve` 在开头先看缓存里的完整凭证：

```go
// domain-M1: prefer the in-process full credential cache when the access
// token is still valid. A previous refresh may have rotated the refresh
// token and failed to persist it (Store error); the persistent Lookup would
// then return the stale (now-invalid) refresh token and the account would
// brick on the next refresh. The cached creds carry the rotated token.
if cached, ok := b.cache.getCreds(accountID); ok && cached.AccessToken != "" && !staleExpiry(cached.ExpiresAt) && !force {
    b.cache.set(accountID, cached.AccessToken, cached.ExpiresAt)
    return cached.AccessToken, nil
}
```

**关键在这行判断的顺序**：先看内存里的完整凭证，**然后**才去持久化层查。

如果反过来（先查数据库拿到旧的 refresh token，再发现内存里有新的），那个旧的就已经被用来刷新了——而它已经失效。

这个设计把开头的场景变成了：

1. 刷新成功，数据库存储失败；
2. 内存里存下新的整套凭证（含轮转后的 refresh token）；
3. 后续请求命中内存缓存，用新的 refresh token 继续刷新；
4. **账号在这个进程的生命周期内一直可用**；
5. 下次成功存储时，数据库被修正。

而只在"**进程重启**"这个前提下，第 3 步才会失效——那时数据库里还是旧的，账号需要重新绑定。

### 3.3 这个设计没解决的

我得说清楚它只是"缓解"：

**如果 `Store` 一直失败（比如数据库权限问题），那内存里的新 refresh token 永远存不回去。进程一重启，账号就废了。**

我没有做的是：**把存储失败重试做成一个持久化的队列**。现在的"下次 resolve 时再试"依赖那个账号还被使用——如果一个账号存储失败之后没人再用它，就永远不会重试。

评论区的注释写的是 "will retry on next resolve"，这是准确的：**它依赖后续请求，而不是主动补偿。**

---

## 4. 并发：同一账号不能同时刷两次

一个账号被很多并发请求同时使用，如果每个都发现 token 快过期，就会一起去打上游的 refresh 接口。

后果有两种，第二种更糟：

**第一种：浪费。** 几次并发的刷新请求，只有第一次是有意义的。

**第二种：如果上游是 rotation 的，多个并发刷新可能互相作废。** 第一个刷新让旧 refresh token 失效，第二个还在用旧的，于是失败——甚至可能触发上游的泄露检测。

所以每个账号一把锁：

```go
type baseTokenProvider struct {
    lookup    AccountLookup
    cache     *tokenCache
    refresher *refresher
    refreshMu sync.Map // accountID int64 -> *sync.Mutex
    // ...
}

func (b *baseTokenProvider) lockFor(accountID int64) *sync.Mutex {
    v, _ := b.refreshMu.LoadOrStore(accountID, &sync.Mutex{})
    return v.(*sync.Mutex)
}
```

```go
func (b *baseTokenProvider) GetAccessToken(ctx context.Context, accountID int64) (string, error) {
    if b.lookup == nil {
        return "", ErrNotConfigured
    }
    if token, _, ok := b.cache.get(accountID); ok && !b.cache.stale(accountID) {
        return token, nil
    }
    mu := b.lockFor(accountID)
    mu.Lock()
    defer mu.Unlock()
    // Re-check after acquiring the lock: another goroutine may have refreshed.
    if token, _, ok := b.cache.get(accountID); ok && !b.cache.stale(accountID) {
        return token, nil
    }
    return b.resolve(ctx, accountID, false)
}
```

注意那个**双重检查**：

1. 锁外先查一次缓存——绝大多数请求走这条快路径，完全不加锁；
2. 拿锁；
3. **锁内再查一次**——因为在我等锁的这段时间，另一个 goroutine 可能已经刷完了。

**第二次检查是必须的。** 如果只有第一次，那么等锁的 N-1 个 goroutine 拿到锁之后会各自再刷一次，锁等于白加。

用 `sync.Map` 而不是 `map + mutex`，是因为锁的获取在热路径上（每个请求都会 `LoadOrStore` 一次），`sync.Map` 在"读多写少、key 集合稳定"的场景下比全局互斥锁好。

---

## 5. 后台任务的重试：两种失败不能同等对待

后台预刷新有重试，但**不是所有错误都值得重试**：

```go
for attempt := 1; attempt <= t.maxRetries; attempt++ {
    err := provider.Refresh(ctx, accountID)
    if err == nil {
        t.invalidate(provider, accountID)
        // ...
        return nil
    }
    lastErr = err
    if isNonRetryableRefreshError(err) {
        t.handleRefreshFailure(ctx, accountID, err, true)
        return err
    }
    if attempt < t.maxRetries {
        if aborted, abortErr := t.sleepBackoff(ctx, attempt); aborted {
            return abortErr
        }
    }
}
t.handleRefreshFailure(ctx, accountID, lastErr, false)
return lastErr
```

```go
func isNonRetryableRefreshError(err error) bool {
    if err == nil {
        return false
    }
    if errors.Is(err, ErrNoRefreshToken) || errors.Is(err, ErrAccountNotFound) {
        return true
    }
    // domain-H2: the refresher now surfaces invalid_grant as the typed
    // ErrInvalidGrant (wrapping ErrRefreshFailed), so errors.Is is the
    // reliable check. The string fallbacks are retained for any caller that
    // still constructs a plain error.
    if errors.Is(err, ErrInvalidGrant) {
        return true
    }
    msg := strings.ToLower(err.Error())
    return strings.Contains(msg, "invalid_grant") || strings.Contains(msg, "invalid refresh")
}
```

三类错误直接放弃重试：

| 错误 | 含义 | 后果 |
|---|---|---|
| `ErrNoRefreshToken` | 没有 refresh token | 要重新授权 |
| `ErrAccountNotFound` | 账号不存在了 | 要人工处理 |
| `ErrInvalidGrant` | refresh token 被撤销/失效 | **要重新绑定** |

**重试一个 `invalid_grant` 是纯粹的浪费，而且会让日志被同一类错误刷满。** 更重要的是：这三种情况都**不会自愈**，只有人重新走一遍 OAuth 绑定才能解决。所以它们的处理路径是 `OnRefreshNonRetryable`，而不是"临时不可调度"：

```go
if nonRetryable {
    if hookErr := t.hook.OnRefreshNonRetryable(ctx, accountID, reason); hookErr != nil {
        // ...
    }
    return
}
until := time.Now().Add(t.tempBlock)
if hookErr := t.hook.OnRefreshRetryExhausted(ctx, accountID, until, reason); hookErr != nil {
    // ...
}
```

**两种失败对应两种 hook**：

- 可重试但重试耗尽了 → 临时不可调度 10 分钟，之后 sweeper 会再试（第 9 篇讲的恢复策略）；
- 不可重试 → 交给人工，进 `manual` 策略。

这个区分直接决定了第 9 篇那个恢复 sweeper 会不会去动它。

### 5.1 `invalid_grant` 为什么要做成类型化错误

注释里的 "domain-H2" 记着这次改动的原因：

**原来的做法是匹配错误字符串。** 刷新失败时把上游的响应体拼进错误消息，然后 `strings.Contains(msg, "invalid_grant")`。

这个做法的问题很明显：**上游改一下错误格式，判断就失效了。** 而失效的后果是——一个永久失效的账号会被无限重试。

现在做成了类型化的 sentinel：

```go
// ErrInvalidGrant is returned when the upstream token endpoint reports an
// invalid_grant error, meaning the refresh token is permanently revoked or
// expired and no amount of retrying will recover it. It wraps ErrRefreshFailed
// so callers checking for a generic refresh failure still match. Callers
// should use errors.Is(err, ErrInvalidGrant) to stop retrying the account
// (code-review 2026-07-30 domain-H2).
ErrInvalidGrant = fmt.Errorf("credential: %w: invalid grant", ErrRefreshFailed)
```

注意它是 `%w` 包着 `ErrRefreshFailed` 的。**这样"泛化的刷新失败"判断和"具体的 invalid_grant"判断都能命中**——两个都没丢。字符串匹配作为兜底还留着（注释里说明了），但主路径是类型。

---

## 6. 退避时间短得有点可疑

后台任务的重试退避是这样算的：

```go
func (t *RefreshTask) sleepBackoff(ctx context.Context, attempt int) (aborted bool, abortErr error) {
    d := t.backoff * time.Duration(1<<(attempt-1))
    timer := time.NewTimer(d)
    // ...
}
```

基准 2 秒，指数退避：**2s、4s**（`MaxRetries = 3`，所以只有两次退避）。

所以三次尝试加起来只覆盖大约 **6 秒**的窗口。

这个时间尺度对一个"上游 refresh 接口临抖动"的场景来说**太短了**。真正需要退避的场景（上游限流、网络分区）都是以分钟计的。

但我不打算简单把数字调大，因为这个任务的周期本身就是 10 分钟：

**如果三次尝试在 6 秒内放弃，那它实际是在等下一个 10 分钟的周期再试。** 换句话说，"重试"在这个任务里几乎不起作用——它真正依赖的是**周期性的重扫**。

这让我觉得当前的重试参数是一个没想清楚的设计：要么把退避拉到分钟级让它真的起作用，要么干脆去掉重试、只靠周期扫描。**现在的形态是"看起来有重试，实际效果接近没有"。**

我把它列在欠账里，因为改动它需要先想清楚"一次刷新失败之后，我应该多快再试"——而这取决于上游 refresh 接口的故障模式，我还没数据。

---

## 7. 一个我必须说清楚的未完成项

包注释里有一句话：

```go
// Caching lives in Redis in a full deployment (key token:{platform}:{accountID});
// the MVP ships an in-process implementation and a Redis-backed implementation
// so the server can run with or without Redis.
```

**"a Redis-backed implementation" 这句是错的。** 我核实过，`domain/upstream/credential` 下只有内存实现（`tokenCache` 就是 `map + RWMutex`），没有 Redis 版本。

这不是文档过期，而是**我在写注释的时候描述了一个我打算做但还没做的设计**。这类注释比过期的注释更危险——它不是"曾经对过"，而是"从来没对过"。

### 7.1 为什么没有 Redis 版本这件事挺严重

`tokenCache` 的注释里写了：

```go
// tokenCache is an in-process cache of access tokens keyed by account ID. It
// exists so the hot path (GetAccessToken) does not hit the AccountLookup on
// every request. In a multi-instance deployment the Redis-backed provider
// should be used instead; this cache is the single-process fallback.
```

也就是说我**自己知道**多副本下需要共享缓存，但没做。

后果是这样的：如果有 N 个 relay 副本，每个副本独立发现"这个账号的 token 快过期了"，于是**N 个副本同时去刷新同一个账号**。

而按第 3 节讲的，刷新是 rotation 的——**并发刷新一个 rotation 型 refresh token，可能让某些副本拿到失效的 token**。而每个副本的 `refreshMu` 只保护自己进程内的并发。

这和第 4 篇那个"并发槽在单进程内是内存版"是同一类问题：**单进程内的保护看起来完整，但它保护不了多副本。**

我没有做 Redis 版的直接原因是我还没把 relay 跑成多副本。但这不等于问题不存在——**它是一个"扩副本时会立刻踩到"的定时炸弹**，而且症状（账号随机失效）很难归因。

---

## 8. 现在的状态

**已经能用的：**

- 五家平台三种凭证形态，静态密钥走独立实现且 `Refresh` 是 no-op
- 请求时刷新（3 分钟 skew）+ 后台预刷新（10 分钟周期、24 小时 lookahead）双保险
- 每账号一把锁 + 双重检查，防止同账号并发刷新
- 刷新成功但存储失败时：不失败请求、把整套凭证（含轮转后的 refresh token）留在内存
- `ErrInvalidGrant` 类型化，包裹 `ErrRefreshFailed`，两种判断都能命中
- 三类不可重试错误走独立 hook，与"重试耗尽"区分
- 关停中断退避返回哨兵错误，不会把未完成的刷新误报成成功

**还没解决的：**

**第一，凭证缓存只有内存版。** 多副本下同账号会被并发刷新，而 rotation 型 refresh token 在并发下可能互相作废。这是目前最大的一个风险，而且症状难归因。

**第二，存储失败没有主动补偿。** 靠"下次 resolve 时再试"，如果那个账号之后没人用，就永远不重试。

**第三，重试退避时间尺度错配。** 6 秒的总窗口对分钟级的上游抖动没有意义，实际靠 10 分钟周期扫描兜底。要么拉到分钟级，要么显式去掉重试。

**第四，包注释里的 "Redis-backed implementation" 是错的。** 需要删掉或者写清楚是待做。

**第五，`logPersistFailure` 用的是标准库 `log` 而不是项目统一的结构化 logger。** 凭证持久化失败是一个应该能被告警的运维事件，但它现在只是标准输出里的一行文本，没有指标。

---

## 9. 下一篇

下一篇讲订阅用量查询接口：用户怎么知道自己还剩多少额度、为什么这个接口要按 API Key 鉴权而不是登录态、以及在途请求（预扣了但还没结算）应该算不算进"已用"里。

[《额度查询接口：为什么“没订阅”要返回 200 而不是 404》](/2026-09-17-micro-one-api-usage-api/)
