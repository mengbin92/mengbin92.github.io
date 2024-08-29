---
layout: post
title: 函数类型的范围
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/range-functions)。  

> 由 Ian Lance Taylor 发布于 2024年8月20日

## 简介

这篇博文是我在 2024 年 GopherCon 大会上演讲的文字版。

函数类型的范围是 Go 1.23 版本中的一项新语言特性。这篇博文将解释我们为什么要添加这个新特性、它到底是什么，以及如何使用它。

## Why？

自 Go 1.18 以来，我们已经能够在 Go 中编写新的泛型容器类型。举个例子，让我们来看一个基于 map 实现的非常简单的 Set 类型。  

```go
// Set holds a set of elements.
type Set[E comparable] struct {
    m map[E]struct{}
}

// New returns a new [Set].
func New[E comparable]() *Set[E] {
    return &Set[E]{m: make(map[E]struct{})}
}
``` 

当然，集合类型会有添加元素的方法和检查元素是否存在的方法，这些暂时不在我们考虑的范围内。

```go
// Add adds an element to a set.
func (s *Set[E]) Add(v E) {
    s.m[v] = struct{}{}
}

// Contains reports whether an element is in a set.
func (s *Set[E]) Contains(v E) bool {
    _, ok := s.m[v]
    return ok
}
``` 

此外，我们还希望有一个函数来返回两个集合的并集。  

```go
// Union returns the union of two sets.
func Union[E comparable](s1, s2 *Set[E]) *Set[E] {
    r := New[E]()
    // Note for/range over internal Set field m.
    // We are looping over the maps in s1 and s2.
    for v := range s1.m {
        r.Add(v)
    }
    for v := range s2.m {
        r.Add(v)
    }
    return r
}
``` 

让我们先看看这个`Union`函数的实现。为了计算两个集合的并集，我们需要一种方法来获取每个集合中的所有元素。在这段代码中，我们使用`for/range`语句遍历了集合类型的一个未导出的字段。这种方式只有在`Union`函数定义在集合包中时才有效。

但实际上，有很多理由让人们可能想遍历集合中的所有元素。因此，这个集合包必须提供某种方式让用户可以做到这一点。

那应该如何实现呢？  

## Push 集合元素  

一种是提供给 Set 一个方法，该方法接受一个函数参数，并将 Set 中的每个元素传递给该函数。我们称之为`Push`，因为集合将每个值“推送”到函数中。如果函数返回`false`，我们就停止调用它。  

```go
func (s *Set[E]) Push(f func(E) bool) {
    for v := range s.m {
        if !f(v) {
            return
        }
    }
}
``` 

