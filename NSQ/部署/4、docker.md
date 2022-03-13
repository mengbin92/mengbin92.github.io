# Docker  

本章节介绍如何在[Docker](https://www.docker.com/)容器中部署和使用nsq。  

尽管nsq镜像很小巧，但它仍包含了NSQ集群需要的所有可执行程序。运行docker容器时，可以通过指定程序来执行每个可执行程序。基本格式如下：  

```bash
$ docker run nsqio/nsq /<command>
```  

需要注意的是命令前的`/`（因为所有的命令在根目录下都建立了软链接）。例如：  

```bash
$ docker run nsqio/nsq /nsq_to_file
```  

## 链接  

* [docker](https://www.docker.com/)
* [nsq镜像](https://registry.hub.docker.com/r/nsqio/nsq/)  

## 执行 nsqlookupd  

```bash
$ docker pull nsqio/nsq
$ docker run --name lookupd -p 4160:4160 -p 4161:4161 nsqio/nsq /nsqlookupd
```  

## nsqd 

首先，获取docker主机ip：  

```bash
$ ifconfig | grep addr
```  

然后运行`nsqd`容器：  

```bash
$ docker pull nsqio/nsq
$ docker run --name nsqd -p 4150:4150 -p 4151:4151 \
    nsqio/nsq /nsqd \
    --broadcast-address=<host> \
    --lookupd-tcp-address=<host>:<port>
```  

使用`--lookupd-tcp-address`指定主机IP和之前运行`nsqlookupd`的TCP端口，就像｀dockerIP:4160`。  

如果主机IP为`172.17.42.1`，示例如下：  

```bash
$ docker run --name nsqd -p 4150:4150 -p 4151:4151 \
    nsqio/nsq /nsqd \
    --broadcast-address=172.17.42.1 \
    --lookupd-tcp-address=172.17.42.1:4160
```  

这里使用的是`4160`端口，是启动`nsqlookupd`容器时开放的端口（也是`nsqlookupd`默认使用的端口）。  

如果不想使用默认端口，可以修改`-p`参数：  

```bash
$ docker run --name nsqlookupd -p 5160:4160 -p 5161:4161 nsqio/nsq /nsqlookupd
```  

此时nsqlookupd服务会在docker主机的5160和5161端口提供服务。  

## 启用TLS  

要与容器化的NSQ一起使用TLS，你需要提供证书、私钥以及根证书。docker镜像中挂载在`/etc/ssl/certs/`目录下的卷就是为了实现这一功能的。将包含这些文件的主机目录挂载到该目录下，并在命令行中指定这些文件：  

```bash
$ docker run -p 4150:4150 -p 4151:4151 -p 4152:4152 -v /home/docker/certs:/etc/ssl/certs \
    nsqio/nsq /nsqd \
    --tls-root-ca-file=/etc/ssl/certs/certs.crt \
    --tls-cert=/etc/ssl/certs/cert.pem \
    --tls-key=/etc/ssl/certs/key.pem \
    --tls-required=true \
    --tls-client-auth-policy=require-verify
```  

`/home/docker/certs`下证书文件会被加载到docker容器中以便之后使用。  

## 持久化NSQ数据  

要将`nsqd`的数据保存到主机硬盘上，可以将`/data`卷（你挂载的[仅数据的docker容器](https://docs.docker.com/userguide/dockervolumes/#creating-and-mounting-a-data-volume-container)或本地目录）作为你的数据目录：  

```bash
$ docker run nsqio/nsq /nsqd \
    --data-path=/data
```  

## 使用docker-compose  

要使用`docker-compose`来同时启动`nsqd`、`nsqlookupd`和`nsqadmin`，需要先创建`docker-compose.yaml`文件：  

```yaml
version: '3'

services:
  nsqlookupd:
    image: nsqio/nsq
    command: /nsqlookupd
    ports: 
      - 4160:4160
      - 4161:4161

  nsqd:
    image: nsqio/nsq
    command: /nsqd --lookupd-tcp-address=nsqlookupd:4160
    depends_on: 
      - nsqlookupd
    ports: 
      - 4150:4150
      - 4151:4151
    
  nsqadmin:
    image: nsqio/nsq
    command: /nsqadmin --lookupd-http-address=nsqlookupd:4161
    depends_on: 
      - nsqlookupd
    ports: 
      - 4171:4171
```  

同级目录下执行下面的命令：  

```bash
$ docker-compose up -d 
```  

之后会创建一个私有网络，以及使用这个私有网络的三个容器。主机上的每个容器都会在`docker-compose.yaml`文件中指定的端口上提供服务。  

查看容器的运行状态及端口使用情况，可以：  

```bash
$ docker-compose ps 
```  

查看运行容器的日志，可以：  

```bash
$ docker-compose logs
```  

主机的4161端口被映射到`nsqlookupd`容器的4161，可以使用`curl`：  

```bash
$ curl http://127.0.0.1:4161/ping
```

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。
> Author: MonsterMeng92

---