---
layout: post
title: 构建基于LLM的Go应用程序
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/llmpowered)。  

> 由 Eli Bendersky 发布于 2024年9月12日

随着过去一年中大语言模型（LLM）及其相关工具（如嵌入模型）能力的显著提升，越来越多的开发者考虑将 LLM 集成到他们的应用中。

由于 LLM 通常需要专用硬件和大量计算资源，因此它们通常作为网络服务打包，提供 API 供访问。这正是 OpenAI 或 Google Gemini 等领先 LLM 的 API 工作原理；即便是像 [Ollama](https://ollama.com/) 这样的自建 LLM 工具也会将 LLM 封装在 REST API 中以便于本地使用。此外，利用 LLM 的开发者通常还需要额外的工具，如向量数据库，这些数据库也通常作为网络服务进行部署。

换句话说，基于 LLM 的应用与其他现代云原生应用非常相似：它们需要对 REST 和 RPC 协议提供卓越的支持，具备良好的并发性和性能。这些正是 Go 语言的强项，使其成为编写基于 LLM 的应用的理想选择。

本文通过一个简单的 LLM 驱动应用示例来展示如何使用 Go。首先描述演示应用所解决的问题，然后展示几个不同实现该任务的应用变种，所有变种使用不同的包进行实现。本文的所有示例代码都[可在线获取](https://github.com/golang/example/tree/master/ragserver)。

## RAG 服务器用于问答

一种常见的基于 LLM 的应用技术是 RAG——[检索增强生成](https://en.wikipedia.org/wiki/Retrieval-augmented_generation)。RAG 是定制 LLM 知识库以进行特定领域交互的最可扩展方法之一。

我们将用 Go 构建一个 RAG 服务器。这是一个 HTTP 服务器，为用户提供两个操作：

- 向知识库添加文档
- 向 LLM 提问有关该知识库的问题

在典型的现实场景中，用户将向服务器添加一组文档，然后提出问题。例如，一家公司可以将内部文档填充到 RAG 服务器的知识库中，并利用其为内部用户提供基于 LLM 的问答能力。

下面是展示我们服务器与外界交互的示意图：  

<div align="center">
  <img src="../img/2024-09-23/rag-server-diagram.png" alt="rag-server-diagram.png">
</div>

除了用户发送 HTTP 请求（上述两个操作），服务器还与以下部分交互：

- 一个嵌入模型，用于计算提交文档和用户问题的[向量嵌入](https://en.wikipedia.org/wiki/Sentence_embedding)。
- 一个向量数据库，用于高效存储和检索嵌入。
- 一个 LLM，用于根据从知识库收集的上下文提出问题。

具体而言，服务器向用户暴露两个 HTTP 端点：

- **/add/**: POST `{"documents": [{"text": "..."}, {"text": "..."}, ...]}`: 提交一系列文本文档到服务器，以添加到其知识库中。对于该请求，服务器：

  - 使用嵌入模型计算每个文档的向量嵌入。
  - 将文档及其向量嵌入存储在向量数据库中。

- **/query/**: POST `{"content": "..."}`: 向服务器提交一个问题。对于该请求，服务器：

  - 使用嵌入模型计算问题的向量嵌入。
  - 使用向量数据库的相似性搜索找到与问题最相关的文档。
  - 使用简单的提示工程，结合在第（2）步中找到的最相关文档作为上下文重新表述问题，并发送给 LLM，将其答案返回给用户。

我们演示中使用的服务有：

- [Google Gemini API](https://ai.google.dev/) 用于 LLM 和嵌入模型。
- [Weaviate](https://weaviate.io/) 用于本地托管的向量数据库；Weaviate 是一个用 [Go 实现的开源向量数据库](https://github.com/weaviate/weaviate)。

更换为其他等效服务应该非常简单。事实上，这正是服务器的第二和第三个变种的内容！我们将从第一个变种开始，直接使用这些工具。

## 直接使用 Gemini API 和 Weaviate

Gemini API 和 Weaviate 都有方便的 Go SDK（客户端库），我们的第一个服务器变种直接使用这些库。该变种的完整代码在[此目录](https://github.com/golang/example/tree/master/ragserver/ragserver)中。

我们不会在本文中重现完整代码，但以下是阅读时需要注意的一些要点：

- **结构**: 代码结构对任何编写过 Go HTTP 服务器的人来说都非常熟悉。Gemini 和 Weaviate 的客户端库被初始化，并存储在一个传递给 HTTP 处理程序的状态值中。
- **路由注册**: 使用 Go 1.22 引入的[路由增强](https://go.dev/blog/routing-enhancements)，设置 HTTP 路由非常简单：

  ```go
  mux := http.NewServeMux()
  mux.HandleFunc("POST /add/", server.addDocumentsHandler)
  mux.HandleFunc("POST /query/", server.queryHandler)
  ```

- **并发性**: 服务器的 HTTP 处理程序通过网络与其他服务交互并等待响应。对 Go 来说，这不是问题，因为每个 HTTP 处理程序在其自己的 goroutine 中并发运行。这个 RAG 服务器可以处理大量并发请求，每个处理程序的代码是线性和同步的。

- **批处理 API**: 由于一个 `/add/` 请求可能提供大量文档添加到知识库中，服务器利用嵌入（`embModel.BatchEmbedContents`）和 Weaviate 数据库（`rs.wvClient.Batch`）的批处理 API 以提高效率。

## 使用 LangChain 的 Go 版本

我们的第二个 RAG 服务器变种使用 LangChainGo 来完成相同的任务。

[LangChain](https://www.langchain.com/) 是一个流行的 Python 框架，用于构建基于 LLM 的应用。[LangChainGo](https://github.com/tmc/langchaingo) 是它的 Go 版本。该框架具有一些构建模块化组件的工具，并支持许多 LLM 提供商和向量数据库的通用 API。这使得开发者可以编写可以与任何提供商一起工作的代码，并很容易更换提供商。

该变种的完整代码在[此目录](https://github.com/golang/example/tree/master/ragserver/ragserver-langchaingo)中。阅读代码时，您会注意到两点：

首先，它比前一个变种稍短。LangChainGo 负责将向量数据库的完整 API 封装在通用接口中，因此初始化和处理 Weaviate 所需的代码更少。

其次，LangChainGo API 使得更换提供商变得相对简单。假设我们想用另一个向量数据库替换 Weaviate；在前一个变种中，我们需要重写所有与向量数据库交互的代码以使用新的 API。而使用像 LangChainGo 这样的框架，我们不再需要这样做。只要 LangChainGo 支持我们感兴趣的新向量数据库，我们只需在服务器中替换几行代码即可，因为所有数据库都实现了一个[通用接口](https://pkg.go.dev/github.com/tmc/langchaingo@v0.1.12/vectorstores#VectorStore)：

```go
type VectorStore interface {
    AddDocuments(ctx context.Context, docs []schema.Document, options ...Option) ([]string, error)
    SimilaritySearch(ctx context.Context, query string, numDocuments int, options ...Option) ([]schema.Document, error)
}
```

## 使用 Genkit 的 Go 版本

今年早些时候，Google 为 [Go 推出了 Genkit](https://developers.googleblog.com/en/introducing-genkit-for-go-build-scalable-ai-powered-apps-in-go/)——一个构建基于 LLM 应用的新开源框架。Genkit 与 LangChain 有一些相似之处，但在其他方面有所不同。

与 LangChain 一样，它提供可由不同提供商（作为插件）实现的通用接口，从而简化了从一个到另一个的切换。然而，它并不试图规定不同 LLM 组件的交互方式；相反，它专注于生产功能，如提示管理和工程，以及与集成开发工具的部署。

我们的第三个 RAG 服务器变种使用 Genkit for Go 来完成相同的任务。其完整代码在[此目录](https://github.com/golang/example/tree/master/ragserver/ragserver-genkit)中。

这个变种与 LangChainGo 的相似性相当——使用 LLM、嵌入器和向量数据库的通用接口，而不是直接的提供商 API，使得切换变得更容易。此外，使用 Genkit 部署基于 LLM 的应用到生产环境要简单得多；我们在变种中没有实现这一点，但如果您感兴趣，可以随意查看[文档](https://firebase.google.com/docs/genkit-go/get-started-go)。

## 总结 - 使用 Go 构建基于 LLM 的应用

本文中的示例仅展示了在 Go 中构建基于 LLM 的应用的可能性。它演示了用相对较少的代码构建强大 RAG 服务器的简单性；最重要的是，这些示例在某些基本的 Go 特性支持下，具备了相当的生产准备度。

与 LLM 服务的交互通常意味着向网络服务发送 REST 或 RPC 请求，等待响应，然后根据响应向其他服务发送新请求，依此类推。Go 在所有这些方面表现出色，提供了出色的工具来管理并发和处理网络服务的复杂性。

此外，Go 作为云原生语言的卓越性能和可靠性，使其成为实现 LLM 生态系统更基本构建模块的自然选择。有关一些示例，请查看像 [Ollama](https://ollama.com/)、[LocalAI](https://localai.io/)、[Weaviate](https://weaviate.io/) 或 [Milvus](https://zilliz.com/what-is-milvus) 等项目。

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  
> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  
---