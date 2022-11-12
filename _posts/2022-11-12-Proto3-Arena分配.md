---
layout: post
title: Proto3 Arenas分配
tags: proto3
mermaid: false
---  

Arena分配是仅C++有的功能，在使用Protocol Buffer时，它可以帮助你优化你的内存使用，提高性能。在`.proto`文件中启用Arena分配会在生成的C++代码中添加处理Arena分配的额外代码。关于Arena分配API的细节，详见[Arena Allocation Guide](https://developers.google.com/protocol-buffers/docs/reference/arenas)。  

### 服务  

如果`.proto`文件中包含下面的内容：  

> option cc_generic_services = true;

之后，Protocol Buffer编译器会根据在本节中描述的文件中找到的服务定义生成代码。然而，生成的代码可能不受欢迎，因为它并没有绑定特定的RPC系统，因此需要为一个系统定制更多级别的间接代码。如果你不想生成这样的代码，你可以在文件中添加这一行：  

> option cc_generic_services = false;

如果上面的行都未给定，默认选项未`false`，因此不推荐使用通用服务。（注意，2.4.0版本之前，默认选项为`true`。）  

基于`.proto`语言服务定义的RPC系统应该提供[插件](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.compiler.plugin.pb)来生成适合系统的代码。这些插件可能需要禁用抽象服务，以便它们可以生成自己的同名类。插件是2.3.0版本（2010年1月）新引入的。  

下面的章节描述抽象服务启用时编译器会生成什么。  

#### 接口  

给出如下服务定义：  

```proto
service Foo {
  rpc Bar(FooRequest) returns(FooResponse);
}
```  

编译器会生成一个名为`Foo`的类来表示该服务。`Foo`中包含服务定义中定义的每个方法的虚方法。这种情况下，`Bar`方法定义如下：  

```c++
virtual void Bar(RpcController* controller, const FooRequest* request,
                 FooResponse* response, Closure* done);
```  

这些参数等同于[Service::CallMethod()](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#Service.CallMethod.details)的参数，只是`method`参数是隐含的，而`request`和`response`指定了它们的确切类型。  

这些生成的方法是虚，但不是纯虚的。默认的实现知识简单地调用`controller->`[SetFailed()](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcController.SetFailed)，并使用一条错误消息指示方法未实现，然后调用`done`回调。在实现你自己的服务时，你必须子类化这个生成的服务并适当的实现它的方法。  

`Foo`子类化[Service](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#Service)接口。编译器会自动实现如下的`Service`的方法：  

- `GetDescriptor`：返回服务的[ServiceDescriptor](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.descriptor.html#ServiceDescriptor)。
- `CallMethod`：根据提供的方法描述符确定要调用哪个方法，并直接调用它，将请求和响应消息对象向下转换为正确的类型。
- `GetRequestPrototype`和`GetResponsePrototype`：针对给定的方法，返回当前类型的请求/响应的默认实例。  

也会生成下列静态方法：  

- `static`[ServiceDescriptor](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.descriptor.html#ServiceDescriptor) `descriptor()`：返回类型的描述，其中包括该服务包含那些方法以及它们的输入输出类型。

#### Stub  

编译器还为每个服务接口生成了一个“Stub”实现，由要向实现服务的服务器发送请求的客户端使用。对于`Foo`服务，Stub实现被定义未`Foo_Stub`。就像内嵌消息类型一样，由于typedef的使用，所以可以使用`Foo::Stub`来引用`Foo_Stub`。  

`Foo_Stub`是实现了如下方法的`Foo`的子类：  

- `Foo_Stub(`[RpcChannel](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcChannel)`* channel)`：在给定的通道上发送请求的新构造的Stub。
- `Foo_Stub(`[RpcChannel](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcChannel)`* channel,`[ChannelOwnership](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#Service.ChannelOwnership)`ownership)`：在给定的通道上发送请求的新构造的Stub,及通道的所有者。如果`ownership`是`Service::STUB_OWNS_CHANNEL`，之后在删除stub对象时也会删除该通道。
- [RpcChannel](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcChannel)`* channel)`：返回传递给构造函数的stub通道。  

stub还额外实现了作为通道打包器的每个服务方法。调用其中一个方法只是简单地调用`channel->`[CallMethod()](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcChannel.CallMethod)。  

Protocol Buffer库并不包含RPC实现。但是，它包括将生成的服务类连接到你所选择的任意RPC实现所需的所有工具。你只需要提供[RpcChannel](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcChannel)和[RpcController](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service.html#RpcController)的实现。更多信息，详见[service.h](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.service)。  

### 插件  

想要扩展c++代码生成器输出的代码，[Code generator plugin](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.compiler.plugin.pb)可以使用给定的插入点名称插入下列类型的代码。除非另做说明，否则每个插入点都出现在`.pb.cc`和`.pb.h`文件中。  

- `includes`：include命令。
- `namespace_scope`：属于文件包/名称空间，但不属于任何特定类的声明。出现在所有其他名称空间范围代码之后。
- `global_scope`：属于顶级声明，位于文件级明明空间之外。出现在文件末尾。
- `class_scope:TYPENAME`：属于消息类的成员声明。`TYPENAME`是完整的proto名称，例如`package.MessageType`。在类中，出现在其它公共声明之后。只出现在`.pb.h`文件中。  

## Arena分配指南  

[为什么要用Arena分配](###为什么要用Arena分配)  
[开始](###开始)  
[Arena类API](###Arena类API)  
[生成消息类](###生成消息类)  
[使用模式和最佳实践](###使用模式和最佳实践)  
[示例](###示例)  

Arena分配是仅C++有的功能，在使用Protocol Buffer时，它可以帮助你优化你的内存使用，提高性能。本章节是[上一章节](##代码生成指南)的补充，它实际上描述了再arena分配启用时，编译器生成了什么。本文默认你已经熟悉了[语言指南](https://developers.google.com/protocol-buffers/docs/proto3)和[C++代码生成指南](##代码生成指南)。

### 为什么要用Arena分配  

在Protocol Buffer代码中，内存的分配与释放占据了CPU耗时的很大一部分。默认情况下，Protocol Buffer为每个消息对象、它的每个子对象，以及一些字段类型，比如字符串，在堆上进行内存分配。在解析消息和构建新的消息时，这个分配操作会大量发生；当消息及其子对象树释放时，会产生相关应的释放操作。  

基于Arena的分配被设计用来减小这一性能开销。使用arena分配，新对象从一个叫做arena的大内存块中分配。通过丢弃整个arena，可以一次释放所有对象，理想情况下不需要运行任何被包含对象的析构函数(虽然arena仍然可以在需要时维护一个析构函数列表)。通过将对象分配减少为一个简单的指针增量，这使得对象分配变得更快，而且使释放时几乎没有消耗。Arena分配还提供了更高的缓存效率:当消息被解析时，它们更有可能被分配到连续内存中，这使得遍历消息更有可能到达热缓存线路。  

为了获得这些好处，你需要了解对象的生命周期，并选择合适的粒度来使用arena（对于服务器，这通常是针对每个请求的）。在[使用模式和最佳实践](###使用模式和最佳实践)中，你可以了解更多。  

### 开始  

首先你需要在每个`.proto`文件中启用arena分配。那么你需要在你的`.proto`文件中添加如下`option`：  

> option cc_enable_arenas = true;

这就告诉编译器为你的消息使用arena分配生成额外的代码，使用如下：  

```c++
#include <google/protobuf/arena.h>
{
  google::protobuf::Arena arena;
  MyMessage* message = google::protobuf::Arena::CreateMessage<MyMessage>(&arena);
  // ...
}
```  

只要`arena`存在，通过`CreateMessage()`创建的消息对象就一直存在，而且你不应该`delete`返回的消息指针。该消息的所有内部存储（少数例外$^1$）以及子类消息（例如，`MyMessage`中重复字段的子类消息）也都在arena上分配。  

在大多数情况下，代码的其余部分与不使用`arena`分配是一样的。  

在下一小节中会看到更多的arena API的细节，在文末的[示例](##示例)中你能看到更多使用细节。  

> 1 目前，即使包含的消息在arena中，字符串字段也将其数据存储在堆中。未知字段也是在堆上分配。  

### Arena类API  

在arena上，你可以使用[google::protobuf::Arena](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.arena.html)类来创建消息对象。该类实现了下列的公共方法。  

#### 构造函数  

- `Arena()`：使用默认参数创建一个新的arena，针对一般的使用场景。
- `Arena(const ArenaOptions& options)`：使用特定的分配选项来创建一个新的arena。在`ArenaOptions`中，可用的选项能够使用一个初始的用户提供的内存块分配之前采取系统分配程序,控制初始和最大请求大小的内存块,并允许你通过自定义块分配和回收函数指针来构建释放列表和其它顶上的块。

#### 分配方法  

- `template<typename T> static T* CreateMessage(Arena* arena)`：在arena上创建一个新的消息类型为`T`的Protocol Buffer对象。消息类型必须是定义在`.proto`文件中，且文件中有`option cc_enable_arenas = true;`，否则，将导致编译错误。
  如果`arena`非空，将返回在arena上的消息对象，它的内部存储以及子类消息（如果有的化）也都在同一arena上分配，且它的声明周期与该arena的一样。该对象不能手动释放：该arena拥有消息对象的生命周期。  
  如果`arena`为空，返回的消息对象被分配在堆上，调用者拥有该对象的所有权。
- `template<typename T> static T* Create(Arena* arena, args...)`：与`CreateMessage()`类似，但允许你在arena上创建任何类的对象，即使Protocol Buffer消息类型没有`option cc_enable_arenas = true;`：你可以从不支持的arena的文件中使用Protocol Buffer消息类，或任意的C++类。例如，你有如下的C++类：  

```c++
class MyCustomClass {
    MyCustomClass(int arg1, int arg2);
    // ...
};
```  

你可以在arena上创建它的实例：  

```c++
void func() {
    // ...
    google::protobuf::Arena arena;
    MyCustomClass* c = google::protobuf::Arena::Create<MyCustomClass>(&arena, constructor_arg1, constructor_arg2);
    // ...
}
```  

- `template<typename T> static T* CreateArray(Arena* arena, size_t n)`：如果`arena`非空， 该方法将为`n`个类型为`T`的元素分配原始存储并返回它。arena所有这返回的内存并在自身销毁时释放它。如果`arena`为空，该方法在堆上分配存储且调用者获得所有权。

`T`必须有一个简单的构造函数：当数组在arena上创建时，构造函数并不会被调用。  

#### “所有权列表”方法  

下面的方法允许你指定特定对象或析构函数为arena所有，从而确保在arena删除它自己的时候也删除它们：  

- `template<typename T> void Own(T* object)`：添加`object`到arena所有的堆对象列表中。当arena销毁时，它将遍历整个列表并使用删除操作释放每个对象，即系统内存分配。当一个对象的声明周期要跟arena绑定，但它本身又不是在arena上分配时，这种情况下该方法很有用。
- `template<typename T> void OwnDestructor(T* object)`：将`object`的析构函数添加到arena的析构函数调用列表中。当arena销毁时，它将遍历整个列表并将调用每个析构函数。它不会试图释放对象的底层内存。当一个对象是内嵌在arena分配的存储中但它的析构函数并不会被调用的情况下，该方法是有用的，例如，因为它的包含类是一个析构函数不会被调用的protobuf消息，或者是因为它是通过`AllocateArray()`手动在被分配的块上构造的。  

#### 其它方法  

- `uint64 SpaceUsed() const`：返回arena的总大小，它是所有底层块大小的总和。该方法时线程安全的；但是如果是多线程并发分配，该方法的返回值可能不包括那些新块的大小。
- `uint64 Reset()`：销毁arena存储：首先调用所有注册的析构函数且释放所有注册的堆对象，之后丢弃所有的arena块。这个销毁过程与arena的析构函数运行时发生的过程是等价的，只是arena在这个方法返回后会被重用。返回arena使用的总大小:此信息对于调优性能非常有用。
- `template<typename T> Arena* GetArena()`：返回arena的指针。虽然不是很有用，但它允许在需要`GetArena()`方法的模板实例化中使用`Arena()`。

#### 线程安全  

`google::protobuf::Arena`的分配方法是线程安全的，且底层实现有一定的长度来确保多线程分配更快。`Reset()`方法不是线程安全的：执行arena重置的线程必须首先与所有执行分配或者使用arena中分配的对象的线程同步。  

### 生成消息类    

当你启用arena分配时，下面的消息类成员会被改变或添加。  

#### 消息类方法  

- `Message(Message&& other)`：如果源消息不在arena上，move构造高效地将一个消息的所有字段*移动*到另一个消息，而无需进行赋值或堆分配（该操作的时间复杂度为`0(number-of-declared-fields)`）。但是如果源消息在arena上，它将执行底层数据的*深拷贝操作*。以上两种情况中，源消息还是有效的但未指定的状态。
- `Message& operator=(Message&& other)`：无论两个消息都不在arena或是同一个arena，赋值操作高效地将一个消息的所有字段*移动*到另一个消息，而无需进行赋值或堆分配（该操作的时间复杂度为`0(number-of-declared-fields)`）。如果只要一个消息在arena上或不在同一个arena上，它将执行底层数据的*深拷贝操作*。以上两种情况中，源消息还是有效的但未指定的状态。
- `void Swap(Message* other)`：如果要交换的两个消息都不在arena或在同一个arena上，[Swao()](https://developers.google.com/protocol-buffers/docs/reference/cpp-generated.html?hl=zh_cn#message)的行为与未启用arena分配相同：它将高效地交换消息对象的内容，通常是通过廉价的指针交换以及尽可能地避免拷贝。如果只用一个消息在arena上或两个消息不在同一个arena上，`Swap()`将执行底层数据的*深拷贝操作*。这一操作是很有必要的，因为交换之后的子对象可能有不同的生命周期，引起use-after-free错误。
- `Message* New(Arena* arena)`：对标准`New()`方法的替换重写。它允许该类型在给定的arena上创建新的消息对象。他的语义与`Arena::CreateMessage<T>(arena)`相同，前提是它所调用的具体消息类型是在启用Arena分配的情况下生成的。如果消息类型不是在启用Arena分配的情况下生成的，当`arena`非空时，它等同于一个后跟`arena->Own(message)`的原始分配。
- `Arena* GetArena()`：返回分配此消息对象的arena（如果有的话）。
- `void UnsafeArenaSwap(Message* other)`：与`Swap()`相同，只是它假设两个对象在同一个arena上（或两个都不在arena上），并且总是使用这个操作的高效指针交换实现。使用该方法可以提升效率，因为，不像`Swap()`，在执行交换之前，它不需要检查那个消息位于那个arena上。正如`Unsafe`前缀所说的，只有在确定消息不在不同的arena上时，你才能使用该方法；否则，该方法可能产生不可预测的结果。

#### 内嵌消息字段  

当你在arena上分配消息对象时，它的内嵌消息字段对象（子消息）自动为该arena所有。如何分配消息对象取决于它们在哪定义的：  

- 如果消息类型是在启用Arena分配的`.proto`文件中定义的，则对象就直接在arena上分配。
- 如果消息类型是在另一个没有启用Arena分配的`.proto`文件中定义的，该对象是在堆上分配的，但它的所有权归父消息的arena所有。这意味着在arena销毁时，属于该arena的对象也会被释放。

下列字段定义之一：  

> optional Bar foo = 1;
> required Bar foo = 1;

在启用arena分配情况下，下面的方法会被添加或有一些特殊的行为。否则，访问器方法只是用[默认行为](####单个内嵌消息字段)。  

- `Bar* mutable_foo()`：返回子消息实例的可变指针。如果父对象在arena上，返回的对象也在arena上。
- `void set_allocated_foo(Bar* bar)`：接受一个新对象并将其作为字段的新值。Arena支持新增了额外的复制语义，来确保对象在跨越arena/arena或arena/heap边界时保持适当的所有权：
  - 如果父对象在堆上且`bar`也在堆上，或父对象和子消息在同一arena上，该消息的行为不变。
  - 如果父对象在arena上且`bar`在堆上，父消息使用`arena->Own()`将`bar`添加到它自己的arena所有去列表。
  - 如果父对象在arena上且`bar`在另一个arena上，该方法生成消息的副本将将其作为字段的新值对待。
- `Bar* release_foo()`：如果存在返回字段已存在的子消息实例，如果不存在则返回空指针；将该实例的所有权移交给调用者并清理父消息字段。Arena支持新增了额外的复制语义，以确保返回的对象总是遵守*heap-allocated*协议：
  - 如果父消息在arena上，该方法在堆上创建子消息的副本，清空该字段的值，并返回该副本。
  - 如果父消息在堆上，该消息行为不变。
- `void unsafe_arena_set_allocated_foo(Bar* bar)`：与`set_allocated_foo`相同，但假定父消息和子消息都在同一个arena。使用该方法可以提升性能，因为它不需要检查消息是不是在特定的arena或堆上。只有在确定父消息在arena上且子消息也在同一arena上（或声明周期与该arena相同）才能使用该方法。
- `Bar* unsafe_arena_release_foo()`：与`release_foo()`类似，但假定父消息在arena上，且返回一个不应该被直接删除的*arena-allocated*对象。只有当父消息在arena上时才能使用该方法。

#### 字符串字段  

目前，即使父消息在arena上，字符串字段也将它们的数据存储在堆上。因此，即使arena分配启用，字符串访问器方法使用[默认行为](####单个字符串字段)。  

当arena启用，字符串和字节字段生成`unsafe_arena_release_field()`和`unsafe_arena_set)allocated_field()`方法。注意这些方法已被**弃用**，且之后会被删除。这些方法是被错误地添加的，与它们的安全方法相比并没有性能优势。  

#### 重复字段  

当包含的消息是在arena上分配的，重复字段也在arena上分配它们的内部数组存储；当这些元素是由指针（消息或字符串）保留的独立对象时，也在arena上分配它们的元素。在消息类级别，为重复字段生成的方法不变。在arena支持启用时，由访问器返回的`RepeatedField`和`RepeatedPtrField`对象确实有新的方法和语义的改变。  

##### 重复数值字段  

在arena支持启用时，包含[原始类型](#####重复数值字段)的`RepeatedField`对象有下列新/变化的方法：  

- `void UnsafeArenaSwap(RepeatedField* other)`：在无需验证该重复字段和另一个是不是在同一个arena的情况下执行`RepeatedField`内容的交换。如果它们不在同一个arena上，那这两个重复字段对象必须在生命周期相同的arena上。一个在arena上另一个在堆上的情况下，先检查然后禁用。
- `void Swap(RepeatedField* other)`：检查每个重复字段对象的arena，如果一个在arena另一个在堆上或两个都在不同的arena上，在交换之前复制底层数组。这意味着交换结束后，每个重复字段都在它自己的arena或堆上保留一个合适的数组。  

##### 重复的内嵌消息字段  

在arena支持启用时，包含消息的`RepeatedPtrField`对象有下列新/变化的方法：  

- `void UnsafeArenaSwap(RepeatedPtrField* other)`：：在无需验证该重复字段和另一个是不是在同一个arena指针的情况下执行`RepeatedField`内容的交换。如果它们不在同一个arena指针上，那这两个重复字段对象必须在生命周期相同的arena指针上。一个对象有一个非空的arena上指针而另一个有一个空的arena指针，这种情况下先检查然后禁用。
- `void Swap(RepeatedPtrField* other)`：检查每个重复字段对象的arena指针，如果一个非空（包含在arena上），另一个为空（包含在堆上），或两个都为非空但值不同，在交换之前会复制底层数组和指向对象的指针。这意味着交换结束后，每个重复字段都在它自己的arena或堆上保留一个合适的数组。  
- `void AddAllocated(SubMessageType* value)`：检查给定的消息对象与重复字段的arena指针是不是一样。如果实在同一个arena上，之后对象的指针就直接添加到底层数组。否则，会生成一个副本，如果对象实在堆上分配的原始的对象会被释放，副本会被放入底层数组。这保证重复字段所指向的所有对象的指针与重复字段的arena指针指向的所有权域（堆或这指定的arena）相同。
- `SubMessageType* ReleaseLast()`：返回与重复字段最后一个消息相同的堆上分配的消息，并从重复字段中移除它。如果重复字段本身有一个空的arena指针（即它所有指向消息的指针都时堆分配的），之后该方法只是简单的返回原始对象的指针。如果重复字段有一个非空的arena指针，该方法会在堆上分配一个副本然后返回该副本。上述两种情况下，调用者会的堆上分配的对象的所有权，并负责删除该对象。
- `void UnsafeArenaAddAllocated(SubMessageType* value)`：与`AddAllocated()`类似，但是不处理堆/arena检查或任何消息的副本。它直接将提供的指针添加到该重复字段的内部数组指针中。如果重复字段有一个空的arena指针，调用者必须保证提供的对象是在堆上分配的，或者如果重复字段有一个非空的arena指针，则必须在arena分配（同一个arena或相同生命周期的arena）的。
- `SubMessageType* UnsafeArenaReleaseLast()`：与`ReleaseLast()`类似，但不处理任何副本，即使重复字段有一个非空的arena指针。相反，它直接返回该对象在重复字段中的指针。如果重复字段的arena指针为空，返回的对象是在堆上的，如果重复字段的arena指针非空，则是在arena上。如果对象是堆分配的，调用者获得所有权；如果对象是arena分配的，调用者不能删除返回的对象。
- `void ExtractSubrange(int start, int num, SubMessageType** elements)`：从索引`start`位置开始，从重复字段中提取`num`个元素，如果`elements`非空的话将移除的元素放入`elememts`中。如果重复字段在arena上，在元素返回之前先将这些元素复制到堆上。这两中情况下（在或不在arena上），调用者拥有堆上的返回对象。
- `void UnsafeArenaExtractSubrange(int start, int num, SubMessageType** elements)`：从索引`start`位置开始，从重复字段中提取`num`个元素，如果`elements`非空的话将移除的元素放入`elememts`中。与`ExtractSubrange()`不同，该方法从不复制提取的元素。

##### 重复的字符串字段  

重复的字符串字段有与重复的消息字段一样的新方法和修改的语义，因为它们都是通过指针引用来保存它们的底层数据（即字符串）。  

### 使用模式和最佳实践  

在使用arena分配的消息时，有几种使用模式可能导致意外的副本或其它负面性能的影响。你应该留意，下面的几种常用的模式在适配arena的代码时需要要有所改变。（注意，在API设计中我们已经注意到这一点，以确保依然正确的行为 --- 但是更高性能的解决方案仍可能需要一些返工。）  

#### 意外的副本  

在启用arena时，有些在未启用arena时并不会创建对象副本的方法可能会创建副本。如果你确保分配的对象合适/或使用提供的arena特定版本的方法，就可以避免这些不需要的副本，下面将对此进行更详细的描述。  

##### 设置分配/添加分配/释放  

默认情况下，`release_field()`和`set_allocate_field()`方法（针对单个消息字段）以及`ReleaseLast()`和`AddAllocated()`方法（针对重复消息字段）允许用户代码直接添加和分离子消息，通过指针的所有权而无需复制任何数据。  

然尔，当父消息在arena上时，这些方法有时候需要复制传入/返回的对象，以保持与现有的所有权兼容。更具体的，当父消息在arena上而新的子消息不在，获取所有权的方法（`set_allocated_field()`和`AddAllocated()`）可能会复制数据；反之亦然；或它们不在同一arena上。如果父消息在arena上，释放所有权的方法（`release_field()`和`ReleaseLast()`）可能会复制数据，因为按照约定返回的对象必须是在堆上。  

为了避免这些复制，我们添加了这些方法的`unsafe arena`版本的协议，在这些版本中复制绝不会被执行：对单个和重复字段，分别是`unsafe_arena_set_allocated_field()`、`unsafe_arena_release_field()`、`UnsafeArenaAddAllocated()`和`UnsafeArenaRelease()`。只有在你了解这么做是安全且父对象和子对象都能如期分配是，你才能使用这些方法。否则，比如，你可能获得具有不同生命周期的父对象和子对象，这将导致use-after-free错误。  

下面是你如何使用这些方法来避免不必要的复制的例子。接下来会在arena上创建下面的消息：  

```c++
Arena* arena = new google::protobuf::Arena();
MyFeatureMessage* arena_message_1 =
  google::protobuf::Arena::CreateMessage<MyFeatureMessage>(arena);
arena_message_1->mutable_nested_message()->set_feature_id(11);

MyFeatureMessage* arena_message_2 =
  google::protobuf::Arena::CreateMessage<MyFeatureMessage>(arena);
```  

下面的代码是`release_...()`API的低效用法：  

```c++
arena_message_2->set_allocated_nested_message(arena_message_1->release_nested_message());

arena_message_1->release_message(); // returns a copy of the underlying nested_message and deletes underlying pointer
```  

使用`unsafe arena`版可以避免复制：  

```c++
arena_message_2->set_allocated_nested_message(
   arena_message_1->unsafe_arena_release_nested_message());
```  

关于这些方法的更多细节，你可以在上面的[内嵌消息字段](####内嵌消息字段)章节了解到。  

##### 交换  

如果两个消息处在不同的arenas上，或一个在arena另一个在堆上，使用`Swap()`交换两个消息的内容时，底层的子对象可能会被复制。如果你想避免这个复制，且知道这两个消息在同一个arena上或在有相同生命周期的不同arena上，或知道这两个消息都在堆上，你可以使用新的方法 --- `UnsafeArenaSwap()`。此方法既避免了执行arena检查的开销，又避免了在可能发生副本检查的情况下进行副本检查。  

例如，下面的代码在`Swap()`调用中会引起复制：  

```c++
MyFeatureMessage* message_1 =
  google::protobuf::Arena::CreateMessage<MyFeatureMessage>(arena);
message_1->mutable_nested_message()->set_feature_id(11);

MyFeatureMessage* message_2 = new MyFeatureMessage;
message_2->mutable_nested_message()->set_feature_id(22);

message_1->Swap(message_2); // Inefficient swap!
```  

在上述代码中要避免复制，你可以在相同的arena像`message_1`一样分配`message_2`：  

```c++
MyFeatureMessage* message_2 =
   google::protobuf::Arena::CreateMessage<MyFeatureMessage>(arena);
```  

##### 内嵌消息字段和arena启用选项  

每个`.proto`都有它自己的arena支持的“功能开关”。如果给定的`.proto`文件中并没有设置`cc_enable_arenas`，那么文件中的类型定义并不会存储到arena上，即使其它类型中包含在了该文件中定义的子消息类型中。换言之，`cc_enable_arenas`是不可传递的。相反，具有arena资格但本身并不支持arena的消息的子消息将始终存储在堆上，且会被添加到父消息的arena的`Own()`中以便将它们的生命周期与arena的绑定。  

这样约定的原因是，如果arena因为一些额外的代码而未被使用，那么添加arena支持会增加一些开销。所以我们选择（目前）不启用arena的全局支持。而且，由于类型和API兼容性的原因，每个proto消息类型只能有一个C++生成的类，因此我们不能同时生成带arena支持和不带arena支持的类版本。未来，功能优化之后，我们可能会取消这个限制，全局启用arena支持。不过现在，应该为尽可能多的子消息启用它以提高性能。  

##### 粒度  

我们发现在大多数服务使用场景中，“arena-per-request”模式表现良好。你可能会尝试进一步扩大arena使用，以减少堆开销（通过更频繁的销毁较小的arena），或者减少感知到的线程竞争问题。然而就如我们上面所说的，使用更细粒度的arena可能会导致意外的消息复制。我们还为多线程用例优化了`Arena`实现，因此单个的arena应该适合在整个请求的生命周期中使用，即使是多线程处理该请求。  

### 示例  

下面是一个简单的完整示例，演示了arena分配API的一些特性。  

```proto
// my_feature.proto

syntax = "proto2";
import "nested_message.proto";

package feature_package;

option cc_enable_arenas = true;

// NEXT Tag to use: 4
message MyFeatureMessage {
  optional string feature_name = 1;
  repeated int32 feature_data = 2;
  optional NestedMessage nested_message = 3;
};
```  

```proto
// nested_message.protofset

syntax = "proto2";

package feature_package;

// add cc_enable_arenas on each submessage for
// the best performance when using arenas.
option cc_enable_arenas = true;

// NEXT Tag to use: 2
message NestedMessage {
  optional int32 feature_id = 1;
};
```  

消息构造与再分配：  

```c++
#include <google/protobuf/arena.h>

Arena arena;

MyFeatureMessage* arena_message =
   google::protobuf::Arena::CreateMessage<MyFeatureMessage>(&arena);

arena_message->set_feature_name("Proto2 Arena");
arena_message->mutable_feature_data()->Add(2);
arena_message->mutable_feature_data()->Add(4);
arena_message->mutable_nested_message()->set_feature_id(247);
```  

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: mengbin92  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
