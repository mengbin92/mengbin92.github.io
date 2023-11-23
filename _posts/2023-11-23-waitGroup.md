---
layout: post
title: sync.WaitGroup 简介
tags: go
mermaid: false
math: false
---  

`sync.WaitGroup` 是 Go 语言标准库 `sync` 包提供的一个同步工具，用于等待一组协程完成执行。它通常用于确保所有协程完成后再继续执行后续的代码。`WaitGroup` 提供了三个主要方法：`Add`、`Done`、和 `Wait`。

### 1. WaitGroup 方法

- **`Add`：** 增加等待的协程数量。在 `Add` 被调用时，等待的协程数量会增加。每个协程在开始执行时应该调用 `Add`，表示有一个协程需要等待。

    ```go
    func (wg *WaitGroup) Add(delta int)
    ```

- **`Done`：** 减少等待的协程数量。在每个协程完成执行时，应该调用 `Done` 减少等待的协程数量。等待的协程数量减为零时，`Wait` 方法将返回。

    ```go
    func (wg *WaitGroup) Done()
    ```

- **`Wait`：** 阻塞直到等待的协程数量减为零。`Wait` 会一直阻塞当前协程，直到等待的协程数量减为零。一般会在主协程中调用 `Wait`。

    ```go
    func (wg *WaitGroup) Wait()
    ```

### 2. 使用示例

以下是一个简单的示例，演示了如何使用 `WaitGroup` 等待一组协程完成：

```go
package main

import (
	"fmt"
	"sync"
	"time"
)

var wg sync.WaitGroup

func main() {
	
	for i := 1; i <= 3; i++ {
		wg.Add(1)
		go worker(i)
	}

	// 等待所有协程完成
	wg.Wait()

	fmt.Println("All workers have finished.")
}

func worker(id int) {
	defer wg.Done()
	fmt.Printf("Worker %d is starting\n", id)
	time.Sleep(2 * time.Second)
	fmt.Printf("Worker %d has finished\n", id)
}
```

在这个例子中，主协程使用 `WaitGroup` 来等待三个 worker 协程完成。每个 worker 协程在开始执行时调用 `Add(1)`，在结束时调用 `Done()`，表示一个协程已完成。主协程通过 `Wait` 阻塞等待，直到所有的 worker 协程都完成后才继续执行。

`WaitGroup` 是 Go 中一种简单而强大的同步机制，适用于需要等待一组协程完成的场景，如并发任务的协同工作。

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
