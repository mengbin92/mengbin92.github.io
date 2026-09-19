---
title: "如果要照这套结构做一个新服务：最小的可运行切片是什么"
date: 2026-09-19T12:00:00+08:00
description: "前面 24 篇讲的是“我为什么这么做”。这一篇不一样——它讲具体怎么做。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 这篇是给"想照抄这套结构"的人写的

前面 24 篇讲的是"我为什么这么做"。这一篇不一样——它讲**具体怎么做**。

因为我发现一件事：这套结构里真正需要照抄的东西不多，但**如果不照抄那几样，后面就很难改回来**。而另外很多东西是"可以后补"的，一开始就上只会拖慢你。

所以这篇分成两部分：

- **第一天必须有的**（不做后面会痛）
- **可以后补的**（做早了是浪费）

然后我会走一遍"加一个资源"的完整步骤。

---

## 1. 第一天必须有的四样

### 1.1 三层模型：DTO / DO / PO

这是整套结构的地基。

```
   client ──► DTO ──► service ──► DO ──► biz ──► DO ──► data ──► PO ──► storage
                                  ▲                ▲
                                  │ declares       │ implements
                                  └─── repo IF ────┘
```

| 层 | 拥有什么 | 边界上说 | 绝不说 |
|---|---|---|---|
| `service` | —— | DTO ↔ DO | PO、存储客户端 |
| `biz` | DO | DO | DTO、PO、存储客户端 |
| `data` | PO | DO ↔ PO | DTO |

**为什么第一天就要立起来？** 因为这三层的价值在于**依赖方向单向**，而依赖方向一旦乱了，后面纠正的成本是逐渐升高的：

- 第一个月：一个 `biz` 里 import `data` 拿个 concrete type，改起来五分钟；
- 半年后：二十个文件都这么干，而且测试全都依赖真实数据库，改起来是几周，还要重写一堆测试。

**而这三层其实很便宜**：就是在包里放不同的结构体，转换函数写两遍。第一天做，成本接近零。

有两个推论我觉得值得单独说：

**推论一：`data` 层的构造函数返回接口，不返回具体类型。**

```go
func New<Resource>Repo(d *Data) biz.<Resource>Repo
```

这不是风格问题。**返回接口意味着调用方拿不到具体类型，也就无法绕过接口去用底层方法。** 依赖倒置的接缝如果不这样收口，很快就有人直接调 `repo.db` 了。

**推论二：PO 只在存储形状和 DO 不同的时候才定义。**

如果一张表的列和 DO 一一对应，那就直接用 DO（或者一个薄的别名）。**为了"完整"给每个资源都写一套 PO 是浪费**——而且它会引入两个必须同步的结构体。

判断标准是：**什么时候它们的字段开始不一样（比如存储用 JSON 存一个复杂结构、或者列名和字段名映射不同），什么时候再拆。**

### 1.2 repo 接口在 biz 声明

这一条是三层模型里最关键的一半：

```go
// biz 里
type <Resource>Repo interface {
    Get(ctx context.Context, id int64) (*<Resource>, error)
    List(ctx context.Context, opts ...ListOption) ([]*<Resource>, error)
    Create(ctx context.Context, r *<Resource>) error
    // ...
}
```

```go
// data 里
func New<Resource>Repo(d *Data) biz.<Resource>Repo {
    return &<resource>Repo{data: d}
}
```

**接口的声明在消费方（biz），实现的提供在 data。** 所以依赖箭头是 `data → biz`，不是反过来。

这个方向的价值在测试上立刻体现：**biz 的测试可以给一个纯内存的 fake repo，跑全部用例，不需要数据库。**

而如果反过来（biz import data），biz 的测试就必须起数据库——**这不是"麻烦一点"，而是"跑得慢、容易 flaky、最后没人跑"。**

### 1.3 分层约束要有一个自动化检查

我在第 1 篇详细讲过 `scripts/check-architecture.sh`，这里只讲**最小版本该做什么**。

第一天你不需要十条规则，四条就够：

