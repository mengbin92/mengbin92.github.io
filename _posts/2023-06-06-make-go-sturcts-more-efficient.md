---
layout: post
title: 如何让你的结构体更高效
tags: 
mermaid: false
math: false
---  

> 文中所涉及到的代码运行结果均是在64位机器上执行得到的.

## 基础知识回顾  

在Go中，我们可以使用`unsafe.Sizeof(x)`来查看变量所占的内存大小。以下是Go内置的数据类型占用的内存大小：  

| 类型                        | 内存大小（字节数） |
| :-------------------------- | :----------------- |
| bool                        | 1                  |
| int8/uint8                  | 1                  |
| int/uint                    | 8                  |
| int32/uint32                | 4                  |
| int64/uint64                | 8                  |
| float32                     | 4                  |
| float64                     | 8                  |
| complex64                   | 8                  |
| complex128                  | 16                 |
| 指针类型：*T, map,func,chan | 8                  |
| string                      | 16                 |
| interface                   | 16                 |
| []T                         | 24                 |   

---

```go  
func main() {
	fmt.Println(unsafe.Sizeof(true))     // 1
	fmt.Println(unsafe.Sizeof(int8(1)))  // 1
	fmt.Println(unsafe.Sizeof(int(1)))   // 8
	fmt.Println(unsafe.Sizeof(int32(1))) // 4
	fmt.Println(unsafe.Sizeof(int64(1))) // 8

	fmt.Println(unsafe.Sizeof(float32(1.0))) // 4
	fmt.Println(unsafe.Sizeof(float64(1.0))) // 8

	a := int(1)
	fmt.Println(unsafe.Sizeof(&a)) // 8

	s := "1234"
	fmt.Println(unsafe.Sizeof(s)) //16

	var b interface{}
	fmt.Println(unsafe.Sizeof(b)) //16

	fmt.Println(unsafe.Sizeof([]string{})) // 24
	fmt.Println(unsafe.Sizeof([]int{}))    // 24
}
```

## 简单示例  

对于一个结构体，其占用的内存大小应该是其内部多个基础类型占用内存大小之和。但实际情况并非如此，甚至字段顺序不同，结构体的大小也不同：  

```go
type Example1 struct {
	a int32 // 4
	b int32 // 4
	c int64 // 8
}

type Example2 struct {
	a int32 // 4
	c int64 // 8
	b int32 // 4
}

type Example3 struct {
	a bool   // 1
	b int8   // 1
	c string // 16
}

func main() {
	fmt.Println(unsafe.Sizeof(Example1{})) // 16
	fmt.Println(unsafe.Sizeof(Example2{})) // 24
    fmt.Println(unsafe.Sizeof(Example3{})) // 24，并不是1+1+16=18
}
```

为什么会出现上面的情况呢？这就引出了本文的重点：**内存对齐**。

## 内存对齐  

内存对齐（Memory Alignment）是指数据在计算机内存中存储时按照特定规则对齐到内存地址的过程。内存对齐是由计算机硬件和操作系统所决定的，它可以提高内存访问效率和系统性能。  

在计算机体系结构中，内存是以字节（byte）为单位进行访问的。数据类型在内存中占用的字节数可以是不同的，例如，整数可能占用2字节、4字节或8字节，而字符可能只占用1字节。  

内存对齐的规则要求变量的地址必须是其数据类型字节数的整数倍。例如，如果一个变量的数据类型是4字节（32位），那么它的起始地址必须是4的倍数。  

内存对齐的主要目的是优化计算机的内存访问性能。当数据按照对齐要求存储在内存中时，读取和写入操作可以更高效地进行。如果数据没有按照对齐要求存储，计算机可能需要进行多次内存读取操作来获取完整的数据，这会增加访问延迟和降低系统性能。  

在编程中，特别是在使用结构体和类的语言中，内存对齐是一个重要的概念。编译器会根据数据类型的对齐要求自动进行内存对齐操作，以确保数据存储的正确性和性能优化。但在某些情况下，可以通过显式地设置对齐属性来控制数据的对齐方式，以满足特定的需求。  

需要注意的是，不同的硬件平台和操作系统可能具有不同的内存对齐规则和要求。因此，在开发跨平台应用程序时，应当考虑到这些差异并遵循适当的内存对齐规则。  

## 为什么需要对齐内存  

内存对齐是为了提高计算机系统的内存访问效率和性能而存在的。以下是几个需要内存对齐的原因：  

1. 硬件要求：许多计算机硬件和体系结构对内存访问有特定的对齐要求。如果数据没有按照硬件要求进行对齐，可能会导致访问错误、异常或性能下降。通过满足硬件对齐要求，可以确保数据能够按照有效的方式访问，提高系统的稳定性和性能。
2. 内存访问效率：当数据按照对齐要求存储在内存中时，计算机系统可以更高效地访问这些数据。对齐数据可以减少或避免多次内存访问，提高数据的读取和写入速度。这对于大量的数据操作和高性能计算非常重要。
3. 缓存性能：现代计算机系统中通常有多级缓存，而缓存的访问是以特定块的方式进行的。内存对齐可以确保数据按照缓存块的大小对齐，使得数据能够更好地利用缓存，减少缓存未命中和读取延迟，提高缓存性能。
4. 结构体和类的内存布局：结构体和类通常包含多个成员变量，这些变量按照一定的顺序存储在内存中。内存对齐确保结构体和类的成员变量按照正确的顺序和对齐要求进行存储，避免内存空洞和访问错误，保证数据的正确性和一致性。

总之，内存对齐是为了满足硬件要求、提高内存访问效率和性能而引入的机制。通过合理地进行内存对齐，可以提高系统的稳定性、性能和响应速度，并避免潜在的内存访问问题。  

## 如何对齐内存  

Go团队开发了一款名为`fieldalignment`的工具可以帮助我们解决内存对齐的问题。  

使用下面的命令安装`fieldalignment`工具：  

```bash
$ go install golang.org/x/tools/go/analysis/passes/fieldalignment/cmd/fieldalignment@latest
```

还是以上面的代码为例，可以执行下面的命令：  

```bash
$ fieldalignment main.go  
main.go:14:15: struct of size 24 could be 16  
main.go:20:15: struct with 16 pointer bytes could be 8
```

也可以使用`--fix`参数直接修改代码：  

```bash
$ fieldalignment --fix main.go
```  

修改后的内容如下：  

```go  
type Example1 struct {
	a int32 // 4
	b int32 // 4
	c int64 // 8
}

type Example2 struct {
	c int64
	a int32
	b int32
}

type Example3 struct {
	c string
	a bool
	b int8
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

---
