---
layout: post
title: 本地搭建golang playground
tags: go
mermaid: false
---  

本文主要是记录我搭建go playground的步骤。  

### 1、安装docker  

如果你使用的Ubuntu，docker的安装步骤可以参见[这里](https://www.cnblogs.com/lianshuiwuyi/p/11819131.html)，这是我之前写的在Ubuntu18.04下安装fabric，其中有docker的安装步骤，这里就不再赘述了。  

CentOS下安装docker的，可以参见[这里](https://developer.aliyun.com/mirror/docker-ce?spm=a2c6h.13651102.0.0.3e221b11ujdHsH)。与Ubuntu不同的是，CentOS需要自己手动安装**docker-compose**，可以从[github.com](https://github.com/docker/compose/releases)下载对应系统的compose。  

### 2、安装runsc  

```bash
wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
chmod +x runsc
sudo mv runsc /usr/local/bin
```  

配置docker使用runsc，需要在`/etc/docker/daemon.json`中添加如下内容：  

```json
{
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc"
        }
    }
}
```  

之后重启docker：  

```bash
sudo systemctl restart docker
```  

### 3、安装playground  

这里使用的golang官方提供的playground，可以从[这里](https://github.com/golang/playground.git)下载。  

按照[README.md](https://github.com/golang/playground/blob/master/README.md)中的指导就可以在本地构建出可运行的playground。  

> Tips：因为构建dock二镜像用到debain使用的是官方的源，国内访问速度很慢，修改Dockerfile使用国内的源替换
> Tips：国内环境的话，还需要修改镜像中的GOPROXY，使用`GOPROXY=https://goproxy.io,direct`代替`ENV GOPROXY=https://proxy.golang.org`，否则在执行`go mod download`时会失败。  

### 4、启动playground  

compose文件示例如下：  

```yaml
version: '2'
services: 
  sandbox_dev:
    image: golang/playground-sandbox:latest
    networks: 
      - sandnet
    command: sh -c '/usr/local/bin/play-sandbox'
    ports: 
      - 8080:80
    volumes: 
      - /var/run/docker.sock:/var/run/docker.sock

  play_dev:
    image: golang/playground:latest
    environment:
      - SANDBOX_BACKEND_URL=http://playground_sandbox_dev_1/run
    networks: 
      - sandnet
    command: sh -c '/app/playground'
    ports: 
      - 8081:8080
    volumes: 
      - /var/run/docker.sock:/var/run/docker.sock

networks: 
  sandnet:
```  

启动：  

```bash
docker-compose -f docker-compose.yaml up
```  

附图：  

<div align="center"><p><img src="../img/2022-11-12/playground01.png"></p>
<p>playground01.png</p></div>

浏览器访问：http://localhost:8081  

<div align="center"><p><img src="../img/2022-11-12/playground02.png"></p>
<p>playground02.png</p></div>

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: mengbin92  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
