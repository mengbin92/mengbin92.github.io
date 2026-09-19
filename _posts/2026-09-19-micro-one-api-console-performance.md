---
title: "每次切页面等一秒：一次把延迟拆成四份的排查"
date: 2026-09-19T12:00:00+08:00
description: "有一段时间我觉得管理后台“卡”。具体表现是：点侧边栏切到 /dashboard、/usage、/admin/logs，要等大约一秒才出内容。"
tags: ["Micro-One-API", "前端", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 症状：服务端很快，但页面就是慢

有一段时间我觉得管理后台"卡"。具体表现是：点侧边栏切到 `/dashboard`、`/usage`、`/admin/logs`，要等大约一秒才出内容。

我第一反应是后端慢。于是量了一遍：

| 测的东西 | 实测 |
|---|---|
| 控制台 TTFB | 约 0.8ms |
| `/api/log` | 13–17ms |
| Dashboard 聚合查询 | 76ms + 69ms |

**服务端一点都不慢。** 一个 0.8 毫秒的 TTFB 说明请求一到就返回了。

那就说明这一秒全花在浏览器里。我打开 Network 面板重新点了一遍，看到了四件独立的事：

1. **串行瀑布**：所有页面都是 `React.lazy`，所以点导航之后是先下载页面 JS，**组件挂载之后才开始发 API 请求**。JS 没到之前，API 请求根本不会发出。
2. **391KB 的 charts 包**：我的手工分包策略把 recharts/d3 归进了一个叫 `charts` 的公共包，于是登录页、Usage、Logs 这些**完全不用图表**的页面也在加载它。
3. **哈希资源没有长期缓存**：`/assets/*` 是带内容哈希的，但服务端只给 HTML 设了禁缓存策略，哈希资源每次都要回源校验，一次 304 往返约 177ms。而且文本资源没开压缩，首屏 11 个脚本加 10 个中文字体分片一共约 1.84MB，全量传输。
4. **重复请求**：导航组件和 Dashboard 页各自请求 `/user/self`、`/user/dashboard`；React Query 没设 `staleTime`，页面重新挂载就重新请求。

**四件事各占一小部分，加在一起就是那一秒。** 这类问题最难的地方不是修，是发现"它不是一件事"。

这篇按这四份拆开讲。

---

## 1. 那一秒的第一份：先下载 JS 才能发请求

这是四份里最隐蔽的，因为它不是"某处写得慢"，而是**架构顺序决定的**。

```tsx
const DashboardPage = React.lazy(() => import('@/pages/DashboardPage'));
```

懒加载的页面，进入路由的顺序是：

```
用户点击
  → 下载 DashboardPage 的 JS chunk
  → 下载完成，React 开始挂载
  → 组件里 useEffect / useQuery 触发
  → 发出 API 请求
  → 渲染数据
```

**JS 下载和 API 请求是串行的，但它们本来可以并行** —— 因为在用户点击的那一刻，"他要去 /dashboard"和"Dashboard 需要哪些数据"这两件事我都已经知道了。

修法是在悬停/聚焦时预取那个路由的模块：

```ts
export function preloadRoute(pathname: string) {
  const loader = routeLoaders[pathname as keyof typeof routeLoaders];
  if (loader) void loader().catch(() => undefined);
}
```

```tsx
onMouseEnter={() => preloadRoute(link.to)}
onFocus={() => preloadRoute(link.to)}
```

`onFocus` 和 `onMouseEnter` 都要加：**键盘用户不会触发 mouseenter。** 只做 hover 预取的话，键盘导航的人一点收益都没有。

而 `.catch(() => undefined)` 是一个刻意的选择：**预取失败不该产生任何可见后果。** 用户并没有"请求"这个页面，他只是把鼠标移过去了。如果预取失败弹出错误提示，那是把内部优化暴露成了用户问题。真正的失败会在点击之后正常暴露。

这个改动把瀑布从"下载 → 请求"变成了"下载和请求并行"，因为鼠标移到导航上到真的点下去，通常有几百毫秒。

---

## 2. 第二份：391KB 的图表包被所有页面预加载

我的分包配置里有一条"公共依赖抽成公共包"的手工规则，它把 recharts 和 d3 归进了一个 `charts` 包。

当时我的想法很合理：**多个页面都用图表，抽出来避免重复打包。**

但它忽略了一件事：**"多个页面共用"不等于"所有页面共用"。**

结果是登录页、Usage、Logs 这些不用图表的页面，也在加载 391KB 的图表库——因为它是"公共包"，被打进了共享 chunk。

修法是**移除那个手工的 `charts` 和兜底的 `vendor` 分包规则**，让图表代码只随真正用它的页面动态加载。

这个改动的思路我在文档里写成了验收标准：

> 生产构建实测非图表路由包不引用 recharts，登录首屏图表资源为 0。

**"登录首屏图表资源为 0"是一个可测的命题。** 不是"应该好一些"，而是"必须是 0"。这和第 20 篇讲的"验收要写成可自动判断的命题"是同一条。

而且这个改动的方向可能违反直觉：**我删掉了分包配置，让包变大了（原本共享的依赖现在会重复出现在多个 chunk 里），但首屏变小了。**

因为：
- 首屏只需要登录页的 JS；
- 图表页的 JS 大一点无所谓（用户到了那页才付这个代价），而且它只加载一次。

**优化的目标是"特定路径上的字节数"，不是"总字节数"。** 抽公共包降的是总量，但它把不用这些代码的路径也拖累了。

---

## 3. 第三份：缓存头和压缩

这一份最"标准"，但有几个边界我没想全。

### 3.1 哈希资源该immutable

根因是我直接用了 `http.FileServer`，它只给 HTML 设了禁缓存。而带内容哈希的 `/assets/*`：

**文件名里已经有内容哈希了，所以同一个 URL 的内容永远不会变。** 这种资源应该给一年 immutable：

```go
const immutableAssetCacheControl = "public, max-age=31536000, immutable"
```

```go
serveWebAsset(&immutableAssetResponseWriter{ResponseWriter: w}, r, a.root)
```

`immutable` 这个词是关键：它告诉浏览器"**连刷新都不要回源校验**"。没有这个词，用户按 F5 时浏览器还是会发一次条件请求，那个 177ms 的往返就还在。

而 HTML 保持原样禁缓存（`no-cache, no-store, must-revalidate`）——因为 HTML 引用了哪些哈希资源是会变的，它必须每次都拿到新的。

### 3.2 gzip 协商比我预想的麻烦

压缩本身简单，但 `Accept-Encoding` 的解析有几个坑：

```go
func acceptsGzip(value string) bool {
    wildcardAccepted := false
    for encoding := range strings.SplitSeq(value, ",") {
        parts := strings.Split(strings.TrimSpace(encoding), ";")
        if len(parts) == 0 {
            continue
        }
        quality := 1.0
        for _, parameter := range parts[1:] {
            name, raw, found := strings.Cut(strings.TrimSpace(parameter), "=")
            if !found || !strings.EqualFold(name, "q") {
                continue
            }
            parsed, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
            if err != nil {
                quality = 0
            } else {
                quality = parsed
            }
        }
        name := strings.TrimSpace(parts[0])
        if strings.EqualFold(name, "gzip") {
            return quality > 0
        }
        if name == "*" {
            wildcardAccepted = quality > 0
        }
    }
    return wildcardAccepted
}
```

**必须解析 `q` 参数。** `Accept-Encoding: gzip;q=0` 的意思是"我不要 gzip"，这是个显式的拒绝。如果不解析 q 值，只检查 `strings.Contains(value, "gzip")`，就会把这种请求也压了——**而拒绝是有理由的**（比如客户端已经自己解压过、或者中间有损坏的解压器）。

而几个文件类型的判断：

```go
func isCompressibleWebAsset(path string) bool {
    switch strings.ToLower(filepath.Ext(path)) {
    case ".css", ".html", ".js", ".json", ".map", ".svg", ".txt", ".xml":
        return true
    default:
        return false
    }
}
```

**`.woff2` 不在列表里，这是对的** —— WOFF2 本身已经是压缩格式，再 gzip 一遍只会浪费 CPU 而且可能变大。

### 3.3 Range 请求不能压缩

```go
if !acceptsGzip(r.Header.Get("Accept-Encoding")) || r.Header.Get("Range") != "" {
    http.FileServer(http.FS(root)).ServeHTTP(w, r)
    return
}
```

**一旦响应经过 gzip，字节偏移就和原始文件不一致了**，`Range` 语义会被破坏。所以带 `Range` 的请求直接不压缩。

还有 `Vary` 头：

```go
w.Header().Add("Vary", "Accept-Encoding")
```

**没有它，中间缓存可能把一个 gzip 响应发给不支持 gzip 的客户端。** 这是一个经典的缓存投毒场景。

### 3.4 文档里记的边界

发布说明里列了实施时要处理的边界：

> 边界处理：尊重 `gzip;q=0` 与 `Range` 请求；WOFF2 字体本身已压缩、不再 gzip；不存在的 `/assets/*` 返回 404 且不加长缓存；空文件输出合法的空 gzip 数据流。

**"不存在的 `/assets/*` 返回 404 且不加长缓存"** 这条值得单独说：如果给一个 404 响应也加了 `max-age=31536000`，那这个资源一旦被请求过一次，浏览器会**记住这个 404 一整年**——即使后来文件真的存在了。

**"空文件输出合法的空 gzip 数据流"** 这条是我没想到、测试逼出来的：一个长度为 0 的文件经过 gzip writer 后如果不 `Close()`，输出的字节可能不完整，客户端解压会报错。

**把这些边界写进发布说明，比写在代码注释里更有用** ——因为发布说明是部署的人会读的，而他们正是会遇到这些边界的人（比如发现某个字体没压缩、或者某个 404 被缓存了）。

---

## 4. 第四份：重复请求和串行的 account 查询

### 4.1 `staleTime` 没设，重新挂载就是重新请求

React Query 的默认 `staleTime` 是 0，意思是"数据立刻过期"。所以页面每次挂载都会重新请求——**即使数据刚刚在同一个会话里拿过。**

修法是抽出共享查询并给它们设新鲜期：

```ts
// 用户信息
staleTime: 5 * 60 * 1000,

// 账户概览
staleTime: 30 * 1000,
```

两个值差别很大，理由不同：

- **用户信息（`/user/self`）5 分钟**：用户名、角色、分组这些几乎不变。5 分钟内的重复请求没有任何意义。
- **账户概览（`/user/dashboard`）30 秒**：余额和用量会变（用户自己可能刚发过请求），所以新鲜期短，但短到 30 秒就足以消掉"切页面就重查"。

**"缓存多久"取决于"数据多久会变"和"用户多久会看到"，而不是统一一个值。**

而抽成共享查询的意义在于：导航栏、Dashboard、个人资料、充值、兑换这几个地方都要用户信息，之前它们各自请求。

### 4.2 顺手修掉的一个安全问题

这一节里有一个我认为比性能更重要的修复，藏在发布说明里：

> 同时修复 `AdminRoute` 刷新时信任 `localStorage.userRole` 导致旧角色闪现管理入口的问题：权限判断改为以共享的 `/user/self` 查询为唯一来源。

原来的逻辑是：页面刷新时，`AdminRoute` 从 `localStorage` 读 `userRole` 来判断要不要显示管理入口。

问题有两个：

**第一，角色是过期数据。** 一个用户被降权之后，`localStorage` 里还是旧角色，他刷新页面会看到管理入口一闪。

**第二，`localStorage` 是可以被改的。** 用户手动把 `userRole` 改成管理员，界面上就会出现管理入口。

当然，**真正的防线在服务端**（管理接口会再校验一次），所以这不是一个越权漏洞。但它是一个"错误的安全信号"：界面告诉用户"你能进这个页面"，然后接口拒绝——**这是最糟糕的失败方式，因为它让人以为系统坏了。**

改成以 `/user/self` 为唯一来源之后，角色判断和权限判断用的是同一份数据。

### 4.3 登出要清整个缓存

同一节还有一条：

> 登录成功与退出时清空整个 React Query 缓存，杜绝跨账号短暂显示上一用户数据。

因为查询的 key 里不一定带用户身份。如果不清，用户 A 登出、用户 B 登入，B 可能在几十毫秒内看到 A 的余额。

**这是一个只有"切换账号"才会暴露的问题**，而开发和测试通常只用一个账号。

---

## 5. 那条索引：优化器可能不用它

后端这一侧只改了一处，而且它的效果是"不确定"的。

Dashboard 按 `user_id + type` 过滤，然后按 `created_at` 分组聚合。原来的索引是 `(user_id, created_at, model_name)`：

```sql
-- User dashboard filters consume ledgers by user and type, then groups by
-- created_at. The existing (user_id, created_at, model_name) index cannot
-- narrow the consume-only range before scanning it.
ALTER TABLE `billing_ledgers`
  ADD KEY `idx_billing_ledgers_user_type_created` (`user_id`, `type`, `created_at`);
```

**列顺序是按"先过滤、后排序/分组"排的**：`user_id` 和 `type` 都是等值过滤，`created_at` 用于范围。原来的索引缺少 `type`，所以它只能收窄到"这个用户的所有账本"，然后再扫出 consume 类型的那部分。

而我在发布说明里诚实地写了当前的实际效果：

> 当前约 4 万行的表上优化器可能仍选择代价相近的既有索引，新索引随数据增长自然生效。

**在 4 万行这个量级，两个索引的代价差不多，优化器选哪个都可能。** 这条索引是为数据增长准备的，不是为现在的性能数字准备的。

我认为把这句话写进发布说明很重要：**否则以后有人会来看"加了索引有没有变快"，发现没变快，然后以为索引写错了。**

索引迁移也照第 14 篇的治理规则做了三方言：

```
migrations/089_add_billing_ledger_dashboard_index.sql
migrations/postgres/089_add_billing_ledger_dashboard_index.sql
migrations/sqlite/089_add_billing_ledger_dashboard_index.sql
```

---

## 6. 我从这次排查里学到的

**第一，先量再改，而且要分开量。**

"服务端 0.8ms 但页面 1 秒"这个对比是整次排查的转折点。如果我一开始就去优化 Dashboard 聚合查询（76+69ms 看起来最像"慢"的那部分），我优化的是一个只占 15% 的部分。

**第二，"公共包"是一个危险的默认选择。**

分包的目标是"每个路径上的字节数"，不是"总字节数"。把一个只被部分页面使用的库抽成公共包，等于让所有页面替它付费。

**第三，可测的验收标准能防止"改了个寂寞"。**

"登录首屏图表资源为 0"和"两次切换应为毫秒级"都是能被验证的。而"优化了首屏加载"不是。

**第四，性能修复往往会顺手碰到正确性问题。**

这一批改动里最严重的不是性能问题，是 `AdminRoute` 信任 `localStorage.userRole`。**它是被"我要减少重复请求"这个动机带出来的** —— 因为我在梳理"谁在请求用户信息"时才注意到有个地方在读 `localStorage`。

---

## 7. 现在的状态和欠账

**已经能用的：**

- 哈希资源一年 `immutable`，HTML 保持 `no-cache`
- 文本资源 gzip，正确解析 `q=0`、跳过 `woff2`、绕过 `Range`、带 `Vary`
- 图表代码只随图表页加载，非图表路由不引用 recharts
- 导航悬停/聚焦预取路由模块，失败静默
- 共享账户查询，用户信息 5 分钟、账户概览 30 秒新鲜期
- 登出清空 React Query 缓存
- `AdminRoute` 权限以 `/user/self` 为唯一来源
- Dashboard 聚合联合索引（三方言 + ownership）

**还没解决的：**

**第一，预取只覆盖侧边栏和导航链接。** 页面内部的跳转（比如 Dashboard 上的快捷操作卡）没有预取。那些也是懒加载页面，点进去还是要等。

**第二，`staleTime` 是拍出来的。** 5 分钟和 30 秒都没有数据支撑——我没有统计过"用户信息多久变一次"或者"用户能接受多旧的数据"。这两个值有可能让用户看到过期的余额。

**第三，索引的效果没有验证。** 发布说明里写了"优化器可能仍选择既有索引"，但我没有在更大的数据集上验证过它到底会不会被用。**这是一条"写下了不确定性但没有后续验证"的改动。**

**第四，没有性能回归门禁。** 这次的问题是用户（我自己）感觉出来的，不是测出来的。前端没有 Lighthouse CI 或者首屏字节数的预算检查，所以同一个问题可以再发生一次而不被发现。

**第五，字体分片还是首屏传输的一大部分。** 10 个中文字体分片约 1.84MB 里占比不小。文档里第 20 篇提到"不预加载全部 CJK 分片，只在真实首屏数据证明有收益时才预加载"，但"按需加载"本身也意味着用户滚动到新字符时要下载新的分片。这块我没有继续优化。

---

## 8. 下一篇

下一篇讲测试：298 个测试文件是怎么组织的、协议兼容性矩阵和 fixture 怎么维护、那个确定性 mock upstream 是怎么让性能基线可复现的，以及一个我特意验证"检查器真的会失败"的测试。

[《313 个测试文件，以及一次「测试自己坏了」的排查》](/2026-09-19-micro-one-api-testing-strategy/)
