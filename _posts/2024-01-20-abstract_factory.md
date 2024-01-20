---
layout: post
title: 设计模式之抽象工厂模式
tags: 设计模式
mermaid: false
math: false
---  

## 概念

抽象工厂模式是一种设计模式，属于创建型模式。它提供了一种方式，允许在系统中独立地产生与所需功能相关的产品族，而不需要指定具体产品的类。抽象工厂模式主要适用于在产品族中存在多个产品系列，而且每个产品系列中包含多个产品的情况。它是一种更为抽象和一般化的工厂模式，可以应对多个产品族结构的问题。

抽象工厂模式包括以下角色：

1. **抽象工厂角色**：它是工厂方法的抽象实现，用于创建多个产品系列的工厂类。
2. **具体工厂角色**：主要是实现抽象工厂中的抽象方法，完成具体产品的创建。
3. **抽象产品角色**：定义了产品的规范，描述了产品的主要特性和功能，抽象工厂模式支持多个抽象产品。
4. **具体产品角色**：实现了抽象产品角色所定义的接口，由具体工厂来创建，它同具体工厂之间是多对一关系。

抽象工厂模式的主要优缺点如下：

优点：

1. 分离了产品的创建和使用：抽象工厂模式将产品的创建过程与使用过程分离，使得客户端不需要关心产品的具体实现，只需要关心产品的接口。这样可以降低系统的耦合度，提高了代码的可维护性和可扩展性。
2. 提高了代码的可扩展性：抽象工厂模式通过引入新的抽象工厂和产品，可以支持新的产品族的创建。这样，在需要添加新的产品族时，只需要引入新的抽象工厂和产品，而不需要修改已有的代码。
3. 提高了代码的可读性：抽象工厂模式将产品的创建过程封装在抽象工厂中，客户端只需要关心调用抽象工厂的方法来创建产品。这样，代码结构更加清晰，易于理解。

缺点：

1. 增加了代码的复杂性：抽象工厂模式引入了许多抽象类和接口，这会增加代码的复杂性。在实现抽象工厂和产品时，需要考虑到更多的细节，增加了开发的难度。
2. 增加了系统的耦合度：抽象工厂模式通过引入抽象工厂和产品的接口，将产品的创建和使用分离。这样，客户端需要知道具体的抽象工厂和产品接口，增加了系统的耦合度。
3. 不适用于创建单个产品的场景：抽象工厂模式主要用于创建多个产品族中的产品。如果只需要创建单个产品，使用工厂模式更加简单和直接。

---

与工厂模式相比，抽象工厂模式和工厂模式的主要区别在于以下几点：  

1. **产品族数量**：工厂模式关注的是创建单个产品族中的多个产品，而抽象工厂模式关注的是创建多个产品族中的产品。
2. **耦合度**：工厂模式中的客户端需要知道具体工厂和产品之间的关联关系，因此耦合度相对较高。而抽象工厂模式通过将产品族的创建与客户端解耦，降低了系统的耦合度。
3. **扩展性**：工厂模式的扩展性相对较差，当需要添加新的产品族时，需要对工厂方法进行改动。而抽象工厂模式通过引入新的抽象工厂和产品即可支持新的产品族，具有更好的扩展性。

---

## 使用示例

在Go语言中使用抽象工厂模式，可以通过以下步骤实现：

- 定义抽象产品接口：首先，需要定义抽象产品接口，它表示产品的基本特性。

```go
type AbstractProductA interface {
    OperationA()
}

type AbstractProductB interface {
    OperationB()
}
```

- 定义具体产品：接下来，定义具体产品，实现抽象产品接口。

```go
type ConcreteProductA1 struct{}

func (c *ConcreteProductA1) OperationA() {
    // ...
}

type ConcreteProductB1 struct{}

func (c *ConcreteProductB1) OperationB() {
    // ...
}

type ConcreteProductA2 struct{}

func (c *ConcreteProductA2) OperationA() {
    // ...
}

type ConcreteProductB2 struct{}

func (c *ConcreteProductB2) OperationB() {
    // ...
}
```

- 定义抽象工厂接口：然后，定义抽象工厂接口，它包含创建产品的方法。

```go
type AbstractFactory interface {
    CreateProductA() AbstractProductA
    CreateProductB() AbstractProductB
}
```

- 定义具体工厂：接着，定义具体工厂，实现抽象工厂接口。

```go
type ConcreteFactory1 struct{}

func (c *ConcreteFactory1) CreateProductA() AbstractProductA {
    return &ConcreteProductA1{}
}

func (c *ConcreteFactory1) CreateProductB() AbstractProductB {
    return &ConcreteProductB1{}
}

type ConcreteFactory2 struct{}

func (c *ConcreteFactory2) CreateProductA() AbstractProductA {
    return &ConcreteProductA2{}
}

func (c *ConcreteFactory2) CreateProductB() AbstractProductB {
    return &ConcreteProductB2{}
}
```

- 客户端代码：最后，在客户端代码中，通过抽象工厂接口创建产品。

```go
func main() {
    var factory AbstractFactory

    factory = &ConcreteFactory1{}
    productA := factory.CreateProductA()
    productB := factory.CreateProductB()
    productA.OperationA()
    productB.OperationB()

    factory = &ConcreteFactory2{}
    productA = factory.CreateProductA()
    productB = factory.CreateProductB()
    productA.OperationA()
    productB.OperationB()
}
```

通过以上步骤，可以在Go语言中实现抽象工厂模式。需要注意的是，Go语言中没有类和接口的概念，因此在实现抽象工厂模式时，可以使用结构体和接口来模拟。

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
