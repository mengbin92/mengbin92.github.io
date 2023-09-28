---
layout: post
title: 解析类型参数
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/deconstructing-type-parameters)。  

> 由 Ian Lance Taylor 发布于2023年9月26日  

## slices 包函数签名  

`slices.Clone` 函数很简单：它返回一个任意类型切片的副本：  

```go
func Clone[S ~[]E, E any](s S) S {
    return append(s[:0:0], s...)
}
```  

这个方法有效的原因是：向容量为零的切片追加元素将分配一个新的底层数组。函数体的长度最终比函数签名的长度要短，函数体短是一方面原因，函数签名长是另一方面原因。在本博客文章中，我们将解释为什么函数签名被写成这样。  

## Simple Clone  

我们将从编写一个简单的通用 `Clone` 函数开始。这不是 `slices` 包中的函数。我们希望接受任何元素类型的切片，并返回一个新的切片：  

```go
func Clone1[E any](s []E) []E {
    // body omitted
}
```  

这个通用函数`Clone1`有一个名为`E`的类型参数。它接受一个参数 `s`，该参数是类型为`E`的切片，并返回相同类型的切片。这个签名对于熟悉 Go 中泛型的人来说是直观的。

然而，存在一个问题。在 Go 中，命名切片类型并不常见，但人们确实在使用它们。  

```go
// MySlice is a slice of strings with a special String method.
type MySlice []string

// String returns the printable version of a MySlice value.
func (s MySlice) String() string {
    return strings.Join(s, "+")
}
```  

假设我们想复制一个 `MySlice`，然后获取可打印版本，但要按照字符串的排序顺序排列：  

```go
func PrintSorted(ms MySlice) string {
    c := Clone1(ms)
    slices.Sort(c)
    return c.String() // FAILS TO COMPILE
}
```  

很不幸，上面的代码并不能成功运行，编译器报错信息如下：  

```bash
c.String undefined (type []string has no field or method String)
```

如果我们手动用类型参数替换类型参数来实例化 `Clone1`，我们可以看到问题所在：  

```go
func InstantiatedClone1(s []string) []string
```

