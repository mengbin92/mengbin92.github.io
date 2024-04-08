---
layout: post
title: Redis 管道
tags: redis 
mermaid: false
math: false
---  

> 原文在[这里](https://redis.io/docs/manual/pipelining/)

Redis管道是一种通过一次发出多个命令而不等待每个单独命令的响应来提高性能的技术。大多数Redis客户端都支持管道。本文档描述了管道旨在解决的问题以及Redis中管道的工作原理。  

## 请求/响应协议和往返时间（RTT）

Redis是一个使用客户端-服务器模型和名为请求/响应协议的TCP服务器。

这意味着通常一个请求是通过以下步骤完成的：  

- 客户端向服务器发送查询，并以阻塞方式从套接字读取服务器的响应。
- 服务器处理命令并将响应发送回客户端。

例如，像下面的四个命令序列：  

- *Client:* INCR X
- *Server:* 1
- *Client:* INCR X
- *Server:* 2
- *Client:* INCR X
- *Server:* 3
- *Client:* INCR X
- *Server:* 4

客户端和服务器通过网络链接相连。这样的链接可能非常快（例如环回接口），也可能非常慢（例如通过互联网建立的连接，两个主机之间有多个跳数）。无论网络延迟如何，数据包从客户端传输到服务器以及从服务器传回客户端以携带响应都需要时间。

这个时间称为RTT（往返时间）。很容易看出，当客户端需要连续执行许多请求时（例如，向同一个列表中添加许多元素，或者用许多键填充数据库），这会如何影响性能。例如，如果RTT时间为250毫秒（在通过互联网连接的非常慢的链路上），即使服务器能够每秒处理10万个请求，我们也最多只能每秒处理四个请求。

如果使用的接口是环回接口，RTT会短得多，通常在亚毫秒级别，但如果你需要连续执行许多写操作，这仍然会累积起来。

幸运的是，有一种方法可以改善这种情况。  

## Redis管道 

请求/响应服务器可以实现为即使在客户端尚未读取旧响应的情况下也能处理新请求。这样，就可以完全不等待回复地向服务器发送*多个命令*，最后在一个步骤中读取回复。

这就是所谓的管道技术，已经被广泛使用了数十年。例如，许多POP3协议实现已经支持此功能，极大地加快了从服务器下载新电子邮件的过程。

Redis自早期以来就支持管道，因此无论您运行的是哪个版本，都可以将管道与Redis一起使用。这是一个使用原始netcat实用程序的示例：

```bash
$ (printf "PING\r\nPING\r\nPING\r\n"; sleep 1) | nc localhost 6379
+PONG
+PONG
+PONG
```  

这次我们只需要支付一次的调用成本。

明确地说，使用管道，我们最初示例的操作顺序将是以下：  

- *Client:* INCR X
- *Client:* INCR X
- *Client:* INCR X
- *Client:* INCR X
- *Server:* 1
- *Server:* 2
- *Server:* 3
- *Server:* 4

> **重要提示**：当客户端使用管道发送命令时，服务器将被迫使用内存对回复进行排队。因此，如果您需要通过管道发送大量命令，最好将它们分批发送，每批包含合理数量的命令，例如10,000个命令，读取回复，然后再发送另外10,000个命令，依此类推。速度几乎相同，但额外使用的内存最多只是这些10,000个命令的回复排队所需的内存量。

## 不仅仅是RTT的问题

管道不仅仅是一种减少与往返时间相关的延迟成本的方法，实际上它大大提高了在给定Redis服务器中每秒可以执行的操作数量。这是因为在不使用管道的情况下，从访问数据结构和生成回复的角度来看，服务每个命令的成本非常低，但从进行套接字I/O的角度来看，成本非常高。这涉及到**read()**和**write()**的系统调用，因为这需要从用户空间切换到内核空间。上下文切换是一个巨大的速度损失。

当使用管道时，通常使用单个**read()**系统调用来读取多个命令，使用单个**write()**系统调用来传递多个回复。因此，每秒执行的总查询数量最初随着管道长度的增加而几乎线性增长，并最终达到未使用管道时获得的基线的10倍，如下图所示：  

<div align="center">
  <img src="../img/2024-04-07/pipeline_iops.png" alt="pipeline_iops">
</div>

## 示例  

在接下来的基准测试中，我们将使用支持管道的Redis Ruby客户端来测试由于管道而带来的速度提升：  

```ruby 
require 'rubygems'
require 'redis'

def bench(descr)
  start = Time.now
  yield
  puts "#{descr} #{Time.now - start} seconds"
end

def without_pipelining
  r = Redis.new
  10_000.times do
    r.ping
  end
end

def with_pipelining
  r = Redis.new
  r.pipelined do
    10_000.times do
      r.ping
    end
  end
end

bench('without pipelining') do
  without_pipelining
end
bench('with pipelining') do
  with_pipelining
end
```  

在我运行Mac OS X系统的环回接口上（在这里管道提供的改进最小，因为RTT已经相当低），运行上述简单脚本产生了以下数据：  

```bash
without pipelining 1.185238 seconds
with pipelining 0.250783 seconds
```  

如你所见，使用管道，我们将传输速度提高了五倍。  

## 管道 vs 脚本

使用[Redis脚本](https://redis.io/commands/eval)（自Redis 2.6起可用），可以通过在服务器端执行大量所需工作的脚本来更有效地解决许多管道用例。脚本的一个主要优势是它能够以最小的延迟读写数据，使得像*读*、*计算*、*写*这样的操作非常快（在这种情况下，管道无法提供帮助，因为客户端需要在调用写命令之前获得读命令的回复）。

有时，应用程序可能还希望在管道中发送**EVAL**或**EVALSHA**命令。这是完全可能的，Redis通过[SCRIPT LOAD](https://redis.io/commands/script-load)命令明确支持这一点（它保证可以在没有失败风险的情况下调用**EVALSHA**）。

## 附录：为什么即使在环回接口上，忙循环也很慢？

即使在本页中介绍了所有背景知识，你可能仍然想知道为什么像下面这样的Redis基准测试（用伪代码表示）即使在环回接口上执行，当服务器和客户端在同一台物理机器上运行时，也会很慢：  

```bash
FOR-ONE-SECOND:
    Redis.SET("foo","bar")
END
```  

毕竟，如果Redis进程和基准测试都在同一个盒子里运行，那不就是将消息在内存中从一个地方复制到另一个地方，并不会涉及任何实际的延迟或网络。

原因是系统中的进程并不总是运行，实际上是内核调度器让进程运行。例如，当基准测试被允许运行时，它会从Redis服务器读取回复（与最后执行的命令相关），并写入一个新命令。现在命令已经在环回接口缓冲区中，但是为了被服务器读取，内核应该调度服务器进程（当前被阻塞在一个系统调用中）运行，等等。所以实际上，由于内核调度器的工作方式，环回接口仍然涉及类似网络的延迟。

基本上，忙循环基准测试是在测量网络服务器性能时可以做的最愚蠢的事情。明智的做法就是避免以这种方式进行基准测试。  

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
