---
title: "守门系统自己的状态坏了，谁来救"
date: 2026-10-25T18:00:00+08:00
description: "ops-agent 建造笔记第 9 篇：当审批、配置、审计等状态都落在 ~/.ops-agent/ 的 JSON 文件上，如何备份恢复 Agent 自身状态，同时让旧授权保持失效。"
tags: ["ops-agent", "备份恢复", "状态管理", "Agent", "运维"]
categories: ["tools"]
draft: false
---

# 守门系统自己的状态坏了，谁来救

> 《ops-agent 建造笔记》第 9 篇
> 代码基线：[v0.1.0-rc.1](https://github.com/mengbin92/ops-agent/tree/v0.1.0-rc.1)，提交 `d897d2c95e70`（2026-10-25 发布的候选版）
> 对照实现：`state_backup.py`、`core.py`、`tests/test_w8_state_backup.py`、`scripts/w8_acceptance.py`

---

## 0. 所有防线都压在一堆 JSON 文件上

回头看前八篇，这个系统的每一条防线都落在 `~/.ops-agent/` 里：

- 审批戳在 `approvals/`，丢了，已批准的变更得重新走确认；
- 快照在 `snapshots/`，丢了，原先保存的文件回滚材料就没了；
- 执行记录在 `executions/`，丢了，未核实的 unknown 也失去了本地证据；
- `targets.json`、`notify.json`、`schedules.json` 保存资产清单、通知渠道和排期；
- `memory.md`、会话、`runs/`、`events.jsonl` 保存排查事实与运行过程。

权限位、敏感读取限制和业务文件快照各有用途，却不能替代这批状态自己的备份。磁盘故障、误删、换机器，都会让我面对同一个问题：一个给别的文件做恢复的系统，自己的证据该从哪找回来。

W8 补上的是 `opsx state backup/verify/restore`。我把目标定得很窄：保存原始材料，恢复出一个可以人工检查的副本。它不会顺手连接服务器，更不会在恢复完成后自动接着改机器。

---

## 1. 备份之前，先让所有写入者停下

```bash
# 先停止调度、Agent、RPC/MCP 及其他状态写入者；父目录须已存在且由自己控制
./opsx state backup /secure/new-backup --quiesced
./opsx state verify /secure/new-backup
```

`--quiesced` 是我作为操作者作出的停写声明，不是一把锁。`backup_state()` 不会替我关闭 daemon，也没有让所有写入入口共同参与的全局事务锁。暂停一条 schedule，显然也不等于停掉别的写入者。

实现仍会检查普通并发变化：先后枚举目录清单，核对文件标识、大小和修改信息，归档时再核对文件状态。发现变化就失败，而不是把在线写入包装成“一致性快照”。我接受的是停下来再备份的边界，不能把这些变化检测理解成在线备份保证。

成功的备份目录只有两个文件：`state.tar` 和 `manifest.json`。目录为 0700，文件为 0600。清单记录归档 SHA-256、条目类型、原权限、大小和逐文件摘要；tar 保存原始字节，包含通知凭据和快照原件。普通输出可以脱敏，恢复原件不能脱敏，否则备份看着安全，真正需要恢复时却少了内容。

这里还有一条容易被“SHA-256”几个字掩盖的边界：哈希能检查内容是否与清单一致，不是签名。能同时改写归档和清单的人，也能制造一份摘要自洽的备份。备份来源仍要可信，工具没有替我做加密、签名或异地保管。

---

## 2. 恢复时，我不让旧授权一起复活

恢复目标必须是不存在的新目录，不能覆盖现有状态，也不能合并两份状态目录。

```bash
# 同样先停全部写入者；/isolated/new-state 必须尚不存在
./opsx state restore /secure/new-backup --to /isolated/new-state --quiesced

# 人工检查副本，不能忘记显式选中恢复目录
OPSX_STATE_DIR=/isolated/new-state ./opsx executions
OPSX_STATE_DIR=/isolated/new-state ./opsagent schedule list
OPSX_STATE_DIR=/isolated/new-state ./opsagent notify status
```

`restore_state()` 先完整验证归档，建立新目录后，写入过程中还会再次逐文件验证。它没有使用 `extractall`：路径穿越、绝对路径、重复或缺失条目、软硬链接和特殊文件都被拒绝。恢复安全处理需要的 JSON 若编码或结构无效，也不会当作“没有这项状态”悄悄跳过。

真正让我在意的是 `_safe_recovery()` 对几种状态的处理：

| 原状态 | 恢复后的处理 |
| --- | --- |
| 所有审批戳 | 移到 `recovery-quarantine-<随机值>/approvals/`，有效审批目录重新建空；旧戳保留作证据，不能搬回去继续用 |
| `executions` 中的 running | 转 unknown，清空 PID 与 resolved，结果必须人工核实 |
| `runs` 中的 running | 转 interrupted，清空 PID，避免新机器上的同号进程被误认成原任务 |
| schedule 与旧心跳 | 排期设为停用，上次 running 改为 interrupted，旧机器心跳元数据清掉 |
| active 长目标 | 改为 paused，保留已用轮次与上限，不因恢复会话而自动续跑 |
| 通知配置与发件箱 | 通知设为停用，URL 和待发送材料保留，核对渠道后才重新启用 |

`targets.json`、预算和用量计数则保留原字节，不替我重置消费或“顺便纠正”目标配置。恢复摘要写到 `recovery.json`；再次恢复时，旧的 recovery 证据也会隔离保留。

所有恢复目录和文件统一收为 0700/0600，不保留原 owner/group、ACL、扩展属性或时间。快照内部的原业务权限仍在原 `meta.json` 里，供以后经确认的业务回滚使用。状态文件权限和业务文件恢复权限，是两回事。

---

## 3. 中断发生在安全重写之前，也得挡住原件读取

只在恢复末尾写“恢复完成”是不够的。提取到一半被 kill，可能已经落下了原始 `notify.json` 或快照，但还没执行禁用通知、隔离审批的步骤。

所以代码在提取第一个原始文件之前就建立 `.ops-agent-recovered` 标记。活动状态仍指向旧目录时，Agent 的读取入口会保护这份恢复副本；切换 `OPSX_STATE_DIR` 后，普通报告和记忆可读，通知凭据、快照原件与状态根目录递归读取仍受限制。只有 `state.tar` 的半成品备份也有读取保护，不必等 manifest 发布。

可捕获异常会清理本次新建的半成品，删除前核对目录 inode，避免删掉被外部替换的新目录。但 SIGKILL 和断电不能执行 finally；我保留标记保护残留，不把它说成跨整个文件系统的事务恢复。

这些行为靠 `test_w8_state_backup.py`、`test_w8_review_archive.py`、`test_w8_review_runtime.py` 等回归验证。原始字节 roundtrip、审批隔离、active goal 暂停、坏归档拒绝和中断清理，都应当在这些测试里找证据。

---

## 4. 10/10 的本地演练，验的是另一条恢复链

这里我得把两种“恢复”分开，否则一个数字很容易越说越大。

```bash
python3 scripts/w8_acceptance.py --output /tmp/w8-local-evidence.json
```

这个脚本的十项检查，跑的是本机变更与业务配置恢复链：无审批不写入、批准后写入、命令 exit=0 但 HTTP 健康仍失败、回滚需确认、恢复配置与权限后服务健康、本地超时停止子进程、unknown 挡住重放、LLM HTTP 失败与恢复、通知失败重试与恢复，以及服务端请求证据。

它用真实本地进程、文件和回环 HTTP；LLM 与通知是桩。unknown 的失败注入是本地 shell 被 SIGTERM 结束，不是一次真实 SSH 断线。它也不调用 `state_backup.py`，因此这份 10/10 不能拿来证明状态归档 roundtrip；后者属于上一节那组回归测试。

固定在本版的 `2026-10-24-w8-local-evidence.json` 是 10/10 通过。parent/worker 核对十个固定检查身份，运行前后复核 24 项代码与策略摘要，避免一段执行失败或中途换过代码的输出被算成通过。

报告仍同时写着 `local_status=passed` 与 `overall_status=blocked`。默认退出 0 表示本地通过；加 `--require-external`，外部门禁未完成就退出 2。真实 SSH 恢复、真实 LLM、真实通知和连续 7 天观察仍未验收，不能写成“已经在观察，只差收尾”。

---

## 5. 现状

到 `v0.1.0-rc.1`，代码候选版已经发布；受控变更正式版的验收仍未完成。我现在能分别指出状态恢复的回归证据、本机配置恢复的演练证据，以及还没有的真实环境证据，这比一个笼统的“支持恢复”准确。

欠账也留着：备份仍是操作者停写后手动执行，没有自动备份轮转和外部保管；工具不会提醒我唯一备份是否也和机器一起坏了。接下来要补的是实际测试环境的恢复与观察，而不是把本地十个绿勾换个名字当作生产验收。

下一篇换个角度，讲 REPL、单发、RPC、MCP 共享了什么，以及它们没有共享什么。

### 对照源码与证据

- [离线备份、逐条校验与安全恢复：state_backup.py](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/state_backup.py)
- [状态恢复约定与人工切换步骤](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/docs/ops/state-backup-recovery.md)
- [原始状态 roundtrip 与拒绝边界回归](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/tests/test_w8_state_backup.py)
- [恢复后的运行、目标与中断状态回归](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/tests/test_w8_review_runtime.py)
- [十项本机变更恢复演练](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/scripts/w8_acceptance.py)
- [2026-10-24 本地演练证据](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/docs/validation/2026-10-24-w8-local-evidence.json)

---

[系列总览](00-overview.md) · [目录](README.md) · [上一篇：agent 该记什么，不该记什么](08-skills-and-memory.md) · [下一篇：同一个内核，四个壳](10-four-forms-one-kernel.md)
