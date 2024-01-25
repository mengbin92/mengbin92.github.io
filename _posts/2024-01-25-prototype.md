---
layout: post
title: 设计模式之原型模式
tags: 设计模式
mermaid: false
math: false
---  

## 概念

原型模式（Prototype Pattern）是一种创建型设计模式，它允许通过复制现有对象来创建新对象，而无需知道其具体类。这种模式适用于对象的创建成本较高，但复制对象的成本较低的情况。

在原型模式中，我们通过复制（Clone）现有对象来创建新对象，而不是通过实例化新的对象。这种方式可以在运行时动态地获取对象的副本，从而避免了显式地使用构造函数。  

## 结构  

原型模式的结构主要包括以下几个部分：  

- **抽象原型类（Abstract Prototype）**：这是一个抽象类，定义了一个克隆（Clone）方法，用于创建新的实例。抽象原型类通常包含一些抽象方法，这些方法需要在具体原型类中实现。
- **具体原型类（Concrete Prototype）**：这是抽象原型类的具体实现。它实现了抽象原型类中定义的抽象方法，并实现了克隆（Clone）方法，用于创建新的实例。具体原型类通常包含一些属性，这些属性在克隆方法中被复制到新实例中。
- **客户端（Client）**：这是使用原型模式的客户端代码。客户端通过调用具体原型类的克隆（Clone）方法来创建新的实例。然后，客户端可以根据需要修改新实例的属性值。

## 适用场景

原型模式适用于以下场景：

1. 创建对象的成本较高：在某些情况下，创建对象可能需要较多的资源和时间。例如，对象的初始化过程可能涉及到复杂的计算或者大量的数据读取。在这种情况下，使用原型模式可以通过复制现有实例来创建新实例，从而避免创建对象的成本。
2. 多个对象之间具有相似性：如果多个对象之间具有相似的结构和行为，但是它们之间仍然存在一些差异，那么可以使用原型模式来创建这些对象。通过在原型对象中定义通用的属性和方法，可以在所有实例中共享这些属性和方法，从而减少代码的重复。
3. 动态地修改对象：原型模式允许在运行时动态地修改对象的行为。例如，如果需要在程序运行过程中添加新的方法或者修改现有方法的实现，可以修改原型对象，从而影响到所有实例。
4. 需要避免使用类继承：在某些情况下，使用类继承可能导致代码结构的复杂化。例如，当需要在一个类中实现多个具有相似行为的接口时，使用类继承可能导致大量的方法重写。在这种情况下，可以使用原型模式来避免使用类继承，降低代码的复杂性。
5. 类的实例化过程比较复杂：实例化时包含很多步骤，而且这些步骤的顺序可能会发生变化。


## 优缺点

原型模式是一种创建型设计模式，其核心思想在于通过复制“原型”来创建对象，而非直接实例化。在原型模式中，我们首先创造一个原型对象，接着通过对其进行复制，获得新的实例。这些原型对象储存在一个共享的“原型管理器”中，当需要新的对象时，只需从管理器获取原型的复制。

**原型模式的主要优点包括**：

1. 提高实例化对象的效率：通过复制原型对象，避免了重复的初始化操作。
2. 隐藏实例化的复杂度：客户端不需要了解具体的对象创建过程，只需请求原型的复制即可。
3. 避免构造函数污染：由于实例化是通过复制原型对象实现的，无需向构造函数中添加不必要的代码。
4. 动态添加和删除原型：可以在运行时扩展或减少原型对象，客户端可以直接使用新增的原型来实例化对象。

**原型模式的缺点包括**：

1. 需要定义接口并确保每个具体原型类都实现了该接口，增加了一定的开发成本。
2. 需要注意原型实例和原型之间的关系，例如修改原型会影响到其他实例。
3. 可能需要实现克隆方法：具体原型类必须实现 clone()方法，这对于某些类而言可能并不容易实现。
4. 共享的对象必须是不可变的：原型对象需要保证每个副本都是独立的，如果原型对象本身包含了可变状态，那么在克隆过程中需要特别注意副本中是否也复制了该对象实例的引用，会影响到其他克隆对象的状态。

## 示例  

下面我们通过一个简单的示例来说明原型模式的用法。假设我们有一个图形类`Shape`，它有一个`clone`方法用于克隆自身：  

```go
package main

import "fmt"

// 抽象原型类
type Shape interface {
    Clone() Shape
    GetInfo() string
}

// 具体原型类 - Circle
type Circle struct {
    Radius int
}

func (c *Circle) Clone() Shape {
    return &Circle{Radius: c.Radius}
}

func (c *Circle) GetInfo() string {
    return fmt.Sprintf("Circle with radius %d", c.Radius)
}

// 客户端
func main() {
    // 创建原型对象
    originalCircle := &Circle{Radius: 5}
    fmt.Println("Original Circle:", originalCircle.GetInfo())   // Original Circle: Circle with radius 5

    // 克隆原型对象
    clonedCircle := originalCircle.Clone().(*Circle)
    fmt.Println("Cloned Circle:", clonedCircle.GetInfo())       // Cloned Circle: Circle with radius 5
}
```

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
