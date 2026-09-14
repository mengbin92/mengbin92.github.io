---
title: "一个 2400 行的 http.go，是怎么被我拆成 9 个服务的"
date: 2026-09-14T10:00:00+08:00
description: "记录 micro-one-api 服务边界的两次反向调整：先把 2391 行的网关 http.go 按依赖方向切成 9 个服务，再把散落的 cmd/internal 收进 app/ 大仓并抽出 platform/pkg/domain 三层共享代码。包含决定边界的三条线、subscription 域为什么做成共享库而不是独立服务、以及用 check-architecture.sh 十条规则把分层约定钉进 CI 的实践。"
tags: ["Micro-One-API", "Go", "Kratos", "微服务", "架构"]
categories: ["architecture"]
draft: false
mermaid: true
---

## 摘要

这个项目还没上线。我在开发过程中把结构翻了一遍，而且方向还相反：第一次是把一个 2391 行的 `internal/relay/server/http.go` 拆开，第二次是把拆出去的九个服务收进 Kratos 大仓结构、抽出共享层，并写脚本卡住服务之间互相 import。这篇讲哪些线是我真的按需要切的，哪些只是抄了微服务的目录形状。

---

## 0. 项目还没上线，但结构已经翻过一遍了

先说清楚状态：这个项目还没正式上线，没有真实流量，也没有生产事故。所以这篇不是"上线之后怎么拆服务"的复盘，而是我在开发过程中被自己写的东西挡住、逼着把结构翻了一遍的记录。

有意思的是我翻了两次，方向还相反。

第一次是把一个巨型单体拆开。最初所有东西都写在 `internal/relay/server/http.go` 里：路由、解析、鉴权、选路、预扣、转发、流式、WebSocket、日志、错误处理，一个文件 2391 行、77KB，40 多个方法。我自己的复盘文档里管它叫 God Object。

第二次是把它收回来。拆完之后我数了一下，`cmd/` 下面排了九个服务，每个服务一套 `internal/{biz,data,service,server,conf}`、一个 Dockerfile、一个 Makefile、一份 config。然后我做了个反向操作：把它们全部收进 `app/<domain>/` 大仓结构，抽出 `platform/`、`pkg/`、`domain/` 三层共享代码，并且写了一个脚本卡住服务之间互相 import。

第二次的方向在直觉上很奇怪——刚拆完为什么又要合回去？这篇就聊这件事：**哪些线我是真的按需要切的，哪些线只是抄了微服务的目录形状。**

先把现状摊开。

---

## 1. 现在的样子

九个可执行服务，一个 `go.mod`：

| 服务 | 入口 | 职责 |
|---|---|---|
| `relay-gateway` | `cmd/relay-gateway` | 对外 HTTP 网关：鉴权、选路、预扣、转发、结算 |
| `admin-api` | `app/admin/cmd/admin` | 管理后台 BFF，托管前端静态资源 |
| `identity-service` | `app/identity/cmd/identity` | 用户、角色、登录、token 校验、权限判定 |
| `channel-service` | `app/channel/cmd/channel` | 渠道、模型、分组、优先级、可用渠道选择 |
| `billing-service` | `app/billing/cmd/billing` | 钱包、账本、兑换码、支付订单、扣费结算 |
| `config-service` | `app/config/cmd/config` | 动态配置 |
| `log-service` | `app/log/cmd/log` | 业务日志写入、查询、删除代理 |
| `monitor-worker` | `app/monitor/cmd/monitor` | 渠道健康检查与告警触发 |
| `notify-worker` | `app/notify/cmd/notify` | 通知发送 |

每个服务的内部形状是一样的：

```
app/<domain>/
  cmd/<name>/        入口 + Wire 注入器
  internal/biz/      DO、用例、repo 接口
  internal/data/     PO、repo 实现
  internal/service/  DTO ↔ DO
  internal/server/   HTTP/gRPC 装配
  internal/conf/     配置 proto（由 make config 生成）
  configs/           config.yaml
  Dockerfile
  Makefile
```

外加四个共享层：

