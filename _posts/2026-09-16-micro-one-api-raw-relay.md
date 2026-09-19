---
title: "透传：为什么 embeddings 不该被“翻译”，以及 29 个明确不支持的接口"
date: 2026-09-16T12:00:00+08:00
description: "做网关的时候我一开始的想法是“给每个上游接口写一个适配器”。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个反直觉的判断：不是所有接口都该被适配

做网关的时候我一开始的想法是"给每个上游接口写一个适配器"。

但列完接口清单之后我停住了。OpenAI 的接口可以明显分成两类：

**第一类：我需要理解它的语义。** `chat/completions`、`responses`、`messages`——这三个要参与协议转换、流式桥接、用量解析（那些是前几篇的主题）。

**第二类：我不需要理解它。** `embeddings`、`moderations`、`images/generations`、`audio/*`——这些的请求和响应格式我只需要原样转发。

对第二类写适配器的代价是什么？

**我要为每个接口维护一套结构体定义、一套转换逻辑、一套测试。** 而收益是零——因为上游返回什么我就返回什么，中间没有任何需要我理解的东西。

而且更糟的是：**每写一个适配器，我就多了一个可能与上游产生分歧的地方。** 上游加一个新字段，我的结构体不认识它，解码再编码就把它丢了（第 2 篇讲过这个坑）。

所以最终的设计是：**需要理解的走"编排路径"，不需要理解的走"透传路径"。**

这篇讲透传这条路——它的代码只有几十行，但里面有几个我认为值得说的决定。

---

## 1. 透传不是"什么都不做"

透传路径的第一版在我脑子里是"直接把请求转发出去"。实际写起来发现，**即使不转换内容，它仍然要承担网关的全部职责：**

- 鉴权（这个 token 有效吗、能不能用这个模型）；
- 选路（该走哪个渠道）；
- 预扣与结算（要收钱）；
- 重试与 failover（上游失败了要换）；
- 用量日志（要留下记录）。

所以 `handleRawRelay` 的骨架和 `chat/completions` 那条路径是**同一个骨架**，区别只在于"请求体怎么处理"和"响应体怎么处理"：

```go
func (s *HTTPServer) handleRawRelay(upstreamPath string, requireModel bool) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
            return
        }
        // ...鉴权、读 body
        clientModel := extractRawModel(body)
        if clientModel == "" {
            clientModel = defaultRawModel(upstreamPath)
        }
        if requireModel && clientModel == "" {
            s.writeError(w, http.StatusBadRequest, "model is required")
            return
        }

        plan, err := s.relayUsecase.Plan(r.Context(), relaybiz.RelayRequest{
            Token: token,
            Model: clientModel,
        })
        // ...选路、预扣、转发、结算
    }
}
```

**"透传"指的是内容不做协议转换，不指跳过网关的职责。** 这是我在写文档时特意区分的一点，因为"raw relay"这个名字容易让人以为它是一条旁路。

---

## 2. 那个 `requireModel` 参数：不是所有接口都有模型

注册路由的时候每个透传接口带一个布尔参数：

```go
s.handleFunc(srv, "/v1/completions", s.handleRawRelay("/completions", true))
s.handleFunc(srv, "/v1/embeddings", s.handleRawRelay("/embeddings", false))
s.handleFunc(srv, "/v1/images/generations", s.handleRawRelay("/images/generations", true))
s.handleFunc(srv, "/v1/audio/transcriptions", s.handleRawRelay("/audio/transcriptions", true))
s.handleFunc(srv, "/v1/audio/translations", s.handleRawRelay("/audio/translations", true))
s.handleFunc(srv, "/v1/audio/speech", s.handleRawRelay("/audio/speech", false))
s.handleFunc(srv, "/v1/moderations", s.handleRawRelay("/moderations", false))
```

`requireModel = true` 的意思是"这个接口的请求体里必须有 model 字段"。

为什么有的接口不需要？因为它们的模型是**由接口本身决定的**：

