---
title: "一个适配器怎么覆盖二十家 provider：上游接入的三种形态和两条边界"
date: 2026-09-16T12:00:00+08:00
description: "接上游 provider 这件事，我一开始以为是“一家一个适配器”。写了才发现不是：三十多个渠道类型里，真正需要单独写协议转换逻辑的只有四家，其余二十多家全是同一个适配器的不同配置。"
tags: ["Micro-One-API", "Go", "Kratos", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 先说结论：只有四家需要真正写代码

接上游 provider 这件事，我一开始以为是"一家一个适配器"。写了才发现不是：三十多个渠道类型里，**真正需要单独写协议转换逻辑的只有四家**，其余二十多家全是同一个适配器的不同配置。

这个结论是我迭代了两轮才形成的：

- 第一轮：按 provider 名写 switch 分支，越写越长；
- 第二轮：把"协议差异"和"端点差异"分开，协议差异才需要代码，端点差异只需要一张表。

这篇讲这个拆分，以及我在做这件事时踩到的两条边界——**SSRF 防护**和**流式超时**。这两条跟协议转换无关，但都属于"接了外部地址之后必须处理"的问题，而且我都做错过。

---

## 1. 第一步：把"协议差异"和"端点差异"分开

### 1.1 第一版的 switch

最早的 provider 工厂就是一个类型分支：

```go
func (f *ProviderFactory) CreateProviderWithConfig(channelType int32, baseURL, apiKey string, config ProviderConfig) (Provider, error) {
    switch channelType {
    case ChannelTypeAnthropic:
        return NewAnthropicProvider(baseURL, apiKey, f.defaultTimeout)
    case ChannelTypeGemini:
        return NewGeminiProvider(baseURL, apiKey, f.defaultTimeout)
    case ChannelTypeAzure:
        if baseURL == "" {
            return nil, fmt.Errorf("azure channel requires base_url")
        }
        return NewAzureProvider(baseURL, apiKey, config.APIVersion, f.defaultTimeout)
    // ...这里我原本一家写一个 case
    }
}
```

写到第十家的时候我意识到：**DeepSeek、Moonshot、Groq、Tongyi、Zhipu、SiliconFlow、Doubao 这些的分支体是完全一样的**，都是 `NewOpenAIProvider(baseURL, apiKey, timeout)`，唯一的区别是 baseURL 怎么算。

所以把它们合并成一段：

```go
case ChannelTypeOpenAI,
    ChannelTypeDeepSeek,
    ChannelTypeMistral,
    ChannelTypeMoonshot,
    ChannelTypeGroq,
    ChannelTypeCohere,
    ChannelTypeBaichuan,
    ChannelTypeZhipu,
    ChannelTypeTongyi,
    ChannelTypeMinimax,
    ChannelTypeTogether,
    ChannelTypeFireworks,
    ChannelTypePerplexity,
    ChannelTypeNovita,
    ChannelTypeOpenRouter,
    ChannelTypeSiliconFlow,
    ChannelTypeDoubao:
    return NewOpenAIProvider(ResolveOpenAICompatibleBaseURL(channelType, baseURL), apiKey, f.defaultTimeout)
```

判断标准很简单：**如果一个 provider 的差异只体现在"往哪个 URL 发"，那它就不是一个适配器，只是一行配置。**

### 1.2 端点差异做成一张表

于是有了这张表：

```go
func ResolveOpenAICompatibleBaseURL(channelType int32, baseURL string) string {
    if baseURL != "" {
        return baseURL
    }
    switch channelType {
    case ChannelTypeOpenAI:
        return "https://api.openai.com/v1"
    case ChannelTypeDeepSeek:
        return "https://api.deepseek.com/v1"
    case ChannelTypeMoonshot:
        return "https://api.moonshot.cn/v1"
    case ChannelTypeGroq:
        return "https://api.groq.com/openai/v1"
    case ChannelTypeCohere:
        return "https://api.cohere.com/compatibility/v1"
    case ChannelTypeZhipu:
        return "https://open.bigmodel.cn/api/paas/v4"
    case ChannelTypeTongyi:
        return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case ChannelTypePerplexity:
        return "https://api.perplexity.ai"
    case ChannelTypeNovita:
        return "https://api.novita.ai/v3/openai"
    case ChannelTypeOpenRouter:
        return "https://openrouter.ai/api/v1"
    case ChannelTypeSiliconFlow:
        return "https://api.siliconflow.cn/v1"
    case ChannelTypeOllama:
        return "http://localhost:11434/v1"
    case ChannelTypeDoubao:
        return "https://ark.cn-beijing.volces.com/api/v3"
    // ...
    default:
        return "https://api.openai.com/v1"
    }
}
```

表里有几个值值得看：

- **Cohere** 用的是 `/compatibility/v1`，不是它自己的原生协议路径——它提供了 OpenAI 兼容层。
- **Zhipu** 是 `/api/paas/v4`，路径里没有 `/v1`，跟 OpenAI 的习惯不一样。
- **Perplexity** 是 `https://api.perplexity.ai` 而且**带不带 `/v1` 都行**，我按官方文档写的是不带。
- **Ollama** 是 `http://localhost:11434/v1`，注意是 **http + localhost**，这条后面会引出一个安全边界问题。
- **Doubao**（火山方舟）是 `/api/v3`。

`if baseURL != "" { return baseURL }` 在最前面，所以**渠道上配了 base_url 就以配置为准**，表只是默认值。代理部署、私有化部署都靠这一行。

**这张表里没有 key。** 这是我刻意维持的：默认端点可以硬编码，凭证永远只能来自渠道配置。

### 1.3 没实现的就明确报错，不要 fallback

`default` 分支是返回 OpenAI 的默认地址，也就是"未知类型按 OpenAI 兼容处理"。这是有意的宽容——新 provider 只要兼容就能直接接上。

但**已知需要原生适配器、而我还没写的那些，必须显式报错**：

```go
case ChannelTypeHunyuan,
    ChannelTypeXingchen,
    ChannelTypeBedrock,
    ChannelTypeCloudflare,
    ChannelTypeVertexAI,
    ChannelTypeReplicate,
    ChannelTypeBaidu,
    ChannelTypeXunfei:
    return nil, fmt.Errorf("channel type %d requires a native provider adapter", channelType)
```

这八个（腾讯混元、讯飞星火、AWS Bedrock、Cloudflare、Vertex AI、Replicate、百度、讯飞）的协议跟 OpenAI 差得比较远，不能靠换 URL 解决。如果不显式拦住，`default` 会把它们当 OpenAI 兼容处理，**请求会带着一个错的 URL 发出去，然后返回一个让人完全看不懂的上游错误**。

我宁可在选到渠道的时候就报"这个类型需要原生适配器"，也不要在转发阶段收到一个玄幻的 404。

---

## 2. 第二步：加一层 adaptor，但只给需要的入口

### 2.1 为什么会有第二套抽象

现在项目里有两个上游抽象并存：

| | `provider.Provider` | `adaptor.Adaptor` |
|---|---|---|
| 位置 | `domain/upstream/provider` | `internal/adaptor` |
| 方法 | `ChatCompletions` / `ChatCompletionsStream` / `Forward` / `ForwardStream` | `ConvertRequest` / `BuildUpstreamRequest` / `ConvertResponse` / `ConvertStreamResponse` |
| 输入 | 强类型结构体 或 原始字节 | 统一的 `RelayContext` |
| 谁在用 | 老的直连路径 | `/v1/messages` 的 API-key 路径、订阅账号路径 |

`adaptor` 包的头部注释把这个定位写清楚了：

```go
// Package adaptor provides the unified upstream adapter abstraction for the
// relay gateway.
//
// It mirrors the design of new-api's relay/channel/adapter.go: each upstream
// (an API-key channel or a subscription account) is represented by an Adaptor
// that is responsible for converting the inbound client protocol into the
// upstream protocol, building the final http.Request (including any identity
// mimicry), and converting the upstream response back to the client's expected
// outbound protocol.
//
// The /v1/messages API-key path uses this layer as its only protocol bridge;
// routing, retries and quota accounting remain in internal/server. Other
// entry points can migrate independently without duplicating conversions.
```

最后一句是关键：**"其他入口可以独立迁移，不用重复转换逻辑"。**

我不打算一次性把四个入口都搬过去。`/v1/messages` 先搬，因为它最需要（Anthropic 入口到 OpenAI 上游的转换最复杂）。这样这一层的设计错了也只影响一个入口。

### 2.2 注册表：二十家一个大循环

```go
func init() {
    // OpenAI-compatible family (20+ types). They all resolve to an
    // OpenAIProvider and share the same adaptor shape.
    for _, t := range []int32{
        provider.ChannelTypeOpenAI,
        provider.ChannelTypeClaude,
        provider.ChannelTypeDeepSeek,
        // ...二十多个
        provider.ChannelTypeVoyageAI,
    } {
        Register(t, func() Adaptor {
            return &lazyAdaptor{
                kind:   "openai_compatible",
                ctor:   func(ctx *RelayContext) (provider.Provider, error) { return providerFor(ctx) },
                models: func(ctx *RelayContext) []string { return modelsFor(ctx) },
                build: func(p provider.Provider, models []string) Adaptor {
                    return NewOpenAICompatibleAdaptor(p, models)
                },
            }
        })
    }
    // ...
}
```

跟工厂那张 switch 表一样：**一个循环注册二十多个类型，因为它们共享同一个适配器形状。**

`Register` 是 last-write-wins 的：

```go
// Register registers a factory for a channel type. It is safe to call from
// init() across packages. Registering the same type twice overwrites the
// previous entry (last-write-wins), matching new-api's GetAdaptor behavior.
```

### 2.3 lazyAdaptor：注册时不建连接

注册进去的是一个 `lazyAdaptor`，它在 `Init(ctx)` 之前什么都不做：

```go
// lazyAdaptor defers provider construction until Init is called with a
// RelayContext. This lets the registry hand out cheap zero-state adaptor
// instances and only pay the provider-construction cost when a real relay
// context is available.
```

**插件注册表里存的是"怎么造"，不是"造好的对象"。** 这样注册阶段就是往 map 里塞函数，没有副作用，也不用在启动时把三十多个 provider 全建出来。

如果 `Init` 时构造 provider 失败，它不会崩，而是换成一个把所有方法都报同一个错的实现：

```go
func (l *lazyAdaptor) Init(ctx *RelayContext) {
    p, err := l.ctor(ctx)
    if err != nil {
        l.inner = &errorAdaptor{kind: l.kind, err: err}
        return
    }
    // ...
}
```

因为 Go 的接口没法返回错误，这种"把错误变成对象"的写法是常见解法。好处是**错误在第一次调用时带着上下文抛出来**，而不是在 `Init` 时被吞掉。

### 2.4 `RelayContext`：把散落的参数收成一个

```go
type RelayContext struct {
    InboundFormat Format      // 客户端进来的协议
    ClientModel   string      // 客户端请求的模型名
    ResolvedModel string      // 映射后的上游模型名
    Channel       *ChannelRef // API-key 渠道（订阅账号时为 nil）
    Account       *AccountRef // 订阅账号（API-key 渠道时为 nil）
    IsStream      bool
    UserID        int64
    RequestID     string
    RawBody       []byte      // 客户端原始请求体

    // InboundHeader is the client's original request headers. OAuth adaptors use
    // it to detect genuine first-party clients (so mimicry is only applied to
    // third-party callers) and to forward client-specific headers. API-key
    // adaptors ignore it.
    InboundHeader http.Header
    HTTPClient    *http.Client
}
```

`InboundHeader` 那个字段的注释说明了为什么它必须传进来：OAuth 适配器要判断"这个请求是不是官方客户端发的"，来决定要不要做身份伪装。这个判断只能靠客户端的原始请求头。

`Channel` 和 `Account` 是**互斥**的，注释也写明了。这个设计直接来自第 2 篇讲过的那个约束——订阅账号的 access token 不能进 `Channel.Key`。

---

## 3. 四个真正需要写代码的适配器

### 3.1 OpenAI-compatible（覆盖二十多家）

```go
func (a *OpenAICompatibleAdaptor) GetUpstreamURL(ctx *RelayContext) (string, error) {
    if ctx == nil || ctx.Channel == nil {
        return "", fmt.Errorf("openai_compatible adaptor: channel is required")
    }
    base := provider.ResolveOpenAICompatibleBaseURL(ctx.Channel.Type, ctx.Channel.BaseURL)
    return strings.TrimRight(base, "/") + "/chat/completions", nil
}
```

请求转换是"能直通就直通"：

```go
// ConvertRequest bridges the inbound client format to Chat Completions.
func (a *OpenAICompatibleAdaptor) ConvertRequest(rc *RelayContext, inbound Format, body []byte) (Format, []byte, error) {
    return convertRequestToChat(rc, inbound, body)
}
```

`convertRequestToChat` 在入站协议已经是 Chat Completions 时原样返回；是 Responses 或 Messages 时才走 `apicompat` 的转换（那块是既有文章的主题）。

### 3.2 Anthropic：三处差异

```go
func (a *AnthropicAdaptor) BuildUpstreamRequest(ctx context.Context, rc *RelayContext, _ Format, body []byte) (*http.Request, error) {
    // ...
    req.Header.Del("x-api-key")
    if key := apiKeyFromContext(rc); key != "" {
        req.Header.Set("x-api-key", key)
    }
    req.Header.Set("anthropic-version", "2023-06-01")
    // ...
}
```

三处必须和 OpenAI 不一样：

1. **鉴权头是 `x-api-key`，不是 `Authorization: Bearer`**；
2. **必带 `anthropic-version`**，我把版本固定成 `2023-06-01`；
3. **不能带 `Authorization`**（先 `Del` 掉），否则上游可能因为同时存在两套凭证而报错。

第 3 点是我吃过亏的：从客户端透传过来的头里可能带着 `Authorization`，如果不显式删掉，就会出现"两套鉴权头同时存在"的请求。

### 3.3 Azure：两点都不一样

Azure 的差异比 Anthropic 更大：

```go
func (a *AzureAdaptor) BuildUpstreamRequest(ctx context.Context, rc *RelayContext, _ Format, body []byte) (*http.Request, error) {
    // ...
    req.Header.Set("Content-Type", "application/json")
    if key := apiKeyFromContext(rc); key != "" {
        req.Header.Set("api-key", key)
    }
    req.Header.Del("Authorization")
    return req, nil
}
```

- 鉴权头是 **`api-key`**（第三个名字了）；
- 端点路径是**按 deployment 拼的**，而且 deployment 名就是模型名：

```go
// GetUpstreamURL returns the Azure deployment chat/completions endpoint. The
// deployment name is taken from the resolved model; the api-version query is
// appended unless the configured base URL already carries one.
func (a *AzureAdaptor) GetUpstreamURL(ctx *RelayContext) (string, error) {
    deployment := ""
    if ctx != nil {
        deployment = ctx.ResolvedModel
    }
    if deployment == "" {
        return "", fmt.Errorf("azure adaptor: resolved model (deployment) is required")
    }
    // ...
    u.Path = strings.TrimRight(basePath, "/") + "/deployments/" + url.PathEscape(deployment) + "/chat/completions"
    if query.Get("api-version") == "" {
        query.Set("api-version", v)
    }
    // ...
}
```

注意 `url.PathEscape(deployment)`。deployment 名来自模型名，是**用户可控的输入**。不转义的话，一个名字里带 `/` 或 `..` 的模型就能把请求路径改到别的地方去。这一行是路径穿越防护，不是风格问题。

还有 `api-version` 的处理：配置的 base_url 里已经带了就不覆盖。因为不同 Azure 部署的 API 版本不一样，我不该替使用者做决定。

### 3.4 Gemini：唯一自带协议的

Gemini 的 inbound/outbound 格式在 adaptor 层有自己的常量：

```go
const (
    FormatOpenAIChatCompletions Format = "chat_completions"
    FormatOpenAIResponses       Format = "responses"
    FormatAnthropicMessages     Format = "anthropic_messages"
    FormatGemini                Format = "gemini"
)
```

**`FormatGemini` 是这个枚举里唯一一个"上游专属"的格式。** 另外三个都是客户端协议。这意味着 Gemini 渠道的转换是双向的：客户端协议 → Gemini 协议 → 客户端协议。

这也是"协议转换矩阵"里最重的一格，属于既有文章的范围，这里只标出它的存在。

---

## 4. 顺带一提：两套上游接口是为什么

`provider.Provider` 有四个方法：

```go
type Provider interface {
    ChatCompletions(ctx context.Context, req *ChatCompletionsRequest) (*ChatCompletionsResponse, error)
    ChatCompletionsStream(ctx context.Context, req *ChatCompletionsRequest) (<-chan StreamChunk, error)
    Forward(ctx context.Context, req *RawRequest) (*RawResponse, error)
    ForwardStream(ctx context.Context, req *RawRequest) (*RawStreamResponse, error)
}
```

前两个是**强类型**的：请求和响应都是结构体，走的是"我认识这个协议"的路子。

后两个是**原始字节透传**的：`RawRequest` 只有方法、路径、头、body，`RawResponse` 只有状态码、头、body。

这两套并存，是因为 relay 的接口分成了两类（第 2 篇提过）：

| 类型 | 例子 | 处理方式 |
|---|---|---|
| 需要理解协议的 | chat/completions、responses、messages | 强类型路径 + 协议转换 |
| 原样透传的 | embeddings、moderations、images、audio | raw 路径，只做鉴权+计费+转发 |

raw 路径存在的意义是：**新接口不需要等我写一个适配器就能用。** OpenAI 出了一个新端点，只要它是 OpenAI 兼容的，走 raw 路径就能立刻转发。

代价是 raw 路径拿不到结构化信息，用量统计只能从响应体里现场解析——这一条我在第 2 篇里讲过。

---

## 5. 边界一：接外部地址就要防 SSRF

这是我做的两条和安全直接相关的处理，跟协议转换无关但绕不开。

### 5.1 为什么需要它

渠道的 `base_url` 是**管理员配置的、由我发起请求去访问的地址**。如果不管，一个恶意或被误配的 base_url 就能让我去访问内网地址：

```
base_url = http://169.254.169.254/latest/meta-data/   # 云元数据
base_url = http://10.0.0.5:6379/                        # 内网 Redis
base_url = http://127.0.0.1:9004/                       # 我自己的 billing gRPC 端口
```

第三种最要命——网关自己去打自己的内部服务。这类问题统称 SSRF。

### 5.2 检查放在拨号层，而不是 URL 校验层

我第一版的思路是校验 URL 字符串：如果是 `localhost`、`127.0.0.1`、`10.` 开头就拦掉。

这个思路有个洞：**域名可以在校验之后解析到另一个 IP。** 攻击者控制一个域名，第一次解析返回公网 IP（通过校验），第二次返回内网 IP（实际连接）。这叫 DNS rebinding。

所以我把它做到了拨号层：

```go
// NewHTTPClient returns the standard non-streaming upstream client. DNS is
// resolved and checked on every new connection, then the approved IP is
// dialled directly so a second DNS lookup cannot rebind the destination.
func NewHTTPClient(timeout time.Duration) *http.Client {
    return newHTTPClient(timeout, false)
}
```

```go
func (d *ssrfSafeDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
    host, port, err := net.SplitHostPort(address)
    // ...
    ips, err := d.lookupIP(ctx, host)
    // ...
    allowLocal := d.allowLocal || localNetworkAccessAllowed(ctx) || os.Getenv("PROVIDER_DISABLE_SSRF_CHECK") == "true"
    for _, resolved := range ips {
        if !allowLocal && isPrivateOrReservedIP(resolved.IP) {
            return nil, fmt.Errorf("upstream host resolves to private/reserved IP: %s", resolved.IP)
        }
    }
    var dialErrors []error
    for _, resolved := range ips {
        conn, dialErr := d.dialContext(ctx, network, net.JoinHostPort(resolved.IP.String(), port))
        if dialErr == nil {
            return conn, nil
        }
        dialErrors = append(dialErrors, dialErr)
    }
    return nil, fmt.Errorf("dial approved upstream addresses: %w", errors.Join(dialErrors...))
}
```

关键就是**"我解析、我检查、我再拿这个 IP 去连"**。连接用的是已经检查过的 IP，DNS 不会在中间再被查一次。

顺带处理了两件事：

**代理被显式关掉了：**

```go
// A forward proxy resolves the ultimate target outside this process and
// would bypass the dial-time IP check. Provider traffic therefore connects
// directly; operators should enforce egress policy at the network layer.
transport.Proxy = nil
```

`http.Transport` 默认会读 `HTTP_PROXY` 环境变量。如果走了正向代理，**代理会替我做 DNS 解析和连接**，我在拨号层的检查就完全绕过了。所以我把它置空，并在注释里写明"出口管控请在网络层做"。

**重定向也要检查：**

```go
func upstreamRedirectPolicy(allowLocal bool) func(*http.Request, []*http.Request) error {
    return func(req *http.Request, _ []*http.Request) error {
        if allowLocal || localNetworkAccessAllowed(req.Context()) || os.Getenv("PROVIDER_DISABLE_SSRF_CHECK") == "true" {
            return validateBaseURLAllowLocal(req.URL.String())
        }
        if err := validateBaseURL(req.URL.String()); err != nil {
            return fmt.Errorf("unsafe upstream redirect: %w", err)
        }
        return nil
    }
}
```

因为只检查第一次请求是不够的——上游返回一个 302 指向内网，跟直接配内网地址是同一个效果。

### 5.3 私有地址怎么判定

```go
func isPrivateOrReservedIP(ip net.IP) bool {
    addr, ok := netip.AddrFromSlice(ip)
    if !ok {
        return true                    // 解析不出来 → 当作不安全
    }
    addr = addr.Unmap()                // ::ffff:10.0.0.1 要还原成 IPv4 判断
    if !addr.IsGlobalUnicast() || addr.IsPrivate() || addr.IsLoopback() ||
        addr.IsLinkLocalUnicast() || addr.IsUnspecified() {
        return true
    }
    for _, prefix := range nonPublicPrefixes {
        if prefix.Contains(addr) {
            return true
        }
    }
    return false
}
```

两个细节：

- **`Unmap()` 是必须的。** IPv4-mapped IPv6 地址（`::ffff:10.0.0.1`）如果不还原，`IsPrivate()` 判断不出来，一个内网地址就能伪装成 IPv6 过检。
- **解析失败按"不安全"处理**（`return true`），默认拒绝。

### 5.4 Ollama 的例外：我改了构造函数而不是关全局开关

Ollama 是自托管服务，默认地址就是 `http://localhost:11434/v1`。这个地址**必然**会被 SSRF 检查拦掉。

最省事的做法是给一个环境变量全局关掉检查：

```go
os.Getenv("PROVIDER_DISABLE_SSRF_CHECK") == "true"
```

这个开关确实存在，但我没用它来支持 Ollama，因为**它是全局的**——一旦打开，所有渠道的内网访问都不再受保护。

我改成了给 Ollama 一个专门的构造函数：

```go
case ChannelTypeOllama:
    // domain-M2: Ollama is a self-hosted provider whose default endpoint is
    // loopback (http://localhost:11434/v1) and realistic deployments are on a
    // private network. The strict SSRF check would reject these, making the
    // advertised Ollama channel type impossible to use without the global
    // PROVIDER_DISABLE_SSRF_CHECK escape hatch (which disables protection for
    // ALL channels). Use the allow-local constructor instead.
    return NewOpenAIProviderAllowLocal(ResolveOpenAICompatibleBaseURL(channelType, baseURL), apiKey, f.defaultTimeout)
```

**例外要精确到类型，不能用全局开关换便利。** 全局开关一旦存在，实际使用中就会有人为了接一个内网渠道把它打开，然后所有人的 SSRF 防护一起消失。

### 5.5 顺带一个内存边界

上游的**成功**响应体也要有上限：

```go
// MaxUpstreamResponseBody caps how many bytes of an upstream *success*
// response body the relay will buffer into memory. 128MB mirrors the
// inbound request cap (64MB) with headroom for large model outputs; an
// upstream exceeding this is treated as malformed (relay-C1: unbounded
// io.ReadAll previously allowed a hostile/buggy upstream to OOM the gateway).
const MaxUpstreamResponseBody = 128 * 1024 * 1024
```

```go
respBody, err := io.ReadAll(io.LimitReader(resp.Body, MaxUpstreamResponseBody))
```

之前是裸的 `io.ReadAll`。一个故意返回无限流的畸形上游，或者一个卡住不结束的响应，就能把这个网关的进程内存吃光。**我只在入站方向做了 64MB 的限制，忘了出站方向也是别人控制的。**

`io.LimitReader` 而不是 `MaxBytesReader`，是因为这里没有 `http.ResponseWriter` 可以拿——它是出站方向。

---

## 6. 边界二：流式请求不能设 Client.Timeout

### 6.1 为什么非流式和流式要用两个客户端

`http.Client.Timeout` 是**整个往返的硬截止时间，包含读 body 的时间**。对一个 SSE 长连接来说，这个语义直接是错的：

```go
// domain-H3: the streaming client has NO Client.Timeout. http.Client.Timeout
// is a hard deadline covering the entire round trip including response-body
// reads, so it would kill an SSE stream mid-flight once the configured
// timeout elapsed regardless of whether bytes were still flowing. The custom
// client instead applies the timeout to response headers and idle periods.
streamClient: newStreamHTTPClient(timeout),
```

一个正常跑 10 分钟、期间一直在吐字的流式回答，如果 `Client.Timeout = 60s`，就会在第 60 秒被硬切断——**而且不是在"卡住了"的时候切断，是在"一切正常"的时候切断。**

所以我给流式单独做了一个客户端：

- **没有 `Client.Timeout`**；
- 超时只作用在**响应头等待**和**两次数据之间的空闲**上。

### 6.2 空闲超时用滑动窗口

```go
// newStreamHTTPClient builds a client without http.Client.Timeout (which would
// impose a hard deadline on an otherwise healthy long-lived SSE response).
// Instead, the transport bounds the response-header wait and wraps successful
// response bodies with a sliding idle timeout that resets whenever bytes arrive.
```

```go
func (r *streamIdleReadCloser) Read(p []byte) (int, error) {
    n, err := r.body.Read(p)
    if n > 0 {
        r.touch()
    }
    if err != nil && r.timedOut.Load() {
        return n, fmt.Errorf("%w after %s", ErrStreamIdleTimeout, r.idleTimeout)
    }
    return n, err
}
```

每读到字节就重置计时器。**"卡住 60 秒"才判定超时，"总共跑了 10 分钟但一直在吐字"不算超时。**

### 6.3 一个并发细节

`watch` 循环里有一段我特意写的处理：

```go
case <-timer.C:
    // Prefer already-buffered activity over a simultaneous timer firing.
    select {
    case <-r.activity:
        resetStreamIdleTimer(timer, r.idleTimeout)
        continue
    default:
    }
    r.timedOut.Store(true)
    _ = r.closeBody()
    return
```

计时器和"有新数据"同时就绪时，**优先认为有新数据**。

因为 Go 的 `select` 在多个 case 同时就绪时是随机选的。如果随机到了 `timer.C` 而刚好有字节到达，一个健康的流会被误判成超时。多查一次 `activity` 通道（非阻塞）就能把这个竞态消掉。

`touch` 用的是非阻塞发送，也是同一个目的：数据到达路径不能因为通道满了而卡住：

```go
func (r *streamIdleReadCloser) touch() {
    select {
    case r.activity <- struct{}{}:
    default:
    }
}
```

通道容量是 1，所以只要有一个"待处理的活跃信号"就够了，不需要排队。

---

## 7. 想接一家新 provider 要做什么

按现在的结构，分三种情况。

**情况一：OpenAI 兼容。** 加一个 `ChannelType*` 常量，把默认 baseURL 加进 `ResolveOpenAICompatibleBaseURL`，把类型加进工厂的兼容组和 adaptor 的注册循环。**不用写任何转换代码。**

**情况二：协议相似但细节不同**（像 Anthropic / Azure）。写一个 adaptor，处理鉴权头、版本头、端点路径。参考 `internal/adaptor/anthropic.go`，大概 150 行。

**情况三：协议完全不同**（Bedrock / Vertex / 混元这些）。先写一个 `provider.Provider` 实现，再写 adaptor。这类现在会显式报"需要原生适配器"。

---

## 8. 现在的状态和欠账

**已经能用的：**

- 三十多个渠道类型，其中二十多个是同一适配器 + 配置
- 四个真正独立的适配器（OpenAI 兼容 / Anthropic / Azure / Gemini）
- 未实现的原生类型显式报错，不会误当 OpenAI 兼容
- 两套上游接口（强类型 + raw 透传），新端点不用等适配器
- SSRF 检查在拨号层（防 DNS rebinding）+ 重定向检查 + 代理显式关闭
- Ollama 的本地访问例外精确到类型，不用全局开关
- 出站响应体 128MB 上限
- 流式客户端无硬超时，改用滑动空闲超时

**还没解决的：**

**第一，两套上游抽象并存，边界不清。** `provider.Provider` 和 `adaptor.Adaptor` 现在都在用，`/v1/messages` 走了新的，其他入口还在旧的。这期间改一个 provider 要同时看两边，容易漏。我打算等 executor 那条路径的事收敛之后再统一（第 2 篇提过 executor 现在默认关闭）。

**第二，`default` 分支的宽容有风险。** 未知类型当成 OpenAI 兼容，好处是新 provider 能直接接上，坏处是**配置写错一个类型数字，就会拿一个错的协议去打上游**，然后收到一个看不懂的错误。我在考虑给它加一条启动期的显式日志，把"这个渠道类型走了 default 分支"打出来。

**第三，`nonPublicPrefixes` 是一张手工维护的表。** 它装的是标准库判断覆盖不到的特殊段：`100.64.0.0/10`（运营商级 NAT）、`192.0.0.0/24`、`192.0.2.0/24` 和 `198.51.100.0/24`（文档示例段）、`198.18.0.0/15`（基准测试段）、`203.0.113.0/24`、`240.0.0.0/4`（保留）、`2001:db8::/32`（IPv6 文档段）。云元数据地址 `169.254.169.254` 不在这个表里——它是 link-local，被 `IsLinkLocalUnicast()` 拦住了。新出现的特殊段需要手工补进这张表。

**第四，`PROVIDER_DISABLE_SSRF_CHECK` 这个全局开关还是很危险。** 我自己不用它，但它存在，而且名字看起来像是"遇到问题就打开"的那种开关。也许该给它加一个启动告警。

---

## 9. 下一篇

下一篇讲订阅额度：一个用户买了套餐之后，"额度"这个东西在上游侧和我本地侧是两套完全不同的账，以及我为什么要同时维护这两套，还有它们各自的重置语义。

[《订阅额度：为什么我要同时维护两套完全不同的账》](/2026-09-16-micro-one-api-quota-windows/)
