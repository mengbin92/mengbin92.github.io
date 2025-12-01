---
layout: post
title: 【跟着AI学】从零开始构建 gRPC-Web 完整示例：Go 服务端 + TypeScript 客户端 + Envoy 代理
tags: AI
mermaid: false
math: false
---  

## 前言

本文记录了一个完整的 gRPC-Web 项目的实现过程，包括使用 Go 实现 gRPC 服务端（包含流式服务）、使用 TypeScript 通过 gRPC-Web 调用服务，以及通过 Envoy 代理的完整配置。在整个实现过程中，我们遇到了多个技术挑战并逐一解决，希望这篇文章能帮助其他开发者避免类似的坑。

## 项目架构

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Browser    │─────▶│   Envoy     │─────▶│  gRPC       │
│ (TypeScript)│      │  (Proxy)    │      │  Server     │
│             │◀────│  :8080      │◀────│  (Go)       │
└─────────────┘      └─────────────┘      └─────────────┘
```

## 第一步：定义 Protocol Buffers

首先，我们需要定义服务接口。创建 `proto/example.proto`：

```protobuf
syntax = "proto3";

package example;

option go_package = "github.com/example/proto";

service ExampleService {
  // 普通RPC调用
  rpc SayHello(HelloRequest) returns (HelloResponse);
  
  // 服务端流式RPC
  rpc StreamMessages(StreamRequest) returns (stream StreamResponse);
}

message HelloRequest {
  string name = 1;
}

message HelloResponse {
  string message = 1;
}

message StreamRequest {
  string message = 1;
  int32 count = 2;
}

message StreamResponse {
  string message = 1;
  int32 index = 2;
}
```

## 第二步：实现 Go gRPC 服务端

### 2.1 项目初始化

创建 `go.mod`：

```go
module github.com/example

go 1.25.4

require (
	google.golang.org/grpc v1.77.0
	google.golang.org/protobuf v1.36.10
)

require (
	golang.org/x/net v0.46.1-0.20251013234738-63d1a5100f82 // indirect
	golang.org/x/sys v0.37.0 // indirect
	golang.org/x/text v0.30.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20251022142026-3a174f9686a8 // indirect
)
```

### 2.2 生成 Go 代码

```bash
protoc --go_out=. --go_opt=paths=source_relative \
    --go-grpc_out=. --go-grpc_opt=paths=source_relative \
    proto/example.proto
```

### 2.3 实现服务端

创建 `server/main.go`：

```go
package main

import (
	"context"
	"log"
	"net"

	pb "github.com/example/proto"
	"google.golang.org/grpc"
)

const (
	port = ":50051"
)

// server 实现 ExampleService
type server struct {
	pb.UnimplementedExampleServiceServer
}

// SayHello 实现普通RPC方法
func (s *server) SayHello(ctx context.Context, req *pb.HelloRequest) (*pb.HelloResponse, error) {
	log.Printf("Received: %v", req.GetName())
	return &pb.HelloResponse{
		Message: "Hello " + req.GetName(),
	}, nil
}

// StreamMessages 实现服务端流式RPC方法
func (s *server) StreamMessages(req *pb.StreamRequest, stream pb.ExampleService_StreamMessagesServer) error {
	log.Printf("Stream request: message=%s, count=%d", req.GetMessage(), req.GetCount())

	count := req.GetCount()
	if count <= 0 {
		count = 5 // 默认发送5条消息
	}

	for i := int32(1); i <= count; i++ {
		response := &pb.StreamResponse{
			Message: req.GetMessage(),
			Index:   i,
		}

		if err := stream.Send(response); err != nil {
			log.Printf("Error sending stream: %v", err)
			return err
		}

		log.Printf("Sent stream message %d", i)
	}

	return nil
}