```go
func defaultRawModel(upstreamPath string) string {
    switch upstreamPath {
    case "/embeddings":
        return "text-embedding-ada-002"
    case "/moderations":
        return "text-moderation-latest"
    case "/audio/speech":
        return "tts-1"
    default:
        return ""
    }
}
```

**`/embeddings` 的默认模型是 `text-embedding-ada-002`。** 用户调 embeddings 的时候经常不写 model（因为确实只有一个可用的），如果我强制要求，就是在制造一个不必要的失败。

但这里有个问题：**如果用户不写 model，我拿什么去选路？**

答案是我用这个默认值去选路。这意味着：**我用 `text-embedding-ada-002` 去找"这个分组里有没有支持它的渠道"。**

而这带来一个我在测试时发现的边角情况：如果一个部署只配了 `text-embedding-3-small`，那么用户不写 model 的 embeddings 请求会选不到渠道——**尽管他写 `model: text-embedding-3-small` 就能用。**

这个行为我认为是对的（用户应该显式说要哪个模型），但它值得知道，因为报错会是"没有可用渠道"，看起来像配置问题而不是参数问题。

---

## 3. 透传里唯一不能透传的东西：模型名

虽然我说"原样转发"，但有一处必须改写：

```go
upstreamBody := rewriteRawModel(body, plan.ResolvedModel)
```

**因为模型名可能被映射过。**

第 2 篇讲过三层模型名（Client / Global / Resolved）。用户写 `gpt-4o`，可能全局映射成 `gpt-4o-2024-08-06`，然后渠道映射成 `azure-gpt4o`。**上游需要看到的是最后那个名字。**

所以透传路径也要做这一处字节级重写，而且重试时要从 `BaseModel()` 重算（第 3 篇讲的那个 failover 的坑）：

```go
currentResolvedModel := relaybiz.ResolveChannelModel(ch, plan.BaseModel()) // recompute from global model
retriedBody := rewriteRawModel(upstreamBody, currentResolvedModel)
```

**"透传"的准确含义是"不改结构，但改标识"。** 用户的请求体里除了 model 那一个字段，其他全部原样。

---

## 4. embeddings 的开销上限：一个我特意做的约束

这是我觉得透传路径里最值得讲的一个设计。

普通的透传请求，预扣时用的是估算 tokens（第 2 篇讲的 4 字符一个 token 的粗略估算）。但 embeddings 有一个特殊之处：**它的开销几乎完全由输入长度决定**，而输出是固定的小向量。

所以对 embeddings 我可以算出一个**可信的开销上限**：

```go
func embeddingCostBound(path string, channelType int32, model string, body []byte) routing.CostBound {
    empty := routing.CostBound{}
    if path != "/embeddings" || (channelType != provider.ChannelTypeOpenAI && channelType != provider.ChannelTypeAzure) {
        return empty
    }
    var fields map[string]jsonx.RawMessage
    if jsonx.Unmarshal(body, &fields) != nil {
        return empty
    }
    for key := range fields {
        switch key {
        case "model", "input", "user", "encoding_format", "dimensions":
        default:
            return empty
        }
    }
    // ...
}
```

**注意那个 key 白名单循环：请求体里只要出现一个不在白名单里的字段，这个函数就放弃。**

这是我加的保守规则。原因是：如果请求体里有我不认识的字段，我不知道它会不会显著改变开销（比如某个未来的参数让输入被放大）。**在有疑问的时候放弃算上限，退回普通估算。**

而返回的 `CostBound` 带着很严格的校验：

```go
func (b CostBound) Valid() bool {
    if b.Protocol != "openai_text_embeddings" || b.InputTokens <= 0 || b.InputTokens > 2_000_000 {
        return false
    }
    return b.UpstreamModel == "text-embedding-3-small" ||
        b.UpstreamModel == "text-embedding-3-large" ||
        b.UpstreamModel == "text-embedding-ada-002"
}
```

