---
layout: post
title: 事件订阅
tags: [blockchain, web3.js]
mermaid: false
math: false
---  

> 原文在[这里](https://docs.web3js.org/guides/events_subscriptions/)。 

## 订阅智能合约事件  

```javascript
import { Web3 } from "web3";

// set a provider - MUST be a WebSocket(WSS) provider
const web3 = new Web3("wss://ethereum-rpc.publicnode.com");

async function subscribe() {
  // create a new contract object, providing the ABI and address
  const contract = new web3.eth.Contract(abi, address);

  // subscribe to the smart contract event
  const subscription = contract.events.EventName();

  // new value every time the event is emitted
  subscription.on("data", console.log);
}

// function to unsubscribe from a subscription
async function unsubscribe(subscription) {
    await subscription.unsubscribe();
}

subscribe();
unsubscribe(subscription);
```  

## 订阅节点事件

[像Geth这样的标准以太坊节点支持订阅特定的事件](https://geth.ethereum.org/docs/interacting-with-geth/rpc/pubsub#supported-subscriptions)。此外，还有一些以太坊节点提供额外的自定义订阅。如你在这个指南中所看到的，web3.js使你能够直接订阅标准事件。它还为你提供了订阅自定义订阅的能力，如你在[自定义订阅](https://docs.web3js.org/guides/events_subscriptions/custom_subscriptions)指南中所看到的。

> 重要提示
> 如果你是为用户提供自定义订阅的开发者。我们鼓励你在阅读下面的[自定义订阅](https://docs.web3js.org/guides/events_subscriptions/custom_subscriptions)部分后，开发一个web3.js插件。你可以在[web3.js插件开发者指南](https://docs.web3js.org/guides/web3_plugin_guide/plugin_authors)中找到如何开发插件的方法。

- `on("data")` - 每当有新的日志进入时触发，日志对象作为参数。
  
  ```javascript
  subcription.on("data", (data) => console.log(data));
  ```

- `on("changed")` - 每当区块链中移除一个日志时触发。该日志将有额外的属性 "removed: true"。
  
  ```javascript
  subcription.on("changed", (changed) => console.log(changed));
  ```

- `on("error")` - 当订阅中出现错误时触发。
  
  ```javascript
  subcription.on("error", (error) => console.log(error));
  ```

- `on("connected")` - 在订阅成功连接后触发一次。返回订阅id。
  
  ```javascript
  subcription.on("connected", (connected) => console.log(connected));
  ```  

### Logs  

- `logs`：在`LogsSubscription`类中实现  

```javascript
import { Web3 } from "web3";

const web3 = new Web3("wss://ethereum-rpc.publicnode.com");

async function subscribe() {
  //create subcription
  const subcription = await web3.eth.subscribe("logs");

  //print logs of the latest mined block
  subcription.on("data", (data) => console.log(data));
}

// function to unsubscribe from a subscription
async function unsubscribe(subscription) {
    await subscription.unsubscribe();
}

subscribe();
unsubscribe(subscription);
```  

### 追加交易

- `newPendingTransactions`：在[NewPendingTransactionsSubscription](https://docs.web3js.org/api/web3-eth/class/NewPendingTransactionsSubscription)类中实现
- `pendingTransactions`：与`newPendingTransactions`一样

```javascript
import { Web3 } from "web3";

const web3 = new Web3("wss://ethereum-rpc.publicnode.com");

async function subscribe() {
  //create subcription
  const subcription = await web3.eth.subscribe("pendingTransactions"); //or ("newPendingTransactions")

  //print tx hashs of pending transactions
  subcription.on("data", (data) => console.log(data));
}

// function to unsubscribe from a subscription
async function unsubscribe(subscription) {
    await subscription.unsubscribe();
}

subscribe();
unsubscribe(subscription);
```  

### Block headers  

- `newBlockHeader`：在[NewHeadsSubscription](https://docs.web3js.org/api/web3-eth/class/NewHeadsSubscription)类中实现
- `newHeads`：与`newBlockHeader`一样

```javascript
import { Web3 } from "web3";

const web3 = new Web3("wss://ethereum-rpc.publicnode.com");

async function subscribe() {
  //create subcription
  const subcription = await web3.eth.subscribe("newBlockHeaders"); //or ("newHeads")

  //print block header everytime a block is mined
  subcription.on("data", (data) => console.log(data));
}

// function to unsubscribe from a subscription
async function unsubscribe(subscription) {
    await subscription.unsubscribe();
}

subscribe();
unsubscribe(subscription);
```  

### Syncing

- `syncing`：在[SyncingSubscription](https://docs.web3js.org/api/web3-eth/class/SyncingSubscription)类中实现

```javascript
import { Web3 } from "web3";

const web3 = new Web3("wss://ethereum-rpc.publicnode.com");

async function subscribe() {
  //create subcription
  const subcription = await web3.eth.subscribe("syncing");

  //this will return `true` when the node is syncing 
  //when it’s finished syncing will return `false`, for the `changed` event.
  subcription.on("data", (data) => console.log(data));
}

// function to unsubscribe from a subscription
async function unsubscribe(subscription) {
    await subscription.unsubscribe();
}

subscribe();
unsubscribe(subscription);
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

> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  

---
