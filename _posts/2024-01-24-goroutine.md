---
layout: post
title: Golang并发控制方式有几种？
tags: go
mermaid: false
math: false
---  

Go语言中的goroutine是一种轻量级的线程，其优点在于占用资源少、切换成本低，能够高效地实现并发操作。但如何对这些并发的goroutine进行控制呢？  

一提到并发控制，大家最先想到到的是锁。Go中同样提供了锁的相关机制，包括互斥锁`sync.Mutex`和读写锁`sync.RWMutex`；除此之外Go还提供了原子操作`sync/atomic`。但这些操作都是针对并发过程中的数据安全的，并不是针对goroutine本身的。  

本文主要介绍的是对goroutine并发行为的控制。在Go中最常见的有三种方式：**sync.WaitGroup**、**channel**和**Context**。  

## 1. sync.WaitGroup

sync.WaitGroup是Go语言中一个非常有用的同步原语，它可以帮助我们等待一组goroutine全部完成。在以下场景中，我们通常会使用sync.WaitGroup：

- 当我们需要在主函数中等待一组goroutine全部完成后再退出程序时。
- 当我们需要在一个函数中启动多个goroutine，并确保它们全部完成后再返回结果时。
- 当我们需要在一个函数中启动多个goroutine，并确保它们全部完成后再执行某个操作时。
- 当我们需要在一个函数中启动多个goroutine，并确保它们全部完成后再关闭某个资源时。
- 当我们需要在一个函数中启动多个goroutine，并确保它们全部完成后再退出循环时。  

在使用`sync.WaitGroup`时，我们需要先创建一个`sync.WaitGroup`对象，然后使用它的`Add`方法来指定需要等待的goroutine数量。接着，我们可以使用go关键字来启动多个goroutine，并在每个goroutine中使用`sync.WaitGroup`对象的`Done`方法来表示该goroutine已经完成。最后，我们可以使用`sync.WaitGroup`对象的`Wait`方法来等待所有的goroutine全部完成。  

下面是一个简单的示例，会启动3个goroutine，分别休眠0s、1s和2s，主函数会在这3个goroutine结束后退出：  

```go
package main

import (
	"fmt"
	"sync"
	"time"
)

func main() {
	var wg sync.WaitGroup

	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			fmt.Printf("sub goroutine sleep: %ds\n", i)
			time.Sleep(time.Duration(i) * time.Second)
		}(i)
	}

	wg.Wait()
	fmt.Println("main func done")
}
```  

## 2. channel  

在Go语言中，使用channel可以帮助我们更好地控制goroutine的并发。以下是一些常见的使用channel来控制goroutine并发的方法：

### 2.1 使用无缓冲channel进行同步

我们可以使用一个无缓冲的channel来实现生产者-消费者模式，其中一个goroutine负责生产数据，另一个goroutine负责消费数据。当生产者goroutine将数据发送到channel时，消费者goroutine会阻塞等待数据的到来。这样，我们可以确保生产者和消费者之间的数据同步。

下面是一个简单的示例代码：

```go
package main

import (
    "fmt"
    "sync"
    "time"
)

func producer(ch chan int, wg *sync.WaitGroup) {
    defer wg.Done()
    for i := 0; i < 10; i++ {
        ch <- i
        fmt.Println("produced", i)
        time.Sleep(100 * time.Millisecond)
    }
    close(ch)
}

func consumer(ch chan int, wg *sync.WaitGroup) {
    defer wg.Done()
    for i := range ch {
        fmt.Println("consumed", i)
        time.Sleep(150 * time.Millisecond)
    }
}

func main() {
    var wg sync.WaitGroup
    ch := make(chan int)

    wg.Add(2)
    go producer(ch, &wg)
    go consumer(ch, &wg)

    wg.Wait()
}
```

在这个示例中，我们创建了一个无缓冲的channel，用于在生产者goroutine和消费者goroutine之间传递数据。生产者goroutine将数据发送到channel中，消费者goroutine从channel中接收数据。在生产者goroutine中，我们使用time.Sleep函数来模拟生产数据的时间，在消费者goroutine中，我们使用time.Sleep函数来模拟消费数据的时间。最后，我们使用sync.WaitGroup来等待所有的goroutine全部完成。

### 2.2 使用有缓冲channel进行限流

我们可以使用一个有缓冲的channel来限制并发goroutine的数量。在这种情况下，我们可以将channel的容量设置为我们希望的最大并发goroutine数量。然后，在启动每个goroutine之前，我们将一个值发送到channel中。在goroutine完成后，我们从channel中接收一个值。这样，我们可以保证同时运行的goroutine数量不超过我们指定的最大并发数量。

下面是一个简单的示例代码：

