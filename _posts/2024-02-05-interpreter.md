---
layout: post
title: 设计模式之解释器模式
tags: 设计模式
mermaid: false
math: false
--- 

## 1. 基本概念

解释器模式（Interpreter Pattern）是一种行为型设计模式，用于定义语言的文法规则，并提供一个解释器来解释执行这些规则。它属于行为型模式，适用于需要解释语言语法或表达式的场景。  

在解释器模式中，有几种不同的角色，它们各自有不同的职责和行为：

1. **AbstractExpression（抽象表达式）**：
   - **职责**： 定义解释器的接口，声明一个`interpret`方法，是解释器模式的核心抽象。
   - **行为**： 为终结符表达式和非终结符表达式定义了一个公共的接口。
2. **TerminalExpression（终结符表达式）**：
   - **职责**： 实现`AbstractExpression`接口中的`interpret`方法，表示文法中的终结符。
   - **行为**： 执行实际的解释操作，通常是基本操作或基本表达式。
3. **NonterminalExpression（非终结符表达式）**：
   - **职责**： 实现`AbstractExpression`接口中的`interpret`方法，表示文法中的非终结符。
   - **行为**： 通常是由终结符表达式和其他非终结符表达式组成，完成复杂的解释操作。
4. **Context（环境类）**：
   - **职责**： 包含解释器之外的一些全局信息，通常是解释器需要的数据。
   - **行为**： 在解释器模式中，上下文负责传递数据，供解释器使用。
5. **Client（客户端）**：
   - **职责**： 构建抽象语法树，组合不同的终结符和非终结符表达式。
   - **行为**： 将表达式组装成一个具体的语法树，并调用解释器执行解释操作。

在一个典型的解释器模式中，这些角色协同工作，通过构建和组合不同的表达式来解释和执行特定的语法规则。解释器通过递归的方式对语法树进行解释，从而实现对特定语言的解释和执行。

## 2. 适用场景

- 当有一个语言需要解释执行，且语法规则相对简单时，可以使用解释器模式。
- 当需要解决一类问题，这类问题可被一定文法规则表示，且可将问题的解决方法表示为语法树时。
- 当语法规则频繁变化，且可以用类表示不同规则时，解释器模式也是一种可考虑的设计方案。

## 3. 优缺点

### 优点：

- **易扩展**： 可以灵活地扩展语法规则，添加新的表达式，而不需要修改已有的解释器。
- **易于实现**： 对于简单的语法规则，实现解释器相对简单。
- **灵活性**： 可以组合不同的表达式，构建复杂的语法结构。

### 缺点：

- **复杂性增加**： 随着语法规则的复杂化，解释器的实现可能变得复杂。
- **执行效率**： 对于复杂的语法规则，解释器模式的执行效率可能较低。

## 4. 示例

考虑一个简单的数学表达式解释器，可以解释加法和减法操作。在这个例子中，我们定义了抽象表达式接口`Expression`和两个具体的表达式类`AddExpression`和`SubtractExpression`。

```go
package main

import (
	"fmt"
	"strconv"
	"strings"
)

// Expression Interface
type Expression interface {
	Interpret() int
}

// Terminal Expression
type NumberExpression struct {
	number int
}

func NewNumberExpression(number int) *NumberExpression {
	return &NumberExpression{number: number}
}

func (ne *NumberExpression) Interpret() int {
	return ne.number
}

// Non-terminal Expression
type AddExpression struct {
	left  Expression
	right Expression
}

func NewAddExpression(left, right Expression) *AddExpression {
	return &AddExpression{left: left, right: right}
}

func (ae *AddExpression) Interpret() int {
	return ae.left.Interpret() + ae.right.Interpret()
}

// Non-terminal Expression
type SubtractExpression struct {
	left  Expression
	right Expression
}

func NewSubtractExpression(left, right Expression) *SubtractExpression {
	return &SubtractExpression{left: left, right: right}
}

func (se *SubtractExpression) Interpret() int {
	return se.left.Interpret() - se.right.Interpret()
}

// Client
func main() {
	// Example: 1 + 2 - 3
	expression := NewSubtractExpression(
		NewAddExpression(NewNumberExpression(1), NewNumberExpression(2)),
		NewNumberExpression(3),
	)

	result := expression.Interpret()
	fmt.Println("Result:", result)
}
```

在这个示例中，`Expression`是表达式接口，`NumberExpression`、`AddExpression`和`SubtractExpression`是具体的表达式类。通过构建不同的表达式组合，可以解释和计算复杂的数学表达式。  

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