**协议名、token 上限、三个具体的模型名——全部是精确匹配。** 这是"白名单而不是黑名单"的写法：任何我没列出来的情况，`Valid()` 都返回 false，上限不生效，退回普通估算。

为什么要把上限限制得这么死？因为它是给**计费预备**用的（`domain/routing/cost_bound.go` 的注释说明了这一点）：

> CostBound is produced by a trusted protocol adapter, never decoded from a public request as billing authority.

**"never decoded from a public request"** —— 这个上限只能由可信的转换层产出，不能从用户的请求里读出来。否则用户就能通过伪造一个字段来影响自己的计费。

**这条约束的意义在于：它让计费侧可以信任这个数字，而不必再去怀疑它的来源。**

---

## 5. 明确不支持的接口：29 个注册点

除了透传和编排，还有第三类：**我明确不支持的接口。**

它们是这样注册的：

```go
s.handleFunc(srv, "/v1/files", s.handleUnsupportedOpenAIRoute("files"))
s.handlePrefix(srv, "/v1/files/", http.HandlerFunc(s.handleUnsupportedOpenAIRoute("files")))
s.handleFunc(srv, "/v1/fine-tunes", s.handleUnsupportedOpenAIRoute("fine-tunes"))
// ...一共 29 处注册
```

处理函数很短：

```go
func (s *HTTPServer) handleUnsupportedOpenAIRoute(feature string) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        s.writeJSON(w, http.StatusNotImplemented, map[string]any{
            "error": map[string]any{
                "message": fmt.Sprintf("%s is not implemented", feature),
                "type":    "one_api_not_implemented",
                "param":   nil,
                "code":    "not_implemented",
            },
        })
    }
}
```

三个设计点：

**第一，用 501 而不是 404。**

`404` 的意思是"这个路径不存在"。但对 `/v1/files` 来说，路径是存在的，只是我没实现。**501 Not Implemented 精确地表达了这个区别。**

为什么要在意这个区别？因为调用方的处理方式不同：

- 404 可能是"版本不对、地址写错了"；
- 501 是"这个功能这里没有"。

**第二，返回 OpenAI 形状的错误体。**

```json
{
  "error": {
    "message": "files is not implemented",
    "type": "one_api_not_implemented",
    "param": null,
    "code": "not_implemented"
  }
}
```

字段名（`error.message` / `error.type` / `error.code`）和 OpenAI 一致，所以 SDK 能正常解析它。**区别在于 `type` 是我的自定义值 `one_api_not_implemented`**，这样调用方能明确区分"是网关不支持"还是"上游报错"。

**第三，前缀注册。**

```go
s.handleFunc(srv, "/v1/files", s.handleUnsupportedOpenAIRoute("files"))
s.handlePrefix(srv, "/v1/files/", http.HandlerFunc(s.handleUnsupportedOpenAIRoute("files")))
```

**两行都要写。** 一行管 `/v1/files`，一行管 `/v1/files/abc123`。

如果只写第一行，那 `/v1/files/abc123` 会返回 **404 而不是 501**——调用方会以为路径写错了，而不是功能没实现。**这个不一致我自己踩过一次**，因为当时以为"注册了 `/v1/files` 就够了"。

为什么注册而不是让它们自然 404？

**因为"不支持"是一种需要被明确声明的能力。** 让一个路径自然 404，和"我明确告诉你我没实现这个"，对调用方来说是完全不同的信息。而且如果哪天我实现了 `files`，它会替换掉这一行——**注册表就是这个功能的开关。**

29 个注册点分几类：

| 类别 | 例子 |
|---|---|
| 文件与微调 | `files`、`fine-tunes`、`fine_tuning/jobs`、`uploads` |
| 批处理与评估 | `batches`、`evals`、`graders` |
| 助手生态 | `assistants`、`threads`、`conversations` |
| 向量与容器 | `vector_stores`、`containers` |
| 实时 | `realtime/` |
| 旧接口 | `engines`、`edits` |

