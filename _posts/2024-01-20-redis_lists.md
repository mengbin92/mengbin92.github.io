---
layout: post
title: Redis Lists
tags: redis
mermaid: false
math: false
---  

> 原文在[这里](https://redis.io/docs/data-types/json/)。 

Redis列表是字符串值的链表。Redis列表经常用于：  

- 实现栈和队列
- 构建后台工作系统的队列管理。

## 基本命令

- **LPUSH**从列表的头部增加一个新元素；**RPUSH**从尾部增加元素
- **LPOP**从列表的头部删除元素并将之返回；**RPOP**从尾部删除并返回元素
- **LLEN**返回列表的长度
- **LMOVE**原子地将元素从一个列表移动到另一个列表。
- **LTRIM**将列表减少到指定范围的元素。

## 阻塞命令

列表支持一组阻塞命令。例如：  

- **BLPOP**从列表头部移除并返回一个元素。如果列表为空，该命令将阻塞，直到有元素可用或达到指定的超时时间。
- **BLMOVE**原子地将元素从源列表移动到目标列表。如果源列表为空，该命令将阻塞，直到有新元素可用。

详见[完整的列表命令](https://redis.io/commands/?group=list)。  

## 示例  

- 将列表视为队列（先进先出）：  
```bash
> LPUSH bikes:repairs bike:1
(integer) 1
> LPUSH bikes:repairs bike:2
(integer) 2
> RPOP bikes:repairs
"bike:1"
> RPOP bikes:repairs
"bike:2"
```
- 将列表视为栈（先进后出）：
```bash
> LPUSH bikes:repairs bike:1
(integer) 1
> LPUSH bikes:repairs bike:2
(integer) 2
> LPOP bikes:repairs
"bike:2"
> LPOP bikes:repairs
"bike:1"
```
- 检查列表的长度：  
```bash
> LLEN bikes:repairs
(integer) 0
```
- 原子地从一个列表中弹出一个元素并推送到另一个列表：
```bash
> LPUSH bikes:repairs bike:1
(integer) 1
> LPUSH bikes:repairs bike:2
(integer) 2
> LMOVE bikes:repairs bikes:finished LEFT LEFT
"bike:2"
> LRANGE bikes:repairs 0 -1
1) "bike:1"
> LRANGE bikes:finished 0 -1
1) "bike:2"
```
- 要限制列表的长度，可以调用LTRIM：
```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3 bike:4 bike:5
(integer) 5
> LTRIM bikes:repairs 0 2
OK
> LRANGE bikes:repairs 0 -1
1) "bike:1"
2) "bike:2"
3) "bike:3"
```

## 什么是列表？

为了解释列表数据类型，最好从一点理论开始，因为信息技术人员通常会以不正确的方式使用术语*列表*。例如，“Python列表”并不是名字可能暗示的链表，而是数组（实际上在Ruby中，相同的数据类型被称为数组）。

从非常一般的角度来看，列表只是有序元素的序列：10,20,1,2,3就是一个列表。但使用数组实现的列表的属性与使用*链表*实现的列表的属性非常不同。  

Redis列表是通过链表实现的。这意味着即使列表中有数百万个元素，将新元素添加到列表的头部或尾部的操作都是在常数时间内执行的。使用**LPUSH**命令将新元素添加到具有十个元素的列表的头部的速度与将元素添加到具有1000万个元素的列表的头部相同。

有什么缺点呢？在使用数组实现的列表中，通过*索引*访问元素非常快（常数时间的索引访问），而在使用链表实现的列表中，通过索引访问元素并不那么快（该操作需要与所访问元素的索引成比例的工作量）。

Redis列表使用链表实现，因为对于数据库系统而言，能够以非常快的方式向非常长的列表中添加元素至关重要。另一个强大的优势，正如你稍后将看到的，是Redis列表可以在常数时间内以常数长度获取。

当快速访问大量元素集合的中间部分很重要时，可以使用一种不同的数据结构，称为有序集合。有序集合在[有序集合](https://redis.io/docs/data-types/sorted-sets)教程页面中有介绍。  

## 使用Redis列表的第一步

**LPUSH**命令将一个新元素添加到列表的左侧（头部），而**RPUSH**命令将一个新元素添加到列表的右侧（尾部）。最后，**LRANGE**命令从列表中提取元素的范围：  

```bash
> RPUSH bikes:repairs bike:1
(integer) 1
> RPUSH bikes:repairs bike:2
(integer) 2
> LPUSH bikes:repairs bike:important_bike
(integer) 3
> LRANGE bikes:repairs 0 -1
1) "bike:important_bike"
2) "bike:1"
3) "bike:2"
```

需要注意的是，**LRANGE**需要两个索引，范围的第一个和最后一个元素。这两个索引都可以为负数，告诉Redis从末尾开始计数：-1是最后一个元素，-2是列表的倒数第二个元素，依此类推。

正如你所看到的，**RPUSH**在列表的右侧追加了元素，而最后的**LPUSH**在列表的左侧追加了元素。

这两个命令都是多参数命令，这意味着你可以在单个调用中自由地将多个元素推入列表中：  

```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3
(integer) 3
> LPUSH bikes:repairs bike:important_bike bike:very_important_bike
> LRANGE mylist 0 -1
1) "bike:very_important_bike"
2) "bike:important_bike"
3) "bike:1"
4) "bike:2"
5) "bike:3"
```

在Redis列表上定义的一个重要操作是*弹出*元素。弹出元素是指从列表中检索元素，同时从列表中删除它的操作。你可以从左侧和右侧弹出元素，类似于你可以将元素推送到列表的两侧。我们将添加三个元素并弹出三个元素，因此在这组命令的最后，列表为空，没有更多元素可以弹出：

```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3
(integer) 3
> RPOP bikes:repairs
"bike:3"
> LPOP bikes:repairs
"bike:1"
> RPOP bikes:repairs
"bike:2"
> RPOP bikes:repairs
(nil)
```

Redis返回了一个NULL值，表示列表中没有元素。  

## 列表通用使用场景

列表在许多任务中都很有用，两个非常典型的用例如下：

- 记录用户在社交网络中发布的最新更新。
- 进程之间的通信，使用生产者-消费者模式，其中生产者将项目推送到列表中，而消费者（通常是*工作进程*）消耗这些项目并执行操作。Redis具有特殊的列表命令，使得这种用例更加可靠和高效。

例如，广受欢迎的Ruby库[resque](https://github.com/resque/resque)和[sidekiq](https://github.com/mperham/sidekiq)在底层使用Redis列表来实现后台作业。

流行的Twitter社交网络将用户发布的[最新推文](http://www.infoq.com/presentations/Real-Time-Delivery-Twitter)放入Redis列表中。

为了逐步描述一个常见的用例，假设你的首页显示了在照片分享社交网络中发布的最新照片，而你想要加速访问。

- 每当用户发布新照片时，我们使用**LPUSH**将其ID添加到列表中。
- 当用户访问首页时，我们使用**LRANGE 0 9**来获取最新发布的10个项目。

## 列表的上限

在许多用例中，我们只想使用列表来存储最新的项目，无论这些项目是什么：社交网络更新、日志或其他任何东西。

Redis允许我们将列表用作有上限的集合，只保留最新的N个项目，并使用**LTRIM**命令丢弃所有最旧的项目。

**LTRIM**命令类似于**LRANGE**，但是**它不是显示指定范围的元素**，而是将此范围设置为新的列表值。给定范围之外的所有元素都将被移除。

例如，如果你正在将自行车添加到维修列表的末尾，但只想关注最早加入列表的3辆自行车：  

```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3 bike:4 bike:5
(integer) 5
> LTRIM bikes:repairs 0 2
OK
> LRANGE bikes:repairs 0 -1
1) "bike:1"
2) "bike:2"
3) "bike:3"
```

上面的**LTRIM**命令告诉Redis仅保留从索引0到2的列表元素，其他所有元素将被丢弃。这使得实现一种非常简单但有用的模式成为可能：将List推送操作与List修剪操作结合在一起，以添加新元素并丢弃超过限制的元素。然后可以使用带有负索引的**LTRIM**仅保留最近添加的3个元素：  

```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3 bike:4 bike:5
(integer) 5
> LTRIM bikes:repairs -3 -1
OK
> LRANGE bikes:repairs 0 -1
1) "bike:3"
2) "bike:4"
3) "bike:5"
```

上述组合添加新元素并仅保留列表中的最新3个元素。使用**LRANGE**，你可以访问顶部项目，而无需记住非常旧的数据。

注意：虽然**LRANGE**在技术上是一个O(N)命令，但访问列表头部或尾部的小范围是一个常数时间的操作。

## 列表上的阻塞操作

列表具有一种特殊的功能，使它们适用于实现队列，通常作为进程间通信系统的构建块：阻塞操作。

想象一下，你希望使用一个进程将项目推送到列表中，并使用另一个进程实际对这些项目进行某种工作。这是通常的生产者/消费者设置，并且可以以下列简单方式实现：

- 为了将项目推送到列表中，生产者调用**LPUSH**。
- 为了从列表中提取/处理项目，消费者调用**RPOP**。

然而，有时可能列表为空，没有任何可处理的内容，此时**RPOP**只会返回NULL。在这种情况下，消费者被迫等待一段时间，然后使用**RPOP**重新尝试。这被称为轮询，在这种情况下并不是一个好主意，因为它有几个缺点：

1. 强制Redis和客户端处理无用的命令（当列表为空时的所有请求都不会执行实际的工作，它们只会返回NULL）。
2. 增加了项目处理的延迟，因为在工作进程收到NULL后，它会等待一段时间。为了使延迟更小，我们可以在调用**RPOP**之间等待较短的时间，但这会放大问题1，即更多的无用的Redis调用。

所以，Redis实现了名为**BRPOP**和**BLPOP**的命令，它们是**RPOP**和**LPOP**的版本，如果列表为空，它们将阻塞：它们仅在将新元素添加到列表时，或达到用户指定的超时时才返回调用方。

这是我们在工作进程中可以使用的**BRPOP**调用示例：

```bash
> RPUSH bikes:repairs bike:1 bike:2
(integer) 2
> BRPOP bikes:repairs 1
1) "bikes:repairs"
2) "bike:2"
> BRPOP bikes:repairs 1
1) "bikes:repairs"
2) "bike:1"
> BRPOP bikes:repairs 1
(nil)
(2.01s)
```

这表示：“等待列表**bikes:repairs**中的元素，但如果1秒后没有元素可用，则返回”。

请注意，你可以使用0作为超时来永久等待元素，并且还可以指定多个列表而不仅仅是一个，以便同时等待多个列表，并在第一个列表接收到元素时收到通知。

关于**BRPOP**需要注意的一些事项：

1. 客户端以有序方式提供服务：等待列表的第一个客户端在其他客户端推送元素时首先得到服务，依此类推。
2. 返回值与**RPOP**不同：它是一个两元素数组，因为它还包括键的名称，因为**BRPOP**和**BLPOP**能够等待来自多个列表的元素。
3. 如果达到超时，则返回NULL。

关于列表和阻塞操作，还有更多需要了解的事项。我们建议你阅读以下内容：

- 使用**LMOVE**可以构建更安全的队列或旋转队列。
- 还有一个名为**BLMOVE**的命令的阻塞变体。

## 原子地创建和删除键

在我们的示例中，我们从未在推送元素之前创建空列表，或在它们不再包含元素时删除空列表。当列表为空时，Redis会负责删除键，或者在键不存在且我们尝试添加元素时创建一个空列表，例如使用**LPUSH**。

这不仅适用于列表，还适用于由多个元素组成的所有Redis数据类型，包括Streams、Sets、Sorted Sets和Hashes。

基本上，我们可以用三个规则来总结这种行为：

1. 当我们向一个聚合数据类型添加元素时，如果目标键不存在，则在添加元素之前创建一个空的聚合数据类型。
2. 当我们从聚合数据类型中删除元素时，如果值保持为空，键会自动被销毁。Stream数据类型是此规则的唯一异常。
3. 调用只读命令（例如**LLEN**，返回列表长度）或删除元素的写命令时，如果键为空，总是产生与该命令期望找到的类型相同的空聚合类型的结果。  

规则1示例：  

```bash
> DEL new_bikes
(integer) 0
> LPUSH new_bikes bike:1 bike:2 bike:3
(integer) 3
```

然而，如果键存在，我们不能对错误的类型执行操作：  

```bash
> SET new_bikes bike:1
OK
> TYPE new_bikes
string
> LPUSH new_bikes bike:2 bike:3
(error) WRONGTYPE Operation against a key holding the wrong kind of value
```  

规则2示例：  

```bash
> RPUSH bikes:repairs bike:1 bike:2 bike:3
(integer) 3
> EXISTS bikes:repairs
(integer) 1
> LPOP bikes:repairs
"bike:3"
> LPOP bikes:repairs
"bike:2"
> LPOP bikes:repairs
"bike:1"
> EXISTS bikes:repairs
(integer) 0
```

在弹出所有元素后，键将不再存在。  

规则3示例：  

```bash
> DEL bikes:repairs
(integer) 0
> LLEN bikes:repairs
(integer) 0
> LPOP bikes:repairs
(nil)
```

## 限制

Redis列表的最大长度是$2^{32} - 1（4,294,967,295）$个元素。

## 性能 

访问列表头部或尾部的列表操作是O(1)，这意味着它们非常高效。然而，通常操纵列表内元素的命令是O(n)。其中一些例子包括**LINDEX**、**LINSERT**和**LSET**。在运行这些命令时要小心，特别是在操作大型列表时。  

## 替代方案

当你需要存储和处理不确定系列事件时，考虑使用Redis Streams而不是列表。  

## 了解更多

- [Redis列表解析](https://www.youtube.com/watch?v=PB5SeOkkxQc)是关于Redis列表的简短而全面的视频解释。
- [Redis University RU101](https://university.redis.com/courses/ru101/?_gl=1*jemn5x*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTc0NjM3Mi44LjEuMTcwNTc0NjM3Ny41NS4wLjA.*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.&_ga=2.11993844.130259205.1705572418-889654803.1705481218)详细介绍了Redis列表。

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