- `platform/`：基础设施。`cache`、`database`、`events`、`grpc`、`http`、`logging`、`middleware`、`metrics`、`registry`、`tracing`、`security`、`websocket`、`audit`……一共 19 个包。
- `pkg/`：纯工具。`jsonx`、`errors`、`filtering`、`ordering`、`pagination`、`safecast`、`safefile`、`timeout`、`usage`、`wildcard`。
- `domain/`：跨服务共享的业务域库。`billing`、`routing`、`subscription`、`upstream`。
- `api/`：全部 proto 契约和生成代码，按领域分目录（`api/identity/v1`、`api/billing/v1`……）。

代码量分布是这样的（不含测试）：

| 目录 | 文件数 | 行数 |
|---|---:|---:|
| `internal/`（relay-gateway） | 119 | 34,232 |
| `app/channel` | 52 | 21,458 |
| `app/billing` | 61 | 16,797 |
| `app/admin` | 37 | 14,330 |
| `platform` | 58 | 11,901 |
| `domain` | 50 | 8,102 |
| `app/identity` | 23 | 7,346 |
| `app/log` | 14 | 3,033 |
| `app/monitor` | 15 | 2,474 |
| `app/notify` | 12 | 2,224 |
| `app/config` | 11 | 1,619 |
| `pkg` | 10 | 1,184 |

这张表本身就是个信号：networking 层（relay-gateway + channel）占了总量的一大半，而 `config-service` 只有 1619 行。**九个服务不是等重的，硬要它们长得一样反而是负担。**

---

## 2. 拆分的出发点：那个 2391 行的文件

回到最开始。我把所有逻辑堆在 `internal/relay/server/http.go` 里，当时觉得挺顺——都在一个请求链路里，放一起省得跳文件。

问题是它长得太快。等到我发现它 2391 行的时候，改任何一个地方都要先在心里过一遍"这个改动会不会影响流式"、"WebSocket 那条路径走不走到这里"。测试文件 `http_raw_test.go` 自己也有 2613 行。

真正让我下决心的是三件具体的事，不是"架构不够优雅"这种理由：

**第一件，我没法单独测一条路径。** 想验证"预扣失败时状态码对不对"，得把整个 handler 跑起来，因为它和路由注册、鉴权、转发焊在同一个结构体上。

**第二件，改 A 总要担心 B。** 我调一次渠道选择的逻辑，结果影响到了 WebSocket 那条完全不同的路径——因为它们共用了一个方法。

**第三件，同一个概念散在好几个地方。** "渠道"这个概念在鉴权分支里出现一次、在选路里出现一次、在转发里出现一次、在用量归因里再出现一次，每处的字段取法还略不一样。

所以拆分的第一个真实动因是：**我需要让每一段能被单独拿出来看。**

---

## 3. 三条真正决定边界的线

拆服务最容易犯的错是按"业务名词"切：用户、渠道、订单、日志各一个服务。我也这么起过手，然后发现切出来的服务之间调用密度极高，等于把进程内的函数调用换成了网络调用。

后来我是按依赖方向和一致性边界来切的，具体三条线。

### 3.1 第一条线：谁必须同步、谁能失败

relay-gateway 依赖四个下游：identity、channel、billing、log。但这四个依赖的性质完全不同。我当时列表格逼自己想清楚：

| 下游 | 挂了会怎样 | 能不能拒绝服务 |
|---|---|---|
| identity-service | 无法鉴权 | 必须失败，否则就是无鉴权放行 |
| channel-service | 无法选路 | 必须失败 |
| billing-service | 无法预扣 | 必须失败（宁可不服务，不能白送） |
| log-service | 日志丢失 | **可以继续**，事后对账补 |

前三者决定了 relay-gateway 的可用性上界，第四者不应该。这个区别后来直接落到代码里：计费路径是 fail-close 的，日志写入是 best-effort 的。

```go
// 计费：预扣失败直接让请求失败，返回 402
if reserveErr != nil {
    return &relaybiz.RetryableError{Status: http.StatusPaymentRequired, Err: reserveErr}
}
```

```go
// 日志：best-effort，写失败只记 Warn，不影响已经写出去的响应
func (s *HTTPServer) logPostResponseCommitError(err error) {
    if err != nil {
        applogger.Log.Warn("failed to commit quota after response was written", zap.Error(err))
    }
}
```

