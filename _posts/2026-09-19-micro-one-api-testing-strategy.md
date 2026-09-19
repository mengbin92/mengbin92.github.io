---
title: "313 个测试文件，以及一次「测试自己坏了」的排查"
date: 2026-09-19T12:00:00+08:00
description: "我有一条每夜跑的 E2E：起一套完整的 compose（MySQL、Redis、所有服务），然后用 Playwright 跑管理后台的关键路径。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 连续五次失败，但这不是 flaky

我有一条每夜跑的 E2E：起一套完整的 compose（MySQL、Redis、所有服务），然后用 Playwright 跑管理后台的关键路径。

有一阵子它连续失败。按常规做法，flaky 测试的处理方式是加 retry、或者放宽断言。我先做了另一件事：**去看失败之间有没有共同点。**

结果发现两类完全不同的失败混在一起：

**第一类：它根本没在测我的代码。**

那天晚上的 scheduled run 跑的是 `main` 上的 `6b10de1`，而那是 `v0.19.1` 的发布合并提交。我的 E2E 修复和相关修复都在 `develop` 上，还没合进 `main`。

**"测试失败"和"测试跑的是旧代码"，在报告里长得一模一样。**

**第二类：断言写错了。**

Playwright 那条失败是 34/35 通过，唯一失败的是"用户导出"这个用例。错误是：**首次请求仍然带着旧的 URL。**

排查下来是这样一条时间线：

```
点击导出
  → React Router 更新 URL（同步的）
  → 前端发起下载请求
  → React 完成新页面的 render/commit（异步的）
  → 断言检查请求是否带新参数
```

我的断言在等 URL 变化，然后就去检查请求了。但**URL 变了不代表组件的重新渲染已经提交。** 组件的 effect 可能在 URL 变化之后、render 提交之前运行，用的还是旧的状态。

这个报错很典型：**问题不是产品有 bug，也不是测试环境不稳，而是测试在断言一个中间状态。**

---

## 1. 我没有做的事：加 retry

面对 flaky，最省事的处理是 `retries: 2`。我没加，理由是：

**如果一次失败可以通过重试变成成功，那说明这个测试没有稳定地验证它声称要验证的东西。** 一个 50% 概率失败的测试，加了 retry 之后会变成 25% 的失败率，然后你可能再加到 3 次——最后你得到一个"几乎总是绿"的测试，而它什么都没保证。

所以我的选择是：**失败必须完成归因与修复后才重新计数。**

这句话我写在了文档头部的准入标准里：

> 准入标准：compose E2E + Playwright admin smoke 连续 5 次成功，或稳定 1–2 周；失败必须完成归因与修复后才重新计数。

### 1.1 "计数归零"这条规则

配套的还有一条更狠的：**在拿到连续 N 次成功之前，任何一次失败都把计数归零。**

文档里留着这个过程：

| 时间 | 结果 | 计数 |
|---|---|---|
| 2026-08-15 01:13 | failure（Playwright 竞态） | 0 / 5 |
| 2026-08-15 01:42 | failure（同一竞态） | 0 / 5 |
| 2026-08-15 03:04 | success（重新开始计数） | 1 / 5 |
| 2026-08-16 | success | 2 / 5 |
| 2026-08-17 | success | 4 / 5 |
| 2026-08-17 | success | **5 / 5** |

**"修复之后重新从 0 开始数"这个规则的价值在于：它不允许我用"大部分时候是好的"来结案。**

如果按"最近 10 次里 5 次成功"这种口径，我可以在没修好的情况下宣布达标。而"从最终修复之后连续 5 次"这个口径，逼着我必须真的把它修稳定。

### 1.2 修复的证据链

文档里每个 run 都记了 commit SHA。这让"修复之后"成为一个可验证的边界：

```
最终修复 9752789
  → 本地 Playwright 通过
  → CI 通过
  → main nightly 31861619643 双 suite 通过
  → 后续 4 次连续成功
```

**每一次成功都对应一个具体的 commit，而不是"修了之后就好了"。**

---

## 2. 那个竞态具体是怎么修的

值得单独讲，因为它是一个很典型的"异步 UI 测试"错误。

第一版的等待条件是 URL：

```ts
await page.waitForURL(/from=.../);
// 然后断言请求参数
```

**为什么不够？** React Router 的 URL 更新和 React 的组件重新渲染是两个不同步的机制。URL 是浏览器的状态，render 是 React 的状态。URL 已经变了，但新页面的 render 还没 commit。

所以首次请求可能仍然用旧状态发出——**这不是被测代码的 bug，这是"URL 变化"和"UI 已更新"之间本来存在的窗口。**

第二版改成等"已提交的 URL 状态"：

> 已改为等待 committed URL status 后点击

而中间还有一次不充分的修复：

> 第一轮 poll 修复不充分

**"第一轮修复不充分"这条记录我认为比最终修复更有价值。** 它说明我不是一次想对的，而且我把"这次没修对"也写在了文档里。

---

