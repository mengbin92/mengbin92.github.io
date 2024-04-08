---
layout: post
title: Redis 事务
tags: redis
mermaid: false
math: false
---  

> 原文在[这里](https://redis.io/docs/interact/transactions/)

Redis事务允许在单步中执行一组命令，它们围绕命令**MULTI**、**EXEC**、**DISCARD**和**WATCH**展开。Redis事务提供两个重要保证：

- 事务中的所有命令都被序列化并按顺序执行。其他客户端发送的请求永远不会在Redis事务执行过程中被处理。这保证了命令作为单一隔离操作执行。
- **EXEC**命令触发事务中所有命令的执行，因此，如果客户端在调用**EXEC**命令之前失去了与服务器的连接，那么在事务上下文中不会执行任何操作。相反，如果调用了**EXEC**命令，则会执行所有操作。在使用[append-only file](https://redis.io/topics/persistence#append-only-file)时，Redis确保使用单个write(2)系统调用将事务写入磁盘。然而，如果Redis服务器崩溃或被系统管理员以某种硬方式杀死，可能会导致只有部分操作被注册。Redis将在重启时检测到此条件，并以错误退出。使用**redis-check-aof**工具可以修复仅附加文件，这将删除部分事务，以便服务器可以再次启动。

从2.2版本开始，Redis在上述两个保证之外，还允许以类似于检查-设置（CAS）操作的方式实现乐观锁定。这在本文档后面有详细说明。  

## 用法

要进入Redis事务，请使用**MULTI**命令。该命令始终回复**OK**。此时，用户可以发出多个命令。Redis不会立即执行这些命令，而是将它们排队。一旦调用**EXEC**，所有命令都将执行。

如果调用**DISCARD**，则会清空事务队列并退出事务。

以下示例原子地递增键**foo**和**bar**。  

```bash
127.0.0.1:6379> MULTI
OK
127.0.0.1:6379(TX)> INCR foo
QUEUED
127.0.0.1:6379(TX)> INCR bar
QUEUED
127.0.0.1:6379(TX)> EXEC
1) (integer) 1
2) (integer) 1
```

从上面的会话中可以清楚地看出，**EXEC**返回一个回复数组，其中每个元素都是事务中单个命令的回复，按照命令发出的相同顺序排列。

当Redis连接处于**MULTI**请求的上下文中时，所有命令都将回复字符串**QUEUED**（从Redis协议的角度来看，作为状态回复发送）。排队的命令仅在调用**EXEC**时安排执行。  

## 事务中的错误

在事务过程中，可能会遇到两种命令错误：

- 命令可能无法排队，因此在调用**EXEC之**前可能会出现错误。例如，命令可能在语法上有误（参数数量错误、命令名称错误等），或者可能存在某些关键条件，如内存不足（如果服务器配置了使用**maxmemory**指令的内存限制）。
- 命令可能在调用**EXEC**之后失败，例如因为我们针对一个键执行了错误的操作（比如对字符串值执行列表操作）。

从Redis 2.6.5开始，服务器将在累积命令期间检测错误。然后它将拒绝执行事务，并在**EXEC**期间返回错误，丢弃事务。  

> **对于Redis < 2.6.5**：在Redis 2.6.5之前，客户端需要通过检查排队命令的返回值来检测在**EXEC**之前发生的错误：如果命令回复**QUEUED**，则表示已正确排队，否则Redis返回错误。如果在排队命令时发生错误，大多数客户端将中止并丢弃事务。否则，如果客户端选择继续执行事务，**EXEC**命令将执行所有成功排队的命令，无论之前的错误如何。

而在**EXEC**之后发生的错误则不会以特殊方式处理：即使在事务过程中某个命令失败，所有其他命令仍将继续执行。

在协议层面这一点更加明确。在以下示例中，即使语法正确，执行时仍有一个命令会失败：  

```bash
127.0.0.1:6379> MULTI
OK
127.0.0.1:6379(TX)> SET a abc
QUEUED
127.0.0.1:6379(TX)> LPOP a
QUEUED
127.0.0.1:6379(TX)> EXEC
1) OK
2) (error) WRONGTYPE Operation against a key holding the wrong kind of value
```

**EXEC**返回了一个包含两个元素的[批量字符串回复](https://redis.io/topics/protocol#bulk-string-reply)，其中一个是**OK**代码，另一个是错误回复。客户端库需要找到一种合理的方式来向用户提供错误。

重要的是要注意，**即使命令失败，队列中的所有其他命令仍将被处理** —— Redis不会停止处理命令。

另一个例子，再次使用telnet进行有线协议演示，展示了语法错误是如何尽快报告的：  

```bash
127.0.0.1:6379> MULTI
OK
127.0.0.1:6379(TX)> INCR a b c
(error) ERR wrong number of arguments for 'incr' command
```

这次由于语法错误，错误的INCR命令根本没有被排队。  

## 支持回滚吗？

Redis不支持事务回滚，因为支持回滚会对Redis的简单性和性能产生重大影响。  

## 丢弃命令队列

**DISCARD**可用于中止事务。在这种情况下，不会执行任何命令，连接的状态将恢复为正常。  

```bash
127.0.0.1:6379> SET foo 1
QUEUED
127.0.0.1:6379(TX)> MULTI
(error) ERR MULTI calls can not be nested
127.0.0.1:6379(TX)> INCR foo
QUEUED
127.0.0.1:6379(TX)> DISCARD
OK
127.0.0.1:6379> GET foo
"1"
```

## 使用检查-设置（CAS）的乐观锁定

**WATCH**用于为Redis事务提供检查-设置（CAS）行为。

**监视的**键被监控以检测对它们的更改。如果在**EXEC**命令之前至少有一个监视的键被修改，整个事务将中止，**EXEC**返回一个[空回复](https://redis.io/topics/protocol#nil-reply)以通知事务失败。

例如，假设我们需要原子地将一个键的值增加1（假设Redis没有**INCR**命令）。

第一次尝试可能是这样的：  

```bash
val = GET mykey
val = val + 1
SET mykey $val
```  

只有在我们有单个客户端在给定时间内执行操作时，这种方法才能可靠地工作。如果多个客户端几乎同时尝试递增键，将会出现竞态条件。例如，客户端A和B都会读取旧值，例如10。两个客户端都将值递增到11，最后将其**设置**为键的值。因此，最终值将是11而不是12。

多亏了**WATCH**，我们能够非常好地模拟这个问题：  

```bash
WATCH mykey
val = GET mykey
val = val + 1
MULTI
SET mykey $val
EXEC
```

使用上述代码，如果在调用**WATCH**和**EXEC**之间的时间内有其他客户端修改了**val**的结果，事务将失败。  

我们只需要重复操作，希望这次不会遇到新的竞态条件。这种锁定方式被称为*乐观锁定*。在许多场景中，多个客户端将访问不同的键，因此冲突的可能性很小——通常不需要重复操作。  

## WATCH说明

那么**WATCH**到底是做什么的呢？它是一个使**EXEC**具有条件的命令：我们要求Redis只有在没有任何被**WATCH**的键被修改时才执行事务。这包括客户端所做的修改（如写命令）以及Redis本身所做的修改（如过期或驱逐）。如果在被**WATCH**和收到**EXEC**之间键被修改了，整个事务将被中止。

**需要注意的是**：
- 在Redis 6.0.9之前的版本中，过期的键不会导致事务中止。[更多相关信息](https://github.com/redis/redis/pull/7920)
- 事务中的命令不会触发**WATCH**条件，因为它们只会在发送**EXEC**之前排队。

**WATCH**可以多次调用。简单地说，所有的**WATCH**调用都会从调用开始直到调用**EXEC**的那一刻，监视键的变化。您还可以向单个**WATCH**调用发送任意数量的键。

当调用**EXEC**时，无论事务是否中止，所有键都会被**UNWATCH**。当客户端连接关闭时，一切都会被**UNWATCH**。

还可以使用**UNWATCH**命令（不带参数）来清除所有被监视的键。有时这很有用，因为我们乐观地锁定了一些键，因为可能需要执行事务来更改这些键，但在读取键的当前内容后，我们不希望继续。当这种情况发生时，我们只需调用**UNWATCH**，以便连接已经可以自由用于新事务。

## 使用WATCH实现ZPOP

一个很好的例子来说明如何使用**WATCH**来创建一个Redis不支持的新的原子操作，这个例子是实现**ZPOP**(**ZPOPMIN** **POPMAX**和它们的阻塞变体在5.0版本中才添加)，这是一个命令，它以原子的方式弹出一个排序集合中的低分数元素。  

```bash
WATCH zset
element = ZRANGE zset 0 0
MULTI
ZREM zset element
EXEC
```

如果**EXEC**失败（即返回[空回复](https://redis.io/topics/protocol#nil-reply)），我们只需重复操作。  

## Redis脚本与事务

在Redis中进行类似事务操作时，需要考虑的另一个问题是事务性的[Redis脚本](https://redis.io/commands/eval)。用Redis事务做任何事情，你都也可以用脚本来做，而且通常脚本会更简单更快。  

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