**边界是从"能不能拒绝"反推出来的，不是从名词切出来的。** 如果当初把 log 也做成强依赖，日志服务抖一下整个网关就跟着抖——这是我明确不想付的代价。

### 3.2 第二条线：数据一致性边界

这条线决定了哪些东西**不能**拆开。

`billing-service` 和钱包相关的操作必须是同一个事务：预扣、提交、释放，还有余额快照。我一度想把"账户快照查询"拆成单独服务，理由是查询量大、可以独立扩容。想了两天放弃了，因为快照读和余额写必须在一致视图里——拆开之后要么加分布式事务，要么接受读到脏数据。

这条线的具体体现是 repo 接口里的 `...InTx` 方法群：

```go
type AccountRepo interface {
    GetAccountSnapshot(ctx context.Context, userID string) (*Account, error)
    // Reads through the caller transaction, without acquiring another connection.
    GetAccountSnapshotInTx(ctx context.Context, tx subscriptionbiz.Tx, userID string) (*Account, error)

    ReserveBalanceInTx(ctx context.Context, tx subscriptionbiz.Tx, userID string, amount int64, allowOverdraft bool) (oldBalance, newBalance, newFrozen int64, err error)
    CommitBalanceInTx(ctx context.Context, tx subscriptionbiz.Tx, userID string, reserved, actual int64, allowOverdraft bool) (int64, int64, error)
    ReleaseBalanceInTx(ctx context.Context, tx subscriptionbiz.Tx, userID string, reserved int64) (newBalance int64, err error)
}
```

注意这些方法把 `tx` 当参数传进来。什么意思？**事务的所有权在 biz，不在 data。** data 层只提供"在这个事务里做这一步"的原子操作，它不自己开事务、不自己提交。

这个约定是我在 review 自己的代码时立的规矩。之前有过 data 层自己开事务的版本，结果 biz 想组合两个操作时出现了嵌套事务，回滚语义变得没法推理。现在的写法是：

```go
// ReserveBalanceInTx 把读-判断-更新合成一条 UPDATE，
// 并发的预约不会互相覆盖（历史版本的读改写是竞态的）
// 钱包要变负数时拒绝，除非 allowOverdraft
ReserveBalanceInTx(ctx, tx, userID, amount, allowOverdraft) (oldBalance, newBalance, newFrozen int64, err error)
```

这段注释里留着当时的问题记录：最早的版本是"先读余额、判断够不够、再写回去"，并发下会互相覆盖。改成单条 UPDATE 之后这个竞态才消失。**这种 bug 拆了服务只会更难修**——所以我把它留在了一个服务里。

### 3.3 第三条线：契约面

把服务切开，就必须有契约。我全部用 proto：

```
api/
├── admin/v1/admin.proto
├── billing/v1/billing.proto        + error_reason.proto
├── channel/v1/channel.proto        + error_reason.proto
├── common/v1/common.proto
├── config/v1/config.proto
├── identity/v1/identity.proto      + error_reason.proto
├── log/v1/log.proto
├── monitor/v1/monitor.proto
├── notify/v1/notify.proto
└── relay/v1/relay.proto
```

`make api` 一次生成所有语言的桩代码，`make config` 单独生成各服务的配置 proto（我把它和 API 生成分开，因为配置 proto 不需要 OpenAPI 插件，混在一起会互相覆盖输出）。

错误原因也是契约的一部分。每个有业务错误的域有自己的 `error_reason.proto`，生成的枚举在 biz 层被包成类型化错误。这样调用方能按 reason 判断，不用去 grep 错误文案。

**契约定下来之后我才敢改实现。** 这是我拆服务最大的收获：`api/` 目录成了"改之前先看这里"的地方。

---

## 4. 分层：三个箭头和三条禁令

每个服务内部我固定了三个层，模型形状也固定成三种：

```
   client ──► DTO ──► service ──► DO ──► biz ──► DO ──► data ──► PO ──► storage
                                  ▲                ▲
                                  │ declares       │ implements
                                  └─── repo IF ────┘
```

| 层 | 拥有 | 边界上说 | 绝不说 |
|---|---|---|---|
| `service` | —— | DTO ↔ DO | PO、存储客户端 |
| `biz` | DO | DO | DTO、PO、存储客户端 |
| `data` | PO | DO ↔ PO | DTO |