func main() {
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterExampleServiceServer(s, &server{})

	log.Printf("gRPC server listening on %s", port)
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
```

## 第三步：配置 Envoy 代理

### 3.1 初始配置问题

最初我们配置了 CORS filter，但遇到了配置错误：

**错误 1：CORS 配置位置错误**
```
no such field: 'cors'
```

**解决方案**：CORS 配置应该在 `virtual_hosts` 级别，而不是 `HttpConnectionManager` 级别。

**错误 2：Filter 顺序问题**
```
Didn't find a registered implementation for 'envoy.filters.http.grpc_web'
```

**解决方案**：所有 HTTP filters 都需要 `typed_config`，并且顺序很重要。

### 3.2 最终 Envoy 配置

创建 `envoy.yaml`：

```yaml
static_resources:
  listeners:
    - name: listener_0
      address:
        socket_address:
          protocol: TCP
          address: 0.0.0.0
          port_value: 8080
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: grpc_json
                codec_type: AUTO
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: local_service
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: grpc_service
                            timeout: 60s
                            max_stream_duration:
                              grpc_timeout_header_max: 60s
                      cors:
                        allow_origin_string_match:
                          - prefix: "*"
                        allow_methods: "GET, PUT, DELETE, POST, OPTIONS"
                        allow_headers: "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout"
                        max_age: "1728000"
                        expose_headers: "grpc-status,grpc-message"
                http_filters:
                  - name: envoy.filters.http.grpc_web
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
                  - name: envoy.filters.http.cors
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
                upgrade_configs:
                  - upgrade_type: websocket

  clusters:
    - name: grpc_service
      connect_timeout: 10s
      type: LOGICAL_DNS
      typed_extension_protocol_options:
        envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
          explicit_http_config:
            http2_protocol_options: {}
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: grpc_service
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: 50051

admin:
  address:
    socket_address:
      protocol: TCP
      address: 127.0.0.1
      port_value: 9901
```

**关键点**：
- CORS 配置在 `virtual_hosts` 级别
- HTTP filters 需要正确的 `typed_config`
- Filter 顺序：grpc_web → cors → router
- HTTP/2 配置使用新的 `typed_extension_protocol_options` 格式

## 第四步：实现 TypeScript 客户端

### 4.1 项目初始化

创建 `client/package.json`：

```json
{
  "name": "grpc-web-client",
  "version": "1.0.0",
  "description": "gRPC-Web client for ExampleService",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "google-protobuf": "^3.21.0",
    "grpc-web": "^1.5.0"
  },
  "devDependencies": {
    "@rollup/plugin-commonjs": "^29.0.0",
    "@rollup/plugin-node-resolve": "^16.0.3",
    "@types/google-protobuf": "^3.15.5",
    "protoc-gen-ts": "^0.8.6",
    "typescript": "^5.6.0",
    "vite": "^5.4.11"
  }
}
```

### 4.2 生成 TypeScript 代码

使用 `protoc-gen-grpc-web` 生成客户端代码：

```bash
# 生成 JavaScript 消息定义
protoc --js_out=import_style=commonjs,binary:./client/src \
    --proto_path=proto proto/example.proto

# 生成 gRPC-Web 服务代码
protoc --plugin=protoc-gen-grpc-web=/opt/homebrew/bin/protoc-gen-grpc-web \
    --grpc-web_out=import_style=commonjs+dts,mode=grpcwebtext:./client/src \
    --proto_path=proto proto/example.proto
```

### 4.3 遇到的重大问题及解决方案

#### 问题 1：CommonJS vs ES Modules

**错误**：
```
require is not defined
```

**原因**：生成的代码使用 CommonJS (`require`/`module.exports`)，但浏览器环境需要 ES 模块。

**解决方案**：创建后处理脚本 `client/fix-proto.js`，将 CommonJS 转换为 ES 模块：

```javascript
#!/usr/bin/env node
// 后处理脚本：将 CommonJS require 替换为 ES 模块导入

const fs = require('fs');
const path = require('path');

const protoDir = path.join(__dirname, 'src/proto');
const grpcWebFile = path.join(protoDir, 'example_grpc_web_pb.js');
const protoFile = path.join(protoDir, 'example_pb.js');

// 修复 grpc-web 文件
if (fs.existsSync(grpcWebFile)) {
  let content = fs.readFileSync(grpcWebFile, 'utf8');
  
  // 替换 require 为 import
  content = content.replace(
    /const grpc = {};\s*grpc\.web = require\('grpc-web'\);/,
    "import * as grpcWebLib from 'grpc-web';\nconst grpc = {};\ngrpc.web = grpcWebLib;"
  );
  
  content = content.replace(
    /const proto = {};\s*proto\.example = require\('\.\/example_pb\.js'\);/,
    "import * as protoLib from './example_pb.js';\nconst proto = {};\nconst importedProto = protoLib.default || protoLib;\nproto.example = {};\nObject.keys(importedProto).forEach(key => { proto.example[key] = importedProto[key]; });"
  );
  
  // 替换 module.exports 为 export
  content = content.replace(
    /module\.exports = proto\.example;/,
    'export default proto.example;'
  );
  
  fs.writeFileSync(grpcWebFile, content);
  console.log('Fixed example_grpc_web_pb.js');
}

