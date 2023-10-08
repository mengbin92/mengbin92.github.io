---
layout: post
title: Go with Protobuf 
tags: [go, protobuf]
mermaid: false
math: false
---  

原文在[这里](https://protobuf.dev/getting-started/gotutorial/)。  

> 本教程为 Go 程序员提供了使用协议缓冲区的基本介绍。  

本教程使用`proto3`向 Go 程序员介绍如何使用 protobuf。通过创建一个简单的示例应用程序，它向你展示了如何：  

- 在`.proto`中定义消息格式
- 使用protocol buffer编译器
- 使用Go protocol buffer API读写消息

这并不是protocol buffer在Go中使用的完整指南。更多细节，详见[Protocol Buffer Language Guide](https://protobuf.dev/programming-guides/proto3)、[Go API Reference](https://pkg.go.dev/google.golang.org/protobuf/proto)、[Go Generated Code Guide](https://protobuf.dev/reference/go/go-generated)和[Encoding Reference](https://protobuf.dev/programming-guides/encoding)。  

## 为什么使用Protocol Buffer

我们要使用的例子是一个非常简单的“通讯录”应用程序，它可以从文件中读写联系人的信息。通讯录中每个人都有一个姓名、ID、邮箱和练习电话。  

你如何序列化并取回这样结构化的数据呢？下面有几条建议：  

- 原始内存中数据结构可以发送/保存为二进制。这是一种随时间推移而变得脆弱的方法，因为接收/读写的代码必须编译成相同的内存布局，endianness等。另外，文件已原始格式积累数据和在网络中到处传输副本，因此扩展这种格式十分困难。
- 你可以编写已临时的方法来讲数据元素编码到单个字符串中 --- 例如用“12:3:-23:67”来编码4个int。这是一种简单而灵活的方法，尽管它确实需要编写一次性的编码和解析代码，并且解析会增加少量的运行时成本。这对于编码非常简单的数据最有效。
- 序列化为XML。这种方法非常有吸引力，因为XML(某种程度上)是人类可读的，而且有许多语言的绑定库。如果你希望与其他应用程序/项目共享数据，这可能是一个不错的选择。然而，XML是出了名的空间密集型，对它进行编码/解码会给应用程序带来巨大的性能损失。而且，在XML DOM树中导航要比在类中导航简单字段复杂得多。

Protocol buffers是解决这个问题的灵活、高效、自动化的解决方案。使用Protocol buffers，你编写一个描述要存储的数据结构的`.proto`文件。然后，Protocol buffer编译器会创建一个类，该类实现了协议缓冲区数据的自动编码和解析，使用高效的二进制格式。生成的类为构成协议缓冲区的字段提供了获取器和设置器，并处理了读取和写入协议缓冲区的细节。重要的是，协议缓冲区格式支持随着时间的推移扩展格式的想法，以使代码仍然能够读取使用旧格式编码的数据。  

## 从哪能找到示例代码呢？

我们的示例是一组用协议缓冲区编码的命令行应用程序，用于管理地址簿数据文件。命令`add_person_go`用于向数据文件添加新条目。命令`list_people_go`解析数据文件并将数据打印到控制台。  

你可以从[这里](https://github.com/protocolbuffers/protobuf/tree/master/examples)下载。  

## 定义Protocol文件

通讯录程序从定义`.proto`文件开始。`.proto`文件中的定义很简单：为要序列化的每个数据结构添加一个*message*，然后为消息中的每个字段指定名称和类型。在我们的示例中，定义消息的`.proto`文件是`addressbook.proto`。  

`.proto`文件以一个包声明开头，这有助于防止不同项目之间的命名冲突。  

```protobuf
syntax = "proto3";
package tutorial;

import "google/protobuf/timestamp.proto";
```

`go_package`选项定义了包含此文件中所有生成代码的包的导入路径。 Go包名称将是导入路径的最后一个路径组件。例如，我们的示例将使用“tutorialpb”作为包名称。

```protobuf
option go_package = "github.com/protocolbuffers/protobuf/examples/go/tutorialpb";
```

接下来，需要定义*message*。消息只是一个包含一组类型化字段的聚合。许多标准简单数据类型都可用作字段类型，包括`bool`、`int32`、`float`、`double`和`string`。你也可以通过使用其他消息类型作为字段类型来为消息添加更多结构。  

```protobuf
message Person {
  string name = 1;
  int32 id = 2;  // Unique ID number for this person.
  string email = 3;

  enum PhoneType {
    PHONE_TYPE_UNSPECIFIED = 0;
    PHONE_TYPE_MOBILE = 1;
    PHONE_TYPE_HOME = 2;
    PHONE_TYPE_WORK = 3;
  }

  message PhoneNumber {
    string number = 1;
    PhoneType type = 2;
  }

  repeated PhoneNumber phones = 4;

  google.protobuf.Timestamp last_updated = 5;
}

// Our address book file is just one of these.
message AddressBook {
  repeated Person people = 1;
}
```  

在上面例子中，`Person`消息包含`PhoneNumber`消息，同时`Person`消息包含在`AddressBook`消息中。你甚至可以定义消息类型嵌套在其它消息中 --- 就像上面`PhoneNumber`定义在`Person`中。你也可以定义`enum`类型，如果你想让你的字段只是用预定义列表中的一个值 --- 这里你想声明的电话类型可以是`MOBILE`、`HOME`或`WORK`其中之一。  

“= 1”，“= 2”标记每个字段在二进制编码中的唯一的“tag”。序号1-15编码的字节数比较高的数字少一位，因此，作为一种优化，你可以决定对常用或重复的元素使用这些标记，而对不常用的可选元素使用标记16或更高。重复字段中的每个元素都需要重新编码标记号，因此重复字段是此优化的特别好的候选项。

如果未设置字段值，则会使用[默认值](https://protobuf.dev/programming-guides/proto3#default)：对于数字类型，使用零；对于字符串，使用空字符串；对于布尔值，使用false。对于嵌套的消息，默认值始终是消息的“默认实例”或“原型”，该实例没有任何字段设置。调用访问器以获取未明确设置的字段的值始终返回该字段的默认值。

如果字段是`repeated`的，那么该字段可以重复任意次数（包括零次）。重复值的顺序将由protocol buffer处理。可以将重复字段视为动态大小的数组。

你可以在[Protocol Buffer语言指南](https://protobuf.dev/programming-guides/proto3)中找到撰写`.proto`文件的完整指南，包括所有可能的字段类型。但不要寻找类继承类似的功能 - 因为protocol buffer不支持这一点。

## 编译Protocol Buffers

现在你已经有`.proto`文件了，接下来你需要生成读写`AddressBook`（包括`Person`和`PhoneNumber`）消息的类。现在，你需要运行protocol buffer编译器`protoc`：

- 如果你还没安装编译器，可从[这里](https://protobuf.dev/downloads)下载并根据README编译安装。
- 使用如下命令按照Go protocol buffers插件：
    ```bash
    $ go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    ```
    `protoc-gen-go`编译器插件将安装在`$GOBIN`中，默认为`$GOPATH/bin`。protocol buffer编译器`protoc`必须能够在你的`$PATH`中找到它。
- 现在运行编译器，指明源目录（应用程序源文件目录，不指定的话默认使用当前目录），目标路径（你要存放生成的代码的目录，通常与`$SRC_DIR`一样），`.proto`文件路径。这样，你可以：
    ```bash
    $ protoc -I=$SRC_DIR --go_out=$DST_DIR $SRC_DIR/addressbook.proto
    ```
    因为要生成Go代码，所以使用`--go_out`选项。若要生成其它支持的语言，提供类似选项即可。
    生成的`github.com/protocolbuffers/protobuf/examples/go/tutorialpb/addressbook.pb.go`文件将保存在你指定的目录下。

## Protocol Buffer API  

生成的`addressbook.pb.go`为你提供了下面这些有用的类型：  

- 包含`People`字段的`AddressBook`结构体
- 包含`Name`、`Id`、`Email`和`Phones`字段的`People`
- 包含`Number`和`Type`字段的`Person_PhoneNumber`
- 自定义枚举类型的`Person.PhoneType`

你可以在[Go 生成的代码指南](https://protobuf.dev/reference/go/go-generated)中详细了解生成的代码的细节，但在大多数情况下，你可以将这些代码视为完全普通的 Go 类型。  


以下是`list_people`命令的单元测试示例，演示了如何创建一个`Person`实例：

```go
p := pb.Person{
    Id:    1234,
    Name:  "John Doe",
    Email: "jdoe@example.com",
    Phones: []*pb.Person_PhoneNumber{
        {Number: "555-4321", Type: pb.Person_PHONE_TYPE_HOME},
    },
}
```

## 创建Message

使用protocol buffers的目的是将数据序列化，以便在其他地方进行解析。在 Go 中，你可以使用`proto`库的[Marshal](https://pkg.go.dev/google.golang.org/protobuf/proto?tab=doc#Marshal)函数来序列化你的protocol buffers数据。protocol buffers消息的结构体指针实现了`proto.Message`接口。调用`proto.Marshal`返回编码后的protocol buffers数据。例如，我们在[`add_person`命令](https://github.com/protocolbuffers/protobuf/blob/master/examples/go/cmd/add_person/add_person.go)中使用了这个函数：  

```go
book := &pb.AddressBook{}
// ...

// Write the new address book back to disk.
out, err := proto.Marshal(book)
if err != nil {
    log.Fatalln("Failed to encode address book:", err)
}
if err := ioutil.WriteFile(fname, out, 0644); err != nil {
    log.Fatalln("Failed to write address book:", err)
}
```

## 读取Message

要解析已编码的消息，可以使用`proto`库的[Unmarshal](https://pkg.go.dev/google.golang.org/protobuf/proto?tab=doc#Unmarshal)函数。调用此函数将数据解析为protocol buffers，并将结果放`book`中。因此，要在[`list_people`命令](https://github.com/protocolbuffers/protobuf/blob/master/examples/go/cmd/list_people/list_people.go)中解析文件，我们使用以下代码：  

```go
// Read the existing address book.
in, err := ioutil.ReadFile(fname)
if err != nil {
    log.Fatalln("Error reading file:", err)
}
book := &pb.AddressBook{}
if err := proto.Unmarshal(in, book); err != nil {
    log.Fatalln("Failed to parse address book:", err)
}
```

## 扩展

在发布protocol buffer生成的代码后不久，你肯定会想`提升`你的protocol buffer定义。如果你想新的buffer可以被后向兼容，并且旧的buffer可以被前向兼容，--- 你确实想这样做 --- 那你需要遵守下面的规则。在新版的protocol buffer中：  

- 你**必须不能**改变已有字段的序号。
- 你**可以**删除repeated字段。
- 你**可以**新增repeated字段，但必须使用新的序号（序号在protocol buffer中没被用过，也没被删除）。  

还有一些[其它的扩展](https://protobuf.dev/programming-guides/proto3#updating)要遵守，但很少会用到它们。

遵循这些规则，旧代码将可以轻松地读取新的消息，并且会忽略任何新字段。对于旧代码来说，已删除的单字段将只是它们的默认值，而已删除的重复字段将为空。新代码也可以透明地读取旧消息。

但请记住，旧消息中不会包含新字段，因此你需要合理地处理默认值。使用类型特定的[默认值](https://protobuf.dev/programming-guides/proto3#default)：对于字符串，默认值是空字符串。对于布尔值，默认值是`false`。对于数值类型，默认值是零。  

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