这个形状的好处是**依赖方向是单向的，而且反转点在 biz**。`biz` 声明 `ChannelRepo` 接口，`data` 去实现它。所以是 data 依赖 biz，不是 biz 依赖 data。

Wire 里能看到这个绑定：

```go
var ProviderSet = wire.NewSet(
    newRepo,
    newEventBus,
    biz.NewChannelUsecase,
    biz.NewModelUsecase,
    biz.NewModelRoutingUsecase,
    data.NewRoutingGroupRepo,
    biz.NewRoutingGroupUsecase,
    service.NewChannelService,
    server.NewGRPCServer,
    server.NewHTTPServer,
    provideRegistrar,
    wire.Bind(new(biz.ChannelRepo), new(*data.Repository)),
    wire.Bind(new(biz.ModelRepo), new(*data.Repository)),
    wire.Bind(new(biz.ModelRoutingRepo), new(*data.Repository)),
)
```

`wire.Bind` 那一行是关键的接缝：biz 只知道接口，data 提供实现，**只有 Wire 知道两者怎么接上**。这意味着我可以把 `*data.Repository` 换成任何满足接口的东西——测试里换成 fake 就是靠这个。

这条禁令我吃过的亏是：一开始图省事，biz 直接 import data 拿了个 concrete type，于是 biz 和 GORM 绑死了，写单元测试必须起数据库。改成接口之后，biz 的测试全是纯内存的。

---

## 5. `domain/`：我做的一个反直觉决定

这一段是整篇里我自己最想说清楚的部分。

如果按标准微服务思路，"订阅"这么完整的业务域应该独立成一个服务：它有实体（订阅、套餐、额度策略）、有用例、有存储。我一开始也这么想过，甚至规划过 `api/subscription/v1` 契约。

最后我没这么做，而是把它做成了一个**共享的域库**，放在 `domain/subscription/`，由三个服务直接嵌入。

`domain/subscription/README.md` 里我把理由写下来了：

> *"a **shared modular domain library**, not an independently deployable microservice. It bundles the subscription business model (DOs, usecases, repo interfaces) and its data implementation (GORM-based repositories) so that the three services that need subscription behavior — **admin**, **billing**, and **relay-gateway** — can embed it directly without introducing an extra network hop.*
>
> *This is a deliberate **modular-monolith** boundary: the three binaries share the same subscription database tables and the same in-process biz/data code, rather than communicating through a `api/subscription/v1` gRPC contract."*

为什么？因为这三个服务看订阅数据的视角虽然不同，但**一致性的要求是一样的**：admin 改一个用户订阅，billing 和 relay 必须立刻看见。如果拆成服务，这个"立刻"就要靠缓存失效、事件通知、或者接受短暂不一致来换。为了一个部署单元的整齐，去换三个服务之间的时序问题，我觉得不划算。

目录形状遵循同一套分层规矩：

```
domain/subscription/
├── biz/     entity.go、repo.go（接口）、*_usecase.go、quota_checker.go
├── data/    data.go、subscription_repo.go、group_repo.go、plan_repo.go
└── README.md
```

消费方式也写清楚了：

> *"Each consumer independently constructs its own `subscriptiondata.NewRepository(...)` using its own config's `Data.Database` settings."*

也就是说：**每个服务自己建自己的 repo 实例，共享的是代码和表，不是连接。**

这件事让我意识到一个更普遍的判断标准——**共享代码是便宜的，共享事务是昂贵的，跨进程保持一致是最贵的。** 我只有在"这三个服务必须看到同一份订阅状态"的前提下才选了共享代码，而不是"我觉得这样省事"。

而且这里有一个我刻意留下的代价，也写在 README 里：`SubscriptionGroup` 这个名字有历史包袱，它指的其实是**订阅额度策略**，和用户/渠道上的字符串 routing group 完全是两回事；`RateMultiplier` 也和 billing 的 `GroupRatio` 不是一回事。名字相近但概念不同，这是共享域库带来的认知成本，我没能靠重构消掉，只能靠文档写清楚。

---

## 6. 剩下三个域：什么时候才该提到 `domain/`

