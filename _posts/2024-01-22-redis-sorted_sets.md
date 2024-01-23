---
layout: post
title: Redis sorted sets
tags: redis 
mermaid: false
math: true
---  

> 原文在[这里](https://redis.io/docs/data-types/sorted-sets/)。

Redis有序集合是一个由相关分数排序的唯一字符串（成员）的集合。当多个字符串具有相同的分数时，字符串按字典顺序排序。有序集的一些用例包括：  

- 排行榜。例如，你可以使用有序集合轻松地维护大型在线游戏中最高分数的有序列表。
- 速率限制器。特别是，你可以使用有序集合构建一个滑动窗口速率限制器，以防止过多的API请求。

你可以将有序集合看作是Set和Hash之间的混合体。与集合一样，有序集合由唯一的、不重复的字符串元素组成，因此从某种意义上说，有序集合也是一个集合。

然而，集合内的元素没有顺序，但有序集合中的每个元素都与一个浮点值关联，称为分数（这也是为什么该类型与哈希相似的原因，因为每个元素都映射到一个值）。

此外，有序集合中的元素是*按顺序*获取的（因此它们不是在请求时有序的，有序是表示有序集合的数据结构的一种特性）。它们按照以下规则排序：  

- A、B两个元素有着不同的分数，如果A的分数 > B的分数，那么A > B。
- A、B两个元素有着相同的分数，如果A字符串的字段顺序 > B的，那么A > B。因为有序集合只包含唯一元素，所以A、B两个字符串不能相同。

下面我们从一个简单的例子开始，我们添加所有的赛车手以及他们在第一场比赛中获得的分数：  

```bash
> ZADD racer_scores 10 "Norem"
(integer) 1
> ZADD racer_scores 12 "Castilla"
(integer) 1
> ZADD racer_scores 8 "Sam-Bodden" 10 "Royce" 6 "Ford" 14 "Prickett"
(integer) 4
```  

如上所示，**ZADD**与**SADD**类似，但多了一个额外的参数（放在要添加的元素之前），即分数。**ZADD**也是可变参数的，因此你可以自由指定多个分数-值对，即使在上面的示例中没有使用。  

使用有序集合，按出生年份返回黑客列表是很简单的，因为它们*已经是有序的*。

实现说明：有序集合通过包含跳跃表和哈希表的双端口数据结构实现，因此每次添加元素时，Redis执行一次O(log(N))操作。当我们要求有序元素时，Redis根本不需要做任何工作，因为它已经是有序的。请注意，**ZRANGE**的顺序是从低到高，而**ZREVRANGE**的顺序是从高到低：  

```bash
> ZRANGE racer_scores 0 -1
1) "Ford"
2) "Sam-Bodden"
3) "Norem"
4) "Royce"
5) "Castilla"
6) "Prickett"
> ZREVRANGE racer_scores 0 -1
1) "Prickett"
2) "Castilla"
3) "Royce"
4) "Norem"
5) "Sam-Bodden"
6) "Ford"
```  

注意：0和-1表示从元素索引0到最后一个元素（-1在这里的工作方式与**LRANGE**命令的情况相同）。

还可以使用**WITHSCORES**参数返回分数：  

```bash
> ZRANGE racer_scores 0 -1 withscores
 1) "Ford"
 2) "6"
 3) "Sam-Bodden"
 4) "8"
 5) "Norem"
 6) "10"
 7) "Royce"
 8) "10"
 9) "Castilla"
10) "12"
11) "Prickett"
12) "14"
```  

## 范围操作

有序集合远不止于此。它们也支持范围操作：我们获取下所有得分为10分或以下的赛车手，这里可以使用**ZRANGEBYSCORE**命令来完成：  

```bash
> ZRANGEBYSCORE racer_scores -inf 10
1) "Ford"
2) "Sam-Bodden"
3) "Norem"
4) "Royce"
```  

以上，我们通过Redis查询所有得分在负无穷和10之间的元素（两个极端都包括在内）。  

要删除一个元素，我们只需使用**ZREM**；还可以删除范围内的元素。现在我们删除Castilla赛车手以及所有得分严格少于10分的赛车手：  

```bash
> ZREM racer_scores "Castilla"
(integer) 1
> ZREMRANGEBYSCORE racer_scores -inf 9
(integer) 2
> ZRANGE racer_scores 0 -1
1) "Norem"
2) "Royce"
3) "Prickett"
```  

**ZREMRANGEBYSCORE**也许不是最佳的命令名称，但它可能非常有用，并返回已移除元素的数量。

对于有序集合元素而言，另一个非常有用的操作是get-rank操作。可以询问一个元素在有序元素集合中的位置。**ZREVRANK**命令也可用于获取排名，考虑到元素按降序排序。  

```bash
> ZRANK racer_scores "Norem"
(integer) 0
> ZREVRANK racer_scores "Norem"
(integer) 3
```  

## 字典分数

在 Redis 2.8 版本中引入了一项新功能，允许按字典顺序获取范围，假设有序集的元素都以相同的相同分数插入（元素使用 C **memcmp** 函数进行比较，因此确保没有排序规则，每个 Redis 实例都将返回相同的输出）。

处理字典范围的主要命令包括**ZRANGEBYLEX**、**ZREVRANGEBYLEX**、**ZREMRANGEBYLEX**和**ZLEXCOUNT**。

例如，让我们再次添加我们的著名黑客列表，但这次为所有元素使用零分数。由于有序集的排序规则，它们已经按字典顺序排列。使用**ZRANGEBYLEX**，我们可以请求字典范围：  

```bash
> ZADD racer_scores 0 "Norem" 0 "Sam-Bodden" 0 "Royce" 0 "Castilla" 0 "Prickett" 0 "Ford"
(integer) 3
> ZRANGE racer_scores 0 -1
1) "Castilla"
2) "Ford"
3) "Norem"
4) "Prickett"
5) "Royce"
6) "Sam-Bodden"
> ZRANGEBYLEX racer_scores [A [L
1) "Castilla"
2) "Ford"
```  

范围可以是包含的或不包含的（取决于第一个字符），同时用 + 和 - 字符串分别指定正无穷和负无穷。有关更多信息，请参阅文档。

这个特性很重要，因为它允许我们将有序集用作通用索引。例如，如果你想通过一个128位无符号整数参数索引元素，你只需要将元素添加到具有相同分数的有序集中（例如0），但使用**大端序的128位数字**构成的16字节前缀。由于大端序的数字在字典顺序（原始字节顺序）下也是按数值顺序排列的，你可以在128位空间中请求范围，并获取元素的值，丢弃前缀。

如果你想在更严肃的演示上看到这个特性，请查看[Redis 自动完成演示](http://autocomplete.redis.io/?_gl=1*1kqxhmz*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTk5NTM4Ni4xNC4wLjE3MDU5OTUzODguNTguMC4w*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.)。  

## 更新分数：排行榜

关于有序集的最后一点说明，然后切换到下一个主题。有序集的分数可以随时更新。只需调用**ZADD**对已包含在有序集中的元素进行操作，就会更新其分数（和位置），时间复杂度为 O(log(N))。因此，当存在大量更新时，有序集是合适的选择。

由于这个特性，一个常见的使用案例是排行榜。典型的应用是Facebook游戏，在这种游戏中，你可以按照用户的高分排序，结合get-rank操作，以显示前N名用户和用户在排行榜中的排名（例如，“你是这里第4932名最高分”）。  

## 示例  

- 有两种方法可以使用有序集表示排行榜。如果我们知道赛手的新分数，我们可以直接通过**ZADD**命令进行更新。然而，如果我们想要给现有分数添加积分，我们可以使用**ZINCRBY**命令。  

```bash
> ZADD racer_scores 100 "Wood"
(integer) 1
> ZADD racer_scores 100 "Henshaw"
(integer) 1
> ZADD racer_scores 150 "Henshaw"
(integer) 0
> ZINCRBY racer_scores 50 "Wood"
"150"
> ZINCRBY racer_scores 50 "Henshaw"
"200"
```  

当成员已经存在时（分数已更新），**ZADD**返回0，而**ZINCRBY**返回新的分数。赛车手Henshaw的分数从100变为150，而无需考虑之前的分数，然后增加了50，变为200。  

## 基本命令  

- **ZADD**将新成员和相关分数添加到有序集中。如果成员已经存在，则更新分数。
- **ZRANGE**返回有序集中在给定范围内排序的成员。
- **ZRANK**返回提供的成员的排名，假设有序集按升序排列。
- **ZREVRANK**返回提供的成员的排名，假设有序集按降序排列。

详见[完整的列表命令](https://redis.io/commands/?group=sorted-set)。  

## 性能

大多数有序集操作的时间复杂度为O(log(n))，其中n是成员的数量。

使用**ZRANGE**命令返回大量值（例如，成千上万个或更多）时，需要谨慎操作。因为该命令的时间复杂度为O(log(n) + m)，其中m是返回的结果数量。  

## 替代方案  

Redis有序集有时用于索引其他Redis数据结构。如果需要对数据进行索引和查询，请考虑使用JSON数据类型以及[搜索和查询](https://redis.io/docs/stack/search)功能。  

## 了解更多

- [Redis有序集合解析](https://www.youtube.com/watch?v=MUKlxdBQZ7g)是对Redis中有序集的有趣介绍。
- [Redis University RU101](https://university.redis.com/courses/ru101/?_gl=1*kus0jf*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTk5NTM4Ni4xNC4wLjE3MDU5OTUzODguNTguMC4w*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.&_ga=2.116329670.130259205.1705572418-889654803.1705481218)深入探讨了Redis集合。

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
 