## 3. 顺手发现的一个启动竞态

这类排查经常会带出别的东西。这次带出的是 MySQL 的 healthcheck：

> **附带发现**：MySQL healthcheck 使用 `localhost` 时可能命中 entrypoint 的临时 Unix socket，在 TCP 3306 尚未可用时提前 healthy。本次已改为强制 `127.0.0.1` TCP readiness，降低 migrate one-shot 的启动竞态。

问题链条是这样的：

1. MySQL 容器启动时会先起一个临时的 Unix socket（初始化阶段用）；
2. `mysqladmin ping -h localhost` 可能连上那个 socket 并返回成功；
3. 于是容器被标记为 healthy；
4. 但**此时 TCP 3306 还没起来**；
5. 依赖它的 migrate 任务立刻启动，连接失败。

**"healthy" 这个信号在描述错误的就绪条件。** 改成 `-h 127.0.0.1` 强制走 TCP，才真正验证了"可以接受连接"。

这个问题平时不一定暴露——因为容器的启动顺序经常"刚好"够快。它只在 CI 这种资源紧张、时序更紧的环境里冒出来。

**而它的表现是"migrate 任务偶发失败"，看起来像 migrate 的问题，实际上是 healthcheck 的定义问题。**

---

## 4. 静态测试：那个会失败的覆盖检查

讲完 E2E，讲另一头的单元测试。

项目里有 313 个 Go 测试文件（不含前端）、50 个前端测试文件。数量本身不是重点，我想讲一个有设计的测试。

协议转换是我改动最多的一块，涉及 Responses / Anthropic / Chat 三个协议和各种组合。我用一张矩阵来管它：

```go
// v0.19 P1.1 — Protocol compatibility contract matrix.
//
// The matrix below is the single, explicit contract table for protocol
// conversion paths. Every cell is registered with a concrete check; a
// TestCompatibilityMatrix_Coverage asserts that each expected cell exists, so
// adding a new provider/tool/adaptor path WITHOUT adding its matrix cells
// fails the gate instead of silently expanding untested surface.
//
// Matrix coordinates:
//
//	                    streaming | tools/history        | errors
//	Responses→Anthropic OAuth      both     web_search skip, fn keep | upstream abort
//	Responses→Anthropic fallback   both     web_search skip, fn keep | fallback error map
//	Anthropic→Responses relay      both     server-tool block drop   | block interrupt
//	Chat↔Responses      adaptor    both     tool call/result round-trip | scanner/terminal
//	WebSocket Responses sticky     stream   history/rebind           | graceful drain
```

关键在注释里那半句：

> **a TestCompatibilityMatrix_Coverage asserts that each expected cell exists, so adding a new provider/tool/adaptor path WITHOUT adding its matrix cells fails the gate instead of silently expanding untested surface.**

**"silently expanding untested surface"** 是我最想防的东西。

普通的测试套件有个特性：**你新增一条代码路径而完全不写测试，测试套件不会告诉你任何事。** 覆盖率工具会显示百分比降了，但那是个软信号——从我加功能到发现覆盖率降了，中间可能隔着几周。

所以这里做的是**先声明矩阵的形状，再检查每个格子都有实现**：

```go
func TestCompatibilityMatrix_Coverage(t *testing.T) {
    // 对期望的每个坐标，断言它已被注册
}
```

于是"加了一条路径但没加测试"从一个软信号变成了一个**硬失败**。

我认为这个模式的通用形式是：

> **不要测"我实现的都对"，而要测"我声称支持的东西都被测到了"。**

前者是单元测试（对已知输入断言已知输出），后者是元测试（对测试集合本身的完整性断言）。两者需要的东西不一样，而后者很少被写。

### 4.1 fixture 集中定义

矩阵的输入形状抽到了单独的文件：

```go
// Shared fixtures for the v0.19 protocol compatibility matrix
// (compatibility_matrix_test.go). Keeping the canonical input shapes here —
// instead of inline in every matrix cell — means the "what a web_search /
// server_tool_use / tool round-trip looks like" contract is defined once and
// reused by every path that must agree on it (OAuth adaptor, fallback, relay,
// chat round-trip).
```

```go
func matrixWebSearchResponsesRequest(stream bool) *ResponsesRequest {
    items := []ResponsesInputItem{
        {Role: "user", Content: raw(`"List the weather in Tokyo"`)},
        {
            Type:    "web_search_call",
            CallID:  "ws_123",
            Name:    "web_search",
            // ...
```

**一个 fixture 描述了一个"跨路径的契约"**：这个输入在所有 4 条 Responses→Anthropic 路径上，都必须跳过 `web_search_call`、丢掉所有 server tool、保留 function tool。

如果 fixture 内联在每个格子里，改一处就要改四处，而且很容易漏——**而漏掉的那处不会失败，它只是不再验证同一件事了。**

---

## 5. 确定性 mock upstream：让性能数字可复现

性能基线里我踩过一个坑：**测出来的数字波动很大，因为我同时在测上游。**