除了 subscription，`domain/` 下还有三个：

| 目录 | 放什么 | 为什么共享 |
|---|---|---|
| `domain/billing` | `source_kind.go` | relay 要产出、billing 要消费，枚举必须只有一份 |
| `domain/routing` | `billing_policy.go`、`context.go`、`cost_bound.go`、`entity.go`、`group.go`、`permission.go` | 选路和定价是同一份规则的两种用法 |
| `domain/subscription` | 订阅实体、用例、repo | 见上一节 |
| `domain/upstream` | `credential/`、`provider/` | 凭证轮转和 provider 适配，relay 与 channel 都要用 |

放进去的标准我最后收敛成一句话：**只有当"两边对同一个概念的理解不一致就会出错"时，才把它提到 `domain/`。**

- `source_kind` 是枚举：relay 写错一个值，billing 就归因错，所以必须共享。
- `routing.Permission` 是判定结果：选路和重试授权都用它，语义必须一致。
- `credential` 是凭证轮转：如果我复制成两份，就会出现"一处刷新了 token，另一处还在用旧的"。

反过来，像 `logging`、`metrics`、`middleware` 这种，我放在 `platform/` 而不是 `domain/`——它们不含业务语义，是基础设施。而 `pkg/` 更纯粹，只允许放没有任何内部依赖的工具（`jsonx`、`safecast`、`wildcard`）。

---

## 7. 边界不是靠自觉，是靠脚本

拆的时候最容易发生的事，是过一阵子又慢慢粘回去。我自己就干过"就 import 这一次"这种事。

所以我把规则写成了一个脚本，`scripts/check-architecture.sh`，挂在 `make verify` 里。它做十件事，我挑几条说。

**它怎么识别一个包属于谁：**

```bash
# app/<svc>/...       → service root 是 micro-one-api/app/<svc>
# internal/...         → service root 是 micro-one-api/internal（relay-gateway）
get_service_root() {
  local pkg="$1"
  case "${pkg}" in
    "${module_path}/app/"*)
      local relative="${pkg#${module_path}/app/}"
      printf '%s/app/%s' "${module_path}" "$(printf '%s' "${relative}" | cut -d/ -f1)"
      ;;
    "${module_path}/internal/"*)
      printf '%s/internal' "${module_path}"
      ;;
    *)
      printf ''
      ;;
  esac
}
```

**规则 1 禁止服务之间互相 import 实现：**

```bash
if [[ -n "${service_root}" \
      && ( "${imported}" == "${module_path}/app/"* || "${imported}" == "${module_path}/internal/"* ) \
      && "${imported}" != "${service_root}" \
      && "${imported}" != "${service_root}/"* \
      && "${allow_cross_app_test_helper}" != 1 ]]; then
  echo "${package_path} imports another app implementation: ${imported}"
  violations=1
fi
```

**规则 2 禁止反向依赖**：`platform`、`pkg`、`domain` 不允许 import `app/` 或根 `internal/`。这条是最重要的一条——共享层一旦反向依赖业务，它就再也不是共享层了。

**规则 3 更进一步**：`pkg/` 连 `platform/` 和 `domain/` 都不许 import。纯工具必须保持纯粹。

然后是四条针对分层的规则：service 不能 import data、biz 不能 import service、biz 不能 import data、data 不能 import service。

**规则 9 我觉得最值得讲。** 它禁止 data 层 import proto 生成的 DTO 包，因为 data 在大多数服务里就是数据库仓储，只该碰 PO。但有几个合法的例外——比如 relay-gateway 的 `internal/data` 是**网关适配器**，它包的是外部 gRPC 客户端、给 biz 提供 DO，这时候必须 import DTO 来做转换。

我没有用一个通配符放过整个目录，而是把例外一对一对列出来：

```bash
# The admin exemptions are enumerated one (package, imported) pair at a
# time on purpose: wiring a new DTO dependency into an admin adapter must
# be an explicit edit here plus a design note, never a wildcard that
# quietly widens the hole for a whole api/ subtree.
if [[ "${package_path}" == "${module_path}/app/admin/internal/data/channelclient" \
      && "${imported}" == "${module_path}/api/channel/v1" ]] \
   || [[ "${package_path}" == "${module_path}/app/admin/internal/data/routingaccess" \
         && ( "${imported}" == "${module_path}/api/identity/v1" \
           || "${imported}" == "${module_path}/api/channel/v1" \
           || "${imported}" == "${module_path}/api/billing/v1" ) ]]; then
  admin_dto_exempt=1
fi
```

