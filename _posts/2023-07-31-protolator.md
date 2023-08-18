---
layout: post
title: protolator简介
tags: go
mermaid: false
math: false
---  

`github.com/hyperledger/fabric-config/protolator` 是 Hyperledger Fabric 中的一个 Go 包，用于将 Protocol Buffers（ProtoBuf）消息和 JSON 格式之间进行转换。它提供了一种方便的方式来将 Fabric 配置文件（以 ProtoBuf 格式表示）与 JSON 配置文件之间进行相互转换。这对于 Fabric 的配置管理和部署非常有用，使得用户可以轻松地在不同的配置格式之间进行切换。

## 功能和用法

`protolator` 提供了一组功能，用于在 ProtoBuf 格式和 JSON 格式之间进行转换：

### `DeepMarshalJSON`

`func DeepMarshalJSON(m proto.Message) ([]byte, error)`

- 该方法用于将给定的 ProtoBuf 消息 `m` 转换为 JSON 格式的字节流。
- 它递归地将 ProtoBuf 的消息及其子消息转换为 JSON 格式，返回表示 JSON 格式数据的字节流。
- 注意：转换后的 JSON 字节流将具有缩进格式，易于阅读。

### `DeepUnmarshalJSON`

`func DeepUnmarshalJSON(data []byte, m proto.Message) error`

- 该方法用于将给定的 JSON 格式字节流 `data` 转换为指定的 ProtoBuf 消息 `m`。
- 它递归地将 JSON 格式的数据解析并填充到 `m` 中，返回 nil 或错误。
- 注意：JSON 字节流必须是有效的，并且与目标消息 `m` 的结构相匹配。

### `Nested`

`type Nested struct{...}`

- `Nested` 类型是用于 ProtoBuf 和 JSON 之间可嵌套转换的通用转换器。
- 它提供了 `Marshal` 和 `Unmarshal` 方法，用于将 ProtoBuf 格式的消息转换为可嵌套的 JSON 格式，以及将可嵌套的 JSON 格式转换为 ProtoBuf 格式。

## 使用示例

```go
package main

import (
	"fmt"
	"github.com/golang/protobuf/proto"
	"github.com/hyperledger/fabric-config/protolator"
	"encoding/json"
)

// 使用 proto 文件定义的 message 结构
// 假设定义了 proto 文件如下：
// message MyData {
//     string name = 1;
//     int32 age = 2;
// }
type MyData struct {
	Name string `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	Age  int32  `protobuf:"varint,2,opt,name=age" json:"age,omitempty"`
}

func main() {
	// 创建一个 MyData 实例
	data := &MyData{
		Name: "John",
		Age:  30,
	}

	// 使用 DeepMarshalJSON 将 ProtoBuf 数据转换为 JSON 字节流
	jsonData, err := protolator.DeepMarshalJSON(data)
	if err != nil {
		fmt.Println("Error marshaling to JSON:", err)
		return
	}

	// 使用 DeepUnmarshalJSON 将 JSON 字节流转换为 ProtoBuf 数据
	newData := &MyData{}
	err = protolator.DeepUnmarshalJSON(jsonData, newData)
	if err != nil {
		fmt.Println("Error unmarshaling from JSON:", err)
		return
	}

	// 输出结果
	fmt.Println("Original data:", data)
	fmt.Println("JSON data:", string(jsonData))
	fmt.Println("Unmarshaled data:", newData)
}
```

在上述示例中，我们使用 `github.com/hyperledger/fabric-config/protolator` 的 `DeepMarshalJSON` 方法将 `MyData` 结构体从 ProtoBuf 格式转换为 JSON 格式的字节流，并使用 `DeepUnmarshalJSON` 方法将 JSON 字节流再转换回 ProtoBuf 格式的数据。输出结果显示了原始数据、转换后的 JSON 数据以及再次转换回来后的数据。

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
