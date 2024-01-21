---
layout: post
title: Redis Sets
tags: redis
mermaid: false
math: true
---  

> 原文在[这里](https://redis.io/docs/data-types/sets/)。 

Redis集合是唯一字符串（成员）的无序集合。你可以使用Redis集合来高效地：

- 追踪唯一项（例如，跟踪访问特定博客文章的所有唯一IP地址）。
- 表示关系（例如，具有特定角色的所有用户的集合）。
- 执行常见的集合操作，如交集、并集和差集。

## 基本命令

- **SADD**添加一个新成员到集合中
- **SREM**从集合中移除指定成员
- **SISMEMBER**测试一个字符串是否是集合的成员
- **SINTER**返回两个或多个集合共有的成员（即交集）
- **SCARD**返回集合的大小（也称为基数）

详见[完整的列表命令](https://redis.io/commands/?group=set)。

## 示例

- 存储在法国和美国参加比赛的自行车的集合。请注意，如果添加一个已经存在的成员，它将被忽略。
```bash
> SADD bikes:racing:france bike:1
(integer) 1
> SADD bikes:racing:france bike:1
(integer) 0
> SADD bikes:racing:france bike:2 bike:3
(integer) 2
> SADD bikes:racing:usa bike:1 bike:4
(integer) 2
```

- 检查自行车1或自行车2是否在美国参加比赛。
```bash
> SISMEMBER bikes:racing:usa bike:1
(integer) 1
> SISMEMBER bikes:racing:usa bike:2
(integer) 0
```

- 哪些自行车在两场比赛中都参加？
```bash
> SINTER bikes:racing:france bikes:racing:usa
1) "bike:1"
```

- 多少自行车参加了France的比赛？
```bash
> SCARD bikes:racing:france
(integer) 3
```  

## 教程

**SADD**命令增加新的元素到集合中。还可以执行其他许多集合操作，比如测试给定元素是否已经存在，对多个集合执行交集、并集或差集等操作。  

```bash
> SADD bikes:racing:france bike:1 bike:2 bike:3
(integer) 3
> SMEMBERS bikes:racing:france
1) bike:3
2) bike:1
3) bike:2
```  

在这里，我已经向我的集合中添加了三个元素，并告诉Redis返回所有元素。集合没有顺序保证。Redis可以在每次调用时以任何顺序返回元素。

Redis有用于测试集合成员资格的命令。这些命令可以用于单个项目和多个项目：  

```bash
> SISMEMBER bikes:racing:france bike:1
(integer) 1
> SMISMEMBER bikes:racing:france bike:2 bike:3 bike:4
1) (integer) 1
2) (integer) 1
3) (integer) 0
```  

我们还可以找到两个集合之间的差异。例如，我们可能想知道哪些自行车在France比赛但不在USA比赛：  

```bash
> SADD bikes:racing:usa bike:1 bike:4
(integer) 2
> SDIFF bikes:racing:france bikes:racing:usa
1) "bike:3"
2) "bike:2"
```  

还有一些非常规的操作，但仍然可以使用正确的Redis命令轻松实现。例如，我们可能想要列出在法国、美国和其他一些比赛中参赛的所有自行车。我们可以使用**SINTER**命令来执行不同集合之间的交集。除了交集之外，还可以执行并集、差集等操作。例如，如果我们添加第三场比赛，我们可以看到其中一些命令的效果：  

```bash
> SADD bikes:racing:france bike:1 bike:2 bike:3
(integer) 3
> SADD bikes:racing:usa bike:1 bike:4
(integer) 2
> SADD bikes:racing:italy bike:1 bike:2 bike:3 bike:4
(integer) 4
> SINTER bikes:racing:france bikes:racing:usa bikes:racing:italy
1) "bike:1"
> SUNION bikes:racing:france bikes:racing:usa bikes:racing:italy
1) "bike:2"
2) "bike:1"
3) "bike:4"
4) "bike:3"
> SDIFF bikes:racing:france bikes:racing:usa bikes:racing:italy
(empty array)
> SDIFF bikes:racing:france bikes:racing:usa
1) "bike:3"
2) "bike:2"
> SDIFF bikes:racing:usa bikes:racing:france
1) "bike:4"
```  

你会注意到当所有集合之间的差异为空时，**SDIFF**命令返回一个空数组。还要注意到传递给SDIFF的集合的顺序很重要，因为差异不是可交换的。

当你想要从集合中删除项目时，可以使用**SREM**命令从集合中删除一个或多个项目，或者可以使用**SPOP**命令从集合中删除一个随机项目。你还可以使用**SRANDMEMBER**命令在不删除它的情况下*返回*集合中的一个随机项目：  

```bash
> SADD bikes:racing:france bike:1 bike:2 bike:3 bike:4 bike:5
(integer) 5
> SREM bikes:racing:france bike:1
(integer) 1
> SPOP bikes:racing:france
"bike:3"
> SMEMBERS bikes:racing:france
1) "bike:2"
2) "bike:4"
3) "bike:5"
> SRANDMEMBER bikes:racing:france
"bike:2"
```  

## 限制

Redis集合的最大长度是$2^{32} - 1（4,294,967,295）$个元素。

## 性能

大多数集合操作，包括添加、删除和检查项是否为集合成员，都是O(1)，这意味着它们非常高效。然而，对于具有数十万个或更多成员的大型集合，在运行**SMEMBERS**命令时应该小心。该命令是O(n)，并以单个响应返回整个集合。作为替代方案，考虑使用**SSCAN**，它允许你迭代检索集合的所有成员。  

## 替代方案

在大型数据集（或流数据）上进行集合成员检查可能会使用大量内存。如果你关心内存使用并且不需要完全精确性，可以考虑使用[Bloom过滤器或Cuckoo过滤器](https://redis.io/docs/stack/bloom)作为集合的替代方案。

Redis集合经常被用作一种索引。如果你需要对数据进行索引和查询，请考虑使用[JSON](https://redis.io/docs/stack/json)数据类型以及[搜索和查询](https://redis.io/docs/stack/search)功能。  

## 了解更多

- [Redis集合解析](https://www.youtube.com/watch?v=PKdCppSNTGQ)和[Redis集合详解](https://www.youtube.com/watch?v=aRw5ME_5kMY)是两个简短但全面的视频解释，涵盖了Redis集合。
- [Redis University RU101](https://university.redis.com/courses/ru101/?_ga=2.17182073.130259205.1705572418-889654803.1705481218&_gl=1*1uclell*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTc1MDM4Ny45LjEuMTcwNTc1MjMxOS41Ny4wLjA.*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.)深入探讨了Redis集合。  

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
