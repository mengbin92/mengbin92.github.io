---
title: "给 DeepSeek Harness 写额度监控插件：十个坑、一次白屏和一个不存在的事件"
date: 2026-10-12T15:30:00+08:00
description: "从一句话需求到九个提交的完整开发调试记录：cordis fiber 激活、TYPERT manifest、ModuleLoader bundle 格式、RemoteResult 信封白屏、并发刷新竞态，以及一个注册了却永不触发的 ready 事件。"
tags: ["DeepSeek", "DSH", "Cordis", "插件开发", "调试"]
categories: ["tools"]
draft: false
---

## 摘要

我在自己的 AI 编程工具 DeepSeek Harness（dsh）里加了个插件，用来监控各家大模型供应商的额度：DeepSeek 官方余额、智谱 Coding Plan 的 5 小时/7 天窗口、自建网关的钱包和订阅套餐。两个包，Host 端定时抓取，Web 端设置页 + 侧栏指示器，代码在 [mengbin92/deepseek-harness-quota-monitor](https://github.com/mengbin92/deepseek-harness-quota-monitor)。

这篇是这个插件的完整开发调试记录。插件代码本身不难，难的是 DSH 的插件体系——bundle 组合、cordis 4 fiber、Typert RPC、Web 端 ModuleLoader——没有任何一处文档把全链路讲清楚。十个坑、一次把页面钉死的白屏、一轮代码评审，和最后那个最好的 bug：**我给一个不存在的框架事件注册了监听器，它安静地什么都没做。**

> dsh 本身是什么、怎么本地部署，见之前的 [《DeepSeek Harness（dsh）本地部署与使用指南》](/2026-09-03-deepseek-harness-dsh/)。

---

## 0. 起点：一句话需求，三个决定

初始需求只有一句话："监控大模型供应商额度使用情况。"动手前先钉死三件事，事后看每一件都省了返工：

1. **只做供应商配额 API，不做本地 token 计量。** 本地计量要包装 `ctx.llm.stream` 拦截每次对话，和"查余额"是两套数据源、两套精度语义。混在一起，首版永远发不出去。
2. **数据模型一开始就分两类**：预付费余额（`balances[]`）和订阅套餐滚动窗口（`limits[]`）。智谱、Kimi、MiniMax 的套餐都有 5 小时/7 天窗口限额，首版只建余额模型的话，后面加窗口就是破坏性改动。
3. **fetcher 可插拔。** 第三方网关的配额接口千奇百怪，内置适配器 + `registerFetcher` 注册口是唯一能不改核心代码接新供应商的形状。

最终内置了四个适配器：

| fetcher kind | 适用 | 协议 |
|---|---|---|
| `deepseek-balance` | DeepSeek 官方 | `GET /user/balance` → `balance_infos[]` |
| `zai-quota` | 智谱 GLM Coding Plan | `GET /api/monitor/usage/quota/limit` → `data.limits[]`（unit 3=5h, 6=7天, 5=月度工具） |
| `neo-gateway` | 自建网关（micro-one-api） | 钱包 `/v1/usage` + 订阅窗口 `/v1/subscription/usage` |
| `generic-http` | 其它任意 JSON 接口 | 用户配 path + 点分路径字段映射 |

---

## 1. 形状：两个包，一条 Remote 边界

| 包 | 运行端 | 职责 |
|---|---|---|
| `dsh-quota-monitor` | Host (Node) | 周期抓取，聚合 `QuotaSnapshot`，暴露 `ctx.quotaMonitor` + Typert Remote 命名空间 `quota` |
| `dsh-client-ui-quota` | Web Client | 设置页"额度"卡片 + 侧栏常驻指示器，60s 轮询快照 |

数据流：供应商 API → Host 定时抓取 → Remote 命名空间 → 浏览器轮询。API key 只在 Host 侧通过 `dsh-credentials` 解析，永不过线——Remote 边界上只传配额数字。

九个提交的时间线：

| 提交 | 内容 |
|---|---|
| `a9c6669` | 首版：双包架构、内置 fetcher、Remote 命名空间、设置页 + 侧栏 |
| `cbeb6e1` | 修 neo 钱包误导性"已用"显示 + refresh 可选参数拒收 |
| `5103fec` | 修客户端 RemoteResult 信封解包（刷新白屏） |
| `48cc419` | 采纳 cc-switch 显示规范 |
| `746db71` | 单供应商显示定制：`order` / `pinned` / `hidden` |
| `0e87b55` | `llmProviders`：跟随在用模型自动聚焦 |
| `625880e` | 侧栏只显示最短（最近重置）的窗口 |
| `5d72d7c` | 全量代码评审加固（10 项） |
| `180cd2c` | 修"装完必须手动刷新"：启动首刷引导 |

仓库是项目中期才公开的，首个提交已经包含早期调试的最终状态，所以下面的排障按问题类别组织，不严格对应提交顺序。

---

## 2. 语言层面先摔的两跤

还没碰到 DSH，先在依赖上摔了两跤：

**schemastery 不是 zod。** 配置 schema 写了 `z.array(z.string()).optional()`，运行时报 `.optional()` 不存在——schemastery 的数组没有这个方法。它的可选性模型是"没有 `.default()` 的字段本身就可选"，把 zod 的心智模型带进去就会踩坑。

**`npx tsc` 拉到假包。** 依赖修剪之后，`npx tsc` 从 npm 拉了一个叫 `tsc` 的占位包，构建行为诡异到一度怀疑人生。修复是把 `typescript@5.6` 固定成 devDependency，脚本直接调 `tsc`。教训：**构建工具链里的每个可执行文件都应该被锁住**。

---

## 3. 接入 DSH 运行时：十个坑

这是整个项目最艰难的一段。每一步都是"跑起来 → 报错 → 读 DSH 源码 → 改"。

### 3.1 安装声明

`dsh plugin add` 警告 "declares no dsh.bundle — installed as a plain dependency"：没有 `dsh.bundle.patch` 声明的包不会被当 bundle 组合进 profile。修复：package.json 加 `"dsh": {"bundle": {"patch": "./cordis.patch.yml"}}` + 一个 insert patch 文件。

### 3.2 fiber 激活失败：inject 的对象形式

`static inject = ['timer', { credentials: { required: false }]`——服务注册了，fiber 永远不激活，**无报错无日志**。读 cordis 源码确认：inject 只接受字符串数组形式。修复：`static inject = ['timer']`，credentials 在调用时用 `this.ctx.get('credentials')` 软解析。

### 3.3 手写 TYPERT manifest

Host 服务要暴露成 Remote 命名空间，`dsh-typert-loader` 探测包的 `./typert` 导出，两次被拒：一次是形状不对（必须是 `TYPERT = { package, face: 'host', schemas, invocations, model }`），一次是 `sourceLocation.line must be a positive integer`——invocation 的行号必须是真实正整数，占位的 0 直接被校验拒绝。

### 3.4 binding namespace

网关报 `gateway/binding-invalid`：`super(ctx, 'quotaMonitor')` 的 wire 命名空间默认取服务键，而客户端描述符声明的是 `quota`。修复：`super(ctx, 'quotaMonitor', { namespace: 'quota' })`。

### 3.5 Web 客户端 bundle 格式

浏览器报 "import failed"：`tsc` 产出的 ESM 在 DSH Web 客户端跑不起来。它的模块体系要求 bundle 是：

```js
window.__ModuleLoader__.load({
  id: "dsh-client-ui-quota",
  factory: (require) => { /* CJS factory */ }
})
```

esbuild 打成 CJS IIFE，用 banner/footer 包上 `load()` 调用；`react`、`react/jsx-runtime`、`@deepseek-ai/cordis` 保持 external（运行时由客户端模块表种子提供），其余依赖打进包里。

### 3.6 空白页面三连

设置页只显示"尚未配置供应商"，前后换过三个根因，每个都足以独立致空：

1. **模块缓存的旧 stub bundle**：一次构建失败留下残缺 bundle 被 ModuleLoader 按 rev 缓存，之后无论如何重建页面都不变。
2. **cordis inject guard**：访问 `remote.quota` 抛 `cannot get property "remote.quota" without inject`——cordis 把 Remote 命名空间挡在 inject 声明后面。但客户端 fiber 自己就是挂载这个命名空间的一方，硬 inject 会死锁。修复：`ctx.get('remote.quota')` 放 try/catch 里探测，拿不到就退回 Gateway 的 HTTP wire 格式（`POST /api/quota/snapshot`，和类型化命名空间同一个端点）。这个兜底保留至今。
3. **嵌套 fiber 方案失败**：试过用 `ctx.plugin()` 起一个 `inject: ['remote.quota']` 的子 fiber 来合法拿到命名空间，结果客户端渲染直接坏掉。放弃，回退扁平 `apply(ctx)`。

### 3.7 刷新即白屏：RemoteResult 信封

页面能打开，点"刷新"整页变白，**刷新页面也救不回来**——slot 入口已经崩了。控制台：`TypeError: Cannot read properties of undefined (reading 'length')`。

根因：类型化命名空间的调用在客户端解析为 **RemoteResult 信封** `{ok:true,value} | {ok:false,error}`，不是裸业务值。store 把信封当快照用，`providers` 是 undefined，组件 `.length` 崩溃；而 slot 渲染器不捕获子组件异常，一次崩溃钉死整个入口。

修复是 store 统一过 `unwrapRemote()`，并补了回归测试。顺带澄清了一个错觉：一直以为"刷新要等两分钟"，其实是崩溃残局造成的体感——服务端单个供应商刷新实际不到 1 秒。

### 3.8 可选参数的 RPC 校验

`quota/refresh` 不带参数调用被拒 "missing providerId"。Typert 参数描述符默认拒收 undefined，可选参数必须显式 `acceptsUndefined: true`。

### 3.9 neo 钱包的误导性"已用"

自建网关钱包接口的 `usage.total.cost` 是**累计历史消耗**，首版把它映射进了"已用"位，页面显示"已用 4,797.95"——极具误导性。修复：删掉映射，钱包只显示余额，窗口用量由订阅接口的 `limits[]` 承载。教训：**上游字段名和业务语义对不上时，宁可少显示也不能错显示**。

### 3.10 识别不了的端点：如实降级

局域网里另一个网关实际是 new-api，余额接口要 web access token（≠ relay API key），插件拿不到。这类端点配置 `fetcher: none` + `hidden: true`，UI 显示"无配额接口"而不是报错刷屏。

---

## 4. 展示层：照着 cc-switch 抄规范

功能跑通之后是展示层打磨。我直接参考了 cc-switch 的用量显示约定：

- 永远显示**剩余**百分比，不是已用百分比；
- 只给数字着色（绿正常 / 黄 <20% 剩余 / 红耗尽），标签和文案保持灰色；
- 刷新按钮至少转 600ms——太快了显得"什么都没发生"。

之后四次小演进：`order`/`pinned`/`hidden` 单供应商定制；`llmProviders` 让行声明自己对应哪些 LLM 供应商键，客户端每 5 秒读主视图会话在用的模型供应商，命中的行挂"使用中"徽标、侧栏优先聚焦；侧栏一行放不下三个窗口，改为只显示 reset 最近的一个（`日额度 剩余 98%`），完整窗口留在设置页和 tooltip。

---

## 5. 代码评审：十项修复

功能全部落地后做了一轮全量评审，10 项：

| # | 问题 | 修复 |
|---|---|---|
| 1 | **并发刷新竞态**：定时器与手动刷新并发时，后完成的旧请求覆盖新结果 | 按供应商 id 的 in-flight Map 去重 |
| 2 | **重复 provider id**：双卡 + React duplicate key | 构造时去重并告警 |
| 3 | **空字符串余额解析成 0**：`Number('') === 0`，缺字段显示 0 并误告警 | 统一 `toNumber`，空白串返回 undefined |
| 4 | **字符串数字流入限额**：客户端 NaN% 进度条 | 逐字段强转 |
| 5 | **neo 部分失败不可见**：订阅接口挂了、钱包好的，行显示"正常"但窗口消失 | 失败分支记日志 |
| 6 | **测试硬编码绝对路径**：公开仓库换机即挂 | `import.meta.url` 相对路径 |
| 7 | **Host 核心逻辑零测试** | 补服务级测试：去重/排序/warn 阈值/错误与缓存行/并发去重 |
| 8 | **死代码**：无人调用的渲染函数、永不执行的 fetcher | 全部删除 |
| 9 | **manifest 行号漂移** | 与源码同步 |
| 10 | **快照只拷贝一半字段** | 一致隔离 |

第 1 项值得展开：定时刷新和手动刷新同时打同一个供应商时，较慢的旧请求后完成会覆盖新结果——旧请求失败的话，会把刚刷好的行改写成 error+缓存。按 id 做 in-flight 去重后，并发触发共享同一次抓取。

---

## 6. 最好的一个 bug：注册给不存在的事件

最后一个 bug 是全程我最喜欢的一个。

**症状**：插件装好后，不手动点一次刷新，额度行永远是灰色的"查询中…"。

**定位**：构造函数里用 `ctx.on('ready', () => this.refresh())` 做首刷。这个写法看起来毫无问题——"ready 之后跑一次"是所有框架的标准姿势。但它从未执行。两个证据：cordis 4 的源码里搜不到 `ready` 这个事件名；整个 DSH 官方代码库也没有任何 `on('ready'` 的用法。**我给一个不存在的框架事件注册了监听器，它安静地什么都没做**，行只能等 30 分钟定时器或手动刷新。

这个 bug 活了三个提交才被发现，因为它太"对"了——代码审查会盯着逻辑看，不会怀疑一个事件的存在性。教训：**对框架 API 的存在性要保持和对自己代码同等的怀疑。**

**第一次修复的教训**：直接改成"延迟 250ms 首刷"，E2E 一跑——行确实自动离开 pending 了，但刷成一排 `credential NEO_API_KEY is not configured`。原因：**credentials 服务在本 fiber 之后异步激活**，250ms 时还没就绪。单元测试全部通过（测试自己驱动 `refresh()`），只有真实启动暴露引导时序。这验证了 E2E 的价值：**单测里自己驱动的方法会把引导时序 bug 完全藏住。**

**最终方案**：

```ts
const boot = (attempt: number): void => {
  if (this.ctx.get('credentials') !== undefined || attempt >= 40) {
    void this.refresh()
    return
  }
  timerish.setTimeout(() => boot(attempt + 1), 250)
}
timerish.setTimeout(() => boot(0), 250)
```

用 timer 插件的 `ctx.setTimeout` 链轮询 credentials（250ms × 最多 10s），就绪即刷；超时也照刷——没有 credentials 服务的环境应该**如实报错**，而不是永远 pending。每一跳都走 timer 插件，fiber dispose 自动取消。配套客户端改动：快照里还有 pending 行时 5 秒快速重轮询，不干等 60 秒整周期。

验证：重启服务、打开页面、**零点击**——Neo 网关（$299.8 + 日/周/月三窗口）和 DeepSeek（¥18.01）在首屏直接就是"正常"状态。

---

## 7. 工具箱

这套组合贯穿全程，值得复用：

| 工具 | 用法 |
|---|---|
| `dsh --profile web --dump-config` | 验证 bundle/patch 组合是否真的进了 profile |
| 服务器日志 | 清场后 `dsh web --no-open`，token 从日志 grep |
| Gateway wire 直调 | `POST /api/quota/snapshot` 带约定 body——绕开浏览器单独验证 Host 侧 |
| Node 级客户端模拟 | 模拟 `window.__ModuleLoader__` + react stub，在 Node 里执行真实 bundle 的 `apply()` |
| 真实挂载测试 | 加载本机 DSH 的真实 typert-registry/api-gateway bundle 跑 `$mount` |
| Playwright E2E | 系统 Chrome headless，打开带 token 的页面 → 设置 → 额度，**捕获全部 console 和 pageerror** |

最后一条是白屏类崩溃唯一的发现手段——slot 入口的组件崩溃会钉死整个页面且刷新不恢复，单测和模拟测试都覆盖不到这类"渲染期"故障。

---

## 8. 清单：给下一个写 DSH 插件的我

1. **cordis 4 没有 `ready` 事件**。启动引导用 timer 插件的 `ctx.setTimeout`；等可选服务就绪用轮询 `ctx.get(name)`，设截止时间，超时按缺席处理。
2. **`static inject` 只收字符串数组**。对象形式会静默阻止 fiber 激活。
3. **客户端拿到的是 RemoteResult 信封**，不是裸值。务必解包，失败信封转错误状态而不是让组件崩掉。
4. **可选 RPC 参数要 `acceptsUndefined: true`**。
5. **客户端 bundle 必须是 ModuleLoader IIFE**；`react`/`react/jsx-runtime`/`@deepseek-ai/cordis` 保持 external。
6. **不要 inject 自己挂载的命名空间**（死锁）；`ctx.get()` 探测 + HTTP wire 兜底。
7. **schemastery ≠ zod**：数组没有 `.optional()`，无 `.default()` 即可选。
8. **typescript 固定为 devDependency**，别依赖 `npx` 解析。
9. **上游字段语义要人工核对**：字段名像"用量"不代表是窗口用量。
10. **必须上真实 E2E**：渲染期崩溃只有这里能抓到。
11. **首刷/引导逻辑必须独立测**：单测自己驱动 `refresh()` 会把引导时序 bug 完全藏住。

---

## 9. 复盘

**做对的**：范围先钉死，首版之后没有破坏性返工；HTTP wire 兜底从排障事故里留下来，成了跨版本韧性路径；E2E harness 一次搭建、反复回本（白屏、credentials 竞态都是它抓的）；每个 bug 修复都补了对应回归测试。

**走弯的**：嵌套 fiber 方案做了再放弃，浪费一轮——应该先读 cordis 的 fiber/事件模型再动手；`on('ready')` 写的时候没验证事件真的存在；早期调试没有即时提交，发布时历史被压扁，这篇记录有一部分是靠记忆补的。

相关文章：[《DeepSeek Harness（dsh）本地部署与使用指南》](/2026-09-03-deepseek-harness-dsh/)。