第一次跑 baseline，P95 在几十毫秒到几秒之间跳。排查发现是上游响应时间本身在变——不同的模型、不同的负载、上游自己的抖动。

所以我写了一个确定性的 mock upstream：

```go
// Command mock-upstream is a deterministic, dependency-free OpenAI-compatible
// upstream server for the relay-gateway k6 baseline benchmark.
//
// It serves the three request shapes the relay-gateway forwards to an
// upstream provider:
//
//	POST /v1/chat/completions        — non-streaming chat completion
//	GET  /v1/models                  — models list
//	GET  /healthz                    — health probe (used by the benchmark harness)
//
// Every response is deterministic (fixed IDs, fixed token counts, no wall-clock
// RNG in the payload) so k6 measures relay-gateway overhead, not upstream
// variance. A small fixed processing delay is applied to keep latency in a
// realistic band; configure via -delay-ms (default 2ms).
```

三个设计点：

**固定 ID、固定 token 数、payload 里没有时间相关的随机数。** 这样两次跑的结果可以直接比较。

**`-delay-ms` 默认 2ms。** 完全零延迟会让延迟分布失真（真实上游总有一点处理时间），2ms 让数字落在一个"看起来像那么回事"的区间。

**它同时提供 `/healthz`。** 这样压测脚本能确认 mock 自己起来了，而不是在测一个连不上的服务。

而 mock 的地址通过渠道配置指过去：

> The relay-gateway's channel/provider config must point its upstream base URL at `http://127.0.0.1:18099`.

**于是"测的是网关自己的开销"这件事在架构上成立，而不是靠我在报告里说明。**

---

## 6. 测试分层的实际形状

回到整体。三层大致是这样分的：

| 层 | 范围 | 依赖 | 数量级 |
|---|---|---|---|
| 单元 | 单个包/函数 | 无（fake 掉接口） | 绝大多数 |
| 集成 | 数据层、跨包流程 | 数据库或 fake server | 数十 |
| E2E | 全栈 | compose + 浏览器 | 少数，每夜跑 |

而"fake 掉接口"这件事能成立，靠的是第 1 篇讲的那个接缝：**biz 声明 repo 接口，data 实现它。**

所以 biz 层的测试可以给一个纯内存的 fake repo 跑全部用例。文档里把这条写成了约定：

> Test layers in isolation: service tests fake the usecase, biz tests fake the repo, data tests exercise repo implementations at the storage boundary.

**每一层 fake 掉的是它的下界，不是上界。** 我见过反过来的写法（biz 测试去 fake 数据库），那等于在 biz 测试里重新实现一遍数据层，而且实现得比真的还简单。

---

## 7. 现在的状态和欠账

**已经能用的：**

- 三层测试分离，层间用接口 fake
- 313 个 Go 测试文件 + 前端 50 个文件 / 184 个用例
- 协议兼容性矩阵 + `TestCompatibilityMatrix_Coverage` 覆盖检查（新增路径不补测试会硬失败）
- 跨路径 fixture 集中定义
- 确定性 mock upstream，固定 ID / 固定 token / 可配延迟
- 每夜 E2E 有准入标准、失败必须归因、修复后计数归零
- 每个 run 记录 commit SHA，形成可验证的"修复之后"边界

**还没解决的：**

**第一，E2E 只覆盖管理后台的关键路径。** relay 的 E2E 更多是靠 k6 压测和手工验证，没有浏览器级的端到端用例。

**第二，5 / 5 这个准入标准是拍的。** 我选它是因为"看起来足够"，但没有统计依据——比如"在真实 flaky 率下，5 次连续成功能把漏检概率压到多少"。

**第三，只有 MySQL 的迁移 smoke 在 CI 里真跑。** Postgres 和 SQLite 是静态检查（文件名镜像），没有真机执行（第 14 篇的欠账，这里是同一个问题的另一面）。

**第四，前端测试偏重组件渲染，缺交互时序。** 那个 React Router 竞态最后是 Playwright 发现的，而单元测试没抓到——因为单元测试不会模拟"URL 变了但 render 没提交"这个中间态。

**第五，没有覆盖率门禁。** 我说"313 个测试文件"，但说不出覆盖率是多少，也没有在 CI 里卡它。`coverage.out` 文件在仓库根目录躺着（188KB），说明我跑过，但没有把它变成决策依据。

**第六，`make verify` 里没有 E2E。** 它是本地/CI 的快速门禁（架构检查、迁移检查、单元、race、前端），E2E 独立在每夜跑。这是合理的分层，但意味着**本地改坏 E2E 只有到第二天才会知道**。

---

## 8. 下一篇

下一篇讲代码质量本身：我做过的两轮系统性审查（架构审查 + 代码审查），怎么把发现变成可跟踪的条目，以及哪些技术债我明确选择了"记录但不修"。

[《两轮系统性审查：哪些债我修了，哪些我明确决定不修》](/2026-09-19-micro-one-api-code-review-remediation/)