| 规则 | 为什么 |
|---|---|
| 服务之间不能互相 import 实现 | 一旦互相 import，你就没有服务边界了 |
| `platform` / `pkg` / `domain` 不能反向 import 业务 | 共享层一旦依赖业务，就再也不是共享层 |
| `service` 不能 import 自己的 `data` | 保证 service 只依赖 biz |
| `biz` 不能 import 自己的 `data` | 保证依赖倒置的箭头方向 |

前两条是**最容易发生、也最难回退**的。第三条第四条是我实际做错过的（第 1 篇讲过：biz 直接 import data 拿 concrete type，结果测试必须起数据库）。

**关键不是规则的数量，是"有这条检查"。** 因为人的记忆不可靠——我自己在同一个项目里重复犯过同一类错误。

一个具体的写法建议：**用 `go list` 拿 import 关系，不要用手写正则去扫源码。**

```bash
go list -e -f '{{.ImportPath}}|{{join .Imports " "}}' ./app/... ./internal/... ./platform/... ./pkg/...
```

**这样得到的是编译器眼里的依赖，而不是文本上的 `import` 字符串。** 两者的区别包括：build tag 排除的文件、生成代码、条件编译——手写正则会在这些地方出错。

### 1.4 错误要在 biz 层类型化

不要在 `service` 层或 `data` 层拼错误字符串：

```go
// biz 里
var (
    Err<Resource>NotFound = errors.New("<resource> not found")
    Err<Resource>Conflict = errors.New("<resource> already exists")
)

func (uc *<Resource>Usecase) Get(ctx context.Context, id int64) (*<Resource>, error) {
    r, err := uc.repo.Get(ctx, id)
    if err != nil {
        if errors.Is(err, ErrNotFound) {
            return nil, Err<Resource>NotFound
        }
        return nil, err
    }
    return r, nil
}
```

而 `data` 层负责把 driver 的错误翻译成语义错误：

```go
// data 里
if errors.Is(err, gorm.ErrRecordNotFound) {
    return nil, biz.ErrNotFound
}
```

**为什么要第一天做？** 因为"错误是字符串"这件事**会扩散**。一旦 `service` 层开始用 `strings.Contains(err.Error(), "not found")` 来判断，这个模式就会被复制到每一个新接口里。

而类型化错误在编译期就有约束——**拼错一个变量名编译不过，拼错一个字符串永远发现不了。**

另外一个实际的收益：字段级校验和业务校验要分层。**请求格式错误（缺字段、类型不对）在 service 层挡掉；业务规则错误（余额不足、模型无权）在 biz 层产生。** 两类的 HTTP 状态码通常不同，混在一起会很难映射。

---

## 2. 可以后补的五样

这一节可能比上一节更有用，因为它说的是"先别做"。

### 2.1 不用一上来就拆多服务

**从一个服务开始。** 把 `relay`、`user`、`billing` 放在同一个进程里，但**保持包的边界**（`internal/biz` 里有几个 usecase，每个有独立的 repo 接口）。

理由：

- 拆服务的成本不只是"多写几个 main 函数"，还有**跨服务的一致性**（第 1 篇那个共享库的决定就是绕这个）；
- 而**包边界可以在第一天就立起来，且不需要任何基础设施**。

**等你需要独立扩容某个部分时再拆。** 那时候你的包边界已经把依赖关系理清楚了，拆出来是机械操作。

第 1 篇里我讲了自己"先跳到目录结构、绕一圈才回来做分层，顺序反了"。**正确的顺序是先有清晰的分层，再有服务边界。**

### 2.2 不用第一天就接 Redis

并发限流、分布式缓存、幂等键这些都可以先用进程内实现。

**但要在代码里留下"这里是单进程"的注释**，并且把接口抽出来：

```go
type <X>Limiter interface {
    TryAcquire(ctx context.Context, key string, limit int32) (func(), bool)
}
```

第 4 篇讲的账号并发槽就是一个例子：内存版和 Redis 版实现同一个接口，**换的时候业务代码一行不用改**。

而那个"单进程"的注释很重要——**因为单进程的限制在多副本时会静默失效，不会报错。**

### 2.3 不用第一天就上消息队列

第 13 篇讲的那套（一张 outbox 表 + Redis Streams）就是"不想引消息队列"的产物。它的量级上限是"每秒几十次事件"，超过之后该上 Kafka。

