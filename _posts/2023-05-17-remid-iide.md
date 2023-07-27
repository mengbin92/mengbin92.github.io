---
layout: post
title: 基于Docker构建 Solidity remix-ide环境
tags: solidity
mermaid: false
math: false
---

Solidity是一门为实现智能合约而创建的面向对象的高级编程语言。智能合约是管理以太坊中账户行为的程序。  

Solidity是一种面向以太坊虚拟机(EVM)的带花括号的语言。它受C++，Python和JavaScript的影响。你可以在语言的影响因素部分中找到更多有关Solidity受哪些语言启发的细节。  

Solidity是静态类型语言，支持继承，库和复杂的用户自定义的类型以及其他特性。  

在编写Solidity合约时，官方建议使用[在线的Remix](https://remix.ethereum.org/)，无需在本地安装任何东西。如果你想离线使用的话，也可以按照[https://github.com/ethereum/remix-live/tree/gh-pages](https://github.com/ethereum/remix-live/tree/gh-pages)的说明进行安装。  

在日常工作中，我习惯使用Docker进行开发环境的部署，这种方式可以减少不必要的环境配置工作。  

以下是我自己总结的基于Docker部署Remix的过程。  

## 准备Dockerfile  

既然要在Docker中运行Remix，首先我们就需要准备Remix的镜像，Dockerfile内容如下：  

```dockerfile
FROM alpine:latest as builder

RUN apk update && apk add git

WORKDIR /root
RUN git clone -b gh-pages https://github.com/ethereum/remix-live.git remix && cd remix && rm -rf .git


FROM nginx:alpine

WORKDIR /

COPY --from=builder /root/remix /usr/share/nginx/html/

EXPOSE 80
```  

之后使用`docker build`命令生成镜像：  

```bash
$ docker build -t remix-ide .
```

## 启动服务  

```yaml
version: '3.3'

networks:
  solidity:

services:
  remix-ide:
    image: remix-ide:latest
    container_name: remix-ide
    ports:
      - 8080:80
    networks:
      - solidity
```

使用`docker-compose`命令启动服务：  

```bash
$ docekr-compose up -d
```  

浏览器访问`localhost:8080`即可使用Remix进行Solidity合约开发了。  

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
