---
title: "浏览器里直接调模型：怎么让 API Key 不落到任何地方"
date: 2026-09-18T12:00:00+08:00
description: "做一个“在浏览器里调模型”的 Playground，聊天界面本身没什么难的：一个输入框、一个消息列表、一个流式渲染。"
tags: ["Micro-One-API", "前端", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 这个页面的难点不在聊天界面

做一个"在浏览器里调模型"的 Playground，聊天界面本身没什么难的：一个输入框、一个消息列表、一个流式渲染。

真正让我花了大部分时间的是一个问题：

**用户要把 API Key 粘贴进来，我怎么保证它不落到任何地方？**

这不是"注意安全"级别的提醒，而是一组必须逐项排除的落地点。我列了一下，一个 Key 可能被存到的地方至少有：

- URL 的 path / query / hash（刷新页面还在）
- React Router 的 `location.state` 或浏览器 history state（同上）
- `localStorage` / `sessionStorage` / `IndexedDB` / cookie
- React Query 的 key 或 query cache
- toast、DOM 文本、错误详情、`console`
- 请求 JSON 预览、cURL 预览
- analytics、错误上报的 breadcrumb、服务端日志

我最后把这些写成了文档里的一节，标题叫"API Key 与隐私设计"，明确列出**允许存在的位置**和**禁止存在的位置**。

这篇讲这个设计，以及做的时候踩到的几个具体问题。

---

## 1. 第一个决定：浏览器直连 Relay，不做代理

最省事的方案是让 admin-api 代理一下：

```
browser -> /api/playground/chat -> admin-api -> relay-gateway
```

这样连 CORS 都不用管（同源）。我否掉了，文档里记了四条理由：

> - API Key 额外经过 `admin-api`，增加日志与内存暴露面；
> - admin-api 必须正确代理 SSE、flush、取消、超时和客户端断连；
> - 登录会话与 API Key 两套鉴权容易混用；
> - 未来可能形成一条行为与公开 Relay 不一致的旁路。

第一条是决定性的：**Key 多经过一个服务，就多一份落进日志的风险。** 而"不经过"是最彻底的防护。

第二条是工程量的现实：正确代理 SSE 要处理 flush、取消传播、超时、断连——这些我在 relay 里已经实现过一遍（第 2 篇），不想再实现一遍而且实现得更差。

第四条是我最不想要的：一旦有了代理，就会有人开始往代理里加"顺手做的事"，最后这条路径和公开 Relay 的行为不一致。**"真实"本身有价值**——Playground 应该验证部署真实的 `ServerAddress`，而不是验证一个内部代理。

所以最终是这样的：

```
┌──────────────────────┐      GET /api/status       ┌──────────────────┐
│ Web 控制台 admin-api │ <------------------------> │ admin-api :8000  │
│ 浏览器 Origin :3000  │                            └──────────────────┘
│                      │
│ Playground fetch     │  Authorization: Bearer API_KEY
│                      │ --------------------------> ┌──────────────────┐
└──────────────────────┘  GET /v1/models             │ relay :8080      │
                          POST /v1/chat/completions   │ 鉴权/路由/计费   │
                          <----- JSON / SSE --------- └──────────────────┘
```

代价是要处理 CORS，这一节最后讲。

---

## 2. 第二个决定：不能复用现有的请求客户端

项目里已经有一个 `web/src/lib/api.ts` 的 `apiClient`，它做了三件事：

- `baseURL` 是 `/api`；
- 自动从 `localStorage.token` 加登录 JWT；
- 特定路径返回 401 时清除登录态并跳转登录页。

**这三件事在这个场景下全是错的。** 文档里写得很直接：

> Playground 不能复用它。新增的 Relay 客户端必须：
>
> - 使用原生 `fetch`，以便消费 `ReadableStream`；
> - 由调用方显式传入 Relay base URL 和 API Key；
> - 不读取登录 JWT；
> - Relay 401 只标记 API Key 无效，绝不清除 Web 登录态；
> - 不进入全局 React Query cache；
> - 不在异常对象中附带 Authorization header。

第四条是我觉得最容易出事的一条。想象一下：用户在 Playground 里粘贴了一个**已经失效的 API Key**，请求返回 401。如果复用了 `apiClient`，它会：

1. 认为"登录过期了"；
2. 清掉 `localStorage.token`；
3. 把用户踢到登录页。

**用户只是打错了一个 Key，结果被登出了。** 而如果他刚好在配置渠道，填的内容可能一起没了。

**控制面的 401 和执行面的 401 是两件完全不同的事，所以必须是两个客户端。**

最后那条（异常对象不带 Authorization header）是防御性的：异常对象经常被打印、被上报。如果它携带着请求的 header，Key 就会顺着错误上报流出去。

---

## 3. 第三个决定：一次性内存交接

从"创建 Token"到"在 Playground 里用它"，Key 需要在两个页面之间传一次。

常规做法是塞进 URL 或者 Router state。**两者都会留在浏览器历史里**，用户按一下后退、或者把 URL 分享出去，Key 就出去了。

所以做了一个只有三个函数的小模块：

```ts
let pendingCredential: string | null = null;

function normalizeCredential(secret: string) {
  const normalized = secret.trim();
  return normalized || null;
}

export function setPlaygroundCredential(secret: string) {
  pendingCredential = normalizeCredential(secret);
}

export function takePlaygroundCredential() {
  const credential = pendingCredential;
  pendingCredential = null;
  return credential;
}

export function clearPlaygroundCredential() {
  pendingCredential = null;
}
```

语义在文档里写死了：

> - Token 创建弹窗点击跳转前调用 `set`；
> - Playground 首次 mount 调用 `take`，读取后立即清空槽；
> - 不通过 Router state，以免 Key 保留在浏览器 session history；
> - 页面刷新、标签关闭和重新打开都会丢失 Key，**这是预期安全行为**；
> - 登出时调用 `clear`；
> - 单元测试验证 `take` 的一次性语义。

用起来是这样：

```tsx
// TokensPage.tsx —— 创建成功的弹窗里
setPlaygroundCredential(createdToken.key as string);

// PlaygroundPage.tsx —— 首次挂载时取一次
const [handedOffKey] = useState<string | null>(() => takePlaygroundCredential());
```

`useState` 的惰性初始化保证 `take` 只执行一次，之后组件重渲染也不会再读。

**这里有个取舍我必须承认：页面刷新后 Key 就没了，用户得重新粘贴。**

从体验上讲这不如"存到 localStorage 然后自动填充"。但那意味着 Key 会长期留在浏览器里，任何一个 XSS 都能读走它。**我选了体验的损失，换掉了这个持久化的攻击面。**

而 `take` 读后即清空，确保这个交接槽在正常流程里永远是空的。

### 3.1 一次性槽解决不了的事

文档里有一句我觉得必须写下来的话：

> 只驻留内存不能抵御同源 XSS。

即使 Key 只在内存里，只要它出现在 DOM 里、被渲染出来，同源的脚本就能拿到它。所以还配套了另外几条：

> - 不使用 `dangerouslySetInnerHTML` 渲染模型输出；
> - 首版按纯文本渲染；后续 Markdown 必须使用安全 renderer 和严格 sanitizer；
> - 不加载第三方 Playground 脚本；
> - 不在页面注入远程字体、统计脚本或 Prompt 插件；
> - 保留现有安全响应头，并在上线验收中检查 CSP / `X-Content-Type-Options` 等头。

**"不把 Key 存进 localStorage"和"防止 Key 被读走"是两件不同的事。** 前者是缩小暴露面，后者要靠 XSS 防护。我把两条都写进了文档，因为只做前一条会给我一种虚假的安全感。

---

## 4. 页面上还要注意的几件事

文档里"页面展示"一节定了这些规则：

> - Key 输入使用 `type="password"`；
> - 提供按住或点击显示按钮，但失焦后恢复隐藏；
> - 验证成功后只显示本地计算的 `前 4 位 + **** + 后 4 位`；
> - 请求预览中的 Authorization 固定显示 `Bearer ••••<suffix>`，或完全省略 headers；
> - "复制请求"默认只复制 JSON body，不复制带真实 Key 的 cURL；
> - 切换 API 地址后必须清除已验证 Key 与模型，防止凭证误发到新地址。

最后一条是我加进去的，因为它是一个真实的泄露路径：

**用户先在一个地址上验证了 Key，然后改 API 地址去连另一个部署。** 如果 Key 还留着，下一次请求就会把 Key 发到那个新地址——那个地址可能是别人控制的。

所以"切换地址"这个动作必须把凭证一起清掉。

"复制 cURL 默认不复制 Key"也是同理：cURL 很容易被贴到 issue、聊天群、工单系统里。默认不复制带 Key 的版本，用户要用的话得自己去改。

---

## 5. 流式：SSE 解析里我踩的两个坑

请求侧是这样的：

```ts
export interface PlaygroundRequest {
  model: string;
  messages: PlaygroundMessageInput[];
  stream: boolean;
  stream_options?: { include_usage: boolean };
  temperature?: number;
  max_tokens?: number;
}
```

注意 `stream_options.include_usage`。**流式响应默认不返回用量**，但对一个"让你试试花多少钱"的页面来说，用量是最该显示的。打开这个选项，最后一个 chunk 会带上 `usage`。

然后解析：

```ts
for await (const event of parseSSEStream(response.body)) {
  callbacks?.onEvent?.(event);
  if (event.data === '[DONE]') {
    sawDone = true;
    continue;
  }
  let payload: unknown;
  try {
    payload = JSON.parse(event.data) as unknown;
    malformedEvents = 0;
  } catch {
    malformedEvents += 1;
    if (malformedEvents >= 3) {
      throw new RelayPlaygroundError(t("Relay 流式响应格式异常"), { kind: 'protocol_error', ... });
    }
    continue;
  }
  // ...
}
```

### 5.1 坑一：`\r` 可能被切在两个 chunk 之间

SSE 的规范里，行结束可以是 `\n`、`\r\n` 或者 `\r`。真实的实现大多用 `\r\n`。

问题在于：**一次 `reader.read()` 返回的字节，不保证切在完整的分隔符上。** 一个 `\r\n` 完全可能被切成"这个 chunk 结尾是 `\r`"和"下个 chunk 开头是 `\n`"。

如果直接做 `replace(/\r\n/g, '\n')`，那个落单的 `\r` 会被当成一个行结束符处理，于是**把一行数据切成了两行**。

解决办法是记住"上一个 chunk 结尾有个待定的 `\r`"：

```ts
let pendingCR = false;

const appendDecoded = (decoded: string, final = false) => {
  let value = pendingCR ? `\r${decoded}` : decoded;
  pendingCR = false;
  if (!final && value.endsWith('\r')) {
    value = value.slice(0, -1);
    pendingCR = true;
  }
  const normalized = normalizeLineEndings(value);
  buffer += normalized;
  bufferBytes += encoder.encode(normalized).byteLength;
};
```

`\r` 被摘下来存着，等下一个 chunk 到了再拼回去。`final = true` 表示流结束了，这时不能再挂起 `\r`。

**这个 bug 的表现是"偶发丢字或者事件错乱"**，而且通常只在特定的网络分片下出现——本地跑基本复现不了。

### 5.2 坑二：不设上限的缓冲区

如果上游是一个不规范的实现，一直发数据但从不发 `\n\n`（SSE 的事件分隔符），那 `buffer` 会无限增长。

所以有一个上限：

```ts
export const MAX_SSE_EVENT_BYTES = 2 * 1024 * 1024;
```

```ts
const drainEvents = () => {
  const events: SSEEvent[] = [];
  let boundary = buffer.indexOf('\n\n');
  while (boundary >= 0) {
    // ...切出事件
  }
  if (bufferBytes > MAX_SSE_EVENT_BYTES) {
    throw new SSEProtocolError(t("SSE 单个事件超过 2 MiB 限制"));
  }
  return events;
};
```

注意检查的位置：**在排空所有完整事件之后。** 因为缓冲区里可能堆了很多正常事件还没处理，先处理掉再判断剩余的是不是超限。

用一个独立累计的 `bufferBytes` 而不是每次 `encoder.encode(buffer).byteLength`，是因为后者会在每次检查时对整个缓冲区重新编码一遍，在事件密集时是明显的浪费。

### 5.3 小细节：容错要容一次，不能容无限次

`malformedEvents` 那个计数器我觉值得说：

```ts
} catch {
  malformedEvents += 1;
  if (malformedEvents >= 3) {
    throw new RelayPlaygroundError(...);
  }
  continue;
}
```

而一旦解析成功就 `malformedEvents = 0`。

**为什么要容错而不是遇到坏事件就报错？** 因为真实的上游偶尔会发一两个不完整的 chunk（比如被代理截断），直接报错会让一次正常的对话失败。

**为什么要有上限？** 因为"一直容忍"等于没有校验——如果上游完全发的是垃圾，用户会看到一个永远在转圈但什么都不出现的界面。

**容 3 次、连续成功就归零**，这个规则的意思是"偶尔的噪音可以忽略，但持续的异常要报出来"。

### 5.4 取消要真的取消

```ts
try {
  for await (const event of parseSSEStream(response.body)) { ... }
} finally {
  if (!completed) {
    try {
      await reader.cancel();
    } catch { /* ... */ }
  }
}
```

用户点了"停止生成"、或者直接离开页面，`AbortController` 会中断 fetch。但**如果只是中断了 fetch 而没有 cancel reader，底层的连接可能不会立刻释放。**

`finally` 里判断 `completed`，是因为正常结束（读到 `[DONE]` 或流自然结束）时不应该再 cancel。而 `aborted` 是一个单独的错误类型：

```ts
export type PlaygroundErrorKind =
  | 'invalid_key'
  | 'forbidden_model'
  | 'insufficient_quota'
  | 'rate_limited'
  | 'upstream_unavailable'
  | 'invalid_request'
  | 'cors_or_network'
  | 'protocol_error'
  | 'aborted'
  | 'unknown';
```

**把"用户主动中断"单独分成一类**，是因为它不该显示成错误——用户知道自己在做什么。如果它和后端失败混在一起，用户会以为是自己弄坏了什么。

---

## 6. CORS：不用 cookie 就干脆关掉 credentials

浏览器直连 Relay 就必须处理 CORS。我改的是 relay 的 CORS 配置：

```go
// RelayCORSConfig returns the credential-free CORS policy used by the public
// Relay HTTP endpoints. Relay authenticates with an Authorization bearer key,
// not browser cookies, so allowing credentials would expand the browser
// attack surface without providing a supported capability.
func RelayCORSConfig() *CORSConfig {
    config := DefaultCORSConfig()
    config.AllowedMethods = []string{"GET", "POST", "OPTIONS", "PUT", "DELETE", "PATCH"}
    config.AllowedHeaders = []string{
        "Authorization", "Content-Type", "X-Request-ID", "X-API-Key",
        "Anthropic-Version", "Anthropic-Beta", "OpenAI-Beta",
        "OpenAI-Organization", "OpenAI-Project", "Idempotency-Key",
        "X-Session-Hash", "OpenAI-Session-Hash",
    }
    config.ExposedHeaders = []string{
        "Content-Length", "Content-Type", "X-Request-ID",
        "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset",
    }
    config.AllowCredentials = false
    return config
}
```

`AllowCredentials = false` 是这条注释的结论：

**Relay 用 Bearer token 鉴权，不用 cookie。** 所以浏览器不需要发送凭证（cookie）到跨源请求里。而一旦打开 `AllowCredentials`，就同时失去了"不能用 `Access-Control-Allow-Origin: *`"的能力，并且让浏览器允许携带 cookie——**扩大了攻击面，却没提供任何我实际支持的能力。**

`ExposedHeaders` 里那几个 `X-RateLimit-*` 是我加上去的：Playground 应该能显示限流状态，否则用户看到 429 时不知道为什么。

而暴露错误信息里也要注意：`bodyPreview` 这种字段必须是**有界的**（第 15、17 篇都讲过）。relay 那边对上游错误体做了 512 字节截断，Playground 这边不额外放大。

---

## 7. 测试怎么做的

`PlaygroundPage.test.tsx` 只有 132 行，覆盖的是**状态机和交接语义**，不是渲染细节：

- `takePlaygroundCredential` 的一次性语义（调用两次第二次返回 null）；
- 401 只标记 Key 无效、不清登录态。

文档里还要求：

> 测试应扫描 query cache 与 mutation cache，确认不存在完整测试 Key。

这条我印象最深，因为它是一个"反直觉的测试"。常规的测试是"断言某个东西存在"，而这个测试是**断言某个东西不存在**——遍历所有缓存，确认找不到那个 Key。

**"Key 不应该出现在任何地方"这个需求，只能用"扫描所有地方确认没有"来验证。** 一条条列禁止项是不完备的（我总会漏掉某个新的缓存层），但"扫一遍所有缓存"能覆盖。

---

## 8. 现在的状态和欠账

**已经能用的：**

- 浏览器直连 Relay，Key 不经过 admin-api
- 独立的执行面客户端，不复用 admin 的 JWT 逻辑，401 不清登录态
- 一次性内存交接槽，不进 URL / Router state / 存储 / Query cache
- Key 输入用 password、失焦恢复隐藏、只显示首尾 4 位
- 切换地址清除凭证；复制请求默认不含 Key
- 不用 `dangerouslySetInnerHTML`，纯文本渲染
- SSE 解析处理跨 chunk 的 `\r`、2 MiB 单事件上限、连续 3 次坏事件才报错
- 中断走 `AbortController` + `reader.cancel()`，`aborted` 单独成一类
- CORS `AllowCredentials = false`，暴露限流头
- 测试覆盖一次性交接语义与"缓存里不存在 Key"

**还没解决的：**

**第一，Markdown 渲染还没有。** 现在是纯文本。上游返回的代码块、表格都只能原样显示。文档里写了"后续 Markdown 必须使用安全 renderer 和严格 sanitizer"，这活我一直没做——**因为一旦引入 Markdown 渲染，XSS 面就回来了，而我现在还没有 sanitizer 的选型。**

**第二，CSP 没有实际配置。** 文档要求"在上线验收中检查 CSP / `X-Content-Type-Options` 等头"，但我在文档层面确认了，没有实际部署验证。考虑到这个页面的核心资产是内存里的 Key，CSP 是第二道防线，不该只停留在清单上。

**第三，多轮对话没有做请求快照。** 文档第 7.2 节提到"请求快照与多轮语义"，我只实现了最基础的多轮消息拼接，没有处理"编辑历史消息后重新请求"这类场景下的上下文一致性。

**第四，没有做请求取消后的服务端确认。** 用户点了停止，前端中断了 fetch，但 relay 那边是否真的停止了上游请求、预扣有没有被释放，我在前端侧无法确认（第 2 篇讲过流式中断会走 Release，但我没有端到端验证过）。

**第五，`X-Request-ID` 的展示还没做完整。** 我在请求里带了 `X-Request-ID`，也在响应里读取它，但页面上没有把"这次请求的 ID"显示给用户。**这正是第 17 篇那个"用户可见的 trace ID"的价值所在**——用户报障时能给你一个 ID。差最后一环没接上。

---

## 9. 下一篇

下一篇讲对账：为什么我第一版对账几乎全是误报、七类核对分别在看什么、为什么不同核对用的容差不一样，以及"只报告不修复"这条我坚持下来的原则。

[《对账：七类核对、五种容差，以及“只报告不修复”为什么是对的》](/2026-09-18-micro-one-api-reconciliation/)