**但第一天你连事件都没有。** 先用同事务的直接调用，等真的需要异步时再考虑。

### 2.4 不用第一天就做完整可观测性

第一天需要的是：

- 一个结构化 logger；
- `/healthz`；
- `/metrics`（Prometheus 端点）。

**不需要**的是：完整的指标设计、追踪接入、审计日志、看板。

第 17 篇讲过一个教训：**我加了从来没看过的指标。** 一个没人看的指标和没有它的区别只是多占存储，而且它会让人以为"这块有监控"。

我现在给"加一个指标"设的门槛是：**先想清楚它的告警规则或者它在看板上的位置。** 想不出来就先不加。

### 2.5 不用第一天就写 E2E

第 22 篇那套（compose + Playwright + 每夜跑 + 连续 5 次准入）是在有真实故障之后才建起来的。

第一天该写的是：

- **biz 的单元测试**（fake repo，跑得快）；
- **data 的存储层测试**（打真实数据库，验证查询正确）。

因为这两层的测试是**随代码增长的**，而 E2E 是**补起来代价高、维护成本也高**的。

**顺序是：单元测试 → 集成测试 → E2E。** 反过来的话，你会有一堆慢而脆的 E2E，但没有快的单元测试来定位问题。

---

## 3. 走一遍"加一个资源"

现在按 `AGENTS.md` 里那份清单实际走一遍。假设要加一个 `Widget` 资源。

### 步骤 1：定义 DTO（proto）

在 `api/<domain>/v1/` 下加：

```proto
service WidgetService {
  rpc CreateWidget(CreateWidgetRequest) returns (Widget);
  rpc GetWidget(GetWidgetRequest) returns (Widget);
  rpc ListWidgets(ListWidgetsRequest) returns (ListWidgetsReply);
  rpc UpdateWidget(UpdateWidgetRequest) returns (Widget);
  rpc DeleteWidget(DeleteWidgetRequest) returns (google.protobuf.Empty);
}
```

命名约定是固定的：

| 操作 | RPC 名 | 返回 |
|---|---|---|
| 创建 | `Create<Resource>` | 资源本身 |
| 读取 | `Get<Resource>` | 资源本身 |
| 列表 | `List<Resources>`（集合用复数） | `List<Resources>Reply` |
| 更新 | `Update<Resource>` | 资源本身 |
| 删除 | `Delete<Resource>` | `google.protobuf.Empty` |

**返回类型跟着 proto 声明走**，不要在 service 层自创一个包装。

然后生成：

```bash
make api
```

生成会产出 `*.pb.go`、`*_grpc.pb.go`、`*_http.pb.go`，以及更新 `openapi.yaml`。

**这些文件不要手改。** `AGENTS.md` 里把这条写成了硬规则，因为手改生成文件是那种"看起来能跑、下次生成就丢"的操作。

### 步骤 2：DO + repo 接口（biz）

```go
// internal/biz/widget.go
type Widget struct {
    ID        int64
    Name      string
    Status    int32
    CreatedAt int64
}
```

**注意这个结构体没有任何 proto 或存储标签。** 它是纯 Go。

```go
type WidgetRepo interface {
    Get(ctx context.Context, id int64) (*Widget, error)
    List(ctx context.Context, opts ...ListOption) ([]*Widget, error)
    Create(ctx context.Context, w *Widget) error
    Update(ctx context.Context, w *Widget) error
    Delete(ctx context.Context, id int64) error
}
```

`ListOption` 是 biz 自己提供的组合器（`ListFilter` / `ListOrderBy` / `ListOffset` / `ListLimit`），**让调用方不需要知道存储的查询语言**：

```go
widgets, err := uc.repo.List(ctx,
    biz.ListFilter("status = 1"),
    biz.ListOrderBy("created_at desc"),
    biz.ListLimit(20),
)
```

**这个"过滤表达式是字符串"的设计有一个取舍**：它对调用方很友好（不用学一个查询 DSL），但**它把表达式语法变成了一份隐式契约**——data 层必须理解 `biz.ListFilter` 的语法。