[Go的赋值规则](https://go.dev/ref/spec#Assignability)允许我们将类型为 `MySlice` 的值传递给类型为 `[]string` 的参数，因此调用 `Clone1` 是可以的。但是 `Clone1` 将返回类型为 `[]string` 的值，而不是类型为 `MySlice` 的值。类型 `[]string` 没有 `String` 方法，因此编译器会报错。  

## Flexible Clone  

要解决这个问题，我们需要编写一个返回与其参数相同类型的`Clone`版本。如果我们能做到这一点，那么当我们使用类型`MySlice`的值调用`Clone`时，它将返回类型`MySlice`的结果。  

结果如下：  

```go
func Clone2[S ?](s S) S // INVALID
```  

这个`Clone2`函数返回与其参数相同类型的值。  

这里我把约束写为了`?`，但这只是一个占位符。要使它工作，我们需要写一个能让我们编写函数体的约束。对于`Clone1`，我们可以只使用`any`进行约束。但对于`Clone2`，这样做不起作用：我们想要要求`s`是一个切片类型。

由于我们知道我们想要一个切片，切片的约束必须是一个切片。我们不关心切片元素类型是什么，所以我们就像在`Clone1`中一样将其命名为`E`。

```go
func Clone3[S []E](s S) S // INVALID
```

这仍然是无效的，因为我们还没有声明`E`。类型参数`E`的类型参数可以是任何类型，这意味着它本身也必须是一个类型参数。由于它可以是任何类型，所以它的约束是`any`。

```go
func Clone4[S []E, E any](s S) S
```

这已经接近了，至少它会编译通过，但我们还没有完全解决问题。如果我们编译这个版本，当我们调用`Clone4(ms)`时会出现错误。

```bash
MySlice does not satisfy []string (possibly missing ~ for []string in []string)
```

编译器告诉我们，我们不能将类型参数`MySlice`用于类型参数`S`，因为`MySlice`不满足约束`[]E`。这是因为`[]E`作为约束仅允许切片类型字面量，如`[]string`。它不允许像`MySlice`这样的命名类型。  

## 基础类型的约束

根据错误提示，答案是加一个波浪线(~)。

```go
func Clone5[S ~[]E, E any](s S) S
```

再次重申，编写类型参数和约束 `[S []E, E any]` 意味着`S`的类型参数可以是任何未命名的切片类型，但不能是定义为切片文字的命名类型。编写 `[S ~[]E, E any]`，带有一个波浪线，意味着 S 的类型参数可以是底层类型为切片的任何类型。

对于任何命名类型 `type T1 T2`，`T1`的底层类型是`T2`的底层类型。预声明类型如 `int` 或类型文字如 `[]string` 的底层类型就是它们自身。有关详细信息，请参阅[语言规范](https://go.dev/ref/spec#Underlying_types)。在我们的示例中，`MySlice`的底层类型是`[]string`。

由于`MySlice`的底层类型是切片，因此我们可以将类型为`MySlice`的参数传递给`Clone5`。正如您可能已经注意到的，`Clone5`的签名与`slices.Clone`的签名相同。我们终于达到了我们想要的目标。

在继续之前，让我们讨论一下为什么 Go 语法需要一个波浪符**（~）**。看起来我们总是希望允许传递`MySlice`，那么为什么不将其作为默认值呢？或者，如果我们需要支持精确匹配，为什么不反过来，使约束`[]E`允许命名类型，而约束，比如`=[]E`，只允许切片类型文字？

为了解释这一点，让我们首先观察一下`[T ~MySlice]`这样的类型参数列表是没有意义的。这是因为`MySlice`不是任何其他类型的底层类型。例如，如果我们有一个定义如`type MySlice2 MySlice`的定义，`MySlice2`的底层类型是`[]string`，而不是`MySlice`。因此，`[T ~MySlice]`要么不允许任何类型，要么与`[T MySlice]`相同，只匹配`MySlice`。无论哪种方式，`[T ~MySlice]`都是没有用的。为了避免这种混淆，语言禁止`[T ~MySlice]`，并且编译器会产生错误，例如

```bash
invalid use of ~ (underlying type of MySlice is []string)
```

如果 Go 不需要波浪符，让`[S []E]`匹配任何底层类型是`[]E`的类型，那么我们将不得不定义`[S MySlice]`的含义。

我们可以禁止`[S MySlice]`，或者我们可以说`[S MySlice]`只匹配`MySlice`，但无论哪种方法都会遇到与预声明类型的问题。预声明类型，比如`int`，其底层类型是它自身。我们希望允许人们编写接受底层类型为`int`的任何类型参数的约束。在今天的语言中，他们可以通过编写`[T ~int]`来实现这一点。如果我们不需要波浪符，我们仍然需要一种方式来表示“任何底层类型是`int`的类型”。自然的表达方式将是`[T int]`。这将意味着`[T MySlice]`和`[T int]`的行为将不同，尽管它们看起来非常相似。

我们也可以说`[S MySlice]`匹配任何底层类型为`MySlice`底层类型的类型，但这将使`[S MySlice]`变得不必要和令人困惑。

我们认为有必要要求使用波浪符，明确何时匹配底层类型而不是类型本身。  

## 类型接口

现在我们已经解释了`slices.Clone`的签名，让我们看看如何通过类型推断来简化实际使用`slices.Clone`。请记住，`Clone`的签名是

```go
func Clone[S ~[]E, E any](s S) S
```

对于`slices.Clone`的调用将传递一个切片给参数`s`。简单的类型推断将允许编译器推断类型参数`S`的类型参数是传递给`Clone`的切片的类型。类型推断还足够强大，可以看出类型参数`E`的类型参数是传递给`S`的类型参数的元素类型。

这意味着我们可以写成

```go
c := Clone(ms)
```

而不必写成

```go
c := Clone[MySlice, string](ms)
```

如果我们引用`Clone`而不调用它，我们必须为`S`指定一个类型参数，因为编译器没有可以用来推断它的信息。幸运的是，在这种情况下，类型推断能够从`S`的参数中推断出类型参数`E`的类型参数，因此我们不必单独指定它。

也就是说，我们可以写成

```go
myClone := Clone[MySlice]
```

而不必写成

```go
myClone := Clone[MySlice, string]
```  

## 解析类型参数

我们在这里使用的一般技术是，通过使用另一个类型参数`E`定义一个类型参数`S`，这是一种在通用函数签名中拆解类型的方法。通过拆解类型，我们可以命名并约束类型的所有方面。

例如，这是`maps.Clone`的签名。

```go
func Clone[M ~map[K]V, K comparable, V any](m M) M
```

与`slices.Clone`一样，我们使用一个类型参数来表示参数`m`的类型，然后使用另外两个类型参数`K`和`V`来拆解类型。

在`maps.Clone`中，我们约束`K`必须是可比较的，因为这是映射键类型所要求的。我们可以按照自己的喜好约束组件类型。

```go
func WithStrings[S ~[]E, E interface { String() string }](s S) (S, []string)
```

这表示`WithStrings`的参数必须是一个切片类型，其元素类型必须具有`String`方法。

由于所有的 Go 类型都可以由组件类型构建而来，因此我们始终可以使用类型参数来拆解这些类型并根据需要对其进行约束。  

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