在 Go 标准库中，我们可以看到这种通用模式用于 [sync.Map.Range](https://pkg.go.dev/sync#Map.Range) 方法、[flag.Visit](https://pkg.go.dev/flag#Visit) 函数和 [filepath.Walk](https://pkg.go.dev/path/filepath#Walk) 函数等情况。这是一种通用模式，而非精确的模式；实际上，这三个例子中的工作方式并不完全相同。

使用`Push`方法打印集合中所有元素的代码看起来是这样的：你调用`Push`方法，并传入一个处理元素的函数。  

```go
func PrintAllElementsPush[E comparable](s *Set[E]) {
    s.Push(func(v E) bool {
        fmt.Println(v)
        return true
    })
}
``` 

## Pull 集合元素  

另一种遍历集合元素的方法是返回一个函数。每次调用该函数时，它会返回集合中的一个值，同时返回一个布尔值来指示该值是否有效。当遍历完所有元素时，布尔结果将为 false。在这种情况下，我们还需要一个停止函数，当不再需要更多值时可以调用它。

这种实现使用了一对通道：一个用于存放集合中的值，另一个用于停止返回值。我们使用一个 goroutine 将值发送到通道中。`next`函数通过从元素通道中读取来返回集合中的元素，而`stop`函数通过关闭停止通道告诉 goroutine 退出。我们需要`stop`函数来确保在不再需要更多值时，goroutine 能够正确退出。  

```go
// Pull returns a next function that returns each
// element of s with a bool for whether the value
// is valid. The stop function should be called
// when finished calling the next function.
func (s *Set[E]) Pull() (func() (E, bool), func()) {
    ch := make(chan E)
    stopCh := make(chan bool)

    go func() {
        defer close(ch)
        for v := range s.m {
            select {
            case ch <- v:
            case <-stopCh:
                return
            }
        }
    }()

    next := func() (E, bool) {
        v, ok := <-ch
        return v, ok
    }

    stop := func() {
        close(stopCh)
    }

    return next, stop
}
```

标准库中没有完全按照这种方式工作的函数。[runtime.CallersFrames](https://pkg.go.dev/runtime#CallersFrames) 和 [reflect.Value.MapRange](https://pkg.go.dev/reflect#Value.MapRange) 与此类似，尽管它们返回的方法值而不是直接返回函数。

这是使用`Pull`方法打印集合中所有元素的示例。你可以调用`Pull`获取一个函数，然后在`for`循环中反复调用该函数。

```go
func PrintAllElementsPull[E comparable](s *Set[E]) {
    next, stop := s.Pull()
    defer stop()
    for v, ok := next(); ok; v, ok = next() {
        fmt.Println(v)
    }
}
```

## 规范化方法

我们已经看到了两种不同的遍历集合所有元素的方法。不同的 Go 包使用这些和其他几种方法。这意味着当你开始使用一个新的 Go 容器包时，你可能需要学习一种新的遍历机制。这也意味着我们无法编写一种可以在多个不同类型的容器中通用的函数，因为容器类型的遍历方式不同。

我们希望通过开发遍历容器的标准方法来改善 Go 生态系统。

### 迭代器

这当然是许多编程语言中都会遇到的问题。

1994 年首次出版的 [设计模式](https://en.wikipedia.org/wiki/Design_Patterns) 一书中描述了这种迭代器模式。你可以使用迭代器“提供一种在不暴露其底层表示的情况下顺序访问聚合对象元素的方法”。这里所谓的聚合对象就是我所说的容器。聚合对象或容器就是包含其他值的值，就像我们之前讨论的`Set`类型。

与编程中的许多概念一样，迭代器可以追溯到 Barbara Liskov 在 1970 年代开发的 [CLU 语言](https://en.wikipedia.org/wiki/CLU_(programming_language))。

如今，许多流行语言都以某种方式提供了迭代器，包括 C++、Java、Javascript、Python 和 Rust 等。

然而，Go 在 1.23 版本之前并没有。

### for/range

众所周知，Go 语言内建了一些容器类型： silces、arrays和maps。它还提供了一种在不暴露底层表示的情况下访问这些值元素的方法：`for/range`语句。`for/range`语句适用于 Go 的内建容器类型（以及字符串、通道，以及 Go 1.22 中的`int`）。

`for/range`语句是迭代，但它并不是今天流行语言中出现的迭代器。尽管如此，能够使用`for/range`来迭代像`Set`这样的用户定义容器仍然是很好的。

然而，Go 在 1.23 版本之前并不支持这一点。

### 此版本中的改进

在 Go 1.23 中，我们决定支持`for/range`遍历用户定义的容器类型，并支持一种标准化的迭代器形式。

我们扩展了`for/range`语句，使其支持函数类型的遍历。我们将在下文中看到这是如何帮助遍历用户定义的容器的。

我们还添加了标准库类型和函数，以支持将函数类型用作迭代器。标准的迭代器定义让我们可以编写在不同容器类型中平滑工作的函数。

### 遍历（某些）函数类型

改进后的`for/range`语句不支持任意函数类型。从 Go 1.23 开始，它支持遍历单个参数的函数。该单个参数本身必须是一个函数，该函数接受零到两个参数并返回一个布尔值；按惯例，我们将其称为`yield`函数。

```go
func(yield func() bool)
func(yield func(V) bool)
func(yield func(K, V) bool)
```

当我们在 Go 中谈论迭代器时，我们指的是具有这三种类型之一的函数。正如我们下面将讨论的，在标准库中还有另一种迭代器：`pull`迭代器。当需要区分标准迭代器和`pull`迭代器时，我们称标准迭代器为`push`迭代器。这是因为，正如我们将看到的，它们通过调用`yield`函数来推送出一系列值。

### 标准（push）迭代器

为了使迭代器更容易使用，新的标准库包`iter`定义了两种类型：`Seq`和`Seq2`。这些名称表示迭代器函数类型，可以与`for/range`语句一起使用。`Seq`是`sequence`（序列）的缩写，因为迭代器遍历的是一系列值。

```go
package iter

type Seq[V any] func(yield func(V) bool)

type Seq2[K, V any] func(yield func(K, V) bool)

// for now, no Seq0
```

`Seq`和`Seq2`的区别仅在于`Seq2`是一对对的序列，例如映射中的键和值。在本文中，为了简化，我们将专注于`Seq`，但我们讨论的大多数内容也适用于`Seq2`。

用一个例子来解释迭代器的工作原理最为简单。这里`Set`的方法`All`返回一个函数。`All`的返回类型为`iter.Seq[E]`，因此我们知道它返回一个迭代器。

```go
// All 是 s 元素的迭代器。
func (s *Set[E]) All() iter.Seq[E] {
    return func(yield func(E) bool) {
        for v := range s.m {
            if !yield(v) {
                return
            }
        }
    }
}
```

迭代器函数本身接受另一个函数作为参数，即`yield`函数。迭代器调用`yield`函数并传入集合中的每个值。在这种情况下，`Set.All`返回的迭代器函数非常类似于我们之前看到的`Set.Push`函数。

这显示了迭代器的工作原理：对于某个值序列，迭代器依次调用`yield`函数并传入该序列中的每个值。如果`yield`函数返回`false`，则表示不再需要更多的值，迭代器可以直接返回，完成所有必要的清理工作。如果`yield`函数从不返回`false`，则迭代器会在调用`yield`完序列中的所有值后返回。

这就是它们的工作方式，但我们要承认，第一次看到这种方式时，你的第一反应可能是“这里有很多函数在飞来飞去”。你的感觉是对的。现在我们专注以下两点。

首先，一旦你越过了这个函数代码的第一行，迭代器的实际实现就相当简单：用集合中的每个元素调用`yield`，如果`yield`返回`false`就停止。

```go
for v := range s.m {
    if !yield(v) {
        return
    }
}
```

其次，使用这个方法非常简单。你调用`s.All`来获取一个迭代器，然后使用`for/range`来遍历`s`中的所有元素。`for/range`语句支持任何迭代器，这显示了它的易用性。

```go
func PrintAllElements[E comparable](s *Set[E]) {
    for v := range s.All() {
        fmt.Println(v)
    }
}
```

在这类代码中，`s.All`是一个返回函数的方法。我们调用`s.All`，然后使用`for/range`遍历它返回的函数。在这种情况下，我们本可以让`Set.All`自身成为一个迭代器函数，而不是返回一个迭代器函数。然而，在某些情况下，这种方法无法工作，例如当返回迭代器的函数需要接受参数或需要执行一些设置工作时。作为一种惯例，我们鼓励所有容器类型提供一个返回迭代器的`All`方法，这样程序员就不必记住是直接遍历`All`还是调用`All`获取一个可以遍历的值。他们总是可以选择后者。

仔细思考，你会发现编译器必须调整循环，以创建一个`yield`函数并将其传递给`s.All`返回的迭代器。Go 编译器和运行时中有相当复杂的部分来使这项工作高效，并正确处理循环中的`break`或`panic`等情况。我们在这篇博客文章中不会讨论这些实现细节。幸运的是，实际使用这个功能时，具体实现细节并不重要。

### Pull 迭代器

我们已经了解了如何在`for/range`循环中使用迭代器。但简单的循环并不是使用迭代器的唯一方式。例如，有时我们可能需要并行迭代两个容器。如何实现呢？

答案是使用一种不同类型的迭代器：拉取迭代器。我们已经看到，标准迭代器（也称为推送迭代器）是一个调用`yield`函数的函数。拉取迭代器是一对函数。

`pull`迭代器则是相反的：它是一个函数，每次调用它时，它会返回序列中的下一个值。

我们再重复一下这两种迭代器的区别，以帮助你记住：

- 推送迭代器会将序列中的每个值推送给一个`yield`函数。推送迭代器是Go标准库中的标准迭代器，并且直接受`for/range`语句支持。
- 拉取迭代器则是相反的。每次调用拉取迭代器时，它会从序列中拉取另一个值并返回它。拉取迭代器并未被`for/range`语句直接支持；然而，编写一个普通的`for`语句来循环拉取迭代器是很简单的。实际上，我们在之前讨论`Set.Pull`方法时看到了一个例子。

你可以自己编写一个拉取迭代器，但通常你不需要这样做。新的标准库函数[iter.Pull](https://pkg.go.dev/iter#Pull)可以接收一个标准迭代器，即推送迭代器函数，并返回一对函数。第一个是拉取迭代器：一个函数，每次调用它时都会返回序列中的下一个值。第二个是一个`stop`函数，应该在我们使用完拉取迭代器时调用。这与我们之前看到的`Set.Pull`方法类似。

`iter.Pull`返回的第一个函数，即拉取迭代器，返回一个值和一个布尔值，布尔值表示该值是否有效。在序列的末尾，布尔值会为`false`。

`iter.Pull`返回的`stop`函数是为了防止我们未读取完序列就结束迭代。在一般情况下，传给`iter.Pull`的推送迭代器可能会启动新的goroutine，或构建需要在迭代完成后清理的新数据结构。当`yield`函数返回`false`，意味着不再需要更多的值时，推送迭代器将执行任何清理工作。当与`for/range`语句一起使用时，`for/range`语句将确保如果循环因`break`语句或其他原因提前退出，则`yield`函数将返回`false`。而对于拉取迭代器，则无法强制`yield`函数返回`false`，因此需要`stop`函数。

换句话说，调用`stop`函数将导致`yield`函数在推送迭代器调用它时返回`false`。

严格来说，如果拉取迭代器返回`false`表示已经到达序列的末尾，那么你不需要调用`stop`函数，但通常情况下，直接调用它更为简单。

下面是一个使用拉取迭代器并行遍历两个序列的示例。此函数用于判断两个任意序列是否包含相同顺序的相同元素。

```go
// EqSeq reports whether two iterators contain the same
// elements in the same order.
func EqSeq[E comparable](s1, s2 iter.Seq[E]) bool {
    next1, stop1 := iter.Pull(s1)
    defer stop1()
    next2, stop2 := iter.Pull(s2)
    defer stop2()
    for {
        v1, ok1 := next1()
        v2, ok2 := next2()
        if !ok1 {
            return !ok2
        }
        if ok1 != ok2 || v1 != v2 {
            return false
        }
    }
}
```

这个函数使用`iter.Pull`将两个推送迭代器`s1`和`s2`转换为拉取迭代器。它使用`defer`语句确保在使用完拉取迭代器后停止它们。

然后代码进入循环，调用拉取迭代器以检索值。如果第一个序列结束了，它会返回`true`，前提是第二个序列也结束了，否则返回`false`。如果两个值不同，则返回`false`。然后循环拉取下一个值。

与推送迭代器一样，Go运行时中也存在一些复杂性来提高拉取迭代器的效率，但这不会影响实际使用`iter.Pull`函数的代码。

## 迭代器的适配器

现在你已经了解了关于函数类型的`range`和迭代器的所有内容。希望你能享受使用它们的过程！

不过，仍然有一些值得一提的内容。

### 适配器  

标准定义的迭代器的一个优势是可以编写使用它们的标准适配器函数。

例如，下面是一个过滤值序列的函数，它返回一个新序列。此`Filter`函数接受一个迭代器作为参数，并返回一个新的迭代器。另一个参数是决定哪些值应该包含在`Filter`返回的新迭代器中的过滤函数。

```go
// Filter returns a sequence that contains the elements
// of s for which f returns true.
func Filter[V any](f func(V) bool, s iter.Seq[V]) iter.Seq[V] {
    return func(yield func(V) bool) {
        for v := range s {
            if f(v) {
                if !yield(v) {
                    return
                }
            }
        }
    }
}
```

和之前的例子一样，函数签名看起来比较复杂，但一旦理解了签名，实际实现非常简单。

```go
        for v := range s {
            if f(v) {
                if !yield(v) {
                    return
                }
            }
        }
```

代码遍历输入迭代器，检查过滤函数，并对应该包含在输出迭代器中的值调用`yield`。  

我们将在下面展示一个使用 `Filter` 的示例。

（目前 Go 标准库中还没有 `Filter` 的版本，但未来的发布中可能会添加。）

### 使用推送迭代器遍历二叉树

下面这个示例展示了使用push迭代器遍历容器类型的便利性。我们来看一个简单的二叉树类型。 

```go
// Tree is a binary tree.
type Tree[E any] struct {
    val         E
    left, right *Tree[E]
}
```

我们不会展示插入值的代码，但显然应该有一种方法来遍历树中的所有值。

事实证明，迭代器代码如果返回布尔值会更容易编写。由于`for/range`支持的函数类型不返回任何内容，这里的`All`方法返回一个小的函数字面量，该字面量调用迭代器本身（这里叫`push`），并忽略布尔结果。

```go
// All returns an iterator over the values in t.
func (t *Tree[E]) All() iter.Seq[E] {
    return func(yield func(E) bool) {
        t.push(yield)
    }
}

// push pushes all elements to the yield function.
func (t *Tree[E]) push(yield func(E) bool) bool {
    if t == nil {
        return true
    }
    return t.left.push(yield) &&
        yield(t.val) &&
        t.right.push(yield)
}
```

`push`方法使用递归遍历整棵树，并对每个元素调用`yield`。如果`yield`函数返回`false`，方法会一路返回`false`，否则它只会在迭代完成后返回`true`。

这展示了使用这种迭代器方法遍历复杂数据结构的简便性。无需维护一个单独的堆栈来记录树中的位置；我们可以直接使用goroutine的调用栈来完成这项工作。

### 新的迭代器函数

Go 1.23还引入了`slice`和`map`包中的一些与迭代器相关的新函数。

以下是 `slices` 包中的新函数。`All` 和 `Values` 是返回切片元素迭代器的函数。`Collect` 从迭代器中提取值并返回包含这些值的切片。其他的请参见文档。

- [All([]E) iter.Seq2[int, E]](https://pkg.go.dev/slices#All)
- [Values([]E) iter.Seq[E]](https://pkg.go.dev/slices#Values)
- [Collect(iter.Seq[E]) []E](https://pkg.go.dev/slices#Collect)
- [AppendSeq([]E, iter.Seq[E]) []E](https://pkg.go.dev/slices#AppendSeq)
- [Backward([]E) iter.Seq2[int, E]](https://pkg.go.dev/slices#Backward)
- [Sorted(iter.Seq[E]) []E](https://pkg.go.dev/slices#Sorted)
- [SortedFunc(iter.Seq[E], func(E, E) int) []E](https://pkg.go.dev/slices#SortedFunc)
- [SortedStableFunc(iter.Seq[E], func(E, E) int) []E](https://pkg.go.dev/slices#SortedStableFunc)
- [Repeat([]E, int) []E](https://pkg.go.dev/slices#Repeat)
- [Chunk([]E, int) iter.Seq([]E)](https://pkg.go.dev/slices#Chunk)

以下是 `maps` 包中的新函数。`All`、`Keys` 和 `Values` 返回映射内容的迭代器。`Collect` 从迭代器中提取键和值，并返回一个新的映射。

- [All(map[K]V) iter.Seq2[K, V]](https://pkg.go.dev/maps#All)
- [Keys(map[K]V) iter.Seq[K]](https://pkg.go.dev/maps#Keys)
- [Values(map[K]V) iter.Seq[V]](https://pkg.go.dev/maps#Values)
- [Collect(iter.Seq2[K, V]) map[K, V]](https://pkg.go.dev/maps#Collect)
- [Insert(map[K, V], iter.Seq2[K, V])](https://pkg.go.dev/maps#Insert)

### 标准库迭代器示例

这里是一个如何使用这些新函数和前面提到的`Filter`函数的示例。此函数接收一个`int`到`string`的map，并返回一个slice，其中只包含长度大于等于某个参数`n`的值。

```go
// LongStrings returns a slice of just the values
// in m whose length is n or more.
func LongStrings(m map[int]string, n int) []string {
    isLong := func(s string) bool {
        return len(s) >= n
    }
    return slices.Collect(Filter(isLong, maps.Values(m)))
}
```

`maps.Values`函数返回一个`m`中值的迭代器。`Filter`读取该迭代器并返回一个只包含长字符串的新迭代器。`slices.Collect`从该迭代器中读取值并生成一个新的slice。

当然，你可以很容易地编写一个循环来完成这项工作，在许多情况下，循环会更清晰。我们并不鼓励所有人总是用这种方式编写代码。尽管如此，使用迭代器的优势在于，这种函数可以与任何序列以相同的方式工作。在这个示例中，请注意`Filter`将`map`作为输入，并将`slice`作为输出，而无需更改`Filter`中的代码。

#### 遍历文件中的行

虽然我们看到的大多数示例都涉及容器，但迭代器非常灵活。

考虑这段简单的代码，它不使用迭代器来遍历字节切片中的行。编写起来非常简单，并且效率相对较高。

```go
    for _, line := range bytes.Split(data, []byte{'\n'}) {
        handleLine(line)
    }
```

然而，`bytes.Split`确实会分配并返回一个切片来保存这些行。垃圾回收器将需要一些工作来最终释放这个切片。

下面是一个返回字节切片中行的迭代器的函数。经过常规的迭代器签名后，函数非常简单。我们不断从`data`中提取行，直到没有内容，然后将每行传递给`yield`函数。

```go
// Lines returns an iterator over lines in data.
func Lines(data []byte) iter.Seq[[]byte] {
    return func(yield func([]byte) bool) {
        for len(data) > 0 {
            line, rest, _ := bytes.Cut(data, []byte{'\n'})
            if !yield(line) {
                return
            }
            data = rest
        }
    }
}
```

现在我们遍历字节切片中的行的代码看起来像这样：

```go
    for _, line := range Lines(data) {
        handleLine(line)
    }
```

编写起来同样简单，而且更高效一些，因为它不需要分配一个行的切片。

#### 向推送迭代器传递函数

在我们的最后一个示例中，我们将看到你不必在`range`语句中使用推送迭代器。

之前我们看到一个`PrintAllElements`函数，它打印集合中的每个元素。这里有另一种打印集合中所有元素的方法：调用`s.All`获取一个迭代器，然后传入一个手写的`yield`函数。这个`yield`函数只是打印一个值并返回`true`。注意这里有两个函数调用：我们调用`s.All`获取一个迭代器（它本身是一个函数），然后用我们手写的`yield`函数调用该函数。

```go
func PrintAllElements[E comparable](s *Set[E]) {
    s.All()(func(v E) bool {
        fmt.Println(v)
        return true
    })
}
```

没有特别的理由以这种方式编写代码。这只是为了表明`yield`函数并不神秘。它可以是任何你喜欢的函数。

## 更新`go.mod`

最后一点说明：每个Go模块都会指定它使用的语言版本。这意味着要在现有模块中使用新语言特性，你可能需要更新该版本。这对于所有新语言特性都适用；这并不是特定于`range`函数类型的要求。由于`range`函数类型是在Go 1.23发布的新特性，使用它需要指定至少Go语言版本1.23。

有（至少）四种方法来设置语言版本：

- 在命令行中，运行`go get go@1.23`（或`go mod edit -go=1.23`，仅编辑go指令）。
- 手动编辑`go.mod`文件并更改`go`行。
- 保留整个模块的旧语言版本，但使用`//go:build go1.23`构建标记来允许在特定文件中使用`range`函数类型。

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