**这张表本身就是一份"我支持什么"的声明。** 看 `routes.go` 就能知道这个网关的能力边界，不需要去猜。

---

## 6. 透传路径的代价

诚实说一下这条路的缺点。

### 6.1 用量只能从响应里现场解析

编排路径的用量来自结构化解析（第 2 篇讲的 `UsageEnvelope`），而透传路径只能从响应体里现场读：

```go
usage = extractCanonicalUsage(rawResp.Body, plan)
```

这不一定是问题——`extractCanonicalUsage` 也是从响应解析的。但它的**输入是原始字节，没有协议适配器保证它长什么样**。所以它的健壮性依赖于解析器的宽容度。

### 6.2 模型级的健康数据是空的

第 4 篇讲过被动模型健康监测按 `(source_kind, source_id, model_id, upstream_model_id)` 记录。而透传路径**没有走那个统一的执行器**，所以它不记录模型健康。

也就是说：**如果 `embeddings` 在某个渠道上一直失败，模型健康看板上看不到。** 这和第 4 篇里提过的 `subscription_account` 路径需要单独补记录是同一类问题——**每条不走统一执行器的路径，都要自己记得记录观测数据。**

我在这条路径上补了 `RecordChannelUsage`（渠道级），但没有补模型级。这是一处已知的不一致。

### 6.3 白名单式的端点列表需要维护

每次 OpenAI 出新端点，我有两个选择：加一行透传、或者加一行"不支持"。

**默认状态是 404**（两条都没加的时候）。所以如果 OpenAI 出了新接口而我不知道，用户会收到 404——**这和"我知道但没实现"（501）在调用方看来是不同的**，但用户分不出来。

如果能有一个"所有 `/v1/*` 的兜底 501"，这个问题就不存在了。但那样会把路由匹配变得更复杂（前缀匹配的优先级问题），我还没做。

---

## 7. 现在的状态和欠账

**已经能用的：**

- 透传路径承担完整的网关职责（鉴权、选路、预扣、结算、重试、日志），只是不做协议转换
- 7 个透传端点，`requireModel` 区分"接口自带模型"和"必须指定模型"
- 三个端点的默认模型（embeddings / moderations / audio speech）
- 透传只重写 model 字段，其余字节原样
- embeddings 的 `CostBound`：字段白名单 + 精确的协议/模型校验，任何不确定都放弃上限
- `CostBound` 只能由可信转换层产出，不从公开请求读取
- 29 个明确不支持的接口，注册为 501 + OpenAI 形状错误体，含前缀变体

**还没解决的：**

**第一，透传路径不记录模型级健康。** 只有渠道级用量。同一个渠道上某个 embedding 模型持续失败，看板看不见。

**第二，不写 model 的 embeddings 请求只能匹配固定默认模型。** 部署只配了 `text-embedding-3-small` 时，不写 model 的请求会选不到渠道，而报错是"没有可用渠道"，容易误判成配置问题。

**第三，端点清单靠人工维护。** OpenAI 新增接口时默认是 404 而不是 501。缺一个"未知 `/v1/*` 返回 501"的兜底。

**第四，透传路径没有端到端测试覆盖。** 它复用编排路径的鉴权/计费/重试逻辑，但那些逻辑的测试是按编排路径写的。透传特有的部分（默认模型、模型重写、上限计算）测试是有的，但完整链路的 E2E 我没有。

**第五，`CostBound` 只覆盖 embeddings。** 其他透传端点（audio、images、moderations）没有开销上限，只能用粗略估算。audio 按时长计费、images 按尺寸和张数计费，理论上都能算出上限，但我还没做。

---

## 8. 下一篇

下一篇讲订阅的账务语义：续费、退款、冲正这三种操作在一个 append-only 的账本上分别该怎么记，以及"已售出的套餐配置被改了"这件事我是怎么处理的。

[《订阅账务：续费、退款、冲正，以及“已售出的套餐被改了”怎么办》](/2026-09-17-micro-one-api-accounting-semantics/)
