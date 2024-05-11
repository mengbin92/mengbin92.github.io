---
layout: post
title: 开始使用eth包
tags: [blockchain, web3.js]
mermaid: false
math: false
---  

> 原文在[这里](https://docs.web3js.org/guides/web3_eth/eth)

## 简介 

`web3-eth`包提供了一套强大的功能，可以与以太坊区块链和智能合约进行交互。在本教程中，我们将指导您如何使用web3.js版本4的`web3-eth`包的基础知识。我们将在整个示例中使用TypeScript。  

## 步骤 1：配置环境

在我们开始编写和部署我们的合约之前，我们需要设置我们的环境。为此，我们需要安装以下内容：

1. Ganache - Ganache是一个用于以太坊开发的个人区块链，它允许你看到你的智能合约在现实世界场景中的功能。你可以从[http://truffleframework.com/ganache](http://truffleframework.com/ganache)下载它
2. Node.js - Node.js是一个JavaScript运行时环境，允许你在服务器端运行JavaScript。你可以从[https://nodejs.org/en/download/](https://nodejs.org/en/download/)下载它
3. npm - Node Package Manager用于发布和安装到公共npm注册表或私有npm注册表的包。这是如何安装它的方法[https://docs.npmjs.com/downloading-and-installing-node-js-and-npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)。（或者，你可以使用yarn代替npm [https://classic.yarnpkg.com/lang/en/docs/getting-started/](https://classic.yarnpkg.com/lang/en/docs/getting-started/)） 

## 步骤 2：创建一个新的项目目录并初始化一个新的Node.js项目

首先，为你的项目创建一个新的项目目录，并导航到该目录：  

```bash
$ mkdir smart-contract-tutorial
$ cd smart-contract-tutorial
```  

然后使用`npm`初始化项目：  

```bash
$ npm init -y 
``` 

这将在你的项目目录中创建一个新的`package.json`文件。   

```bash
$ npm i typescript @types/node
```  

这将为我们的项目安装typescript。  

## 步骤3：设置web3.js并连接到Ganache网络

在这一步，我们将设置web3.js库并连接到Ganache网络。所以，如果你还没有运行Ganache，一定要运行。

首先，使用npm安装`web3`包：  

```bash
$ npm i web3
```  

接下来，在你的项目目录中创建一个名为`index.ts`的新文件，并向其中添加以下代码：  

```typescript
import { Web3 } from 'web3';

// Set up a connection to the Ganache network
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));
/* NOTE:
instead of using ganache, you can also interact with a testnet/mainnet using another provider
https://app.infura.io/
https://dashboard.alchemy.com/
or use a public provider https://chainlist.org/
*/

// Log the current block number to the console
const block = await web3.eth.getBlockNumber();

console.log('Last block:', block);
// ↳ Last block: 4975299n
```  

这段代码建立了与Ganache网络的连接，并将当前的区块号记录到控制台。

运行以下命令来测试连接：

```bash
$ npx ts-node index.ts
```

如果一切正常，你应该能在控制台看到当前的区块号。然而，如果你得到了一个错误，原因是`connect ECONNREFUSED 127.0.0.1:7545`，那么请再次检查你是否在本地的`7545`端口上运行Ganache。  

## 步骤4：使用web3.js将智能合约部署到Ganache网络

在这一步，我们将使用web3.js将智能合约部署到Ganache网络。

在第一个例子中，我们将发送一个简单的交易。创建一个名为`transaction.ts`的文件，并用以下代码填充它：  

```typescript
import { Web3 } from 'web3';
import fs from 'fs';
import path from 'path';

// Set up a connection to the Ethereum network
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));
web3.eth.Contract.handleRevert = true;

async function interact() {
  //fetch all the available accounts
  const accounts = await web3.eth.getAccounts();
  console.log(accounts);

  let balance1, balance2;
  //The initial balances of the accounts should be 100 Eth (10^18 wei)
  balance1 = await web3.eth.getBalance(accounts[0]);
  balance2 = await web3.eth.getBalance(accounts[1]);

  console.log(balance1, balance2);

  //create a transaction sending 1 Ether from account 0 to account 1
  const transaction = {
    from: accounts[0],
    to: accounts[1],
    // value should be passed in wei. For easier use and to avoid mistakes,
    //	we utilize the auxiliary `toWei` function:
    value: web3.utils.toWei('1', 'ether'),
  };

  //send the actual transaction
  const transactionHash = await web3.eth.sendTransaction(transaction);
  console.log('transactionHash', transactionHash);

  balance1 = await web3.eth.getBalance(accounts[0]);
  balance2 = await web3.eth.getBalance(accounts[1]);

  // see the updated balances
  console.log(balance1, balance2);

  // irrelevant with the actual transaction, just to know the gasPrice
  const gasPrice = await web3.eth.getGasPrice();
  console.log(gasPrice);
}

(async () => {
  await interact();
})();
```  

> 重要信息
> 当使用Ganache运行本地开发区块链时，所有账户通常默认解锁，允许在开发和测试期间轻松访问和执行交易。这意味着可以在不需要私钥或密码短语的情况下访问这些账户。这就是为什么我们在示例中只用`from`字段指示账户。  

运行下面的命令：  

```bash
$ npx ts-node transaction.ts
```  

如果一切正常，你应该会看到如下内容：  

```typescript
[
  '0xc68863f36C48ec168AD45A86c96347D520eac1Cf',
  '0x80c05939B307f9833d905A685575b45659d3EA70',
  '0xA260Cf742e03B48ea1A2b76b0d20aaCfe6F85E5E',
  '0xf457b8C0CBE41e2a85b6222A97b7b7bC6Df1C0c0',
  '0x32dF9a0B365b6265Fb21893c551b0766084DDE21',
  '0x8a6A2b8b00C1C8135F1B25DcE54f73Ee18bEF43d',
  '0xAFc526Be4a2656f7E02501bdf660AbbaA8fb3d7A',
  '0xc32618116370fF776Ecd18301c801e146A1746b3',
  '0xDCCD49880dCf9603835B0f522c31Fcf0579b46Ff',
  '0x036006084Cb62b7FAf40B979868c0c03672a59B5'
]
100000000000000000000n 100000000000000000000n

transactionHash {
  transactionHash: '0xf685b64ccf5930d3779a33335ca22195b68901dbdc439f79dfc65d87c7ae88b0',
  transactionIndex: 0n,
  blockHash: '0x5bc044ad949cfd32ea4cbb249f0292e7dded44c3b0f599236c6d20ddaa96cc06',
  blockNumber: 1n,
  from: '0xc68863f36c48ec168ad45a86c96347d520eac1cf',
  to: '0x80c05939b307f9833d905a685575b45659d3ea70',
  gasUsed: 21000n,
  cumulativeGasUsed: 21000n,
  logs: [],
  status: 1n,
  logsBloom: '0x......000'
}

98999580000000000000n 101000000000000000000n

20000000000n
```  

> 注意事项
> 为了计算实际花费的以太币，我们需要计算发送的值加上费用。初始余额 = (剩余余额 + 值 + gasUsed*gasPrice)。在我们的情况下：
>
> 98999580000000000000 + 1000000000000000000 + (20000000000*21000) = 100 Ether

在下一个示例中，我们将使用`estimateGas`函数来查看合约部署预期的gas。（关于合约的更多信息，请参阅相应的教程）。创建一个名为`estimate.ts`的文件，并用以下代码填充它：  

```typescript
import { Web3, ETH_DATA_FORMAT, DEFAULT_RETURN_FORMAT } from 'web3';

async function estimate() {
  // abi of our contract
  const abi = [
    {
      inputs: [{ internalType: 'uint256', name: '_myNumber', type: 'uint256' }],
      stateMutability: 'nonpayable',
      type: 'constructor',
    },
    {
      inputs: [],
      name: 'myNumber',
      outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
      stateMutability: 'view',
      type: 'function',
    },
    {
      inputs: [{ internalType: 'uint256', name: '_myNumber', type: 'uint256' }],
      name: 'setMyNumber',
      outputs: [],
      stateMutability: 'nonpayable',
      type: 'function',
    },
  ];

  const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));

  //get the available accounts
  const accounts = await web3.eth.getAccounts();
  let acc = await accounts[0];

  let contract = new web3.eth.Contract(abi);

  const deployment = contract.deploy({
    data: '0x608060405234801561001057600080fd5b506040516101d93803806101d983398181016040528101906100329190610054565b806000819055505061009e565b60008151905061004e81610087565b92915050565b60006020828403121561006657600080fd5b60006100748482850161003f565b91505092915050565b6000819050919050565b6100908161007d565b811461009b57600080fd5b50565b61012c806100ad6000396000f3fe6080604052348015600f57600080fd5b506004361060325760003560e01c806323fd0e401460375780636ffd773c146051575b600080fd5b603d6069565b6040516048919060bf565b60405180910390f35b6067600480360381019060639190608c565b606f565b005b60005481565b8060008190555050565b60008135905060868160e2565b92915050565b600060208284031215609d57600080fd5b600060a9848285016079565b91505092915050565b60b98160d8565b82525050565b600060208201905060d2600083018460b2565b92915050565b6000819050919050565b60e98160d8565b811460f357600080fd5b5056fea2646970667358221220d28cf161457f7936995800eb9896635a02a559a0561bff6a09a40bfb81cd056564736f6c63430008000033',
    // @ts-expect-error
    arguments: [1],
  });

  let estimatedGas = await deployment.estimateGas({ from: acc }, DEFAULT_RETURN_FORMAT);
  // the returned data will be formatted as a bigint

  console.log('Default format:', estimatedGas);

  estimatedGas = await deployment.estimateGas({ from: acc }, ETH_DATA_FORMAT);
  // the returned data will be formatted as a hexstring

  console.log('Eth format:', estimatedGas);
}

(async () => {
  await estimate();
})();
```  

运行下面的命令：  

```bash
$ npx ts-node estimate.ts
```  

如果一切正常，你应该会看到如下内容：  

```typescript
Default format: 140648n
Eth format: 0x22568
```  

> 注意事项
> 从web3.js返回的数字默认以`BigInt`格式返回。在这个例子中，我们使用了`ETH_DATA_FORMAT`参数，它可以在web3.js的大多数方法中传递，以便以十六进制格式化结果。

在下一个示例中，我们将签署一个交易，并使用`sendSignedTransaction`来发送已签署的交易。创建一个名为`sendSigned.ts`的文件，并用以下代码填充它：  

```typescript
import { Web3 } from 'web3';
const web3 = new Web3('http://localhost:7545');

//make sure to copy the private key from ganache
const privateKey = '0x0fed6f64e01bc9fac9587b6e7245fd9d056c3c004ad546a17d3d029977f0930a';
const value = web3.utils.toWei('1', 'ether');

async function sendSigned() {
  const accounts = await web3.eth.getAccounts();
  const fromAddress = accounts[0];
  const toAddress = accounts[1];
  // Create a new transaction object
  const tx = {
    from: fromAddress,
    to: toAddress,
    value: value,
    gas: 21000,
    gasPrice: web3.utils.toWei('10', 'gwei'),
    nonce: await web3.eth.getTransactionCount(fromAddress),
  };

  // Sign the transaction with the private key
  const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);

  // Send the signed transaction to the network
  const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

  console.log('Transaction receipt:', receipt);
}
(async () => {
  await sendSigned();
})();
```  

运行下面的命令：  

```bash
$ npx ts-node sendSigned.ts
```  

如果一切正常，你应该会看到如下内容： 

```typescript
Transaction receipt: {
  transactionHash: '0x742df8f1ad4d04f6e5632889109506dbb7cdc8a6a1c80af3dfdfc71a67a04ddc',
  transactionIndex: 0n,
  blockNumber: 1n,
  blockHash: '0xab6678d76499b0ee383f182ab8f848ba27bd787e70e227524255c86b25224ed3',
  from: '0x66ce32a5200aac57b258c4eac26bc1493fefddea',
  to: '0x0afcfc43ac454348d8170c77b1f912b518b4ebe8',
  cumulativeGasUsed: 21000n,
  gasUsed: 21000n,
  logs: [],
  logsBloom: '0x...0000',
  status: 1n,
  effectiveGasPrice: 10000000000n,
  type: 2n
}
```  

## 步骤5：导入指定的包

为了利用web3-eth包的功能，你可以选择直接导入这个包，而不是依赖全局的web3包，这将会减小构建大小。  

### 直接导入web3-eth 

例如使用[getBalance](https://docs.web3js.org/api/web3-eth/function/getBalance)方法：  

```typescript
import { Web3Eth } from 'web3-eth';

const eth = new Web3Eth('http://localhost:7545');

async function test() {
	const accounts = await eth.getAccounts();
	const currentBalance = await eth.getBalance(accounts[0]);
	console.log('Current balance:', currentBalance);
	// 115792089237316195423570985008687907853269984665640564039437613106102441895127n
}

(async () => {
	await test();
})();
```  

### 直接将配置设置到web3-eth包中  

```typescript
import { Web3Eth } from 'web3-eth';

const eth = new Web3Eth('http://localhost:8545');

console.log('defaultTransactionType before', eth.config.defaultTransactionType);
// defaultTransactionType before 0x0

eth.setConfig({ defaultTransactionType: '0x1' });

console.log('eth.config.defaultTransactionType after', eth.config.defaultTransactionType);
// defaultTransactionType before 0x1
```  

## 步骤6：发送不同类型的交易

### 传统交易

在以太坊中，'传统交易'通常指的是传统的交易，其中燃气费由发送者明确设定，并且可以根据网络需求波动。这些传统交易在实施以太坊改进提案(EIP) 1559之前在以太坊网络上非常普遍。

传统交易的主要特点包括：

1. 燃气价格：在传统交易中，发送者指定他们愿意为交易消耗的每单位燃气支付的燃气价格（以Gwei计）。燃气价格可以由发送者调整，它决定了交易被矿工处理的优先级。更高的燃气价格意味着更快的交易确认。
2. 燃气限制：发送者还设定了一个燃气限制，这是交易可以消耗的最大燃气量。燃气是用于在以太坊网络上执行交易和智能合约的计算燃料。主要设定燃气限制是为了确保发送者在处理交易时不会耗尽以太币。它也可能影响交易的成功或失败。
3. 费用不确定性：传统交易受到基于网络拥堵的燃气价格波动的影响。在需求高的时期，燃气价格可能会飙升，导致用户为他们的交易被及时处理而支付更多的费用。相反，在网络较为安静的时期，用户可以支付较低的费用。
4. 手动费用估算：用户负责手动估算在他们的传统交易中包含的适当的燃气价格，以确保及时处理。这个过程可能很具挑战性，因为设定的燃气价格过低可能导致确认慢，而设定的价格过高可能导致过度支付。
5. 如下所述的EIP-1559引入了对以太坊交易费用系统的改变，使其更加用户友好和可预测。在EIP-1559中，'基础费用'的概念取代了手动设定燃气价格，这减少了与传统交易相关的一些不确定性。

虽然EIP-1559大大改善了用户体验，但传统交易仍然在以太坊网络上得到支持，用户如果愿意，可以继续发送带有手动指定的燃气价格和燃气限制的交易。然而，EIP-1559机制现在是大多数交易的推荐方法，因为它简化了过程，减少了过度支付费用的可能性。

要发送传统交易，请使用下面的代码：  

```typescript
import { Web3 } from 'web3';

const web3 = new Web3('http://localhost:8545');

async function test() {
  const privateKey = 'YOUR PRIVATE KEY HERE';
  // add private key to wallet to have auto-signing transactions feature
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);

  // create transaction object
  const tx = {
    from: account.address,
    to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
    value: '0x1',
    gas: BigInt(21000),
    gasPrice: await web3.eth.getGasPrice(),
    type: BigInt(0), // <- specify type
  };

  // send transaction
  const receipt = await web3.eth.sendTransaction(tx);

  console.log('Receipt:', receipt);
  // Receipt: {
  //   blockHash: '0xc0f2fea359233b0843fb53255b8a7f42aa7b1aff53da7cbe78c45b5bac187ad4',
  //   blockNumber: 21n,
  //   cumulativeGasUsed: 21000n,
  //   effectiveGasPrice: 2569891347n,
  //   from: '0xe2597eb05cf9a87eb1309e86750c903ec38e527e',
  //   gasUsed: 21000n,
  //   logs: [],
  //   logsBloom: '0x0...00000',
  //   status: 1n,
  //   to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
  //   transactionHash: '0x0ffe880776f5631e4b64caf521bd01cd816dd2cc29e533bc56f392211856cf9a',
  //   transactionIndex: 0n,
  //   type: 0n
  // }
}
(async () => {
  await test();
})();
```  

### EIP-2930交易  

以太坊改进提案2930是对以太坊网络的一项改变提案，该提案作为柏林硬分叉的一部分实施，于2021年4月激活。EIP-2930引入了一个名为“交易类型和访问列表”的功能。这项改进提高了某些智能合约交互的燃气效率，并在指定谁可以访问智能合约内特定资源方面提供了更多的灵活性。以下是EIP-2930的主要组成部分：

1. 交易类型：EIP-2930引入了一种新的交易类型，称为“访问列表交易”。这种交易类型旨在通过允许发送者指定可能在交易过程中被访问或修改的地址列表，使与智能合约的某些交互更加高效。
2. 访问列表：访问列表是与交易一起包含的结构化数据格式。它包含了预期在交易执行过程中被访问或修改的地址和存储键的列表。这有助于减少这些操作所需的燃气量，因为矿工可以检查访问列表以优化执行。
3. 燃气节省：EIP-2930旨在显著降低使用访问列表功能的交易的燃气成本。通过指定与交易相关的存储槽和地址，它允许更有效地使用燃气，特别是在与具有大状态的智能合约的交互中。
4. 合约交互：这项改进在与具有复杂状态结构的合约交互时特别有用，因为它最小化了从特定存储槽读取或写入所需的燃气。这可以为用户节省成本，并使某些交互更加实用。

EIP-2930是以太坊持续努力提高网络效率和降低交易成本的一部分，使其对去中心化应用和用户更加可接入和可扩展。它对于与依赖特定存储操作和访问控制机制的有状态合约的交互特别有益。

要发送EIP-2930交易，请使用下面的代码：  

```typescript
import {Web3} from 'web3';

const web3 = new Web3('http://localhost:8545');

async function test() {
  const privateKey = 'YOUR PRIVATE KEY HERE';
  // add private key to wallet to have auto-signing transactions feature
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);

  // create transaction object
  const tx = {
    from: account.address,
    to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
    value: '0x1',
    gasLimit: BigInt(21000),
    type: BigInt(1), // <- specify type
    // gasPrice - you can specify this property directly or web3js will fill this field automatically
  };

  // send transaction
  const receipt = await web3.eth.sendTransaction(tx);

  console.log('Receipt:', receipt);
  // Receipt: {
  //   blockHash: '0xd8f6a3638112d17b476fd1b7c4369d473bc1a484408b6f39dbf64410df44adf6',
  //   blockNumber: 24n,
  //   cumulativeGasUsed: 21000n,
  //   effectiveGasPrice: 2546893579n,
  //   from: '0xe2597eb05cf9a87eb1309e86750c903ec38e527e',
  //   gasUsed: 21000n,
  //   logs: [],
  //   logsBloom: '0x...0000',
  //   status: 1n,
  //   to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
  //   transactionHash: '0xd1d682b6f6467897db5b8f0a99a6be2fb788d32fbc1329b568b8f6b2c15e809a',
  //   transactionIndex: 0n,
  //   type: 1n
  // }
}
(async () => {
  await test();
})();
```  

以下是在交易中使用访问列表的示例。

> 注意
> 你可以在这里找到`Greeter`合约的代码

```typescript
import {Web3} from 'web3';

import { GreeterAbi, GreeterBytecode } from './fixture/Greeter';

const web3 = new Web3('http://localhost:8545');

async function test() {
  const privateKey = 'YOUR PRIVATE KEY HERE';
  // add private key to wallet to have auto-signing transactions feature
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);

  // deploy contract
  const contract = new web3.eth.Contract(GreeterAbi);
  const deployedContract = await contract
    .deploy({
      data: GreeterBytecode,
      arguments: ['My Greeting'],
    })
    .send({ from: account.address });
  deployedContract.defaultAccount = account.address;

  const transaction = {
    from: account.address,
    to: deployedContract.options.address,
    data: '0xcfae3217', // greet function call data encoded
  };
  const { accessList } = await web3.eth.createAccessList(transaction, 'latest');

  console.log('AccessList:', accessList);
  // AccessList: [
  //   {
  //     address: '0xce1f86f87bd3b8f32f0fb432f88e848f3a957ed7',
  //     storageKeys: [
  //       '0x0000000000000000000000000000000000000000000000000000000000000001'
  //     ]
  //   }
  // ]

  // create transaction object with accessList
  const tx = {
    from: account.address,
    to: deployedContract.options.address,
    gasLimit: BigInt(46000),
    type: BigInt(1), // <- specify type
    accessList,
    data: '0xcfae3217',
    // gasPrice - you can specify this property directly or web3js will fill this field automatically
  };

  // send transaction
  const receipt = await web3.eth.sendTransaction(tx);

  console.log('Receipt:', receipt);
  // Receipt: {
  //   blockHash: '0xc7b9561100c8ff6f1cde7a05916e86b7d037b2fdba86b0870e842d1814046e4b',
  //   blockNumber: 43n,
  //   cumulativeGasUsed: 26795n,
  //   effectiveGasPrice: 2504325716n,
  //   from: '0xe2597eb05cf9a87eb1309e86750c903ec38e527e',
  //   gasUsed: 26795n,
  //   logs: [],
  //   logsBloom: '0x...00000000000',
  //   status: 1n,
  //   to: '0xce1f86f87bd3b8f32f0fb432f88e848f3a957ed7',
  //   transactionHash: '0xa49753be1e2bd22c2a8e2530726614c808838bb0ebbed72809bbcb34f178799a',
  //   transactionIndex: 0n,
  //   type: 1n
  // }
}
(async () => {
  await test();
})();
```  

### EIP-1559交易

以太坊改进提案1559是对以太坊网络费用市场和交易定价机制的重大升级。它作为以太坊伦敦硬分叉的一部分实施，该硬分叉于2021年8月发生。EIP-1559引入了几项改变以太坊区块链上交易费用工作方式的变化，其主要目标是改善用户体验和网络效率。

以下是EIP-1559引入的一些关键特性和变化：

1. 基础费用：EIP-1559引入了一个名为“基础费用”的概念。基础费用是交易被包含在区块中所需的最低费用。它由网络通过算法确定，并根据网络拥堵动态调整。当网络繁忙时，基础费用增加，当网络拥堵较少时，基础费用减少。
2. 包含费用：除基础费用外，用户可以自愿包含一个“小费”或“包含费用”以激励矿工将他们的交易包含在下一个区块中。这允许用户通过向矿工提供小费来加快他们的交易。
3. 可预测的费用：有了EIP-1559，用户有更可预测的方式来估算交易费用。他们可以设定他们愿意支付的最高费用，包括基础费用和小费。这消除了用户需要猜测适当的燃气价格的需要。
4. 销毁机制：EIP-1559引入了一种机制，通过该机制，基础费用从流通中“销毁”，减少了以太币（ETH）的总供应量。这种通缩机制可以帮助解决一些与ETH供应量增加相关的问题，并可能使其成为更好的价值储存。
5. 改进的费用拍卖：在EIP-1559下，费用拍卖更有效。用户指定他们愿意支付的最高费用，协议自动调整小费，以确保交易得到及时处理，而不会过度支付。
6. 更简单的交易过程：用户体验到一个简化的交易过程，因为他们不必手动设定燃气价格。相反，他们指定他们愿意支付的最高费用，钱包软件处理其余的事情。

EIP-1559因其创建更用户友好和高效的交易费用系统的潜力而受到好评，使以太坊网络对用户更加可接入和可预测。它也被视为过渡到以太坊2.0的重要步骤，以太坊2.0旨在解决网络上的可扩展性和可持续性挑战。

要发送EIP-1559交易，请使用下面的代码：  

```typescript
import { Web3 } from 'web3';

const web3 = new Web3('http://localhost:8545');

async function test() {
  const privateKey = 'YOUR PRIVATE KEY HERE';
  // add private key to wallet to have auto-signing transactions feature
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);

  // create transaction object
  const tx = {
    from: account.address,
    to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
    value: '0x1',
    gasLimit: BigInt(21000),
    type: BigInt(2), // <- specify type
    // maxFeePerGas - you can specify this property directly or web3js will fill this field automatically
    // maxPriorityFeePerGas - you can specify this property directly or web3js will fill this field automatically
  };

  // send transaction
  const receipt = await web3.eth.sendTransaction(tx);

  console.log('Receipt:', receipt);
  // Receipt: {
  //   blockHash: '0xfe472084d1471720b6887071d32a793f7c4576a489098e7d2a89aef205c977fb',
  //   blockNumber: 23n,
  //   cumulativeGasUsed: 21000n,
  //   effectiveGasPrice: 2546893579n,
  //   from: '0xe2597eb05cf9a87eb1309e86750c903ec38e527e',
  //   gasUsed: 21000n,
  //   logs: [],
  //   logsBloom: '0x0000...00000000000',
  //   status: 1n,
  //   to: '0x27aa427c1d668ddefd7bc93f8857e7599ffd16ab',
  //   transactionHash: '0x5c7a3d2965b426a5776e55f049ee379add44652322fb0b9fc2f7f57b38fafa2a',
  //   transactionIndex: 0n,
  //   type: 2n
  // }
}
(async () => {
  await test();
})();
```  

## 结论

在这个教程中，我们学习了如何使用`web3-eth`包提供的不同方法。

有了这些知识，你可以开始尝试使用以太坊区块链。请记住，这只是开始，关于以太坊和web3.js还有很多需要学习的内容。所以继续探索和建设，玩得开心！

Web3.js 4.x版本为与以太坊网络交互和构建去中心化应用提供了强大且易于使用的接口。并且它已经用TypeScript重写，但为了简化这个教程，我们用JavaScript与它交互。

以太坊生态系统正在不断发展，总是有更多的东西可以学习和发现。当你继续发展你的技能和知识时，继续探索和尝试新的技术和工具，构建创新和去中心化的解决方案。  

## 提示和最佳实践

- 在将智能合约部署到主网之前，始终在本地网络（如Ganache或Hardhat）上测试你的智能合约。
- 使用最新版本的web3.js和Solidity，以利用最新的功能和安全补丁。
- 保护好你的私钥，切勿与任何人分享。
- 谨慎使用燃气限制和燃气价格参数，以避免在交易费用上花费过多。
- 在将交易发送到网络之前，使用web3.js中的`estimateGas`函数来估算交易所需的燃气。
- 使用事件来通知客户端应用程序关于智能合约状态的更改。
- 使用像Solhint这样的linter来检查常见的Solidity编码错误。

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
