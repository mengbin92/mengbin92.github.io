---
layout: post
title: Ubuntu 24.04安装shadowsocks-libev
tags: tools
mermaid: false
math: false
---  

Shadowsocks-libev 是一个基于 libev 的高性能的代理工具，支持多种加密方式，适用于个人和企业的网络加速。本文将指导您在 Ubuntu 24.04 上安装 Shadowsocks-libev。

## 1. 更新系统

首先，打开终端并更新系统软件包列表：

```bash
$ sudo apt update
$ sudo apt upgrade
```

## 2. 安装依赖库

安装 Shadowsocks-libev 需要以下依赖库：

```bash
$ sudo apt install build-essential libevent-dev libssl-dev libsodium-dev
```

## 3. 下载并编译 Shadowsocks-libev

从 GitHub 上克隆 Shadowsocks-libev 仓库：

```bash
$ git clone https://github.com/shadowsocks/shadowsocks-libev.git
```

进入克隆的目录：

```bash
$ cd shadowsocks-libev
```

配置编译选项：

```bash
$ ./configure --prefix=/usr/local/shadowsocks-libev --with-libevent --with-openssl --with-libsodium
```

编译并安装 Shadowsocks-libev：

```bash
$ make && sudo make install
```

## 4. 下载并编译 simple-obfs

从 GitHub 上克隆 simple-obfs 仓库：  

```bash
$ git clone https://github.com/shadowsocks/simple-obfs.git
```  

进入克隆的目录：  

```bash
$ cd simple-obfs
```  

编译并安装：  

```bash
$ make && sudo make install
```

## 5. 配置 Shadowsocks-libev 和 simple-obfs

编辑配置文件 `/usr/local/shadowsocks-libev/config.json`：

```bash
$ sudo nano /usr/local/shadowsocks-libev/config.json
```

将以下内容粘贴到文件中，替换为您自己的服务器信息和密码：

```json
{
  "server": "your_server_ip",
  "server_port": 8381,
  "local_address": "127.0.0.1",
  "local_port": 1080,
  "password": "your_password",
  "timeout": 300,
  "method": "aes-256-gcm",
  "obfs": "http",
  "obfs_host": "www.example.com"
}
```

保存并退出编辑器。

## 6. 启动 Shadowsocks-libev 服务

启动 Shadowsocks-libev 服务并将其设置为开机自启：

```bash
$ sudo systemctl start shadowsocks-libev
$ sudo systemctl enable shadowsocks-libev
```

## 7. 检查服务状态

使用以下命令检查 Shadowsocks-libev 服务的状态：

```bash
$ sudo systemctl status shadowsocks-libev
```

如果服务正常运行，您将看到类似以下的输出：

```
● shadowsocks-libev.service - Shadowsocks-libev
   Loaded: loaded (/etc/systemd/system/shadowsocks-libev.service; enabled; vendor preset: enabled)
   Active: active (running) since Mon 2023-09-11 10:00:00 UTC; 1min ago
 Main PID: 12345 (ss-server)
    Tasks: 5 (limit: 4915)
   Memory: 12.0M
   CGroup: /system.slice/shadowsocks-libev.service
           └─12345 /usr/local/shadowsocks-libev/bin/ss-server -c /usr/local/shadowsocks-libev/config.json
```

现在，Ubuntu 24.04 上成功安装了 Shadowsocks-libev，并可以使用它进行网络加速了。  

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