第 1 篇提过这个我做错过的例子：`routingclient.FindRoutingGroup` 拼了一个 `key = "..."` 的过滤字符串发给 channel-service。**那个语法是 AIP 的过滤语法，所以两边的实现要对齐。** 如果你的项目不用 AIP，第一天就该想清楚这个字符串的语法是什么。

### 步骤 3：repo 实现（data）

```go
// internal/data/widget.go
type widgetPO struct {
    ID        int64  `gorm:"primaryKey"`
    Name      string `gorm:"column:name"`
    Status    int32  `gorm:"column:status"`
    CreatedAt int64  `gorm:"column:created_at"`
}

func (widgetPO) TableName() string { return "widgets" }

func newWidget(w *biz.Widget) *widgetPO { /* DO → PO */ }
func toBizWidget(p *widgetPO) *biz.Widget { /* PO → DO */ }
```

**构造函数返回接口：**

```go
func NewWidgetRepo(d *Data) biz.WidgetRepo {
    return &widgetRepo{data: d}
}
```

**repo 从 `*Data` 拿客户端，不自己建连接。** `*Data` 是长生命周期存储客户端的持有者。

**driver 错误在这里翻译：**

```go
func (r *widgetRepo) Get(ctx context.Context, id int64) (*biz.Widget, error) {
    var po widgetPO
    if err := r.data.db.WithContext(ctx).First(&po, id).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, biz.ErrNotFound
        }
        return nil, err
    }
    return toBizWidget(&po), nil
}
```

### 步骤 4：service（DTO ↔ DO）

```go
type WidgetService struct {
    v1.UnimplementedWidgetServiceServer
    uc *biz.WidgetUsecase
}
```

**先嵌 `Unimplemented<Resource>ServiceServer`。** 这样以后 proto 加了新方法，老代码不会编译失败——**它会在运行时返回"未实现"，而不是在编译期炸掉。**

然后用 `convert<Resource>` 把请求转成 DO：

```go
func (s *WidgetService) CreateWidget(ctx context.Context, req *v1.CreateWidgetRequest) (*v1.Widget, error) {
    if req.GetName() == "" {
        return nil, errors.BadRequest("INVALID_ARGUMENT", "name is required")
    }
    w, err := s.uc.Create(ctx, &biz.Widget{Name: req.GetName()})
    if err != nil {
        return nil, err
    }
    return &v1.Widget{Id: w.ID, Name: w.Name, Status: w.Status}, nil
}
```

两条约定：

- **入参在 service 边界校验**（"name is required" 是格式问题，不是业务规则）；
- **返回方向内联构造**，因为返回类型是 proto 声明的那个，不需要单独一个转换函数。

**列表请求要按 AIP 解析。** 这是 `pkg/filtering` / `ordering` / `pagination` 那三个包存在的原因。

**部分更新用 `fieldmask.Update`。** 因为它要区分"这个字段没传"和"这个字段传了空值"——而 proto3 的标量字段默认值无法区分这两者。

### 步骤 5：Wire 装配

三处注册：

```go
// data.ProviderSet 加
NewWidgetRepo,

// biz.ProviderSet 加
NewWidgetUsecase,

// service.ProviderSet 加
NewWidgetService,
```

然后在 `internal/server` 里注册 HTTP/gRPC 服务。

**`cmd` 是唯一 import 所有层的地方。** 这个约束的意义是：**装配关系集中在一个地方，而各层之间互不认识。**

然后生成：

```bash
make wire
```

### 步骤 6：`make all` 收尾

```bash
make all   # api + config + generate
```

`AGENTS.md` 里的清单是六步，最后一步是"regenerate"。

**我建议把 `make verify` 加到最后一步**（第 1 篇讲过它串了架构检查、迁移检查、单元测试、race、前端）。因为架构检查会立刻告诉你"你是不是不小心让 biz import 了 data"。

---

## 4. 几个具体的坑

### 4.1 `make config` 和 `make api` 要分开

配置 proto 的生成不能带 OpenAPI 插件：

```yaml
# buf.gen.config.yaml
# Config generation must not invoke protoc-gen-openapi: the config-only
# target has no API paths and would otherwise overwrite the root spec.
plugins:
  - local: protoc-gen-go
  - local: protoc-gen-go-grpc
  - local: protoc-gen-go-http
```

