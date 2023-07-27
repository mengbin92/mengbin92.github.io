---
layout: post
title: 
tags: 
mermaid: false
math: false
---  

原文在[这里](https://github.com/google/wire/blob/main/docs/best-practices.md)  

以下是我们推荐在使用 Wire 时应遵循的最佳实践。这个列表会随着时间的推移而增长。

## 区分类型

如果你需要注入一个常见类型，比如 `string`，请创建一个新的字符串类型，以避免与其他提供者产生冲突。例如：

```go
type MySQLConnectionString string
```

## 选项结构体

对于包含许多依赖项的提供者函数，可以与其配对一个选项结构体。

```go
type Options struct {
    // Messages is the set of recommended greetings.
    Messages []Message
    // Writer is the location to send greetings. nil goes to stdout.
    Writer io.Writer
}

func NewGreeter(ctx context.Context, opts *Options) (*Greeter, error) {
    // ...
}

var GreeterSet = wire.NewSet(wire.Struct(new(Options), "*"), NewGreeter)
```

## 库中的提供者集

当为在库中使用的提供者集时，你可以进行以下更改而不会破坏兼容性：

- 更改提供者集使用的提供者来提供特定的输出，只要不引入新的提供者集输入。它可能会删除输入。但请注意，现有的注入器将继续使用旧的提供者，直到重新生成。
- 将新的输出类型引入到提供者集中，但只有在类型本身是新增的情况下才可以。如果类型不是新的，则有可能某些注入器已经包含了输出类型，这将导致冲突。

所有其他更改都是不安全的。包括：

- 要求提供者集中增加新的输入。
- 从提供者集中删除输出类型。
- 将现有输出类型添加到提供者集中。

而不是进行上述任何破坏性更改，请考虑添加一个新的提供者集。

例如，如果你有一个如下所示的提供者集：

```go
var GreeterSet = wire.NewSet(NewStdoutGreeter)

func DefaultGreeter(ctx context.Context) *Greeter {
    // ...
}

func NewStdoutGreeter(ctx context.Context, msgs []Message) *Greeter {
    // ...
}

func NewGreeter(ctx context.Context, w io.Writer, msgs []Message) (*Greeter, error) {
    // ...
}
```

你可以：

- 在 `GreeterSet` 中使用 `DefaultGreeter` 替代 `NewStdoutGreeter`。
- 创建一个新类型 `T` 并将提供者添加到 `GreeterSet`，只要 `T` 是在与提供者在同一次提交/发布中引入的即可。

你不能：

- 在 `GreeterSet` 中使用 `NewGreeter` 替代 `NewStdoutGreeter`。这会同时添加一个输入类型（`io.Writer`），并要求注入器返回一个 `error`，而在提供者为 `*Greeter` 时不需要这样做。
- 从 `GreeterSet` 中删除 `NewStdoutGreeter`。依赖 `*Greeter` 的注入器将被破坏。
- 向 `GreeterSet` 添加一个 `io.Writer` 的提供者。注入器可能已经有一个提供者用于 `io.Writer`，这可能会与这个提供者冲突。

因此，在库中提供者集中，你应该仔细选择输出类型。一般来说，应该优先选择较小的库提供者集。例如，库提供者集通常只包含单个提供者函数以及 `wire.Bind` 来绑定返回类型实现的接口。避免使用较大的提供者集可以减少应用程序遇到冲突的可能性。举个例子，想象一下你的库提供了一个用于 web 服务的客户端。虽然可能会希望在库的客户端提供者集中捆绑一个 `*http.Client` 的提供者，但这样做会导致每个库都这样做时出现冲突。相反，库的提供者集应该只包含用于 API 客户端的提供者，并让 `*http.Client` 成为提供者集的输入。

## 模拟

有两种方法可以创建一个包含模拟依赖项的注入应用。这里展示了这两种方法的示例：

[https://github.com/google/wire/tree/master/internal/wire/testdata/ExampleWithMocks/foo](https://github.com/google/wire/tree/master/internal/wire/testdata/ExampleWithMocks/foo)。

### 方法A：将模拟对象传递给注入器

创建一个仅用于测试的注入器，将所有模拟对象作为参数传递给它；参数类型必须是模拟的接口类型。由于 `wire.Build` 不能包含用于模拟依赖项的提供者，以避免冲突，因此如果你正在使用提供者集，你将需要定义一个不包含模拟类型的提供者集。

### 方法B：从注入器返回模拟对象

创建一个新的结构体，其中包含应用程序以及你想要模拟的所有依赖项。创建一个仅用于测试的注入器，返回这个结构体，并为具体的模拟类型提供者，使用 `wire.Bind` 来告诉 Wire 这些具体的模拟类型应该用于满足相应的接口。  

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
