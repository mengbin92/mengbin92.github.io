---
layout: post
title: Go：接口
tags: go
mermaid: false
math: false
---  

在 Go 语言中，接口（interface）是一种定义对象行为的类型。接口定义了一组方法的集合，但是不会实现这些方法。任何类型只要实现了接口中定义的所有方法，就被称为实现了该接口。

## Go 接口的特点和用法

1. **接口定义**：
   - 使用 `type` 关键字定义接口，接口中包含一组方法签名（没有具体的实现），例如：
     ```go
     type Shape interface {
         Area() float64
         Perimeter() float64
     }
     ```
   - 上述代码定义了一个 `Shape` 接口，要求实现 `Area()` 和 `Perimeter()` 方法。
2. **接口实现**：
   - 任何类型（包括结构体、基本类型等）只要实现了接口中定义的所有方法，就被视为实现了该接口。
   - 实现接口的类型无需显式声明，只要方法签名与接口中定义的方法一致即可。
3. **隐式实现**：
   - Go 中的接口实现是隐式的，不需要显式声明类型实现了某个接口。只要类型拥有接口中定义的所有方法，它就自动满足该接口的要求。
4. **接口类型**：
   - 接口类型可以作为变量、函数参数或返回值使用，从而实现多态性。
   - 例如，可以定义一个接收 `Shape` 接口类型的函数，这样不同实现了 `Shape` 接口的类型都可以作为参数传递给该函数。
5. **空接口**：
   - 空接口 `interface{}` 没有任何方法，因此任何类型都实现了空接口。
   - 空接口在需要保存任意类型值的场景下很有用，类似于其他语言中的通用类型。
6. **接口嵌套**：
   - 接口可以嵌套在其他接口中，这样新的接口将包含所有嵌套接口的方法。
7. **接口与类型断言**：
   - 使用类型断言可以将接口值转换为具体的实现类型，以访问实现类型的特定方法或字段。

## 示例

```go
package main

import (
	"fmt"
	"math"
)

// 定义接口
type Shape interface {
	Area() float64
	Perimeter() float64
}

// 实现接口的结构体：矩形
type Rectangle struct {
	width, height float64
}

// 矩形实现接口方法
func (r Rectangle) Area() float64 {
	return r.width * r.height
}

func (r Rectangle) Perimeter() float64 {
	return 2*r.width + 2*r.height
}

// 主程序
func main() {
	// 创建一个矩形实例
	rect := Rectangle{width: 3, height: 4}

	// 将矩形实例传递给函数，该函数接收 Shape 接口类型
	printShapeInfo(rect)
}

// 函数接收 Shape 接口类型
func printShapeInfo(s Shape) {
	fmt.Printf("Area: %f\n", s.Area())
	fmt.Printf("Perimeter: %f\n", s.Perimeter())
}
```

在这个示例中，`Rectangle` 结构体实现了 `Shape` 接口的 `Area()` 和 `Perimeter()` 方法。在 `main` 函数中，`Rectangle` 类型的实例被传递给 `printShapeInfo` 函数，该函数接收 `Shape` 接口类型作为参数。这样，通过接口，可以实现对不同类型的形状（比如矩形、圆形等）统一的操作和处理。

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
