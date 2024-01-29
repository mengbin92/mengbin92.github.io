---
layout: post
title: Function vs. Method in Go 
tags: go
mermaid: false
math: false
---  

##  函数与方法的区别

在Go语言中，函数（Function）和方法（Method）是两个相关但又有区别的概念，主要涉及到它们的定义和调用方式。  

### 定义方式

对函数（Function）而言，  

- 是独立的代码块，没有与特定的类型关联
- 定义时没有接受者参数
- 语法：`func functionName(parameters) returnType { // function body}`

而方法（Method），  

- 与特定的类型关联
- 定义时包含一个接收者（Receiver）参数，这个接收者参数相当于方法所属的类型的一个实例
- 语法：`func (receiverType) methodName(parameters) returnType { // method body }`

### 调用方式  

- 函数（Function）调用时直接通过包名或者导入包的别名调用，`packageName.functionName(parameters)`或者`alias.functionName(parameters)`
- 方法（Method）是通过接受者来调用的，`instance.methodName(parameters)`  

### 示例

```go
// 函数定义
func add(a int, b int) int {
    return a + b
}

// 结构体定义
type Rectangle struct {
    width  int
    height int
}

// 方法定义，与Rectangle结构体关联
func (r *Rectangle) area() int {
    return r.width * r.height
}
```

在这个例子中，`add`是一个普通的函数，而`area`是一个与`Rectangle`结构体关联的方法。注意，方法`area`的第一个参数是一个指向`Rectangle`类型的指针，这个指针被称为接收器。

### 总结

函数和方法在 Go 语言中的区别：  

1. 方法与特定的数据类型（如结构体）关联，而函数是独立的代码块
2. 方法需要通过实例来调用，而函数通过包名或导入包的别名来调用
3. 方法在定义时需要指定接收者，而函数不需要
4. 方法可以直接操作关联的数据类型，而函数不能直接操作其他数据类型

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
