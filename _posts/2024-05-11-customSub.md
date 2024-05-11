---
layout: post
title: 自定义订阅
tags: [blockchain, web3.js]
mermaid: false
math: false
---  

> 原文在[这里](https://docs.web3js.org/guides/events_subscriptions/custom_subscriptions)。 

你可以扩展`Web3Subscription`类来创建自定义订阅。这样，你就可以订阅由提供者发出的自定义事件。

> 注意
> 这个指南很可能是针对那些连接到提供额外自定义订阅的节点的高级用户。对于普通用户，你可以在支持的订阅中找到[标准订阅](https://docs.web3js.org/guides/events_subscriptions/)是开箱即用的。

> 重要提示
> 如果你是为用户提供自定义订阅的开发者。我们鼓励你在阅读下面的指南后，开发一个web3.js插件。然而，你可以在[web3.js插件开发者指南](https://docs.web3js.org/guides/web3_plugin_guide/plugin_authors)中找到如何开发插件的方法。
> 即使你不是提供这种自定义订阅的开发者，我们也鼓励你为自定义订阅编写一个web3.js插件，并将其发布到npm包注册表。这样，你可以帮助社区。他们可能会为你的仓库做出贡献，帮助你做一些事情，如：添加功能，维护和检测错误。  

## 实现订阅  

### 扩展Web3Subscription

要创建一个自定义订阅，首先需要扩展`Web3Subscription`类。然而，`Web3Subscription`是泛型类型。通常，你只需要提供前两种类型，它们是：

- `EventMap`： 订阅发出的事件的事件映射
- `ArgsType`： 传递给订阅的参数

例如：  

```javascript
class MyCustomSubscription extends Web3Subscription<
  {
    // here provide the type of the `data` that will be emitted by the node
    data: string;
  },
  // here specify the types of the arguments that will be passed to the node when subscribing
  {
    customArg: string;
  }
> {
  // ...
}
```  

### 声明订阅参数

你需要指定将传递给提供者的确切数据。你可以通过在你的类中重写`_buildSubscriptionParams`来实现这一点。它可能是如下所示：

```javascript
protected _buildSubscriptionParams() {
  // 下面的`someCustomSubscription`是你连接的节点提供的订阅的名称。
  return ['someCustomSubscription', this.args];
}
```

按照上面的实现，将对提供者进行的调用将如下所示：  

```javascript
{
  id: '[GUID-STRING]', // something like: '3f839900-afdd-4553-bca7-b4e2b835c687'
  jsonrpc: '2.0',
  method: 'eth_subscribe',
  // The `someCustomSubscription` below is the name of the subscription provided by the node you are connected to.
  // And the `args` is the variable that has the type you provided at the second generic type
  //  at your class definition. That is in the snippet above: `{customArg: string}`.
  // And its value is what you provided when you will call:
  //  `web3.subscriptionManager.subscribe('custom', args)`
  params: ['someCustomSubscription', args],
}
```  

## 额外的自定义处理

你可能需要在构造函数中进行一些处理。或者你可能需要在数据被事件发射器发出之前对其进行一些格式化。在这一部分，你可以查看如何进行其中一种或两种操作。

### 自定义构造函数

你可以选择性地编写一个构造函数，以防你需要进行一些额外的初始化或处理。下面是一个构造函数实现的例子：

```javascript
constructor(
  args: {customArg: string},
  options: {
    subscriptionManager: Web3SubscriptionManager;
    returnFormat?: DataFormat;
  }
) {
  super(args, options);

  // Additional initialization
}
```

构造函数将参数传递给`Web3Subscription`父类。

你可以通过`this.subscriptionManager`访问订阅管理器。

### 自定义格式化

如果你需要在数据从节点接收到并被发出之前对其进行格式化，你只需要在你的类中重写受保护的方法`formatSubscriptionResult`。它将会像下面这样。然而，数据类型可以是节点提供的任何类型，这是你在扩展`Web3Subscription`时已经提供的第一个泛型类型：  

```javascript
protected formatSubscriptionResult(data: string) {
  const formattedData = format(data);
  return formattedData;
}
```  

## 订阅与取消订阅

要订阅，你需要将自定义订阅传递给`Web3`。然后，你可以为你的自定义订阅调用`subscribe`方法，如下面的示例所示：  

```javascript
const CustomSubscriptions = {
  // the key (`custom`) is what you chose to use when you call `web3.subscriptionManager.subscribe`.
  // the value (`CustomSubscription`) is your class name.
  custom: MyCustomSubscription,
  // you can have as many custom subscriptions as you like...
  // custom2: MyCustomSubscription2,
  // custom3: MyCustomSubscription3,
};

const web3 = new Web3({
  provider, // the provider that support the custom event that you like to subscribe to.
  registeredSubscriptions: CustomSubscriptions,
});

// subscribe at the provider:
// Note: this will internally initialize a new instance of `MyCustomSubscription`,
// call `_buildSubscriptionParams`, and then send the `eth_subscribe` RPC call.
const sub = web3.subscriptionManager.subscribe('custom', args);

// listen to the emitted event:
// Note: the data will be optionally formatted at `formatSubscriptionResult`, before it is emitted here.
sub.on('data', (result) => {
  // This will be called every time a new data arrived from the provider to this subscription
});
```  

取消订阅：  

```javascript
// this will send `eth_unsubscribe` to stop the subscription.
await sub.unsubscribe();
```  

## 合并一处  

以下是自定义订阅实现的完整示例：  

```javascript
// Subscription class
class MyCustomSubscription extends Web3Subscription<
  {
    // here provide the type of the `data` that will be emitted by the node
    data: string;
  },
  // here specify the types of the arguments that will be passed to the node when subscribing
  {
    customArg: string;
  }
> {
  protected _buildSubscriptionParams() {
    // the `someCustomSubscription` below is the name of the subscription provided by the node your are connected to.
    return ['someCustomSubscription', this.args];
  }

  protected formatSubscriptionResult(data: string) {
    return format(data);
  }

  constructor(
    args: { customArg: string },
    options: {
      subscriptionManager: Web3SubscriptionManager;
      returnFormat?: DataFormat;
    }
  ) {
    super(args, options);

    // Additional initialization
  }
}

// Usage

const args = {
  customArg: 'hello custom',
};

const CustomSubscriptions = {
  // the key (`custom`) is what you chose to use when you call `web3.subscriptionManager.subscribe`.
  // the value (`MyCustomSubscription`) is your class name.
  custom: MyCustomSubscription,
  // you can have as many custom subscriptions as you like...
  // custom2: MyCustomSubscription2,
  // custom3: MyCustomSubscription3,
};

const web3 = new Web3({
  provider, // the provider that support the custom event that you like to subscribe to.
  registeredSubscriptions: CustomSubscriptions,
});

const sub = web3.subscriptionManager.subscribe('custom', args);

sub.on('data', (result) => {
  // New data
});

/* Unsubscribe:
If you want to subscribe later based on some code logic:

if () { await sub.subscribe(); }
*/
```  

## 关键点

### 订阅定义

- 扩展`Web3Subscription`类以创建自定义订阅。
- 在泛型类型中指定事件数据和订阅参数类型。
- 重写`_buildSubscriptionParams()`以定义RPC参数。
- 可选地添加自定义构造函数进行初始化逻辑。
- 可选地使用`format SubscriptionResult()`在发出数据之前格式化结果。

### 订阅使用

- 通过在`Web3`构造函数选项中传递订阅来注册订阅。
- 使用`subscriptionManager`订阅/取消订阅。
- 监听订阅事件，如`data`，以获取新的结果。

## 结论

总的来说，web3.js订阅提供了一种灵活的方式来订阅自定义提供者事件。通过扩展`Web3Subscription`，实现关键方法，并与`Web3`注册，你可以为提供者可以发出的任何自定义事件创建定制的订阅。订阅API处理底层的JSON-RPC调用，并允许对结果进行自定义处理和格式化。  

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
