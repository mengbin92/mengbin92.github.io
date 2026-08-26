---
layout: post
title: 大模型缓存完全指南：从 KV Cache 到语义缓存
tags: LLM AI 缓存
mermaid: false
math: false
---

# 大模型缓存知识介绍

> 面向 LLM 应用 / 网关开发者的缓存知识梳理。覆盖从推理引擎内部到 API 网关的完整缓存层次，以及各厂商 Prompt Caching 的用法与计费规则。
>
> ⚠️ 各厂商的定价与缓存规则更新频繁，文中数字仅为撰写时（2026-08）的参考量级，落地前请以官方最新文档为准。

---

## 1. 为什么需要缓存

LLM 推理有两个显著的“贵”：

| 维度 | 无缓存 | 有缓存 |
|---|---|---|
| **成本** | 每个 token 都按全价计算 | 命中部分按折扣价计费（视厂商与模型，约 0.1×~0.5×） |
| **延迟** | 长 prompt 的 prefill 耗时随长度线性增长 | 命中部分跳过 prefill，TTFT 大幅下降 |

典型受益场景：

- **长系统提示词 / 多工具定义**：每轮对话重复发送几千 token 的 system prompt
- **多轮对话**：历史消息逐轮累积，前缀高度重合
- **RAG / 文档问答**：同一份长文档被反复提问
- **Agent 循环**：工具调用往返中上下文不断追加，前缀不变
- **少数示例（few-shot）**：固定示例集在每请求中重复

---

## 2. 缓存的三个层次

大模型“缓存”一词在不同层次含义完全不同，先建立全局视图：

```
用户请求
   │
   ▼
┌─────────────────────────────────────────┐
│ L3 网关/应用层缓存                        │  ← 缓存"回答"
│   - 精确匹配缓存（Exact Cache）           │
│   - 语义缓存（Semantic Cache）            │
└─────────────────────────────────────────┘
   │ 未命中，调用上游 LLM API
   ▼
┌─────────────────────────────────────────┐
│ L2 提供商 Prompt Caching                 │  ← 缓存"前缀的计算结果"
│   - Anthropic / OpenAI / Gemini / ...    │
│   - 命中前缀按折扣价计费                   │
└─────────────────────────────────────────┘
   │ 推理引擎执行
   ▼
┌─────────────────────────────────────────┐
│ L1 推理引擎 KV Cache                     │  ← 缓存"中间激活（KV）"
│   - PagedAttention / RadixAttention      │
│   - 同一实例内的前缀复用                   │
└─────────────────────────────────────────┘
```

| 层次 | 缓存对象 | 位置 | 命中收益 | 谁来实现 |
|---|---|---|---|---|
| L1 KV Cache | token 的 Key/Value 张量 | 推理引擎（vLLM/SGLang 等） | 省 prefill 计算 | 推理框架自动 |
| L2 Prompt Caching | 提示词前缀的缓存状态 | LLM 服务商 | 省 prefill 计算 + 按折扣计费 | 提供商，用户需配合组织 prompt |
| L3 响应缓存 | 完整的模型回答 | 网关 / 应用 | 省整个调用（成本≈0，延迟≈0） | 开发者自建 |

---

## 3. L1：推理引擎 KV Cache（基础原理）

### 3.1 什么是 KV Cache

Transformer 自回归生成时，每个新 token 都要对之前所有 token 做注意力计算。若不缓存，第 n 个 token 的生成需要重算前 n-1 个 token 的 Key/Value 矩阵，复杂度 O(n²)。

KV Cache 把每层每头的 K/V 张量存下来，生成时只做增量计算：

```
prefill 阶段：一次性计算整个 prompt 的 KV  →  计算密集，决定 TTFT
decode  阶段：每步只为新 token 算 KV      →  访存密集，决定吐字速度
```

### 3.2 前缀复用（Prefix Caching）

如果两个请求的 prompt 有公共前缀，这段前缀的 KV 完全相同，可以直接复用，跳过 prefill。这是所有上层缓存机制的物理基础。

代表性技术：

- **PagedAttention**（vLLM）：借鉴操作系统虚拟内存分页思想管理 KV Cache 显存，块级共享前缀
- **RadixAttention**（SGLang）：用基数树（Radix Tree）组织 KV 块，自动完成前缀匹配与 LRU 淘汰

### 3.3 关键推论

- KV Cache 命中**不改变模型输出**（数值上等价），只省算力
- 命中要求**前缀逐 token 完全一致**，中间改一个字符，其后全部失效
- 缓存活在推理实例的显存/内存里，**有容量上限**，按 LRU 之类的策略淘汰

---

## 4. L2：提供商 Prompt Caching

云厂商把前缀复用做成了计费产品：命中的输入 token 按折扣价计费（主流厂商现行模型约为原价的 0.1×）。

### 4.1 通用规则（所有厂商一致）

