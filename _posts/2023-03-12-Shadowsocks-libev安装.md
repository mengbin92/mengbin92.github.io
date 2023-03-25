---
layout: post
title: Shadowsocks-libev安装
tags: tools
mermaid: false
math: false
---  

本文简单记录下我依照[shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)中的介绍，在CentOS9系统下手动编译安装shadowsocks-libev的过程。  

## 1. 安装环境准备

```shell
yum install epel-release -y
yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libsodium-devel mbedtls-devel git -y
```  

在CentOS9的源中没有*libev-devel*包，这个需要自己手动安装。  

### 1.1

我这里使用的是libev-4.33，可以从[这里](http://dist.schmorp.de/libev/Attic/libev-4.33.tar.gz)下载。  

下载完成之后执行以下步骤即可完成安装：  

```shell
tar -zxvf libev-4.33.tar.gz
cd libev-4.33
./autogen.sh && ./configure && make && make install
```

## 2. 编译安装

### 2.1 下载源码  

shadowsocks-libev源码可以从github上直接下载，执行以下命令即可：  

```shell
git clone https://github.com/shadowsocks/shadowsocks-libev.git
cd shadowsocks-libev
git submodule update --init --recursive
```  

### 2.2 编译安装

安装方法与libev类型，执行以下命令即可：

```shell
./autogen && ./configure && make && make install

ss-server --help

shadowsocks-libev 3.3.5

  maintained by Max Lv <max.c.lv@gmail.com> and Linus Yang <laokongzi@gmail.com>

  usage:

    ss-server

       -s <server_host>           Host name or IP address of your remote server.
       -p <server_port>           Port number of your remote server.
       -l <local_port>            Port number of your local server.
       -k <password>              Password of your remote server.
       -m <encrypt_method>        Encrypt method: rc4-md5, 
                                  aes-128-gcm, aes-192-gcm, aes-256-gcm,
                                  aes-128-cfb, aes-192-cfb, aes-256-cfb,
                                  aes-128-ctr, aes-192-ctr, aes-256-ctr,
                                  camellia-128-cfb, camellia-192-cfb,
                                  camellia-256-cfb, bf-cfb,
                                  chacha20-ietf-poly1305,
                                  xchacha20-ietf-poly1305,
                                  salsa20, chacha20 and chacha20-ietf.
                                  The default cipher is chacha20-ietf-poly1305.

       [-a <user>]                Run as another user.
       [-f <pid_file>]            The file path to store pid.
       [-t <timeout>]             Socket timeout in seconds.
       [-c <config_file>]         The path to config file.
       [-n <number>]              Max number of open files.
       [-i <interface>]           Network interface to bind.
       [-b <local_address>]       Local address to bind.

       [-u]                       Enable UDP relay.
       [-U]                       Enable UDP relay and disable TCP relay.
       [-6]                       Resovle hostname to IPv6 address first.

       [-d <addr>]                Name servers for internal DNS resolver.
       [--reuse-port]             Enable port reuse.
       [--fast-open]              Enable TCP fast open.
                                  with Linux kernel > 3.7.0.
       [--acl <acl_file>]         Path to ACL (Access Control List).
       [--manager-address <addr>] UNIX domain socket address.
       [--mtu <MTU>]              MTU of your network interface.
       [--mptcp]                  Enable Multipath TCP on MPTCP Kernel.
       [--no-delay]               Enable TCP_NODELAY.
       [--key <key_in_base64>]    Key of your remote server.
       [--plugin <name>]          Enable SIP003 plugin. (Experimental)
       [--plugin-opts <options>]  Set SIP003 plugin options. (Experimental)

       [-v]                       Verbose mode.
       [-h, --help]               Print this message.
```

至此，shadowsocks-libev的安装就已经完成了。  

### 2.3 使用  

shadowsocks-libev通过配置文件来执行，以下是配置样例：  

```json
{
    "server":"0.0.0.0",
    "server_port":8388,
    "local_port":1080,
    "password":"you_password",
    "timeout":60,
    "method":"aes-256-gcm"
}
```  

> ss-server -u -c /path/to/your/config.json

通过上述命令就可以启动shadowsocks-libev了。  

## 3. 扩展

### 3.1 多端口使用

ss-server并不支持通过单个配置文件来启动多个端口，可以通过ss-manager来启动多个端口，配置文件示例如下：  

```json
{
    "server":"0.0.0.0",
    "port_password":{
        "port1":"password1",
        "port2":"password2",
        "port3":"password2"
    },
    "timeout":300,
    "method":"aes-256-gcm"
}
```

> ss-manager -u -c /path/to/your/config.json

通过上述命令就可以同时启动多个端口了。  

### 3.2 通过systemctl命令管理shadowsocks-libev 

新建`/etc/systemd/system/ss-manager.service`文件，内容如下：  

```text
[Unit]
Description=Shadowsocks-Libev Server
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ss-manager -c /etc/shadowsocks-libev/config-mgmt.json
[Install]
WantedBy=multi-user.target
```  

之后就可以通过`systemctl enalbe/start/stop/restart/status`来设置ss-manager服务开机启动/启动/关闭/重启/状态查询。  

### 3.3 安装v2ray-plugin  

v2ray-plugin可以提供混淆，提高ss的安全性。  

v2ray-plugin可以从[这里](https://github.com/shadowsocks/v2ray-plugin/releases/tag/v1.3.2)获得，下载完成后将文件放入`/usr/bin`或`/usr/local/bin`目录下，执行`ldconfig`命令即可完成v2ray-plugin安装。  

在配置文件中通过**plugin**来启用v2ray-plugin：  

```json
{
    "server":"0.0.0.0",
    "port_password":{
        "port1":"password1",
        "port2":"password2",
        "port3":"password2"
    },
    "timeout":300,
    "method":"aes-256-gcm",
    "plugin":"v2ray-plugin",
    "plugin_opts":"server"
}
```  

### 3.3 ipv6支持

使用`v2ray-plugin`时，server设置为"0.0.0.0"即可同时支持ipv4和ipv6，详见[issue](https://github.com/shadowsocks/v2ray-plugin/issues/28)。  

可以通过`ipv6_first`来设置是否优先ipv6：  

```json
{
    "server":"0.0.0.0",
    "port_password":{
        "port1":"password1",
        "port2":"password2",
        "port3":"password2"
    },
    "timeout":300,
    "method":"aes-256-gcm",
    "ipv6_first":true,
    "plugin":"v2ray-plugin",
    "plugin_opts":"server"
}
```

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: mengbin92  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
