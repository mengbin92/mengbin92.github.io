---
layout: post
title: protojson简介
tags: [go, protobuf]
mermaid: false
math: false
---  

`google.golang.org/protobuf/encoding/protojson` 是 Go 语言中的一个库，用于处理 Protocol Buffers（protobuf）和 JSON 之间的转换，遵循[https://protobuf.dev/programming-guides/proto3#json](https://protobuf.dev/programming-guides/proto3#json)实现。  

以下是该库的一些主要功能：

- 将 protobuf 消息转换为 JSON 格式：这是通过 `Marshal` 或 `MarshalOptions.Marshal` 函数实现的。这些函数接收一个 protobuf 消息并返回一个 JSON 格式的字符串。
- 将 JSON 格式的数据转换为 protobuf 消息：这是通过 `Unmarshal` 或 `UnmarshalOptions.Unmarshal` 函数实现的。这些函数接收一个 JSON 格式的字符串和一个 protobuf 消息的指针，然后将 JSON 数据解析并填充到 protobuf 消息中。
- 自定义 JSON 编码和解码的行为：`MarshalOptions` 和 `UnmarshalOptions` 结构体提供了一些选项，可以用来自定义 JSON 编码和解码的行为。例如，可以通过 `EmitUnpopulated` 选项控制是否输出未设置的字段，通过 `UseProtoNames` 选项控制是否使用 protobuf 字段的原始名称作为 JSON 字段的键。
- 支持 Well-Known Types：该库提供了对 protobuf 的 Well-Known Types 的特殊处理，例如 `Timestamp`、`Duration`、`Struct`、`Value` 等。

接下来我们以下面的 `.proto` 为例，介绍下如何使用 `google.golang.org/protobuf/encoding/protojson` ，并简单对比下 `proto` 、 `protojson` 和 `encoding/json` 三者之间的性能对比:  

```protobuf
syntax = "proto3";

package example.pb;

option go_package = "./;pb";

import "google/protobuf/struct.proto";

message Base {
    string tx_hash = 1;
    int64 timestamp = 2;
    google.protobuf.Struct extra = 3;
    uint64 block_number = 4;
    int32 category = 5;
  }

message CertGen {
    string id = 1;
    string issuer = 2;
    string name = 3;
    string number = 4;
    string seal_name = 5;
    string seal_number = 6;
    string sign_hash = 7;
    string date = 8;
    Base base = 9;
}
```

```go
func genData() *pb.CertGen {
	data := map[string]interface{}{
		"name":  "1234",
		"age":   12,
		"score": 1345.452434,
	}

	extra, _ := structpb.NewStruct(data)
	base := &pb.Base{
		TxHash:      "1234556",
		Timestamp:   1234566,
		Extra:       extra,
		BlockNumber: 123456,
		Category:    4,
	}

	return &pb.CertGen{
		Id:         uuid.NewString(),
		Issuer:     uuid.NewString(),
		Name:       uuid.NewString(),
		Number:     uuid.NewString(),
		SealName:   uuid.NewString(),
		SealNumber: uuid.NewString(),
		SignHash:   uuid.NewString(),
		Date:       time.Now().Format(time.DateTime),
		Base:       base,
	}
}

func BenchmarkProto(b *testing.B) {
	gen := genData()

	for i := 0; i < b.N; i++ {
		proto.Marshal(gen)
	}
}

func BenchmarkProtoJson(b *testing.B) {
	gen := genData()

	for i := 0; i < b.N; i++ {
		protojson.Marshal(gen)
	}
}

func BenchmarkStdJson(b *testing.B) {
	gen := genData()
	for i := 0; i < b.N; i++ {
		json.Marshal(gen)
	}
}
```  

结果如下：  

```shell
$ go test -bench=.
goos: linux
goarch: amd64
pkg: example
cpu: 12th Gen Intel(R) Core(TM) i7-1260P
BenchmarkProto-16                 817065              1412 ns/op
BenchmarkProtoJson-16             218583              5372 ns/op
BenchmarkStdJson-16               343822              3216 ns/op
PASS
ok      example       3.554s
```  

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
