---
layout: post
title: Go面试：读写已经关闭的channel会怎样？
tags: [go, 面试]
mermaid: false
math: false
---  

## 读操作

对已关闭的channel进行读操作时：  

- 如果channel是一个有缓冲的channel（即容量大于 0），那么在关闭channel后，所有的数据都可以被正常读取。但是一旦channel中的所有数据被读取完毕，对该channel进行读操作将不会收到任何数据，而是立即返回对应类型的零值。
- 如果channel是一个无缓冲的channel（即容量为 0），那么在关闭channel后，对该channel进行读操作将立即返回对应类型的零值。

> Russ Cox 2011年3月12日提交的 gc,runtime: replace closed(c) with x, ok := <-c，使用x, ok := <-c替代closed(c)来判断channel的关闭状态

示例代码如下：  

```go
// 从已关闭的channel读取数据，chan容量为2
// 2
// 1
// 0 ，int的零值为0
func ReadFromClosedChanWithBuffer() {
	ch := make(chan int, 2)
	ch <- 1
	ch <- 2

	close(ch)

	fmt.Println(<-ch)
	fmt.Println(<-ch)
	fmt.Println(<-ch)
}

// 从已关闭的channel读取数据
// 0 ，int的零值为0
func ReadFromClosedChan() {
	ch := make(chan int, 2)
	close(ch)

    // channel关闭后，可以通过x, ok := <-c来判断channel的关闭状态；关闭后ok为false
	i,ok := <- ch
	if !ok{
		fmt.Println("channel closed")
	}
	fmt.Println(i)
}
```

## 写操作

对已关闭的channel进行写操作时：

- 无论channel是一个有缓冲的channel（即容量大于 0）还是无缓冲的channel（即容量为 0），在关闭 channel 后，对其进行写操作将立即导致程序发生运行时错误（panic）。

示例代码如下：  

```go
// 向已关闭的channel写入数据，chan容量为2
// 执行后报错：panic: send on closed channel
func Write2ClosedChanWithBuffer() {
	// 带缓存的channel
	ch := make(chan int, 2)
	close(ch)

	ch <- 1
	ch <- 2
	ch <- 3
}

// 向已关闭的channel写入数据
// 执行后报错：panic: send on closed channel
func Write2ClosedChan() {
	// 带缓存的channel
	ch := make(chan int)
	close(ch)

	ch <- 1
}
```  

## 为什么会这样？

以**go 1.21.6**为例，向已关闭的channel写入数据时，为什么会`panic`呢？从`src/runtime/chan.go`中可以看出：  

```go
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
	// 省略其它处理逻辑

	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("send on closed channel"))
	}

	// 省略其它处理逻辑
}
``` 

而从已关闭的channel读取数据时：  

```go
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
	// 省略其它处理逻辑

	lock(&c.lock)

    // channel关闭后
	if c.closed != 0 {
        // 且缓存为空
		if c.qcount == 0 {
			if raceenabled {
				raceacquire(c.raceaddr())
			}
			unlock(&c.lock)
			if ep != nil {
				typedmemclr(c.elemtype, ep)
			}
			return true, false
		}
		// The channel has been closed, but the channel's buffer have data.
	} else {
		// Just found waiting sender with not closed.
		if sg := c.sendq.dequeue(); sg != nil {
			// Found a waiting sender. If buffer is size 0, receive value
			// directly from sender. Otherwise, receive from head of queue
			// and add sender's value to the tail of the queue (both map to
			// the same buffer slot because the queue is full).
			recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
			return true, true
		}
	}

	// 省略其它处理逻辑
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
