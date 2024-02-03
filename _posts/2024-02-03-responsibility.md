---
layout: post
title: 设计模式之责任链模式
tags: 设计模式
mermaid: false
math: false
---  

## 1. 基本概念

责任链模式（Chain of Responsibility Pattern）是一种行为型设计模式，它通过一条链传递请求，直到某个对象处理该请求为止。在责任链模式中，每个处理者都包含对下一个处理者的引用，形成一条链。请求沿着链传递，直到有一个处理者能够处理它为止。

## 2. 适用场景

- 当一个请求需要被多个对象处理，但具体处理者在运行时确定。
- 当需要避免发送者和接收者之间的直接耦合关系。
- 当系统中有多个对象可以处理同一请求，但具体处理者未知。

## 3. 优缺点

### 优点：

- **解耦发送者和接收者**： 责任链模式解耦了请求的发送者和接收者，使得系统更灵活，易于扩展。
- **简化对象**： 每个处理者只需关注自己能够处理的请求，无需了解整个系统的结构。
- **动态性**： 可以动态地添加、删除处理者，改变处理顺序。

### 缺点：

- **请求未必被处理**： 如果责任链上的所有处理者都不能处理请求，请求可能会被忽略，需要谨慎设计责任链。

## 4. 示例

考虑一个简单的购买审批的例子，假设有三个处理者：主管、经理和总经理。每个处理者有不同的审批权限，请求需要从主管开始，经过经理，最终到总经理。

```go
package main

import "fmt"

// Handler Interface
type Approver interface {
	HandleRequest(request int)
	SetSuccessor(successor Approver)
}

// ConcreteHandler
type Supervisor struct {
	successor Approver
}

func (s *Supervisor) HandleRequest(request int) {
	if request <= 100 {
		fmt.Println("Supervisor approves the request.")
	} else if s.successor != nil {
		s.successor.HandleRequest(request)
	}
}

func (s *Supervisor) SetSuccessor(successor Approver) {
	s.successor = successor
}

// ConcreteHandler
type Manager struct {
	successor Approver
}

func (m *Manager) HandleRequest(request int) {
	if request <= 500 {
		fmt.Println("Manager approves the request.")
	} else if m.successor != nil {
		m.successor.HandleRequest(request)
	}
}

func (m *Manager) SetSuccessor(successor Approver) {
	m.successor = successor
}

// ConcreteHandler
type GeneralManager struct{}

func (gm *GeneralManager) HandleRequest(request int) {
	if request > 500 {
		fmt.Println("General Manager approves the request.")
	} else {
		fmt.Println("Request cannot be approved.")
	}
}

// Client
func main() {
	supervisor := &Supervisor{}
	manager := &Manager{}
	generalManager := &GeneralManager{}

	supervisor.SetSuccessor(manager)
	manager.SetSuccessor(generalManager)

	// Example requests
	supervisor.HandleRequest(50)
	supervisor.HandleRequest(200)
	supervisor.HandleRequest(1000)
}
```

在这个示例中，`Approver`是处理者接口，而`Supervisor`、`Manager`和`GeneralManager`是具体的处理者。每个处理者都实现了处理请求的方法，并且包含了对下一个处理者的引用。客户端创建一个责任链，将请求从主管传递到总经理，根据请求的金额进行不同级别的审批。

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
