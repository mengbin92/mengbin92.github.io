---
title: "给 AI 一个 bash 之前，我先想清楚了自己怕什么"
date: 2026-10-25T10:00:00+08:00
description: "ops-agent 建造笔记第 1 篇：为什么不能直接给 LLM 一个 bash 工具就上线，R0–R3 分级授权与守门机制是如何成为整个系统地基的。"
tags: ["ops-agent", "Agent", "安全", "运维", "LLM"]
categories: ["tools"]
draft: false
---

# 给 AI 一个 bash 之前，我先想清楚了自己怕什么

> 《ops-agent 建造笔记》第 1 篇
> 代码基线：[v0.1.0-rc.1](https://github.com/mengbin92/ops-agent/tree/v0.1.0-rc.1)，提交 `d897d2c95e70`（2026-10-25 发布，候选版）
> 主要代码：`core.py`、`config.yaml`、`agent/tools.py`；运行时仅需 Python 3.9+ 标准库

---

## 0. 我不敢真用的那个形态

让 LLM 帮我运维，最直接的做法是给它一个 bash 工具，告诉它"你是运维专家，去查吧"。

推演这个形态时，我发现自己不敢直接把它放到真实机器上。不是模型不够聪明，是整条链路上没有任何一环能回答我几个问题：

- 它敲 `systemctl restart nginx` 之前，谁来看一眼？
- 它说"我改一下配置"，改之前的那份在哪？
- 它在远程机器上跑命令，SSH 断了，那条命令到底执行了没有？
- 会话记录、审计日志、发给模型的上下文里，会不会混着我服务器上的私钥和 token？

四个问题一个都答不上来。我想清楚的是：排查可以自动做，变更得在明确边界里做。只读命令可以直接走，涉及写入就要有可核对的命令、目标、授权和执行记录。

项目后来的形状就是这么定下来的。守门不是后来加的功能，是先有的地基。巡检、通知、场景、调度都是后盖上去的，而且每一层都不许绕过它。

下面是我在那条边界上做的几个决定。

---

## 1. 分级标准是我要不要在场

命令分 R0–R3 四级。我用它安排介入程度，但它首先是一套实际匹配规则，不能凭操作听起来“轻不轻”替代码定级。这个版本的默认配置是：

| 级别 | 含义 | 例子 | 流程 |
|---|---|---|---|
| R0 | 只读 | `df -h`、`systemctl status`、`kubectl get pods` | 直接放行 |
| R1 | 配置中列出的较低级别变更 | `systemctl restart/reload`、`docker restart` | 变更单 → 确认 → 审批戳 → 受控执行 |
| R2 | 较高风险或未知命令 | `kubectl apply`、软件包变更；普通配置写入若未命中规则也默认 R2 | 同样确认完整命令、环境与回滚安排 |
| R3 | 配置中列出的最高风险变更 | `rm -rf`、`systemctl stop`、写设备的 `dd`、删库类 | 额外要 `force=true` + 明确确认，审批只能用 1 次 |

分级规则写在 `config.yaml` 里，追加覆盖走 `~/.ops-agent/config.override.yaml`。分类实现是线性正则匹配——这一点我在 README 的已知边界里写明了：不解析 shell AST，复合命令按 `;` `&&` `||` `|`、换行和后台 `&` 分段，取各段的最高级。

为什么不解析 AST？我权衡过。完整分析要处理 bash/zsh/sh 的语法差异、引号展开、命令替换的边界。我最后没有引入完整 shell 解析器，而是在分段分类之外加保守检查：命令替换、写重定向、`find -exec/-delete` 等不能凭只读命令名放行。误伤是“合法命令被多确认一次”，漏判是“写操作被当成只读放行”，这两个代价不对称。

发布前复审让我看到，只检查原始字符串仍然不够。回归里有 `find victim -de''lete`、`-de*` 和 `-{delete,print}`：shell 去掉引号或展开后，得到的才是程序真正接收的选项。`_has_write_marker()` 现在会结合解码后的参数、动态参数和 glob/brace 选项合成检查；Git 的 `--upload-pack`、`--ext-diff`，less 的初始命令和日志参数也不能因为挂在读取命令后面就免审。

这个代价能直接看见：`cat $HOME/file` 不再按 R0 放行，要改成确认过的路径或走审批；`echo '$HOME'` 里的字面量仍然可以。反过来，普通的 `grep -n "def check" core.py` 不会仅仅因为搜索词里有 `check` 就升到 R2。我宁可把这类边界写成可复现的回归，也不拿一次说不清原因的误伤替规则背书。

---

## 2. prompt 之外，工具内部还要自己守门

只读是默认，写操作的完整链路是这样：

```
变更单（风险说明 + 回滚计划）
  → 向用户展示完整命令与目标，明确批准
  → 建审批戳（core.approve）
  → opsx exec 执行（校验戳、按显式参数建快照、落执行记录）
```

变更单里的风险说明与回滚安排仍有流程纪律的部分，模型走神、上下文被污染时，prompt 不能替我兜底。所以独立 Agent 的 `bash` handler 自己调用 `core.classify()` 和 `core.check()`，只执行 R0；写命令即使已有戳，也必须走 `ops_exec`，不能借 bash 绕掉次数消耗、写锁和执行记录。

仓库还保留了给 Claude Code 宿主使用的 PreToolUse hook。`.claude/settings.json` 里注册了对 Bash 命令执行 `opsx hook`。它只放行两类：

1. R0 只读命令；
2. 本仓库受守门的 CLI（`opsx` 本身，由入口内部再校验审批与快照）。

裸写命令——即使有审批戳——也拒绝。在这个宿主里直接调用 `Bash("systemctl restart nginx")`，会在 hook 停住；独立 REPL、单发和 RPC 则靠自己的工具实现守门，不要求外面再套一层 Claude Code。

这里有个我必须承认的边界，README 里写着：审批戳由 Agent 侧在获得用户确认后创建，防"误执行"不防"恶意 Agent"。模型铁了心要作恶，它可以在确认环节骗我点同意。这套系统的前提是"模型可能犯错但不是敌人"。我用另一把尺接受了它：我一个人运维自己的机器，风险敞口本来就只有我自己。

---

## 3. 审批戳绑的不只是命令，还有在哪执行

早期审批只靠命令和目标名称还不够，复审时我按这样一个场景检查：

假设我批准了 `systemctl restart nginx`，目标是 web1，然后把 `~/.ops-agent/targets.json` 里 web1 的 host 从 `10.0.0.11` 换成另一台机器。如果审批只绑“命令 + 目标名”，旧戳仍然有效，同一条命令就可能被送到一台没批准过的机器上。

现在审批戳绑定实际执行环境，`core.resolve_env` 采集：

```python
def local_env() -> dict:
    return {"scope": "local", "host": socket.gethostname() or "localhost",
            "cwd": os.path.realpath(os.getcwd()),
            "kubeconfig": os.environ.get("KUBECONFIG", "")}
```

远程目标则展开成实际的 host/user/port/identity/options。`check_stamp()` 校验时比对整个 env 字典，任何一项变了——换了目录、改了注册表、切了 `KUBECONFIG`——旧戳立即失效，要重新批准。kubectl 的 context/namespace 也由 `resolve_env()` 加进执行环境，不只靠那段 `local_env()`。

kubectl 还有一条额外的硬规则：变更命令必须在命令里显式写 `--context`，否则拒绝发戳（`core._validate_k8s_change_scope`）。不写 context 意味着用当前默认的，而默认值取决于执行那一刻的环境，等于审批绑定了一个运行时才知道的值。这条规则连 `sh -c` 内层脚本和注释里的假 `--context` 都不算数：`sh -c "kubectl apply …"` 的内层不解析，直接视为没绑；`kubectl apply … # --context=prod` 的注释会被剥掉。

代价是明确的：迁移提示里写着 W1 之前的旧戳一律失效，要重新授权。这类事我给项目定过几条规矩，兼容性往后放，安全往前放。

---

## 4. 输出保护要共用，恢复原件要隔离

运维场景的秘密泄露面比一般应用宽得多。模型排查问题要看配置、看日志，而配置和日志里恰恰最容易有私钥、token、webhook URL。这些东西一旦进了模型上下文就等于发给了第三方 API，一旦写进会话文件或审计日志就落在磁盘上成了永久副本。

我的做法是所有出口共用同一个脱敏函数（`core.redact`）：模型请求、会话落盘、审计、长输出落盘、审批列表展示，走的都是它。

```python
def redact(text: str) -> str:
    """把常见凭据/私钥换成占位符；幂等，可重复用于同一段文本。"""
    if not isinstance(text, str) or not text:
        return text
    text = _PEM_KEY.sub(REDACTED + " 私钥", text)
    text = _AUTH_HEADER.sub(r"\1" + REDACTED, text)
    text = _SECRET_KV.sub(
        lambda m: m.group(1) + m.group(2) + m.group(1) + m.group(3) + REDACTED, text)
    return _TOKEN.sub(REDACTED, text)
```

这段来自 `core.py`。它用前面定义的 PEM 私钥、Authorization、秘密键值和常见 token 模式做替换，`redact_obj()` 再递归处理字典和列表。它们只能识别已知模式，我不能据此承诺任意秘密都能被认出来。

恢复原件走另一条路。快照保留原始内容不脱敏，因为脱敏过的快照恢复回去配置就坏了；离线状态备份也会保存这些原始字节。状态/快照目录 0700，模型的 `read` 和命令读取入口禁止把原件送进上下文。原件仍存在于磁盘和备份里，远程恢复还会经 SSH 传回目标机，所以这里做的是权限隔离与读取限制，不是让秘密只在某一瞬间存在。

除了输出侧，输入侧还有一层敏感文件读取限制：`read` 直接拒绝私钥、`.env`、`.netrc`、`.kube/config`、`~/.aws/credentials`、`~/.ops-agent/notify.json`（webhook URL 的 path 就是 token，0600 挡不住同 uid 的模型进程）。命令入口也覆盖：`cat ~/.ssh/id_rsa`、经符号链接指向私钥、`ssh host "cat id_rsa"` 的内层、`kubectl get secret -o yaml` 都拒。边界同样写明：正则不保证覆盖所有秘密格式，偏保守地拒绝，改密钥请由人直接执行。

这次还补了通配和 API 入口。`cat .env*` 会检查本机实际匹配项及软链接目标，累计超过 1024 项就拒绝；远程内容 glob 无法在本机核实，内容读取的 brace 展开也保守拒绝。`kubectl get --raw`、`config view --raw` 和动态生成资源名的读取，不能用来绕过 Secret 保护。敏感读取拒绝和“需要审批”是两回事，已有审批也不能覆盖前者。

只在写入时脱敏也不够。人工编辑的 `memory.md` 与旧事件可能根本没走过写侧入口，所以这个版本在记忆召回和事件读取时再次脱敏，原始文件不改。第 8 篇再展开记忆；这里我先把“导入的旧内容也会重新发给模型”这条出口补上。

验证方式是哨兵。`selftest` 里埋了假密钥，断言模型请求、会话、审计、落盘输出各出口都不出现明文。309 项自检里有一批就是这个。

---

## 5. 几处我自己都嫌严的地方，最后没改

开发过程中有几处我犹豫过是不是太严了，最后都留着了。

我要求受控远程执行的 `target` 先在注册表里登记。`ops_exec` 的目标必须是 `~/.ops-agent/targets.json` 里已有的名字，模型不能临时拼一个 target。这里要说窄一点：守门还允许一种严格受限的 `ssh host "只读命令"` 直连形态，所以它并不是网络访问的完整沙箱；注册表约束的是受控目标通道，不能把它夸成“模型无法连接任意新主机”。

独立 Agent 的 `ops_approve` 看的是有没有确认回调。非 TTY 单发通常没有，于是拒绝自建戳；RPC 可以通过反向请求让客户端回答，并不等于一律不可确认。定时巡检更严格，工具白名单根本不暴露 approve/exec，预先建戳也不会把写工具变出来。人工预授权的非交互 CLI 可以执行变更，但那是人明确准备的动作，不能写成 daemon 会自行修复。

目标字段要在加载与使用前校验。`targets.json` 里的 host/user/identity 等连接字段不能含空白或前导 `-`，port 单独校验为合法端口。否则这些值进入 SSH 参数后，一个看似主机名的配置就可能被当成选项。这个版本没有“注册服务端”，清单由人编辑，我不把运行时校验写成并不存在的注册接口。

---

## 6. 到写这篇时的状态

地基之上已经交付了按 W1–W8 拆分的能力；这些是工作包编号，不能当成已经历八周线上运行。`v0.1.0-rc.1` 有 309 项自检、223 项独立回归，发布时 Ubuntu/macOS × Python 3.9/3.12 四组 CI 都通过。本地演练 10/10，但本版 W8 的真实 SSH/LLM/通知外部验收及修复后连续 7 天观察仍未完成。

我对“安全”的宣称仍停在同一个位置：这套系统防的是误操作和已知流程绕过，不是恶意模型沙箱；分类不是完整 AST；秘密识别有漏报面。发布候选版没有把这几条变成过去式。

下一篇聊盖在地基上的第一种能力：巡检。为什么我坚持检查项固定在代码里、模型只做解读，以及 `unknown` 这个状态为什么比 `ok` 更重要。

### 这篇对应的代码

- [默认分级与白名单：config.yaml](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/config.yaml)
- [分类、敏感读取、审批与回滚：core.py](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/core.py)
- [独立 Agent 的 bash/approve/exec 入口：agent/tools.py](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/agent/tools.py)
- [守门、通配与路径改向回归](https://github.com/mengbin92/ops-agent/blob/v0.1.0-rc.1/tests/test_review_20261024_execution.py)

---

[系列总览](00-overview.md) · [目录](README.md) · [下一篇：巡检我不交给模型判](02-deterministic-inspection.md)
