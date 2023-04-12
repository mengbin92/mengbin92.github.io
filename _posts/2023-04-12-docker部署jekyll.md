---
layout: post
title: Docker部署Jekyll 
tags: [其它, 建站]
mermaid: false
math: false
---  

## 1. 起因  

前两天终于下单买了个域名，10年的使用期限。既然有了域名，那自己的博客就可以搞起来了。  

现在博客的记录用的是Jekyll+Github Pages，所以决定之后自己的博客网站也采用Jekyll来部署实现，为了之后的维护、升级，决定采用docker来部署Jekyll。

## 2. 部署

`docker-compose.yaml`文件内容如下：  

```yaml
version: '3.7'
services:
  blog:
    # build: .
    image: jekyll/jekyll:latest
    ports:
      - 4000:4000/tcp
    volumes:
      - ./:/srv/jekyll
    environment:
      - JEKYLL_ENV=docker
    command: jekyll serve
```

`docker-compose up -d`，经过短暂等待后，服务将在4000端口运行。  

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---

