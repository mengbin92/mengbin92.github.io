---
title: "同一个内核，四个壳"
date: 2026-10-25T19:00:00+08:00
description: "ops-agent 建造笔记第 10 篇：REPL、单发、RPC、MCP 四种使用形态共用守门、共用状态与共用 Agent loop 的边界与差异。"
tags: ["ops-agent", "Agent", "MCP", "RPC", "架构"]
categories: ["tools"]
draft: false
---

# 同一个内核，四个壳

> 《ops-agent 建造笔记》第 10 篇
> 代码基线：[v0.1.0-rc.1](https://github.com/mengbin92/ops-agent/tree/v0.1.0-rc.1)，提交 `d897d2c95e70`（2026-10-25 发布的候选版）
> 对照实现：`opsagent`、`agent/loop.py`、`agent/session.py`、`agent/rpc.py`、`mcp_server.py`

---

## 0. 一个名字里，其实有两层内核

把这个项目画成“四个壳围着一个 loop”，画面很顺，代码却不是这样。四种使用方式在这一版都存在，但模型循环并不是四份入口共同拥有的东西。

| 入口 | 谁负责模型循环 | 这一版的边界 |
| --- | --- | --- |
| REPL：`./opsagent` | 内置 `agent/loop.py` | 终端交互、流式展示、`/resume`、REPL 长目标 |
| 单发：`./opsagent -p '看一下本机磁盘和内存'` | 同一个内置 loop | 跑一轮请求后退出，不自动续跑长目标 |
| RPC：`./opsagent rpc` | 同一个内置 loop | stdio JSON-RPC，客户端负责展示与确认回路 |
| MCP：`python3 mcp_server.py` | Claude Code 等宿主 | server 暴露守门工具，不运行内置 provider、loop 或 Agent 会话 |

前三种复用 `agent/` 的 provider、工具分发与会话。四种共同复用的是更下面的守门与状态能力：`core.py` 的分类、审批、快照和回滚，以及 `execution.py` 等记录逻辑。`core.py` 里有文件与进程 I/O，我这里把它当共享核心库，不把“核心”误写成所有函数都无副作用。

这层区分让我能说清楚复用的收益：CLI 建的审批戳可以被使用同一状态目录、同一执行环境的 MCP 工具校验，daemon 的运行记录可以由 CLI 查询。它不意味着每个入口都暴露所有功能，也不意味着四种形态能随意接管同一个对话。

---

## 1. 守门放到实际执行入口里

独立 Agent 的 bash handler 直接调用 `core.check()`，且只执行 R0。哪怕某条写命令已经有戳，也不能经 bash 绕开快照；要走 `ops_exec`。命令与参数来自模型，检查不能只写在 prompt 里。

这里我把两种“用户说了可以”分开了。`ask_user` 可以澄清“想 restart 还是 reload”，但它的回答不代替 `ops_approve` 对完整命令与目标的确认。独立 Agent 的审批 handler 自己发起确认，明确肯定后才建戳，模型不能拿前一段聊天替当前命令授权。

非 TTY 的单发没有终端确认通道，`ops_approve` 拒绝建戳；人可以事先用 `opsx approve` 批准具体命令，再由受控执行入口校验使用。定时巡检又更窄一层：工具集合本身是只读的，不能把“没有终端但能预授权”理解成 schedule 可以自动修改机器。

RPC 则不能简单归进“非交互，所以一律不能确认”。它在协议上提供反向 `ask_user` 请求，客户端用响应回传回答：

```json
{"jsonrpc":"2.0","id":"srv-...","method":"ask_user","params":{"question":"完整命令与目标的确认内容"}}
```

`agent/rpc.py` 用独立 stdin 读线程接收这份回答，主线程才不至于一边等待、一边又没法读到回答。断开、超时或非字符串回答按未回答处理；客户端若实现了有效的人机确认回路，审批就可沿这条路完成。确认依赖真实回答，不依赖终端长得像不像 REPL。

---

## 2. 会话落盘以后，也不能直接信任

`agent/session.py` 保存的是带格式头的 JSONL，首行包含 `format: 1` 和 session id。之后每条消息既可能来自旧版本，也可能是人工导入，不能因为“在自己的磁盘上”就只检查一个 role。

这次复审把 assistant 的 `tool_calls`、调用 id、函数名、字符串参数和消息内容形状补进了读取校验。旧的无关联字段工具结果仍保留展示兼容，明确畸形的记录会受控拒绝。崩溃留下的最后半条 JSON 可以截掉；中间损坏不能伪装成正常会话。旧记录在读取时同样再次脱敏。

还有一个更贴近副作用的分支：会话已经记下模型发出的工具调用，却没记下工具结果。进程可能在调用前死，也可能在变更完成后、落结果前死。`run_turn()` 不会看到一条“待完成调用”就替我重放，而是补一条工具结果：

> 工具调用未记录结果，可能已执行；请先核实状态，勿直接重试写操作。

这是补齐对话协议，不是查明业务结果。真的有没有改过，仍要去查 execution 记录与目标状态。把 `/resume` 做成自动续做未记录的写命令，恰好会破坏第 4 篇的 unknown 边界。

RPC 每次 `serve()` 会新建会话，当前只有 `prompt`、`reset`、`ping` 方法，没有“给一个历史 session id 并恢复”的 RPC 方法。REPL 的 `/resume` 能在本地选择已保存的 Agent 会话，MCP 宿主的对话历史则归宿主管。我不再用“共享目录”推导出代码里并不存在的会话接管能力。

---

## 3. 协议出错，不能把后面的对话一起拖死

把 provider 都转换成 OpenAI 形状，能让 loop 少分支，却没法取消边界校验。`llm._validate_message()` 只保留支持的 `role/content/tool_calls` 等协议字段，未知 provider metadata 不会原封不动进入递归脱敏和持久化路径。

深层 JSON 在不同 CPython 版本上可能正常解析，也可能触发递归限制。代码对解析和脱敏错误做受控处理；这里没有发明一个“第 600 层一定非法”的公共协议。测试既覆盖真实深层输入，也用确定性的异常分支检查错误后还能继续。

Anthropic 的历史工具调用还有一个细节。loop 已经把 `null`、数组等非对象参数作为工具错误回填，但回放给 Anthropic 时，`tool_use.input` 仍必须是对象。`_tool_use_blocks()` 会把这类非法参数转换为空对象，保留对应的工具错误结果，让一次参数错误不至于把后续每轮请求也卡死。

RPC 的数值 id 也有一个回归：`1e999` 会在解码后成为无限浮点值。照抄回响应就会输出非标准的 `Infinity`。本版拒绝非有限 id，返回 `id: null` 的 Invalid Request；深层坏 JSON也不会让读取线程退出，后续 `ping` 仍可响应。

这些修复都没有增加新能力，只是在保证“这一条错了”不自动变成“这个会话再也不能用”。

---

## 4. 交互层的决定，也和证据有关

语义配色是防误读：确认框黄色，R3/不可逆警示升级为红色；拒绝、成功、降级和普通结果用不同颜色。非 TTY 或 `NO_COLOR` 禁色，libedit 与 GNU readline 的提示符处理不同，这些平台差异在实现和回归里都有对应分支。

basic compaction 只裁发送给模型的内容，不改会话文件。超过 6 万字符的上下文里，最近八条之外的较长工具输出会替换为占位符；它不是一次完整的语义摘要，也不保证裁完必然落进任意模型的 token 窗口。

长输出超过 3 万字符时，工具会把脱敏后的完整内容写到 `outputs/`，回复给预览和路径，`read` 可以按 `offset/limit` 分段读。正常情况下保留 200 份。磁盘写失败会退回截断文本并说明全文没有落盘，不能把内存里曾经有过完整输出说成证据已经保存。

`/copy` 是另一个让我把“体验”重新算进副作用的地方。仓库有一条明确的修复记录：自检不再覆盖系统剪贴板。测试如果为了验证复制功能真的调用 pbcopy，就在改运行者的外部状态，哪怕这份状态只是刚复制的一段文字。

---

## 5. MCP 保留宿主自己的确认层

MCP server 的只读工具包括 `ops_check`、`ops_list`、`ops_audit`、`ops_executions`；审批、执行、撤销、快照、回滚等入口建议在宿主侧保持确认。工具的提示与分类不是宿主权限系统的替代品。

尤其是 MCP 的 `ops_approve`，实现直接调用 `core.approve()`，没有内置终端问答。这里的人类授权由宿主调用流程承担，不能把独立 Agent handler 会主动确认的行为套到 MCP 上。宿主许可调用工具和审批戳校验是两层约束；它们也不意味着 server 会自动弹出两次同样的确认。

回滚仍有清楚的两段式：先请求 `ops_rollback` 返回目标、文件和差异，核对后带 `confirm=true` 才执行。MCP 的执行工具没有 `target` 参数，仍以本机为边界；需要 SSH 目标操作时，宿主可以调用已有 `opsx ... --target` 通道。

长目标则只在 REPL 跨轮自动推进，默认六轮、上限二十。单发、RPC、定时任务不自动续跑，goal 创建入口也会拒绝这些形态。自动续跑始终不等于自动授权。

四种入口共享底层规则，让我不用给每个壳再造一份审批和回滚。还没做的部分也很具体：没有 Web/IM 客户端、没有双向 IM，也没有 RPC 历史会话恢复接口。下一篇讲我怎样给这些能力和边界留测试证据。

### 对照源码与证据

- [loop、消息归一与中断调用补齐](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/agent/loop.py)
- [JSONL 会话格式与恢复校验](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/agent/session.py)
- [RPC 方法、确认读线程与 ID 校验](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/agent/rpc.py)
- [Anthropic 的历史消息转换](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/agent/llm_anthropic.py)
- [MCP 工具定义与直接分发](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/mcp_server.py)
- [会话、provider 与 RPC 的本轮回归](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/tests/test_review_20261024_agent.py)

---

[系列总览](00-overview.md) · [目录](README.md) · [上一篇：守门系统自己的状态坏了，谁来救](09-state-backup-recovery.md) · [下一篇：没有同事，我一个人怎么 review](11-testing-and-reviews.md)
