---
layout: post
title: Go：条件控制语句
tags: go
mermaid: false
math: false
---  

在 Go 语言中，主要的条件控制语句有 `if-else`、`switch` 和 `select`。以下是对它们的简单介绍：

### 1. `if` 语句：

`if` 语句用于根据条件执行不同的代码块。它的基本形式如下：

```go
if condition {
    // code block
} else if condition2 {
    // code block 2
} else {
    // default code block
}
```

- `condition` 是一个布尔表达式，如果为真，将执行与 `if` 关联的代码块。
- 可以有零个或多个 `else if` 部分，每个 `else if` 部分都有一个条件，如果前面的条件为假且当前条件为真，则执行相应的代码块。
- 可以有一个可选的 `else` 部分，用于处理所有条件均为假的情况。

```go
// 示例
num := 42

if num > 50 {
    fmt.Println("Number is greater than 50")
} else if num < 0 {
    fmt.Println("Number is negative")
} else {
    fmt.Println("Number is between 0 and 50 (inclusive)")
}
```

### 2. `switch` 语句：

`switch` 语句用于根据一个表达式的值选择不同的执行路径。它的基本形式如下：

```go
switch expression {
case value1:
    // code block 1
case value2:
    // code block 2
default:
    // default code block
}
```

- `expression` 是一个表达式，其值会与各个 `case` 的值进行比较。
- 如果 `expression` 的值与某个 `case` 的值相匹配，将执行相应的代码块。
- 可以有多个 `case`，每个 `case` 后面跟着一个值。
- `default` 是一个可选部分，表示如果没有匹配的 `case`，则执行 `default` 后面的代码块。

```go
// 示例
day := "Saturday"

switch day {
case "Monday", "Tuesday", "Wednesday", "Thursday", "Friday":
    fmt.Println("It's a weekday.")
case "Saturday", "Sunday":
    fmt.Println("It's a weekend.")
default:
    fmt.Println("Invalid day.")
}
```

### 3. `select` 语句：

`select` 语句用于处理通道（channel）操作，它类似于 `switch`，但专门用于选择执行哪个通道操作。`select` 语句用于在多个通道操作中进行选择，如果有多个通道操作都可以执行，则随机选择一个执行。

```go
select {
case msg1 := <-ch1:
    // code block 1
    fmt.Println("Received", msg1)
case msg2 := <-ch2:
    // code block 2
    fmt.Println("Received", msg2)
case ch3 <- "Hello":
    // code block 3
    fmt.Println("Sent Hello")
default:
    // default code block
    fmt.Println("No communication")
}
```

在 `select` 语句中，只有一个 `case` 会被执行，选择规则是随机的。如果没有可执行的 `case`，则执行 `default`。

### 4. 对比 `if-else` 和 `switch` 

`if-else` 和 `switch` 是用于控制流的两个主要语句。它们都用于根据条件执行不同的代码块，但在某些情况下，`switch` 语句可能更适合一些特定的场景。下面是对比它们的一些方面：

#### 4.1 可读性和简洁性

- **`if-else`：** 适用于简单的条件判断，易于理解和编写。当只有少数几个条件时，`if-else` 可能更直观。

    ```go
    if condition1 {
        // code block 1
    } else if condition2 {
        // code block 2
    } else {
        // default code block
    }
    ```

- **`switch`：** 适用于多个条件的情况，尤其是当条件是固定的值时。`switch` 语句可以更加清晰地表达多个相等条件的情况。

    ```go
    switch value {
    case condition1:
        // code block 1
    case condition2:
        // code block 2
    default:
        // default code block
    }
    ```

#### 4.2 条件匹配

- **`if-else`：** 使用 `if` 语句可以使用任意的条件表达式，包括比较运算符、逻辑运算符等。

    ```go
    if x > 0 && x < 10 {
        // code block
    } else {
        // default code block
    }
    ```

- **`switch`：** `switch` 语句可以用于比较固定值，不仅仅是等于条件，还可以是其他比较操作符。

    ```go
    switch x {
    case 1:
        // code block 1
    case 2, 3:
        // code block 2
    default:
        // default code block
    }
    ```

#### 4.3 类型匹配

- **`if-else`：** 可以通过类型断言来进行类型匹配。

    ```go
    if value, ok := x.(int); ok {
        // code block
    } else {
        // default code block
    }
    ```

- **`switch`：** `switch` 语句可以直接匹配接口值的类型。

    ```go
    switch x.(type) {
    case int:
        // code block 1
    case string:
        // code block 2
    default:
        // default code block
    }
    ```

#### 4.4 Fallthrough

- **`if-else`：** 不支持 `fallthrough`。
- **`switch`：** `switch` 语句可以使用 `fallthrough` 来继续执行下一个 `case`。

    ```go
    switch x {
    case 1:
        // code block 1
        fallthrough
    case 2:
        // code block 2
    default:
        // default code block
    }
    ```

#### 4.5 比较多个值

- **`if-else`：** 需要使用多个 `if` 语句来比较多个值。

    ```go
    if x == 1 {
        // code block 1
    } else if x == 2 {
        // code block 2
    } else {
        // default code block
    }
    ```

- **`switch`：** `switch` 语句可以一次性比较多个值。

    ```go
    switch x {
    case 1, 2:
        // code block
    default:
        // default code block
    }
    ```

### 扩展：fallthrough

`fallthrough` 是 Go 语言中的一个特殊关键字，用于在 `switch` 语句中强制执行下一个 `case` 的代码块，而不进行条件判断。在正常情况下，`switch` 语句在匹配到一个 `case` 后会退出整个 `switch` 语句，但使用 `fallthrough` 关键字可以改变这一行为。

以下是一个使用 `fallthrough` 的简单示例：

```go
package main

import "fmt"

func main() {
    switch num := 2; num {
    case 1:
        fmt.Println("This is case 1.")
        fallthrough
    case 2:
        fmt.Println("This is case 2.")
        fallthrough
    case 3:
        fmt.Println("This is case 3.")
    }
}
```

在这个示例中，`fallthrough` 关键字被用于在匹配到 `case 1` 和 `case 2` 后继续执行 `case 3` 的代码块，即使 `case 2` 的条件也匹配。

需要注意的是，`fallthrough` 会导致下一个 `case` 的代码块无条件执行，而不进行后续的条件判断。这在某些情况下可能会带来意外的结果，因此在使用 `fallthrough` 时需要谨慎。一般而言，`fallthrough` 的使用场景相对较少，通常在需要某种特定的逻辑流程时才会使用。

在实际编程中，大多数情况下，`fallthrough` 并不是必须的，而是通过 `case` 条件来控制流程更加清晰和容易理解。

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
