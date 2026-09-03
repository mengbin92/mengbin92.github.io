---
title: "DeepSeek Harness（dsh）本地部署与使用指南"
date: 2026-09-03T10:00:00+08:00
description: "DeepSeek 官方 Agent 工具 dsh 的本地运行指南：npm 直接跑与源码构建两种方式、Web UI 首次配置、配置文件布局、headless/ACP/SDK 等 profile、权限沙箱机制与常见排错。"
tags: ["DeepSeek", "Agent", "CLI", "Node.js", "AI 工具"]
categories: ["tools"]
draft: false
---

## 摘要

DeepSeek Harness 的命令叫 `dsh`。本地跑有两种方式：**npm 直接跑**（推荐）和**源码构建**。两种方式最后都是同一个 Web UI，默认 `http://127.0.0.1:3080`。

> 版本状态：官方 **developer preview**，迭代极快，明确声明会有破坏性变更。
> 通道现状：npm `latest` = `0.1.1-rc.2`，`alpha` 通道实测安装到 `0.1.2-alpha.4`（2026-09-03）。

> **本地装比容器装省心得多。** 容器化踩过的三个坑（pnpm 符号链接布局导致插件解析失败、alpine/musl 加载不了 node-pty 的 glibc 预编译产物、profile patch 被卷挂载遮住）在本地全都不存在——本地直接 `npx`/`npm i -g`，macOS 拿到的也是 `darwin-arm64` 预编译包。

---

## 0. 前置条件

| 项目 | 要求 | 我本地 |
|---|---|---|
| Node.js | `^22.19.0 \|\| >=24.0.0`（仓库 `package.json` 的 `engines` 硬要求） | `v22.22.2` ✅ |
| npm / npx | 随 Node 自带 | `10.9.7` ✅ |
| pnpm | **仅源码方式需要**，官方锁 `pnpm@11.7.0` | 未安装（源码方式再装） |

检查：

```bash
node -v    # 必须 >= 22.19.0 或 >= 24
```

Node 版本不对的话，用 nvm / fnm 装一个：

```bash
nvm install 24 && nvm use 24
```

---

## 方式 A：npm 直接跑（推荐）

一条命令，不用克隆仓库、不用构建：

```bash
# 稳定通道
npx @deepseek-ai/dsh web

# alpha 通道（更新更快，推荐尝鲜）
npx @deepseek-ai/dsh@alpha web
```

启动后：

- 服务监听 `http://127.0.0.1:3080`
- 本机启动会**自动打开默认浏览器**（启动前会打印一行
  `dsh web: opening the default browser; pass --no-open to disable`）
- 日志里会打印一个**带一次性 token 的启动 URL**，浏览器用 token 换取签名 cookie 后跳转到干净地址

常用参数：

```bash
npx @deepseek-ai/dsh@alpha web --no-open     # 不自动开浏览器，只打印 URL
npx @deepseek-ai/dsh@alpha web --port 8080   # 换端口
npx @deepseek-ai/dsh@alpha web --help        # 看 web 应用自己的帮助
```

> ⚠️ **`--host 0.0.0.0` 是被 CLI 明确禁止的**，传了会以 usage error 退出。
> 这是官方的安全设计：本地跑就用默认的 `127.0.0.1`。
> 确实要绑全部网卡（比如容器里），只能改配置层 patch，不能直接传 flag。

### 想省掉每次 npx 解析，就全局装一次

```bash
npm i -g @deepseek-ai/dsh@alpha
dsh web
```

升级：

```bash
npm i -g @deepseek-ai/dsh@alpha
```

---

## 方式 B：从源码跑

适合想看代码、改代码、或装开发版插件的人。

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness

# pnpm 是官方锁定的包管理器（packageManager: pnpm@11.7.0）
npm i -g pnpm@11.7.0     # 或者 corepack enable && corepack prepare pnpm@11.7.0 --activate

pnpm install
pnpm run build           # 必须单独跑：构建 host 产物 + 前端 dist
pnpm dsh web             # 用已构建产物启动，不会再重建
```

注意点：

- `pnpm run build` 和启动是**分开的两步**，脚本不会自动帮你构建。
- 前端没构建时，启动会直接报"去跑 `pnpm run build`"的提示。
- 启动器**不检查产物是否最新**，所以改了前端代码后要手动重跑 `pnpm run build`，否则会一直跑旧版浏览器代码。

---

## 首次使用（Web UI）

启动后打开 `http://127.0.0.1:3080`。

**1. 配置模型**