注释里那句 "never a wildcard that quietly widens the hole for a whole api/ subtree" 是我特意写的。因为**规则一旦可以整片放开，它就等于不存在了**。每加一个例外都必须回来改一次脚本，这个摩擦是故意的。

**规则 10 是 Wire 的编译检查：**

```bash
if ! go test -tags wireinject ${wire_pkgs} >/dev/null 2>&1; then
  echo "Wire injector compile check failed (go test -tags wireinject)"
  violations=1
fi
```

这条是我被坑出来的。`wire.go` 上有 `//go:build wireinject` 标签，平时 `go build` 根本不会编译它。有一次我在里面引用了只在非 wireinject 下可见的 helper，本地 `go build` 全绿，跑 `wire` 生成时才炸。现在编译检查进 CI 了。

---

## 8. 我没拆干净的地方

诚实交代一下现在还有的问题。

**第一，还是共享一个 MySQL。** 九个服务连同一个库。表级争用是真实存在的：`billing_ledgers` 高频写和用户查询会互相影响，`logs` 这种大表也一样。我用分区和迁移治理去缓解，但没有真正做物理隔离。这是个开放的债。

**第二，配置是分片的。** 每个服务一份 `config.yaml`，同一个概念（比如数据库 DSN）在几个服务里各配一遍。改一个环境变量经常要改好几处。

**第三，`relay-gateway` 还是太重。** 34k 行，比第二大的 channel 多 60%。它的 `internal/biz/relay.go` 一个文件 1352 行。这个文件我还没拆开，因为它处在"选路 + 鉴权 + 计费边界"的交汇处，硬切容易切错。我宁愿先让 executor 那条新路径跑通再说。

**第四，服务之间的调用还没有熔断降级。** 我在复盘文档里明确写过这条：identity、channel、billing 三个下游任何一个挂了，整个网关就不可用。现在 `platform/grpc` 里有 `ResilientClient`，`internal/data/resilient_clients.go` 也接上了，但默认是关的（`RELAY_RESILIENCE_ENABLED` 默认 false），我没有在生产形态下验证过它。

**第五，这是个九服务但非严格微服务的结构。** `domain/subscription` 的存在意味着"服务边界"和"部署边界"不完全重合。我认为这是对的取舍，但它确实让"一个服务一个数据库"这种简单心智模型失效了。

---

## 9. 回头看，我还会这么做吗

如果重来一次，有两件事我会改。

**第一，我会更早拆那个 2391 行的文件，但不急着拆服务。** 现在回想，最初的问题根本不是"需要更多服务"，而是"需要更清楚的函数边界"。我先跳到了目录结构，绕了一圈才回来做分层。顺序反了。

**第二，我不会一开始就把九个服务都做成一模一样的目录。** `config-service` 只有 1619 行，给它一套完整的 `biz/data/service/server/conf` + Dockerfile + Makefile，维护成本相对它的体量是偏高的。现在这个形状是"统一"带来的好处，但也有点为了整齐而整齐。

反过来说，有三件事我认为做对了：

1. **`check-architecture.sh` 这个脚本。** 它把架构约定从"我记得应该这样"变成了 CI 的一道门。九条规则里有四条是我在被 import 坑了之后补的。
2. **`domain/subscription` 的选择。** 没有为了架构的整齐，去制造三个服务之间的一致性问题。
3. **`api/` 统一收口。** 所有契约在一个目录，改之前先看它，这个习惯救了我很多次。

---

## 10. 相关的一篇

结构拆完之后，我写了一篇更细的：把一次 `/v1/chat/completions` 从进入网关到落账的完整链路走一遍，包括中间件顺序、选路、预扣、流式结算和重试归因——
[《一次 /v1/chat/completions 从进来到落账，中间发生了什么》](/2026-09-14-micro-one-api-request-lifecycle/)。

