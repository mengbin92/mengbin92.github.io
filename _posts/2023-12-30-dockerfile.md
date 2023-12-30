---
layout: post
title: Dockerfile 简介
tags: docker
mermaid: false
math: false
---  

Dockerfile 是 Docker 容器构建的关键蓝图。它是一个文本文件，包含了一系列命令和指令，用于自动化构建 Docker 镜像。通过 Dockerfile，你可以定义容器的环境、依赖关系、配置等方面，确保容器能够一致、可重复地构建。  

## 常用 Dockerfile 指令

Dockerfile 通常以基础镜像开始，基础镜像是构建的起点。基础镜像可能是官方提供的镜像，也可以是自定义的基础镜像。接下来，通过一系列的指令来定义镜像的构建过程。  

Dockerfile 是一个文本文件，包含了一系列的指令和参数，用于描述如何构建 Docker 镜像。以下是 Dockerfile 的基础结构和一些常用指令的详细介绍：

### 1. FROM

`FROM` 指令指定了基础镜像，即构建当前镜像的起点。可以使用官方提供的镜像，也可以使用其他已经存在的镜像。

```Dockerfile
FROM ubuntu:20.04
```

### 2. LABEL

`LABEL` 指令用于为镜像添加元数据。这些元数据可以包括作者、版本、描述等信息。

```Dockerfile
LABEL maintainer="your_name" \
      version="1.0" \
      description="This is a custom Docker image."
```

### 3. WORKDIR

`WORKDIR` 指令用于设置工作目录，即后续命令的执行路径。如果目录不存在，会被创建。

```Dockerfile
WORKDIR /app
```

### 4. COPY

`COPY` 指令将文件从构建上下文（通常是 Dockerfile 所在的目录）复制到镜像中指定的路径。

```Dockerfile
COPY . /app
```

### 5. ADD

`ADD` 指令类似于 `COPY`，但还支持从 URL 复制文件以及解压缩 tar 归档。

```Dockerfile
ADD https://example.com/file.tar.gz /app/
```

### 6. RUN

`RUN` 指令用于在镜像中执行命令。每个 `RUN` 指令都会在上一个指令的基础上创建一个新的镜像层。

```Dockerfile
RUN apt-get update && \
    apt-get install -y python3
```

### 7. CMD

`CMD` 指令用于设置容器启动时执行的默认命令。如果在 Dockerfile 中有多个 `CMD`，只有最后一个生效。

```Dockerfile
CMD ["python3", "app.py"]
```

### 8. EXPOSE

`EXPOSE` 指令声明容器将在运行时使用的端口，但并不实际映射或打开这些端口。

```Dockerfile
EXPOSE 80
```

### 9. ENV

`ENV` 指令用于设置环境变量。

```Dockerfile
ENV APP_HOME /app
WORKDIR $APP_HOME
```

### 10. ARG

`ARG` 指令用于定义构建时的参数，可以在构建时使用 `--build-arg` 传递。

```Dockerfile
ARG user
ENV USER=$user
```

### 11. VOLUME

`VOLUME` 指令用于使容器中的目录可供挂载。

```Dockerfile
VOLUME /data
```

### 12. USER

`USER` 指令用于指定运行容器时使用的用户名或 UID。

```Dockerfile
USER appuser
```

这些指令构成了 Dockerfile 的基础结构。通过合理组织和使用这些指令，你可以定义一个清晰、可维护的 Dockerfile，从而创建一个符合预期的 Docker 镜像。  

## 构建和运行 Docker 容器

以下面的 `Dockerfile` 为例，简单介绍下如何通过 Dockerfile 来构建和运行 Docker 容器。

```Dockerfile
# 使用基础镜像
FROM ubuntu:20.04

# 作者信息
LABEL maintainer="your_name"

# 定义工作目录
WORKDIR /app

# 复制本地文件到容器
COPY . .

# 安装依赖
RUN apt-get update && \
    apt-get install -y python3

# 暴露端口
EXPOSE 80

# 容器启动时执行的命令
CMD ["python3", "app.py"]
```

### 1. 构建 Docker 镜像

在包含 Dockerfile 的目录下，使用 `docker build` 命令构建 Docker 镜像。`.` 表示当前目录，你也可以指定其他目录。

```bash
docker build -t your_image_name .
```

这会根据 Dockerfile 中的指令逐步构建镜像。确保网络通畅，因为可能需要从互联网下载基础镜像和依赖。

### 2. 运行 Docker 容器

使用 `docker run` 命令运行构建好的 Docker 镜像，并指定端口映射等选项。

```bash
docker run -p 8080:80 your_image_name
```

这会启动一个新的容器，将本地机器的端口 8080 映射到容器内的端口 80。你可以根据需要更改端口映射规则。

### 3. 查看运行中的容器

使用 `docker ps` 命令可以查看当前正在运行的容器。

```bash
docker ps
```

如果需要查看所有容器（包括已停止的），可以使用 `docker ps -a`。

### 4. 访问容器

打开浏览器或使用其他工具，访问 `http://localhost:8080`（或你所映射的端口）即可查看容器中运行的应用。

### 5. 容器内部操作

如果你需要进入容器内部执行一些操作，可以使用 `docker exec` 命令。

```bash
docker exec -it container_id /bin/bash
```

上述命令将打开一个交互式的终端会话，你可以在其中执行命令。

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
