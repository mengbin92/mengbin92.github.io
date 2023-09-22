---
layout: post
title: 设计模式之单例模式
tags: [go, 设计模式]
mermaid: false
math: false
---  

## 单例模式简介  

单例模式是一种设计模式，用于确保一个类只有一个实例，并提供全局访问点以获取该实例。它是一种创建型模式，通常用于需要严格控制某个类的实例数量的情况。单例模式确保一个类在整个应用程序生命周期中只有一个实例，因此可以节省系统资源，同时提供了一个集中的访问点，以便在需要时获取该实例。

以下是单例模式的关键特点： 

1. 单一实例：单例模式确保一个类只有一个实例对象存在。
2. 全局访问点：单例模式提供了一个全局的访问点，其他对象可以通过该访问点获取单例实例。
3. 延迟加载（可选）：在需要时才进行单例对象的创建，可以减少应用程序启动时的资源占用。
4. 线程安全性（可选）：在多线程环境下，单例模式需要考虑线程安全性，以确保只有一个实例被创建。

## 单例模式实现  

懒汉模式（Lazy Initialization）和饿汉模式（Eager Initialization）是两种单例模式的实现方式，它们之间的主要区别在于单例对象的初始化时机。

### 1. 懒汉模式（Lazy Initialization）：

- **初始化时机**：懒汉模式是延迟加载的，也就是说，单例对象在首次访问时才进行初始化。在多线程环境中，可能会出现竞态条件，需要额外的线程安全措施来确保只创建一个实例。
- **优点**：
  - 节省了系统资源，因为在应用程序启动时不会创建单例对象。
  - 可以实现延迟加载，只有在需要时才进行初始化。
- **缺点**：
  - 在多线程环境下，需要考虑线程安全性，通常需要使用互斥锁等机制来保证单例对象的唯一性。
  - 首次访问单例对象时可能会引入额外的性能开销，因为需要进行初始化。

### 2. 饿汉模式（Eager Initialization）：

- **初始化时机**：饿汉模式是在应用程序启动时就进行单例对象的初始化，无论是否会被使用。因此，单例对象在应用程序生命周期内都存在。
- **优点**：
  - 不需要考虑多线程环境下的线程安全性，因为单例对象在应用程序启动时就已经创建。
  - 访问单例对象时不会引入额外的性能开销，因为它已经初始化。
- **缺点**：
  - 可能会浪费系统资源，因为单例对象在应用程序启动时就被创建，如果一直未被使用，可能会占用内存。
  - 不支持延迟加载，因为单例对象在应用程序启动时就已经初始化。

### 如何选择懒汉模式还是饿汉模式：

- 如果应用程序对资源要求敏感，希望尽量减少启动时的内存占用，或者需要支持延迟加载，可以选择懒汉模式。
- 如果应用程序对性能要求高，可以接受在应用程序启动时进行初始化，并且不希望处理多线程环境下的线程安全问题，可以选择饿汉模式。

总之，选择懒汉模式还是饿汉模式应该根据具体的需求和性能要求来决定。无论选择哪种模式，都需要确保单例对象的唯一性，以及在多线程环境下的线程安全性。

## 懒汉模式实现  

在 Go 中实现懒汉模式相对简单，因为 Go 的包系统和并发机制使得这一模式变得非常优雅和安全。下面是一个示例，展示了如何在 Go 中创建一个线程安全的单例对象：

```go
package singleton

import (
	"sync"
)

// Singleton 是一个单例对象的结构体
type Singleton struct {
	data int
}

var instance *Singleton
var once sync.Once

// GetInstance 返回 Singleton 的唯一实例
func GetInstance() *Singleton {
	once.Do(func() {
		instance = &Singleton{} // 只会执行一次
	})
	return instance
}

// SetData 设置 Singleton 的数据
func (s *Singleton) SetData(data int) {
	s.data = data
}

// GetData 获取 Singleton 的数据
func (s *Singleton) GetData() int {
	return s.data
}
```

在这个示例中，我们创建了一个 `Singleton` 结构体，它包含一个字段 `data` 用于存储单例对象的数据。我们使用 `sync.Once` 来确保 `GetInstnace` 函数只会被执行一次，从而保证单例对象只会被创建一次。

在 `main` 函数或其他地方，您可以这样使用这个单例对象：

```go
package main

import (
	"fmt"
	"singleton"
)

func main() {
	instance1 := singleton.GetInstance()
	instance1.SetData(42)

	instance2 := singleton.GetInstance()

	fmt.Println("Instance 1 data:", instance1.GetData())
	fmt.Println("Instance 2 data:", instance2.GetData())

	if instance1 == instance2 {
		fmt.Println("Both instances are the same")
	}
}
```

这个示例中，我们首先通过 `GetInstance` 函数获取单例对象 `instance1`，然后设置其数据为 42。接着，我们再次获取单例对象 `instance2`，并检查两个实例是否相同，从而验证单例模式的实现。

使用 `sync.Once` 是 Go 中实现单例模式的推荐方法，因为它既能保证线程安全，又能保证懒加载（即只在第一次访问时创建实例）。这样可以确保在应用程序中只存在一个实例，并且在需要时进行初始化。  

## 饿汉模式实现

饿汉模式是在应用程序启动时就进行单例对象的初始化。以下是一个使用饿汉模式的示例：

```go
package singleton

type Singleton struct {
    data int
}

var instance = &Singleton{}

func GetInstance() *Singleton {
    return instance
}

func (s *Singleton) SetData(data int) {
    s.data = data
}

func (s *Singleton) GetData() int {
    return s.data
}
```

在这个示例中，我们在包级别直接创建了一个单例实例 `instance`，并在程序启动时进行初始化。这意味着单例对象在应用程序启动时就已经存在，而不是在首次访问时才创建。

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