```go
package main

import (
    "fmt"
    "sync"
)

func main() {
    var wg sync.WaitGroup
    maxConcurrency := 3
    semaphore := make(chan struct{}, maxConcurrency)

    for i := 0; i < 10; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            semaphore <- struct{}{}
            fmt.Println("goroutine", i, "started")
            // do some work
            fmt.Println("goroutine", i, "finished")
            <-semaphore
        }()
    }

    wg.Wait()
}
```

在这个示例中，我们创建了一个带缓冲的channel，缓冲区大小为3。然后，我们启动了10个goroutine，在每个goroutine中，我们将一个空结构体发送到channel中，表示该goroutine已经开始执行。在goroutine完成后，我们从channel中接收一个空结构体，表示该goroutine已经完成执行。这样，我们可以保证同时运行的goroutine数量不超过3。

## 3. Context  

在Go语言中，使用Context可以帮助我们更好地控制goroutine的并发。以下是一些常见的使用Context来控制goroutine并发的方法：

### 3.1 超时控制

在某些情况下，我们需要对goroutine的执行时间进行限制，以避免程序长时间阻塞或者出现死锁等问题。使用Context可以帮助我们更好地控制goroutine的执行时间。我们可以创建一个带有超时时间的Context，然后将其传递给goroutine。如果goroutine在超时时间内没有完成执行，我们可以使用Context的Done方法来取消goroutine的执行。

下面是一个简单的示例代码：

```go
package main

import (
    "context"
    "fmt"
    "time"
)

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()

    go func() {
        for {
            select {
            case <-ctx.Done():
                fmt.Println("goroutine finished")
                return
            default:
                fmt.Println("goroutine running")
                time.Sleep(500 * time.Millisecond)
            }
        }
    }()

    time.Sleep(3 * time.Second)
}
```

在这个示例中，我们创建了一个带有超时时间的Context，然后将其传递给goroutine。在goroutine中，我们使用select语句来监听Context的Done方法，如果Context超时，我们将会取消goroutine的执行。

### 3.2 取消操作

在某些情况下，我们需要在程序运行过程中取消某些goroutine的执行。使用Context可以帮助我们更好地控制goroutine的取消操作。我们可以创建一个带有取消功能的Context，然后将其传递给goroutine。如果需要取消goroutine的执行，我们可以使用Context的Cancel方法来取消goroutine的执行。

下面是一个简单的示例代码：

```go
package main

import (
    "context"
    "fmt"
    "sync"
    "time"
)

func main() {
    ctx, cancel := context.WithCancel(context.Background())

    var wg sync.WaitGroup
    wg.Add(1)
    go func() {
        defer wg.Done()
        for {
            select {
            case <-ctx.Done():
                fmt.Println("goroutine finished")
                return
            default:
                fmt.Println("goroutine running")
                time.Sleep(500 * time.Millisecond)
            }
        }
    }()

    time.Sleep(2 * time.Second)
    cancel()
    wg.Wait()
}
```

在这个示例中，我们创建了一个带有取消功能的Context，然后将其传递给goroutine。在goroutine中，我们使用select语句来监听Context的Done方法，如果Context被取消，我们将会取消goroutine的执行。在主函数中，我们使用time.Sleep函数来模拟程序运行过程中的某个时刻需要取消goroutine的执行，然后调用Context的Cancel方法来取消goroutine的执行。

### 3.3 资源管理

在某些情况下，我们需要对goroutine使用的资源进行管理，以避免资源泄露或者出现竞争条件等问题。使用Context可以帮助我们更好地管理goroutine使用的资源。我们可以将资源与Context关联起来，然后将Context传递给goroutine。当goroutine完成执行后，我们可以使用Context来释放资源或者进行其他的资源管理操作。

下面是一个简单的示例代码：

```go
package main

import (
    "context"
    "fmt"
    "sync"
    "time"
)

func worker(ctx context.Context, wg *sync.WaitGroup) {
    defer wg.Done()
    for {
        select {
        case <-ctx.Done():
            fmt.Println("goroutine finished")
            return
        default:
            fmt.Println("goroutine running")
            time.Sleep(500 * time.Millisecond)
        }
    }
}

func main() {
    ctx, cancel := context.WithCancel(context.Background())

    var wg sync.WaitGroup
    wg.Add(1)
    go worker(ctx, &wg)

    time.Sleep(2 * time.Second)
    cancel()
    wg.Wait()
}
```

在这个示例中，我们创建了一个带有取消功能的Context，然后将其传递给goroutine。在goroutine中，我们使用select语句来监听Context的Done方法，如果Context被取消，我们将会取消goroutine的执行。在主函数中，我们使用time.Sleep函数来模拟程序运行过程中的某个时刻需要取消goroutine的执行，然后调用Context的Cancel方法来取消goroutine的执行。

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