`Settings → Models` → 填 [DeepSeek API Key](https://platform.deepseek.com/) → 保存。保存后模型路由**立即可用，不用重启服务**。

**2. 选择工作区**

点 `Choose workspace`，把你的项目目录加进来并选中。

> 未选中工作区之前，会话输入框是不可用的。
> `dsh` 会把**启动命令所在目录**作为默认文件系统位置。

**3. 发任务**

```
Summarize this repository and identify its main packages.
```

Agent 能读写工作区文件、跑命令、派子任务、维护计划。按当前权限策略需要审批的操作，UI 会先问你。

---

## 配置文件在哪

`$DSH_HOME` 是总目录，**默认 `~/.dsh`**（可用环境变量 `DSH_HOME` 改）。

| 路径 | 内容 |
|---|---|
| `~/.dsh/.credentials.yaml` | API 密钥。密钥是**只写**的，保存后页面只返回脱敏描述符 |
| `~/.dsh/settings.yaml` | 模型 / Provider / 路由配置 |
| `~/.dsh/profiles/web/cordis.patch.yml` | web profile 的用户覆盖层 |
| `~/.dsh/profiles/web/node_modules` | `dsh plugin` 装的外部插件 |

**密钥解析顺序**（前者优先）：

1. 继承的环境变量
2. `$DSH_HOME/.credentials.yaml`
3. 调用目录的 `.env`
4. `$DSH_HOME/.env`

---

## 其他运行模式

`dsh` 是唯一的启动器，SDK / ACP 都是 **profile**，不是独立命令。

| 命令 | 用途 |
|---|---|
| `dsh web` | Web UI（= `--profile web` 的别名） |
| `dsh --profile headless "跑一下测试"` | 一次性任务：跑一个新会话，打印最终答案后退出（成功退 0，否则退 1） |
| `dsh --profile acp` | ACP stdio 服务，接自动化客户端 |
| `dsh --profile sdk` | JSON-RPC stdio，接 Python SDK |
| `dsh --profile sdk-minimal` | 极简 agent 配置树 |
| `dsh plugin --profile web add <pkg>` | 装插件（转发给 pnpm，**pnpm 必须在 PATH 上**） |
| `dsh --profile web --dump-config` | 打印组合后的配置树并退出，不启动服务（排错利器） |
| `dsh --help` | 启动器自己的帮助（`dsh --profile web --help` 才是 web 应用的） |

装官方子 agent 插件：

```bash
dsh plugin --profile web add @deepseek-ai/dsh-subagent-codex
dsh plugin --profile web add @deepseek-ai/dsh-subagent-claude-code
```

> bundle 增删后**必须重启** profile；普通 `cordis.patch.yml` 编辑是热重载的。

### headless 模式适合塞进脚本

```bash
dsh --profile headless "run the tests"    # stdout 只输出最终答案，stderr 输出推理过程
```

---

## 常用环境变量

| 变量 | 作用 |
|---|---|
| `DSH_HOME` | 改 home 目录（默认 `~/.dsh`） |
| `DEEPSEEK_API_KEY` | DeepSeek 密钥，同时供内置 `web_search` 使用 |
| `DEEPSEEK_SEARCH_BASE_URL` | 自建搜索端点 |
| `DSH_PERMISSION_MODE` | 改进程级权限默认值 |
| `DSH_TOOLS_MODE` | `native` / `ptc` / `both`，填别的会启动失败 |
| `DSH_TELEMETRY_MODE` | `FULL` 全量上报 / `DISABLED` 全留本地 |
| `DSH_TELEMETRY_DISABLED` | 非空即为**最终生效**的遥测强制关闭开关 |
| `NODE_USE_ENV_PROXY=1` | 让 Node 遵循 `HTTP_PROXY` / `HTTPS_PROXY` |

> 遥测默认是**反馈门控**的：你在会话里记录 `/feedback` 之前不上传任何数据。

---

## 权限与沙箱（新会话默认值）

- 默认权限预设是 `workspace-write`：Bash 和文件修改**仅限**会话 workspace 与平台临时目录；读取和网络访问不受限制。
- macOS 用 **Seatbelt**，Linux 用 **bwrap / Landlock**。bwrap 会在私有 PID 命名空间里跑命令（看不到宿主进程），Landlock/Seatbelt 则保持宿主进程可见。
- 会加载项目里的 `AGENTS.md` / `CLAUDE.md`，渲染预算 65,536 字节。
- 会话内容索引用**内存 SQLite**（`:memory:`）。

---

## 排错

| 现象 | 处理 |
|---|---|
| 启动时提示前端未构建 | 源码方式需要 `pnpm run build` |
| 端口被占 | `dsh web --port 8080` |
| 想看生效的完整配置 | `dsh --profile web --dump-config`（会注释每行来自哪个文件） |
| 浏览器没自动打开 | 看日志里打印的 URL 手动访问；服务器仍在运行 |
| SSH 远程跑时不开浏览器 | 正常行为：检测到 `SSH_CONNECTION` / `SSH_TTY` 非空就不做交接，只打印 URL（那是**远端**的 loopback 地址，需自己做端口转发） |
| 停止服务 | `Ctrl+C`（SIGINT，退出码 130）；优雅排空最多 5 秒，再按一次强制退出 |

---

## 安全提醒

`dsh` 具备文件读写与命令执行能力。跑之前建议先看一眼官方 [`SAFETY.md`](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)。Web UI 默认只监听 `127.0.0.1`，**不要**改绑公网地址。

## 参考

- [官方仓库](https://github.com/deepseek-ai/deepseek-harness)
- [官方文档](https://deepseek-harness.github.io/deepseek-harness/)
- [配置目录（所有字段）](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/config-catalog.md)