// 修复 proto 文件
if (fs.existsSync(protoFile)) {
  let content = fs.readFileSync(protoFile, 'utf8');
  
  // 替换 require 为 import
  content = content.replace(
    /var jspb = require\('google-protobuf'\);/,
    "import * as jspb from 'google-protobuf';"
  );
  
  // 替换 exports 为 export
  content = content.replace(
    /goog\.object\.extend\(exports, proto\.example\);/,
    'export default proto.example;'
  );
  
  // 替换 readStringRequireUtf8 为 readString（兼容 google-protobuf 3.x）
  content = content.replace(
    /reader\.readStringRequireUtf8\(\)/g,
    'reader.readString()'
  );
  
  fs.writeFileSync(protoFile, content);
  console.log('Fixed example_pb.js');
}

console.log('Proto files fixed!');
```

**关键点**：
- 创建新对象 `proto.example = {}` 而不是直接赋值，避免对象不可扩展的问题
- 使用 `Object.keys().forEach()` 复制属性
- 将 `readStringRequireUtf8` 替换为 `readString` 以兼容 google-protobuf 3.x

#### 问题 2：对象不可扩展错误

**错误**：
```
TypeError: Cannot add property ExampleServiceClient, object is not extensible
```

**原因**：直接赋值 `proto.example = protoLib` 时，如果导入的对象是冻结的，无法添加新属性。

**解决方案**：创建新对象并复制属性（见上面的脚本）。

#### 问题 3：方法不存在错误

**错误**：
```
TypeError: reader.readStringRequireUtf8 is not a function
```

**原因**：
- `protoc` 6.33.1 生成的代码使用 `readStringRequireUtf8()`
- `google-protobuf` 3.21.4 只提供 `readString()` 方法
- 版本不匹配

**解决方案**：
1. 降级 `google-protobuf` 到 3.21.0（与 `grpc-web` 1.5.0 兼容）
2. 在修复脚本中将 `readStringRequireUtf8()` 替换为 `readString()`

#### 问题 4：CORS 预检请求失败

**错误**：
```
Access to XMLHttpRequest at 'http://localhost:8080/...' has been blocked by CORS policy
```

**解决方案**：在 Envoy 配置中正确设置 CORS（见第三步）。

### 4.4 客户端实现

创建 `client/src/main.ts`：

```typescript
// 显示加载状态
function showLoading() {
  const app = document.getElementById('app');
  if (app) {
    app.innerHTML = `
      <div style="max-width: 800px; margin: 50px auto; padding: 20px; font-family: Arial, sans-serif; text-align: center;">
        <h1>gRPC-Web 客户端</h1>
        <p>正在加载...</p>
      </div>
    `;
  }
}

