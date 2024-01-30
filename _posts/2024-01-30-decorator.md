---
layout: post
title: 设计模式之装饰器模式
tags: 设计模式
mermaid: false
math: false
---  

## 1. 基本概念：

装饰器模式是一种结构型设计模式，它允许在运行时通过将对象封装在一系列装饰器类的对象中，动态地扩展其行为。装饰器模式通过组合和递归的方式，使得客户端可以在不修改原始对象的情况下，以自由组合的方式增加新的功能。

## 2. 适用场景：

- 当需要在不修改现有代码的情况下，动态地添加或覆盖对象的行为时。
- 当有许多相似但不同的装饰类，并且需要根据需求组合它们时。
- 当不适合使用子类进行扩展，或者扩展子类可能会导致类爆炸的情况下，可以考虑使用装饰器模式。

## 3. 优缺点：

### 优点：

- **灵活性：** 可以动态地添加、删除或覆盖对象的行为，使得系统更灵活，更容易扩展。
- **遵循开闭原则：** 客户端代码无需修改，即可引入新的装饰器类或修改装饰器的组合，符合开闭原则。

### 缺点：

- **复杂性增加：** 随着装饰器的增加，可能导致类的数量增加，复杂性也会增加。
- **顺序问题：** 装饰器的顺序可能影响最终的结果，需要谨慎设计装饰器的顺序。

## 4. 示例：

考虑一个咖啡店的例子，我们有一个基础的咖啡类（`Coffee`），然后通过装饰器模式来动态添加不同的调料，例如牛奶、糖等。

```python
# Component
class Coffee:
    def cost(self):
        return 5

# Decorator
class MilkDecorator:
    def __init__(self, coffee):
        self._coffee = coffee

    def cost(self):
        return self._coffee.cost() + 2

# Decorator
class SugarDecorator:
    def __init__(self, coffee):
        self._coffee = coffee

    def cost(self):
        return self._coffee.cost() + 1

# Client
def main():
    simple_coffee = Coffee()
    print("Cost of simple coffee:", simple_coffee.cost())

    milk_coffee = MilkDecorator(simple_coffee)
    print("Cost of milk coffee:", milk_coffee.cost())

    sugar_milk_coffee = SugarDecorator(milk_coffee)
    print("Cost of sugar milk coffee:", sugar_milk_coffee.cost())

if __name__ == "__main__":
    main()
```

在这个例子中，`Coffee`是基础的咖啡类，`MilkDecorator`和`SugarDecorator`是装饰器类，它们分别用于添加牛奶和糖的功能。通过动态地组合这些装饰器，我们可以得到不同调料组合的咖啡，而无需修改原始咖啡类。  


在 Go 中，由于语言的特性，装饰器模式的实现可能略有不同。Go不直接支持类似于其他语言的继承和类的概念，但我们可以使用函数和接口来模拟装饰器模式：  

```go
package main

import "fmt"

// Component
type Coffee interface {
	Cost() int
}

// ConcreteComponent
type SimpleCoffee struct{}

func (c *SimpleCoffee) Cost() int {
	return 5
}

// Decorator
type MilkDecorator struct {
	Coffee Coffee
}

func (d *MilkDecorator) Cost() int {
	return d.Coffee.Cost() + 2
}

// Decorator
type SugarDecorator struct {
	Coffee Coffee
}

func (d *SugarDecorator) Cost() int {
	return d.Coffee.Cost() + 1
}

// Client
func main() {
	simpleCoffee := &SimpleCoffee{}
	fmt.Println("Cost of simple coffee:", simpleCoffee.Cost())

	milkCoffee := &MilkDecorator{Coffee: simpleCoffee}
	fmt.Println("Cost of milk coffee:", milkCoffee.Cost())

	sugarMilkCoffee := &SugarDecorator{Coffee: milkCoffee}
	fmt.Println("Cost of sugar milk coffee:", sugarMilkCoffee.Cost())
}
```  

通过组合和嵌套的方式，我们在运行时动态地给咖啡对象添加调料。这样的实现方式利用了Go语言的接口和嵌套特性，是一种在Go中模拟装饰器模式的常见方式。  

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
