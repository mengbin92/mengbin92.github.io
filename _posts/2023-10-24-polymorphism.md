---
layout: post
title: Go 如何实现多态
tags: go
mermaid: false
math: false
---  

在 Go 语言中，虽然没有经典的面向对象编程中的继承和多态的概念，但你可以通过接口（interface）来实现多态性。Go 语言鼓励组合和接口多态，这使得代码更加灵活和模块化。下面将详细介绍 Go 语言中如何实现多态。

多态性是面向对象编程的一个核心概念，它允许不同类型的对象在一致的接口下执行不同的操作。在 Go 中，多态性通常是通过接口来实现的。

### 1. 定义接口

首先，你需要定义一个接口，该接口定义了一组方法，这些方法将被不同类型的对象实现。接口通常用于描述对象的行为。

```go
type Shape interface {
    Area() float64
}
```

上面的 `Shape` 接口定义了一个名为 `Area` 的方法，该方法返回一个浮点数。任何实现了 `Shape` 接口的类型都必须提供 `Area` 方法的具体实现。

### 2. 创建不同类型的结构体

接下来，你可以创建不同类型的结构体，这些结构体将实现 `Shape` 接口。每个结构体都需要提供 `Area` 方法的具体实现。

```go
type Rectangle struct {
    Width  float64
    Height float64
}

type Circle struct {
    Radius float64
}

func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

func (c Circle) Area() float64 {
    return math.Pi * c.Radius * c.Radius
}
```

上述代码定义了两种形状，矩形和圆形，并为它们分别实现了 `Area` 方法。

### 3. 使用多态

现在，你可以创建不同类型的对象，并使用它们通过接口进行多态调用。

```go
func main() {
    r := Rectangle{Width: 4, Height: 5}
    c := Circle{Radius: 3}

    shapes := []Shape{r, c}

    for _, shape := range shapes {
        fmt.Printf("Area: %f\n", shape.Area())
    }
}
```

在上面的 `main` 函数中，我们创建了一个 `shapes` 切片，该切片包含了不同类型的形状对象（矩形和圆形）。然后，我们遍历 `shapes` 切片，并通过接口 `Shape` 调用 `Area` 方法。由于这两种形状都实现了 `Shape` 接口，因此多态性使我们能够以一致的方式调用它们的 `Area` 方法。

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
