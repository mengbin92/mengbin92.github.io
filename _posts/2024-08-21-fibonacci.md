---
layout: post
title: Fibonacci数列
tags: 算法
mermaid: false
math: false
---  

Fibonacci 数列是一种在数学中非常著名的数列，其定义如下：

- Fibonacci 数列的第一个数为 0（有时也以 1 为第一个数），第二个数为 1。
- 其后的每一个数都是前两个数之和。即：
  
  \[
  F(0) = 0, F(1) = 1
  \]
  \[
  F(n) = F(n-1) + F(n-2) \quad \text{for } n \geq 2
  \]

因此，Fibonacci 数列的前几个数是：

\[
0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, \ldots
\]

## Go 语言实现基础版 Fibonacci 数列

在 Go 语言中，可以用递归、循环或记忆化递归来实现 Fibonacci 数列。我们先来看一个最基础的递归实现。

```go
package main

import "fmt"

// 递归计算Fibonacci数列
func fibonacci(n int) int {
    if n <= 1 {
        return n
    }
    return fibonacci(n-1) + fibonacci(n-2)
}

func main() {
    n := 10 // 求第10个Fibonacci数
    fmt.Println(fibonacci(n))
}
```

这个递归实现非常直观，直接按照 Fibonacci 数列的定义进行计算。然而，基础的递归实现有一些严重的性能问题。

## 性能问题分析

上述递归方法在计算 Fibonacci 数时会出现大量的重复计算。例如，在计算 `fibonacci(5)` 时需要计算 `fibonacci(4)` 和 `fibonacci(3)`，而计算 `fibonacci(4)` 时又要计算 `fibonacci(3)` 和 `fibonacci(2)`，这样 `fibonacci(3)` 就被计算了多次。随着 `n` 的增大，这种重复计算的次数呈指数级增长，导致算法的时间复杂度为 `O(2^n)`。

## Go 语言优化版 Fibonacci 数列

为了优化 Fibonacci 数列的计算，我们可以采用以下几种方法：

### 1. 记忆化递归

通过使用一个数组或映射来存储已经计算过的 Fibonacci 值，避免重复计算。这种技术叫做“记忆化”。

```go
package main

import "fmt"

// 记忆化递归计算Fibonacci数列
func fibonacci(n int, memo map[int]int) int {
    if n <= 1 {
        return n
    }
    if val, ok := memo[n]; ok {
        return val
    }
    memo[n] = fibonacci(n-1, memo) + fibonacci(n-2, memo)
    return memo[n]
}

func main() {
    n := 10 // 求第10个Fibonacci数
    memo := make(map[int]int)
    fmt.Println(fibonacci(n, memo))
}
```

记忆化递归显著减少了重复计算，将时间复杂度降至 `O(n)`。

### 2. 动态规划

动态规划方法通过从下往上计算 Fibonacci 数列，逐步累积结果，而不需要递归。这是最常用的优化手段。

```go
package main

import "fmt"

// 动态规划计算Fibonacci数列
func fibonacci(n int) int {
    if n <= 1 {
        return n
    }
    fib := make([]int, n+1)
    fib[0] = 0
    fib[1] = 1
    for i := 2; i <= n; i++ {
        fib[i] = fib[i-1] + fib[i-2]
    }
    return fib[n]
}

func main() {
    n := 10 // 求第10个Fibonacci数
    fmt.Println(fibonacci(n))
}
```

这种方法也将时间复杂度降低为 `O(n)`，并且由于只需记录前两个 Fibonacci 数，因此空间复杂度可以进一步优化到 `O(1)`。

### 3. 滚动数组优化

我们可以进一步优化动态规划算法，使其只使用常数级别的空间。因为在计算第 `n` 个 Fibonacci 数时，只需要用到前两个数，所以只需两个变量存储前两个数的值。

```go
package main

import "fmt"

// 滚动数组优化计算Fibonacci数列
func fibonacci(n int) int {
    if n <= 1 {
        return n
    }
    a, b := 0, 1
    for i := 2; i <= n; i++ {
        a, b = b, a+b
    }
    return b
}

func main() {
    n := 10 // 求第10个Fibonacci数
    fmt.Println(fibonacci(n))
}
```

在这个版本中，空间复杂度已经优化到 `O(1)`，依然保持时间复杂度为 `O(n)`。

## 最后

- 基础的递归方法直观但效率低下，适用于小规模计算。
- 记忆化递归通过避免重复计算，显著提升了递归方法的效率。
- 动态规划通过从下往上的方式计算 Fibonacci 数列，进一步提升效率。
- 滚动数组优化在动态规划的基础上进一步降低了空间复杂度，使算法更加高效。  

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
