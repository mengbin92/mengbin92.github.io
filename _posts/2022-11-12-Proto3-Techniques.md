---
layout: post
title: Proto3 Techniques
tags: protobuf
mermaid: false
---  

本文描述处理Protocol Buffer常用到的一些设计模式。你也可以给[Protocol Buffers discussion group](http://groups.google.com/group/protobuf)发送设计或使用问题。  

## 流式多条消息  

如果你想将多个消息写入到单个文件或流中，你需要记录一条消息的结束及另一个的开始。Protocol Buffer wire格式并不会自定义界限，所以protocol buffer解析器无法自行确定消息的结束位置。解决此问题最简单的方法就是在你写入消息之前写入每个消息的大小。当你重新读取消息时，你先读取到大小，然后将之后的字节读入到单个缓冲区，之后再从该缓冲区解析。（如果你希望避免拷贝字节到单个缓冲区，请查看`CodeInputStream`类（在C++和Java中），它保存着读取一定数量字节的限制。）  

## 大数据集  

Protocol Buffer并不是设计用来处理大数据。根据一般的使用经验，如果你要处理的消息大于1M，那么可能需要考虑换种方式。  

也就是说，Protocol Buffer*大数据集中的单个消息*。通常，大数据集也只是一个小碎片的集合，每个小碎片可能是一段结构化的数据片段。尽管Protocol Buffer不能一次性地处理完整个数据集，但使用Protocol Buffer来编码每个碎片也极大地简化了你的问题：现在你要处理的是一组字节字符串，而不是一组结构。  

Protocol Buffer并不包含对大数据集的任何内置支持，因为不同的场景需要不同的解决方案。有时候一个简单的记录列表就足够了，但其它时间你可能更想要一个类似数据库的东西。每个解决方案都应该作为一个独立的库来开发，这样只有需要它的人才需要为其支付代价。  

## 自描述消息  

Protocol Buffer并不包含其自身类型的说明。因此，如果只提供原始消息，而没有相应的`.proto`文件定义其类型，则很难提取任何有用的数据。  

但是，请注意，`.proto`文件的内容本身可以用Protocol Buffer表示。源码包中的文件`src/google/protobuf/descriptor.proto`定义了相关的消息类型。使用`--descriptor_set_out`选项，`protoc`可以输出一个`FileDescriptorSet`来表示一组`.proto`文件。这样，你可以像下面那样定义你自己的自描述protocol消息：  

```proto
syntax = "proto3";

import "google/protobuf/any.proto";
import "google/protobuf/descriptor.proto";

message SelfDescribingMessage {
  // Set of FileDescriptorProtos which describe the type and its dependencies.
  google.protobuf.FileDescriptorSet descriptor_set = 1;

  // The message and its type, encoded as an Any message.
  google.protobuf.Any message = 2;
}
```  

通过使用类似`DynamicMessage`（C++和Java中可用），稍后你可以实现操作`SelfDescribingMessage`的工具。  

总而言之，这个功能没有包含在Protocol Buffer库中的原因是Google从未使用过它。  

该技术需要使用描述符支持动态消息。所以，在使用自描述消息前，请检查你的平台是否支持此功能。  

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: mengbin92  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