// 异步初始化函数
async function init() {
  try {
    console.log('开始加载 gRPC-Web 模块...');
    showLoading();
    
    // 使用动态导入来加载 ES 模块
    const grpcWebModule = await import('./proto/example_grpc_web_pb.js');
    const protoModule = await import('./proto/example_pb.js');

    console.log('模块加载成功:', { grpcWebModule, protoModule });

    // 从模块中提取需要的类（ES 模块使用 default 导出）
    const grpcWebExports = grpcWebModule.default || grpcWebModule;
    const protoExports = protoModule.default || protoModule;
    
    console.log('导出的类:', { 
      grpcWebKeys: Object.keys(grpcWebExports),
      protoKeys: Object.keys(protoExports)
    });
    
    const ExampleServiceClient = grpcWebExports.ExampleServiceClient;
    const ExampleServicePromiseClient = grpcWebExports.ExampleServicePromiseClient;
    const HelloRequest = protoExports.HelloRequest;
    const StreamRequest = protoExports.StreamRequest;

    if (!ExampleServiceClient || !ExampleServicePromiseClient || !HelloRequest || !StreamRequest) {
      throw new Error('无法找到所需的类: ' + JSON.stringify({
        ExampleServiceClient: !!ExampleServiceClient,
        ExampleServicePromiseClient: !!ExampleServicePromiseClient,
        HelloRequest: !!HelloRequest,
        StreamRequest: !!StreamRequest
      }));
    }

    // 创建客户端，连接到envoy代理
    // Promise 客户端用于普通 RPC
    const promiseClient = new ExampleServicePromiseClient('http://localhost:8080', null, null);
    // 普通客户端用于流式 RPC
    const streamClient = new ExampleServiceClient('http://localhost:8080', null, null);

    // 测试普通RPC调用
    async function testSayHello() {
      const request = new HelloRequest();
      request.setName('World');
      
      try {
        console.log('发送请求:', request.toObject());
        const response = await promiseClient.sayHello(request, {});
        console.log('SayHello Response:', response);
        console.log('Response type:', typeof response);
        console.log('Response methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(response)));
        console.log('Response message:', response.getMessage());
        document.getElementById('hello-result')!.textContent = response.getMessage();
      } catch (error: any) {
        console.error('SayHello Error:', error);
        console.error('Error details:', {
          message: error.message,
          code: error.code,
          metadata: error.metadata,
          stack: error.stack
        });
        document.getElementById('hello-result')!.textContent = 'Error: ' + (error.message || error);
      }
    }

    // 测试流式RPC调用
    function testStreamMessages() {
      const request = new StreamRequest();
      request.setMessage('Hello from stream');
      request.setCount(5);
      
      const stream = streamClient.streamMessages(request, {});
      const resultDiv = document.getElementById('stream-result')!;
      resultDiv.innerHTML = '<p>开始接收流式消息...</p>';
      
      stream.on('data', (response: any) => {
        console.log('Stream Response:', response.getMessage(), 'Index:', response.getIndex());
        const p = document.createElement('p');
        p.textContent = `[${response.getIndex()}] ${response.getMessage()}`;
        resultDiv.appendChild(p);
      });
      
      stream.on('error', (error: any) => {
        console.error('Stream Error:', error);
        const p = document.createElement('p');
        p.style.color = 'red';
        p.textContent = 'Error: ' + (error.message || error);
        resultDiv.appendChild(p);
      });
      
      stream.on('end', () => {
        console.log('Stream ended');
        const p = document.createElement('p');
        p.style.color = 'green';
        p.textContent = '流式传输完成';
        resultDiv.appendChild(p);
      });
    }

    // 创建UI
    function createUI() {
      const app = document.getElementById('app')!;
      app.innerHTML = `
        <div style="max-width: 800px; margin: 50px auto; padding: 20px; font-family: Arial, sans-serif;">
          <h1>gRPC-Web 客户端示例</h1>
          
          <div style="margin: 30px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px;">
            <h2>普通RPC调用</h2>
            <button id="hello-btn" style="padding: 10px 20px; font-size: 16px; cursor: pointer;">
              调用 SayHello
            </button>
            <div id="hello-result" style="margin-top: 10px; padding: 10px; background: #f5f5f5; border-radius: 3px;">
              等待调用...
            </div>
          </div>
          
          <div style="margin: 30px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px;">
            <h2>流式RPC调用</h2>
            <button id="stream-btn" style="padding: 10px 20px; font-size: 16px; cursor: pointer;">
              调用 StreamMessages
            </button>
            <div id="stream-result" style="margin-top: 10px; padding: 10px; background: #f5f5f5; border-radius: 3px; max-height: 300px; overflow-y: auto;">
              等待调用...
            </div>
          </div>
        </div>
      `;
      
      document.getElementById('hello-btn')!.addEventListener('click', testSayHello);
      document.getElementById('stream-btn')!.addEventListener('click', testStreamMessages);
    }

    // 初始化UI
    createUI();
    console.log('初始化完成！');
  } catch (error: any) {
    console.error('初始化错误:', error);
    const errorMessage = error?.message || error?.toString() || '未知错误';
    const app = document.getElementById('app');
    if (app) {
      app.innerHTML = `
        <div style="max-width: 800px; margin: 50px auto; padding: 20px; font-family: Arial, sans-serif;">
          <h1 style="color: red;">初始化失败</h1>
          <p><strong>错误:</strong> ${errorMessage}</p>
          <p>请检查浏览器控制台获取更多信息。</p>
          <pre style="background: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto;">${error?.stack || ''}</pre>
        </div>
      `;
    } else {
      document.body.innerHTML = `
        <div style="max-width: 800px; margin: 50px auto; padding: 20px; font-family: Arial, sans-serif;">
          <h1 style="color: red;">严重错误</h1>
          <p>无法找到 app 元素</p>
          <p><strong>错误:</strong> ${errorMessage}</p>
        </div>
      `;
    }
  }
}

// 立即显示加载状态
showLoading();

// 确保 DOM 加载完成后再初始化
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
```

## 第五步：构建和运行

### 5.1 Makefile

创建 `Makefile` 简化操作：

```makefile
# 生成Go代码
proto-go:
	protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		proto/example.proto

# 生成TypeScript代码
proto-ts:
	mkdir -p client/src/proto
	protoc --js_out=import_style=commonjs,binary:./client/src \
		--proto_path=proto proto/example.proto
	protoc --plugin=protoc-gen-grpc-web=/opt/homebrew/bin/protoc-gen-grpc-web \
		--grpc-web_out=import_style=commonjs+dts,mode=grpcwebtext:./client/src \
		--proto_path=proto proto/example.proto
	mv client/src/example_pb.js client/src/proto/ 2>/dev/null || true
	mv client/src/example_pb.d.ts client/src/proto/ 2>/dev/null || true
	mv client/src/example_grpc_web_pb.js client/src/proto/ 2>/dev/null || true
	mv client/src/example_grpc_web_pb.d.ts client/src/proto/ 2>/dev/null || true
	cd client && node fix-proto.js

# 运行服务器
server:
	go run server/main.go

# 运行客户端
client:
	cd client && npm run dev

# 运行envoy
envoy:
	envoy -c envoy.yaml
```

### 5.2 运行步骤

1. **生成代码**：
   ```bash
   make proto-go
   make proto-ts
   ```

2. **启动服务**（需要3个终端）：
   ```bash
   # 终端1：gRPC 服务
   make server
   
   # 终端2：Envoy 代理
   make envoy
   
   # 终端3：客户端
   make client
   ```

3. **访问**：打开浏览器访问 `http://localhost:3000`

## 关键经验总结

### 1. 版本兼容性至关重要

- `google-protobuf` 3.x 与 `grpc-web` 1.5.0 兼容
- `google-protobuf` 4.x 与 `grpc-web` 1.5.0 **不兼容**
- `protoc` 6.33.1 生成的代码需要适配 `google-protobuf` 3.x

### 2. CommonJS 到 ES 模块的转换

浏览器环境不支持 CommonJS，需要：
- 将 `require()` 转换为 `import`
- 将 `module.exports` 转换为 `export default`
- 处理对象扩展性问题

### 3. Envoy 配置要点

- CORS 配置在 `virtual_hosts` 级别
- HTTP filters 需要 `typed_config`
- Filter 顺序很重要
- HTTP/2 配置使用新格式

### 4. 调试技巧

- 使用浏览器开发者工具查看网络请求
- 检查控制台错误信息
- 验证 proto 文件生成是否正确
- 确认服务端、代理、客户端都在运行

## 项目结构

```
example/
├── proto/
│   └── example.proto          # Protocol Buffers 定义
├── server/
│   └── main.go                # Go gRPC 服务端
├── client/
│   ├── src/
│   │   ├── main.ts            # TypeScript 客户端
│   │   └── proto/             # 生成的 proto 代码
│   ├── fix-proto.js           # 后处理脚本
│   ├── package.json
│   └── vite.config.ts
├── envoy.yaml                 # Envoy 代理配置
├── go.mod
└── Makefile
```

## 总结

通过这个项目，我们成功实现了：
- ✅ Go gRPC 服务端（包含流式服务）
- ✅ TypeScript gRPC-Web 客户端
- ✅ Envoy 代理配置
- ✅ 解决了多个版本兼容性问题
- ✅ 处理了 CommonJS 到 ES 模块的转换
- ✅ 配置了正确的 CORS 策略

希望这篇文章能帮助其他开发者避免类似的坑，顺利实现 gRPC-Web 项目！

## 参考资源

- [gRPC-Web 官方文档](https://github.com/grpc/grpc-web)
- [Envoy 配置参考](https://www.envoyproxy.io/docs/envoy/latest/)
- [Protocol Buffers 文档](https://protobuf.dev/)
- [google-protobuf npm 包](https://www.npmjs.com/package/google-protobuf)

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  
---