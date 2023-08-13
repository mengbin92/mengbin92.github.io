---
layout: post
title: Fabric区块链浏览器（1）
tags: [go, fabric]
mermaid: false
math: false
---  

本文是区块链浏览器系列的第三篇，本文介绍区块链浏览器的主体部分，即区块数据的解析。  


这一版本的[区块链浏览器](https://github.com/mengbin92/browser/tree/gin)是基于[gin](https://github.com/gin-gonic/gin)实现的，只提供三种接口：  

- **/block/upload**：**POST**，上传Protobuf格式的区块数据文件
- **/block/parse/:msgType**：**GET**，根据`msgType`来解析上传的区块文件
- **/block/update/:channel**：**POST**，根据上传的json格式配置文件生成Protobuf格式的文件

结构如下：  

```shell
$ tree
.
├── LICENSE
├── README.md
├── cmd                             # 解析区块的示例
│   ├── main.go
│   ├── mychannel_config.block
│   └── mychannel_newest.block
├── conf                            # 浏览器的配置
│   ├── conf.pb.go
│   └── conf.proto
├── configs                         # 配置文件存放路径
│   └── config.yaml
├── go.mod
├── go.sum
├── log                             # 日志库
│   └── logger.go   
├── main.go                         # 程序入口
├── service                         # 项目实现代码
│   ├── handler.go
│   ├── service.go
│   └── utils.go
└── utils                           # 一些工具函数
    ├── protoutils.go
    └── utils.go

7 directories, 17 files
```  

## 详细介绍  

### 配置介绍  

当前版本配置比较简单，使用Protobuf进行定义：  

```protobuf
syntax = "proto3";

package browser.conf;

option go_package = "./;conf";

import "google/protobuf/duration.proto";

message Bootstrap {
  Server server = 1;
  Log log = 2;
}

message Server {
  message HTTP {
    string network = 1;
    string addr = 2;
    google.protobuf.Duration timeout = 3;
  }
  message TLS {
    // 是否启用tls
    bool enbale = 1;
    // 证书路径
    string cert = 2;
    // 对应私钥路径
    string key = 3;
  }
  HTTP http = 1;
  TLS tls = 2;
}

message Log {
  // 日志级别设置
  // 支持debug(-1)、info(0)、warn(1)、error(2)、dpanic(3)、panic(4)、fatal(5)
  int32 level = 1;
  // 日志输出格式，支持json or console
  string format = 2;
}
```  

### 日志  

`log`基于`zap`进行简单封装使用：  

```go
func DefaultLogger(logConf *conf.Log) *zap.Logger {
	var coreArr []zapcore.Core

	//获取编码器
	encoderConfig := zap.NewProductionEncoderConfig()
	encoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder        //指定时间格式
	encoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder //按级别显示不同颜色
	encoderConfig.EncodeCaller = zapcore.ShortCallerEncoder      //显示完整文件路径

	var encoder zapcore.Encoder //NewJSONEncoder()输出json格式，NewConsoleEncoder()输出普通文本格式
	if logConf.Format == "console" {
		encoder = zapcore.NewConsoleEncoder(encoderConfig)
	} else {
		encoder = zapcore.NewJSONEncoder(encoderConfig)
	}

	//日志级别
	highPriority := zap.LevelEnablerFunc(func(lev zapcore.Level) bool { //error级别
		return lev >= zap.ErrorLevel
	})
	lowPriority := zap.LevelEnablerFunc(func(lev zapcore.Level) bool { //info和debug级别,debug级别是最低的
		return lev < zap.ErrorLevel && lev >= zap.DebugLevel
	})

	infoCore := zapcore.NewCore(encoder, zapcore.NewMultiWriteSyncer(zapcore.AddSync(os.Stdout)), lowPriority)   //第三个及之后的参数为写入文件的日志级别,ErrorLevel模式只记录error级别的日志
	errorCore := zapcore.NewCore(encoder, zapcore.NewMultiWriteSyncer(zapcore.AddSync(os.Stdout)), highPriority) //第三个及之后的参数为写入文件的日志级别,ErrorLevel模式只记录error级别的日志

	coreArr = append(coreArr, infoCore)
	coreArr = append(coreArr, errorCore)

	return setLogLevel(zap.New(zapcore.NewTee(coreArr...), zap.AddCaller()), logConf.GetLevel())
}

func setLogLevel(log *zap.Logger, level int32) *zap.Logger {
	switch level {
	case -1:
		return log.WithOptions(zap.IncreaseLevel(zapcore.DebugLevel))
	case 0:
		return log.WithOptions(zap.IncreaseLevel(zapcore.InfoLevel))
	case 1:
		return log.WithOptions(zap.IncreaseLevel(zapcore.WarnLevel))
	case 3:
		return log.WithOptions(zap.IncreaseLevel(zapcore.DPanicLevel))
	case 4:
		return log.WithOptions(zap.IncreaseLevel(zapcore.PanicLevel))
	case 5:
		return log.WithOptions(zap.IncreaseLevel(zapcore.FatalLevel))
	default:
		return log.WithOptions(zap.IncreaseLevel(zapcore.ErrorLevel))
	}
}
```  

### service  

`service`为本项目的主体，提供区块解析服务。  

`/block/upload`和`/block/parse/:msgType`二者配合使用。  

`/block/upload`完成文件上传后，会存储在`./pb`目录下，通过**session**记录上传的Protobuf格式区块文件与用户交互：  

```go
type pbCache struct {
	// 缓存session
	cache sync.Map
	// 定时器，超时后自动删除对应的pb文件
	time  *time.Ticker
}

type pbFile struct {
	// pb文件名称，文件存储在服务端的名称
	Name    string
	// 文件过期时间，过期后自动删除
	Expired int64
}
```

调用`/block/parse/:msgType`时，服务端通过`loadSession`从**session**中获取，每次调用都会对当前pb文件自动续期：  

```go
func loadSession(ctx *gin.Context) (string, error) {
	// get filename from session
	session := sessions.Default(ctx)
	buf := session.Get("filename")
	if buf == nil {
		srvLogger.Error("no filename in session")
		return "", errors.New("no filename in session")
	}

	// 更新pbFile过期时间
	pf := &pbFile{}
	pf.Unmarshal([]byte(buf.(string)))
	pf.renewal()

	data, _ := pf.Marshal()
	session.Set("filename", string(data))
	session.Save()
	return pf.Name, nil
}
```  

`msgType`支持以下类型：  

- **block**：将上传的pb文件解析为json
- **header**：获取区块header域信息
- **metadata**：获取区块metadata域信息
- **data**：获取区块的data域信息
- **config**：获取配置块信息，如果解析的是数据块，将返回空信息
- **chaincode**：获取智能合约信息
- **actions**、**transaction**：区块中包含的交易信息
- **input**：获取交易信息中的输入信息
- **rwset**：获取交易中包含的读写集信息
- **channel**：获取通道信息
- **endorsements**：获取交易的背书信息
- **creator**：获取交易发起者信息

调用`/block/update/:channel`时，可以将json格式的配置块信息转换为Protobuf格式。  

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
