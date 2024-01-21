---
layout: post
title: Redis hashes
tags: redis 
mermaid: false
math: true
---  

> 原文在[这里](https://redis.io/docs/data-types/hashes/)。

Redis哈希是以字段-值对的形式组织的记录类型。你可以使用哈希表示基本对象，并存储计数器的分组，等等。  

```bash
> HSET bike:1 model Deimos brand Ergonom type 'Enduro bikes' price 4972
(integer) 4
> HGET bike:1 model
"Deimos"
> HGET bike:1 price
"4972"
> HGETALL bike:1
1) "model"
2) "Deimos"
3) "brand"
4) "Ergonom"
5) "type"
6) "Enduro bikes"
7) "price"
8) "4972"
```  

虽然哈希很方便表示*对象*，但实际上，你可以放置在哈希中的字段数量没有实际限制（除了可用内存），因此你可以在应用程序中以许多不同的方式使用哈希。

**HSET**命令设置哈希的多个字段，而**HGET**检索单个字段。**HMGET**类似于**HGET**，但返回值数组：

```bash
> HMGET bike:1 model price no-such-field
1) "Deimos"
2) "4972"
3) (nil)
```

还有一些命令可以对单个字段执行操作，比如**HINCRBY**：  

```bash
> HINCRBY bike:1 price 100
(integer) 5072
> HINCRBY bike:1 price -100
(integer) 4972
```

你可以在[文档中找到哈希命令的完整列表](https://redis.io/commands#hash)。  

值得注意的是，小型哈希（即，具有小值的几个元素）以内存中的一种特殊方式进行编码，使它们非常内存高效。  

## 基本命令

- **HSET**在哈希上设置一个或多个字段的值。
- **HGET**返回给定字段的值。
- **HMGET**返回一个或多个给定字段的值。
- **HINCRBY**按所提供的整数递增给定字段的值。

详见[完整的列表命令](https://redis.io/commands/?group=hash)。  

## 示例  

- 存储bike:1已经骑行的次数、发生事故的次数或更改所有者的次数的计数器：  

```bash
> HINCRBY bike:1:stats rides 1
(integer) 1
> HINCRBY bike:1:stats rides 1
(integer) 2
> HINCRBY bike:1:stats rides 1
(integer) 3
> HINCRBY bike:1:stats crashes 1
(integer) 1
> HINCRBY bike:1:stats owners 1
(integer) 1
> HGET bike:1:stats rides
"3"
> HMGET bike:1:stats owners crashes
1) "1"
2) "1"
```  

## 性能

大多数Redis哈希命令都是O(1)。  

少部分命令 - 如**HKEYS**，**HVALS**和**HGETALL** - 是 O(n)，n是字段-值的数量。

## 限制

每个哈希可以存储最多4,294,967,295（$2^{32} - 1$）个字段-值对。在实践中，你的哈希仅受托管Redis部署的VMs上的总体内存限制。

## 了解更多

- [Redis哈希解析](https://www.youtube.com/watch?v=-KdITaRkQ-U)是一个简短而全面的视频解释，涵盖了Redis哈希。
- [Redis University RU101](https://university.redis.com/courses/ru101/?_ga=2.74392018.130259205.1705572418-889654803.1705481218&_gl=1*1q0u96o*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTgyNjQ0OS4xMS4xLjE3MDU4MjY0NTIuNTcuMC4w*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.)深入探讨了Redis哈希。  

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
