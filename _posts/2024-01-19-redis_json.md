---
layout: post
title: JSON in Redis
tags: redis 
mermaid: false
math: false
---  

> 原文在[这里](https://redis.io/docs/data-types/json/)。  

Redis Stack的JSON功能为Redis提供了JavaScript Object Notation（JSON）支持。与其它Redis数据类型类似，它允许你在Redis数据库中存储、更新和检索JSON值。Redis JSON还可以与[搜索和查询](https://redis.io/docs/stack/search/)无缝配合，使你能够对[JSON文档进行索引和查询](https://redis.io/docs/stack/search/indexing_json)。  

## 主要功能

- 全面支持JSON标准
- 使用[JSONPath](http://goessner.net/articles/JsonPath/)语法选择/更新文档内的元素（详见[JSONPath syntax](https://redis.io/docs/data-types/json/path#jsonpath-syntax)）。
- 以二进制数据形式存储的文档，采用树形结构，可以快速访问子元素。
- 针对所有JSON变量类型提供有类型的原子操作。

## 使用 Redis JSON 

要学习如何使用JSON，最好从Redis CLI开始。以下示例假定你已连接到启用JSON的Redis服务器。  

### redis-cli 示例

首先，在交互模式下打开**redis-cli**。  

要尝试的第一个JSON命令是**JSON.SET**，它使用JSON值设置Redis键。**JSON.SET**接受所有JSON值类型。以下示例创建了一个JSON字符串：  

```bash
> JSON.SET animal $ '"dog"'
"OK"
> JSON.GET animal $
"[\"dog\"]"
> JSON.TYPE animal $
1) "string"
```  

请注意命令中包含美元符号字符$。这是JSON文档中值的路径（在本例中，它只是表示根）。  

以下是一些更多的字符串操作。**JSON.STRLEN**告诉你字符串的长度，你可以使用**JSON.STRAPPEND**将另一个字符串追加到它后面。  

```bash
> JSON.STRLEN animal $
1) "3"
> JSON.STRAPPEND animal $ '" (Canis familiaris)"'
1) "22"
> JSON.GET animal $
"[\"dog (Canis familiaris)\"]"
```  

数字可以[递增](https://redis.io/commands/json.numincrby)和[乘积](https://redis.io/commands/json.nummultby)：  

```bash
> JSON.SET num $ 0
OK
> JSON.NUMINCRBY num $ 1
"[1]"
> JSON.NUMINCRBY num $ 1.5
"[2.5]"
> JSON.NUMINCRBY num $ -0.75
"[1.75]"
> JSON.NUMMULTBY num $ 24
"[42]"
```  

以下是一个更有趣的例子，其中包含JSON数组和对象：

```bash
> JSON.SET example $ '[ true, { "answer": 42 }, null ]'
OK
> JSON.GET example $
"[[true,{\"answer\":42},null]]"
> JSON.GET example $[1].answer
"[42]"
> JSON.DEL example $[-1]
(integer) 1
> JSON.GET example $
"[[true,{\"answer\":42}]]"
```  

**JSON.DEL**命令使用**路径**参数删除你指定的任何JSON值。  

你可以使用专用的JSON命令子集来操作数组：  

```bash
> JSON.SET arr $ []
OK
> JSON.ARRAPPEND arr $ 0
1) (integer) 1
> JSON.GET arr $
"[[0]]"
> JSON.ARRINSERT arr $ 0 -2 -1
1) (integer) 3
> JSON.GET arr $
"[[-2,-1,0]]"
> JSON.ARRTRIM arr $ 1 1
1) (integer) 1
> JSON.GET arr $
"[[-1]]"
> JSON.ARRPOP arr $
1) "-1"
> JSON.ARRPOP arr $
1) (nil)
```  

JSON对象也有它专有命令：  

```bash
> JSON.SET obj $ '{"name":"Leonard Cohen","lastSeen":1478476800,"loggedOut": true}'
OK
> JSON.OBJLEN obj $
1) (integer) 3
> JSON.OBJKEYS obj $
1) 1) "name"
   2) "lastSeen"
   3) "loggedOut"
```  

为了以更易读的格式返回JSON响应，请在**redis-cli**中以原始输出模式运行，并在**JSON.GET**命令中包含格式化关键字，例如**INDENT**、**NEWLINE**和**SPACE**：  

```bash
$ redis-cli --raw
> JSON.GET obj INDENT "\t" NEWLINE "\n" SPACE " " $
[
	{
		"name": "Leonard Cohen",
		"lastSeen": 1478476800,
		"loggedOut": true
	}
]
```  

## Python 示例  

这个代码片段展示了如何使用[redis-py](https://github.com/redis/redis-py)从Python使用原始的Redis命令处理JSON：  

```python
import redis

data = {
    'dog': {
        'scientific-name' : 'Canis familiaris'
    }
}

r = redis.Redis()
r.json().set('doc', '$', data)
doc = r.json().get('doc', '$')
dog = r.json().get('doc', '$.dog')
scientific_name = r.json().get('doc', '$..scientific-name')
```  

## 使用Docker运行  

要使用Docker运行RedisJSON，请使用**redis-stack-server** Docker镜像：  

```bash
$ docker run -d --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest
```  

有关在Docker容器中运行Redis Stack的更多信息，请参阅[在Docker上运行Redis Stack](https://redis.io/docs/getting-started/install-stack/docker)。  

## 下载二进制文件  

要下载并运行提供JSON数据结构的RedisJSON模块的预编译二进制文件：  

1. 从[Redis download center](https://redis.com/download-center/modules/?_ga=2.49741926.130259205.1705572418-889654803.1705481218&_gl=1*1lk3j32*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTY0NzAzOC40LjEuMTcwNTY1NDk4OS4xNy4wLjA.*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.)下载编译好的二进制文件
2. 在Redis中启用该模块：  

```bash
$ redis-server --loadmodule /path/to/module/src/rejson.so
```  

## 从源码构建  

从源码构建RedisJSON，需要：  

1. 从[repository](https://github.com/RedisJSON/RedisJSON)（确保使用 **--recursive**选项克隆子模块）克隆源码：
   ```bash
   $ git clone --recursive https://github.com/RedisJSON/RedisJSON.git
   $ cd RedisJSON
   ```
2. 安装依赖：
   ```bash
   $ ./sbin/setup
   ```
3. 构建：
   ```bash
   $ make build
   ```

## 加载Redis模块  

先决条件：  

通常，最好的是运行最新版本的Redis。  

如果你的操作系统有[Redis 6.x或更高版本的包](http://redis.io/download)，可以使用操作系统的包管理器进行安装。

否则，你可以调用：  

```bash
$ ./deps/readies/bin/getredis
```  

要加载RedisJSON模块，可以使用以下其中一种方法：  

- 使用Makefile
- 通过配置文件
- 命令行选项
- MODULE LOAD命令

### 使用Makefile

使用RedisJSON运行Redis：  

```bash
$ make run
```  

### 配置文件

或者你可以让Redis在启动时加载该模块，方法是在**redis.conf**文件中添加以下内容：  

```bash
loadmodule /path/to/module/target/release/librejson.so
```  

在Mac OS中，该模块被编译成dynamic库，需要执行下面：  

```bash
loadmodule /path/to/module/target/release/librejson.dylib
```  

在上述行中，将`/path/to/module/`替换为模块的实际路径。  

另外，你可以下载并运行预编译的Redis二进制文件：

1. 从[Redis download center](https://redis.com/download-center/modules/?_gl=1*17hjhai*_ga*ODg5NjU0ODAzLjE3MDU0ODEyMTg.*_ga_8BKGRQKRPV*MTcwNTcyMTM5Ni42LjAuMTcwNTcyMTM5OC41OC4wLjA.*_gcl_au*MTQzNTAwOTk2LjE3MDU0ODEyMTc.&_ga=2.74441170.130259205.1705572418-889654803.1705481218)下载预编译好的RedisJSON。

### 命令行选项

或者，你可以使用以下命令行参数语法让Redis加载该模块：

```bash
$ redis-server --loadmodule /path/to/module/librejson.so
```  

将`/path/to/module/`替换为模块的实际路径。  

### MODULE LOAD命令

你还可以使用**MODULE LOAD**命令加载RedisJSON。请注意，**MODULE LOAD**是一个**危险的命令**，由于安全考虑，可能会在将来被阻止/弃用。  

在模块成功加载后，Redis日志应该包含类似于以下的行：  

```bash
...
9:M 11 Aug 2022 16:24:06.701 * <ReJSON> version: 20009 git sha: d8d4b19 branch: HEAD
9:M 11 Aug 2022 16:24:06.701 * <ReJSON> Exported RedisJSON_V1 API
9:M 11 Aug 2022 16:24:06.701 * <ReJSON> Enabled diskless replication
9:M 11 Aug 2022 16:24:06.701 * <ReJSON> Created new data type 'ReJSON-RL'
9:M 11 Aug 2022 16:24:06.701 * Module 'ReJSON' loaded from /opt/redis-stack/lib/rejson.so
...
```  

## 限制

传递给命令的JSON值的深度最多为128。如果传递给命令的JSON值包含具有超过128个嵌套级别的对象或数组，则命令将返回错误。  

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