**如果两个 target 用同一份 buf 模板，跑 `make config` 会把 `openapi.yaml` 覆盖成空的。** 我踩过这个。

### 4.2 生成文件的 proto 依赖要管住

`buf.gen.yaml` 的注释里有一句：

> 插件二进制由 make init / Dockerfile builder 预装到 PATH，与 go.mod 版本对齐。

**"与 go.mod 版本对齐"是关键。** 如果本地的 `protoc-gen-go-http` 版本和 CI 的不一样，生成的代码就会不同——**而生成文件是提交进仓库的，于是每次换机器提交都会产生大量 diff。**

做法是**固定工具版本**（`scripts/tool-versions.env` 就是这个用途），并且让 CI 用同一份。

### 4.3 `wireinject` build tag 的坑

Wire 的注入器文件带 build tag：

```go
//go:build wireinject
```

**所以普通的 `go build` 不会编译它。**

后果是：你在 `wire.go` 里引用了只在非 wireinject 下可见的 helper，本地 `go build` 全绿，跑 `wire` 生成时才炸。

第 1 篇讲的 `scripts/check-architecture.sh` 规则 10 就是为这个：

```bash
go test -tags wireinject ${wire_pkgs}
```

**第一天就该有这条检查**，因为它是那种"只有在跑生成命令时才发现"的错误。

### 4.4 JSON 序列化要统一

`AGENTS.md` 里那条规则值得第一天就立：

> 所有 JSON 序列化在业务代码里都走 `pkg/jsonx`。

**为什么？** 第 24 篇讲过：sonic 的默认配置和 `encoding/json` 有三处行为差异，其中"解码字符串共享输入缓冲区"那一条会导致**字符串在之后静默变化**的 bug。

统一到一个 wrapper 之后，这个风险就消失了。而统一的成本很低——就是多一层 import。

反过来说，**如果不统一，后面你会发现仓库里两种 JSON 行为并存，而且没人知道哪处是哪处。**

---

## 5. 我建议的顺序

如果把这篇压缩成一个开工顺序：

**第一天：**

1. 一个服务、一个 `go.mod`、一个 `biz` / `data` / `service` 目录结构
2. 一个资源走通全链路（proto → biz → data → service → wire）
3. 四条分层规则的检查脚本
4. `make api` / `make config` / `make wire` / `make verify`
5. 一个结构化 logger + `/healthz` + `/metrics`

**第一个月内：**

6. 第二个资源（验证这套结构是可复制的）
7. biz 的单元测试 + data 的存储层测试
8. 错误类型化收口

**需要的时候再加：**

9. Redis（记住留"单进程"注释）
10. 事件/Outbox
11. 多服务拆分（此时包边界已经清楚）
12. E2E、完整的可观测性、审计

---

## 6. 这套结构我愿意背的代价

诚实说一下这个结构的成本。

**第一，转换代码是重复的。** 每个资源要写 DTO↔DO 和 DO↔PO 的转换。一个 CRUD 资源大概多出几十行。

**第二，文件数变多。** 一个资源散在四个包里，找东西要跳几次。

**第三，小服务不值得。** 第 1 篇里我提过 `config-service` 只有 1619 行，给它一整套 `biz/data/service/server/conf` 加 Dockerfile 加 Makefile，维护成本相对体量偏高。

我仍然选择这套结构，是因为**第一个和第二个成本是"每次加资源固定付"，而收益是"每次改需求都在收"。**

具体说，收益体现在这些时刻：

- 换存储（加一个 repo 实现就行，biz 不动）；
- 写测试（fake repo，不用起数据库）；
- 加缓存（在 data 层包一层，biz 不知道）；
- 查一个行为（`data` 里没有业务规则，`biz` 里没有 SQL）。

**这四件事在项目的第二年会反复发生，而"多写几十行转换"只在第一天发生一次。**

---

## 7. 系列收尾

这是「micro-one-api 拆解」这一批 24 篇的最后一篇。

如果只留一句给未来的自己：

**先把依赖方向理清楚，再考虑拆服务、加中间件、做可观测性。** 因为依赖方向是唯一"越晚改越贵"的东西，而其他所有东西都是"需要的时候再加"。