1. **前缀匹配**：缓存以 token 序列为单位从头匹配，任何位置不同则其后全部 miss
2. **最小长度门槛**：缓存前缀需达到一定长度才开始生效（视厂商和模型，从几十到几千 token 不等，见 4.2）
3. **TTL**：缓存条目有时间窗口，过期后重新写入
4. **模型/参数绑定**：换模型、换系统级参数（如 temperature 之外影响 token 序列的内容）会导致失配

### 4.2 各厂商概览

| 厂商 | 启用方式 | 最小缓存长度 | TTL | 命中价 | 写入价 |
|---|---|---|---|---|---|
| **Anthropic** | 显式：在消息块上标 `cache_control: {"type": "ephemeral"}`（最多 4 个断点）；也支持顶层自动缓存 | 视模型 512~4096 token：Sonnet 1024，Haiku 4.5 / Opus 4.5 为 4096，最新旗舰（Opus 5 等）512 | 默认 5 分钟，可选 1 小时；命中读取免费续期 | ≈ 0.1× | 5m 缓存 1.25×；1h 缓存 2× 原价 |
| **OpenAI** | 自动：达到门槛的前缀自动缓存（默认开启）；也支持显式模式（`prompt_cache_options`，最多 4 个断点） | 新模型 1024 token（旧模型 2048，旧模型以 128 token 为粒度增量匹配） | 默认 30 分钟（命中续期）；旧模型 in-memory 模式约 5~10 分钟空闲淘汰 | 新模型 ≈ 0.1×；旧模型 ≈ 0.5× | 新模型 1.25×；旧模型无写入费 |
| **Gemini** | 隐式（自动，2.5 系列起默认开启）+ 显式（Context Caching API，可指定 TTL，需 generateContent API） | 隐式：2.5 Flash/Pro 为 2048，新模型 4096；显式最低 1024 起（视模型） | 隐式短期；显式自定义（默认 1 小时） | 命中按折扣价（约 0.1×~0.25×，视模型）；显式另收存储费 | 显式按 token×时长收存储费（约 $1~4.5 / 1M token / 小时） |
| **DeepSeek** | 自动：Context Caching on Disk，磁盘级持久化 | 64 token（按 64 token 前缀块匹配） | 数小时~数天（闲置自动清除） | ≈ 0.1×（新模型更低），另有峰谷电价 | 无写入费 |

> 使用时务必核对官方定价页；上表比例用于建立量级直觉。

### 4.3 Anthropic 显式缓存示例

Anthropic 是显式控制的代表，理解它有助于理解所有厂商：

```json
{
  "model": "claude-sonnet-4-5",
  "system": [
    {
      "type": "text",
      "text": "你是一个代码审查助手……（很长的系统提示词）",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "这是项目的长文档：……"},
        {"type": "text", "text": "请审查以下代码……", "cache_control": {"type": "ephemeral"}}
      ]
    }
  ]
}
```

响应的 `usage` 会区分：

```json
{
  "usage": {
    "input_tokens": 20,
    "cache_creation_input_tokens": 3000,
    "cache_read_input_tokens": 0,
    "output_tokens": 150
  }
}
```

- 第一次请求：`cache_creation_input_tokens` 计入写入价（比原价贵）
- TTL 内的后续请求：对应前缀进入 `cache_read_input_tokens`，按 ~10% 计费
- **策略含义**：只有前缀会被**多次复用**时缓存才划算；一次性 prompt 反而多付写入费

### 4.4 OpenAI 自动缓存

自动模式无需任何标注，默认开启。新模型（GPT-5.6+）prompt ≥1024 token 时启用，旧模型门槛 2048 且以 128 token 为粒度增量匹配。响应中：

```json
{
  "usage": {
    "prompt_tokens": 2000,
    "prompt_tokens_details": {"cached_tokens": 1792},
    "completion_tokens": 100
  }
}
```

---

## 5. L3：网关 / 应用层响应缓存

缓存的是**最终回答**，命中时完全不调用上游。这是开发者可以完全自主掌控的一层。

### 5.1 精确匹配缓存（Exact Cache）

对请求归一化后做哈希作为 key：

```
key = hash(model + system + messages + temperature + ...)
```

- ✅ 实现简单、零误判
- ❌ 命中率低：空格、措辞、时间戳任何差异都 miss
- 适用：FAQ、固定模板调用、批处理任务去重

### 5.2 语义缓存（Semantic Cache）

把请求 embed 成向量，在向量库中找相似历史请求，相似度超过阈值则直接返回缓存回答：

```
请求 → embedding → 向量近邻搜索
                   ├─ 相似度 ≥ 阈值 → 返回缓存回答（成本≈0）
                   └─ 相似度 < 阈值 → 调用 LLM → 写入缓存
```

