---
layout: post
title: 设计模式之享元模式
tags: 设计模式 
mermaid: false
math: false
---  

## 1. 基本概念

享元模式（Flyweight Pattern）是一种结构型设计模式，它旨在减少对象的数量，通过共享已经存在的相似对象来减小内存占用和提高性能。享元模式适用于需要创建大量相似对象，但这些对象中的许多属性是可以共享的情况。

## 2. 适用场景

- 当一个应用程序使用了大量相似对象，而这些对象占用大量内存时。
- 当对象中有可共享的状态，而这些状态对于应用程序而言是相对稳定的。
- 当创建新对象的代价较高，可以通过共享已有对象来减小创建的数量。

## 3. 优缺点

### 优点：

- **减小内存占用**： 通过共享相似对象的状态，减小了内存占用，提高了系统性能。
- **提高性能**： 由于共享了对象，减少了创建对象的数量，提高了系统性能。
- **分离内部状态和外部状态**： 将对象的状态分为内部状态和外部状态，内部状态可以被共享，而外部状态可以根据需要在运行时传递。

### 缺点：

- **引入共享状态可能导致线程安全问题：** 如果多个线程同时修改共享的状态，可能会引发线程安全问题，需要在使用时考虑线程安全。

## 4. 示例

考虑一个简单的文本编辑器的例子，其中有大量字符对象。在享元模式中，我们将字符的外部状态（位置、颜色等）和内部状态（字符的本身）分开，并通过共享相同的字符实例来减小内存占用。

```go
package main

import "fmt"

// Flyweight Interface
type Character interface {
	Display() string
}

// ConcreteFlyweight
type ConcreteCharacter struct {
	character rune
}

func NewConcreteCharacter(character rune) *ConcreteCharacter {
	return &ConcreteCharacter{character: character}
}

func (c *ConcreteCharacter) Display() string {
	return fmt.Sprintf("Character: %c", c.character)
}

// FlyweightFactory
type CharacterFactory struct {
	characters map[rune]Character
}

func NewCharacterFactory() *CharacterFactory {
	return &CharacterFactory{characters: make(map[rune]Character)}
}

func (cf *CharacterFactory) GetCharacter(character rune) Character {
	if _, exists := cf.characters[character]; !exists {
		cf.characters[character] = NewConcreteCharacter(character)
	}
	return cf.characters[character]
}

// Client
func main() {
	characterFactory := NewCharacterFactory()

	text := "ABCABD"
	for _, char := range text {
		flyweight := characterFactory.GetCharacter(char)
		fmt.Println(flyweight.Display())
	}
}
```

在这个示例中，`ConcreteCharacter`表示具体的字符对象，`CharacterFactory`是享元工厂，负责创建和管理字符对象。客户端通过享元工厂获取字符对象，并显示它们的内容。通过共享相同的字符实例，减小了内存占用。

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