- ✅ 命中率大幅提升（"怎么退款" ≈ "如何申请退款"）
- ❌ **可能返回语义相近但错误的答案**，阈值调优是核心难点
- 代表实现：GPTCache、Redis LangCache、vLLM Semantic Cache 等
- 适用：客服问答、知识库问答等**容错场景**；代码生成、精确计算等场景慎用

### 5.3 设计要点与风险

| 问题 | 说明与对策 |
|---|---|
| **缓存键维度** | 必须包含 model、temperature、工具定义等影响输出的全部参数；多租户场景必须隔离 user/tenant 维度 |
| **隐私泄漏** | A 用户的问题命中 B 用户的缓存回答 → 数据泄露。语义缓存跨用户共享是**高危设计**，默认应按租户隔离 |
| **失效策略** | 知识更新后旧答案变错。需要 TTL + 主动失效通道（如知识库变更事件触发清除） |
| **流式请求** | 缓存命中可以"伪流式"回放（分片吐出），保持客户端体验一致 |
| **命中率观测** | 必须监控 hit rate、节省的 token/成本、以及语义缓存的"误命中"投诉率 |
| **与计费的关系** | L3 命中请求成本为 0，如果对外提供 API 服务，计费策略需要单独定义（免费？按次低价收费？）——这是产品设计决策 |

---

## 6. Prompt 组织最佳实践（让缓存真正命中）

无论哪一层缓存，命中率都取决于**前缀稳定性**：

### ✅ 推荐结构：稳定在前，动态在后

```
[系统提示词 / 角色设定]      ← 最稳定，永远不变
[工具定义]                   ← 稳定（注意保持顺序一致）
[Few-shot 示例]              ← 稳定
[长文档 / RAG 召回内容]      ← 半稳定
[对话历史]                   ← 只追加，不修改
[当前用户问题]               ← 每轮都变，放最后
```

### ❌ 常见破坏缓存的做法

| 做法 | 为什么破坏 |
|---|---|
| 在 system prompt 里嵌入当前时间戳 | 前缀每秒都在变，命中率归零 |
| 工具列表顺序随机（如遍历 map） | 序列化结果不稳定，逐 token 比较失败 |
| 在中间插入/修改历史消息 | 插入点之后全部 miss |
| 对历史消息做"滑动窗口改写" | 每轮都在改写前缀 |
| JSON 键序不稳定 | 同一份内容序列化出不同字节流 |

### 命中率的度量

- L2 缓存命中率 = `cache_read_tokens / total_input_tokens`
- 上线优化动作前后对比 TTFT P50/P95 与成本曲线
- 命中率突降通常意味着有人改了 prompt 模板——值得加告警

---

## 7. 常见误区（FAQ）

**Q1：开启缓存会改变模型输出吗？**
不会。L1/L2 缓存复用的是数学上等价的中间计算结果，输出与全量计算一致（数值误差层面等价）。L3 语义缓存例外——它返回的是"别人的答案"，这是产品语义变化，不是推理优化。

**Q2：temperature=0 时相同请求为什么输出仍可能不同？**
缓存解决的是 prefill 计算复用，不保证跨请求的完全确定性（浮点非确定性、batch 组合差异等）。需要严格复现请用 seed 参数（如厂商支持）+ 固定版本。

**Q3：多轮对话需要每轮都标 cache_control 吗？**
Anthropic 官方推荐的做法是对多轮对话直接使用**顶层自动缓存**（automatic caching），无需手动管理断点；若用显式断点，则断点跟随内容走，最新一轮追加后把断点前移到新前缀末尾即可。TTL 会随命中读取免费续期，但要注意：**TTL 从请求开始时计算，响应生成时间也占用缓存窗口**——长响应可能吃掉 5 分钟窗口的一部分。

**Q4：缓存有数据安全风险吗？**
厂商 Prompt Caching 通常保证租户隔离，不会跨用户命中。但 L3 自建语义缓存若跨用户共享，是真实的高危泄漏面，见 5.3。

**Q5：什么时候不值得用缓存？**
- prompt 短（< 最小门槛）或一次性使用
- 前缀复用率低于 ~2 次时，Anthropic 显式缓存的写入费可能超过节省
- 强实时内容（每请求都不同的 RAG 召回）放在前缀位置会把后面的稳定内容也拖垮

---

## 8. 参考资料

- Anthropic Prompt Caching 官方文档：<https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching>
- OpenAI Prompt Caching：<https://platform.openai.com/docs/guides/prompt-caching>
- Gemini Context Caching：<https://ai.google.dev/gemini-api/docs/caching>
- DeepSeek Context Caching：<https://api-docs.deepseek.com/guides/kv_cache>
- vLLM PagedAttention 论文：<https://arxiv.org/abs/2309.06180>
- SGLang RadixAttention：<https://arxiv.org/abs/2312.07104>
- GPTCache：<https://github.com/zilliztech/GPTCache>

---

*最后更新：2026-08-26*
