---
layout: post
title: 钱包与账户概览
tags: blockchain
mermaid: false
math: false
---  

> 原文在[这里](https://docs.web3js.org/guides/wallet/)

## 简介

Web3.js `Wallet`是我们在想要直接使用私钥进行任何区块链操作（交易）时的主要入口点，在其它库中也被称为`Signer`。

与其它只能保存一个账户的库不同，Web3.js `Wallet`可以保存**多个账户**，每个账户都有它自己的私钥和地址。因此，无论这些密钥是在计算机的内存中还是由MetaMask保护，`Wallet`都使以太坊任务变得安全且简单。  

`web3-eth-accounts`包中包含了生成Ethereum账户、签名交易和数据的函数。  

在以太坊中，私钥是用于保护和控制以太坊地址所有权的加密密钥对中的关键部分。在公钥加密系统中，每个以太坊地址都有一对匹配的公钥和私钥。这个密钥对让我们能够拥有一个以太坊地址，管理资金，并发起交易。  

关于钱包的更多介绍，详见[这里](https://ethereum.org/en/wallets/)。  

我们可以通过不同的方式签署和发送交易：

- [本地钱包](https://docs.web3js.org/guides/wallet/local_wallet)（**强烈推荐**）
- [节点钱包](https://docs.web3js.org/guides/wallet/node_wallet)（**已弃用**）

对于它们中的每一个，我们都可以使用[Web3PromiEvent](https://docs.web3js.org/guides/wallet/promi_event)来捕捉额外的交易事件。  

## 钱包 vs 账户

在web3.js中，**账户**是一个对象，它指的是一个带有相关公钥和私钥的单独以太坊地址。而钱包是用于管理多个账户的高级结构，单个以太坊地址被视为一个账户。  

```typescript
/* 创建新账户 */
const account = web3.eth.accounts.create();

console.log(account)
/* ↳ 
{
  address: '0x9E82491d1978217d631a3b467BF912933F54788f',
  privateKey: '0x4651f9c219fc6401fe0b3f82129467c717012287ccb61950d2a8ede0687857ba',
  signTransaction: [Function: signTransaction],
  sign: [Function: sign],
  encrypt: [Function: encrypt]
}
*/
```  

在 web3.js 中，**钱包**是一个包含多个以太坊账户的数组。它提供了一种方便的方式来管理一系列账户并与之进行交互。可以将其视为用于存储和组织各种以太坊地址的数字钱包。  

```typescript
/* 创建新的钱包 */
//create a wallet with `1` random account
const wallet = web3.eth.accounts.wallet.create(1);

console.log(wallet)
/* ↳ 
Wallet(1) [
  {
    address: '0xB2D5647C03F36cA54f7d783b6Fa5afED297330d4',
    privateKey: '0x7b907534ec13b19c67c2a738fdaa69014298c71f2221d7e5dec280232e996610',
    signTransaction: [Function: signTransaction],
    sign: [Function: sign],
    encrypt: [Function: encrypt]
  },
  _accountProvider: {
    create: [Function: createWithContext],
    privateKeyToAccount: [Function: privateKeyToAccountWithContext],
    decrypt: [Function: decryptWithContext]
  },
  _addressMap: Map(1) { '0xb2d5647c03f36ca54f7d783b6fa5afed297330d4' => 0 },
  _defaultKeyName: 'web3js_wallet'
]
*/
```

## 示意图

<div align="center">
  <img src="../img/2024-04-23/diagram.jpeg" alt="diagram">
</div>

想了解更多`accounts`方法，可以访问[web3.js accounts API](https://docs.web3js.org/libdocs/Accounts)。  

想了解更多`wallet`方法，可以访问[web3.js wallet API](https://docs.web3js.org/libdocs/Wallet)。

## 发送交易

这件事最简单的方法是直接通过添加一个私钥（私钥必须以'0x'开头，并且必须有资金来执行交易）来创建一个`Wallet`。  

```typescript
/* 使用添加私钥的方式来发送交易 */
import { Web3 } from 'web3';

const web3 = new Web3('https://ethereum-sepolia.publicnode.com');

//this will create an array `Wallet` with 1 account with this privateKey
//it will generate automatically a public key for it
//make sure you have funds in this accounts
const wallet = web3.eth.accounts.wallet.add('0x152c39c430806985e4dc16fa1d7d87f90a7a1d0a6b3f17efe5158086815652e5');

const _to = '0xc7203efeb54846c149f2c79b715a8927f7334e74';
const _value = '1'; //1 wei

//the `from` address in the transaction must match the address stored in our `Wallet` array
//that's why we explicitly access it using `wallet[0].address` to ensure accuracy
const receipt = await web3.eth.sendTransaction({
  from: wallet[0].address,
  to: _to,
  value: _value,
});
//if you have more than 1 account, you can change the address by accessing to another account
//e.g, `from: wallet[1].address`

console.log('Tx receipt:', receipt);
/* ↳
Tx receipt: {
  blockHash: '0xa43b43b6e13ba47f2283b4afc15271ba07d1bba0430bd0c430f770ba7c98d054',
  blockNumber: 4960689n,
  cumulativeGasUsed: 7055436n,
  effectiveGasPrice: 51964659212n,
  from: '0xa3286628134bad128faeef82f44e99aa64085c94',
  gasUsed: 21000n,
  logs: [],
  logsBloom: '0x00000...00000000',
  status: 1n,
  to: '0xc7203efeb54846c149f2c79b715a8927f7334e74',
  transactionHash: '0xb88f3f300f1a168beb3a687abc2d14c389ac9709f18b768c90792c7faef0de7c',
  transactionIndex: 41n,
  type: 2n
}
*/
```  

## 与合约进行交互

### 写函数

要与修改或更新智能合约中数据的功能（写入功能）进行交互，我们需要创建一个`Wallet`。这个钱包至少必须持有一个帐户，且该帐户中必须有执行这些区块链操作所需的资金。  

```typescript
/* 调用智能合约的写函数 */
import { Web3 } from 'web3';

const web3 = new Web3('https://ethereum-sepolia.publicnode.com');

//create a wallet
const wallet = web3.eth.accounts.wallet.add('0x152c39c430806985e4dc16fa1d7d87f90a7a1d0a6b3f17efe5158086815652e5');

//this is how we can access to the first account of the wallet
console.log('Account 1:', wallet[0]);
/* ↳
Account 1: {
  address: '0x57CaabD59a5436F0F1b2B191b1d070e58E6449AE',
  privateKey: '0x152c39c430806985e4dc16fa1d7d87f90a7a1d0a6b3f17efe5158086815652e5',
  ...
}
*/

//instantiate the contract
const myContract = new web3.eth.Contract(ABI, CONTRACT_ADDRESS);

//interact with the contract
//wallet[0].address == '0x57CaabD59a5436F0F1b2B191b1d070e58E6449AE'
const txReceipt = await myContract.methods.doSomething().send({ from: wallet[0].address });

console.log('Transaction receipt:', txReceipt);
/* ↳
  Transaction receipt: {...}
*/
```  

### 读函数（查看）

要与查看智能合约的`public/external returns`进行交互，我们不需要实例化一个钱包，我们可以仅通过实例化智能合约和提供者来实现。  

```typescript
/* 调用智能合约的读函数 */
import { Web3 } from 'web3';

//instantiate the provider
const web3 = new Web3('https://ethereum-sepolia.publicnode.com');

//instantiate the contract
const myContract = new web3.eth.Contract(ABI, CONTRACT_ADDRESS);

//call the `view function` in the contract
const result = await myContract.methods.doSomething().call();

console.log('Result:', result)
/* ↳
  Result: ...
*/
```

## 钱包方法

下面罗列出`web3.th.accounts.wallet`包中提供的`Wallet`[方法](https://docs.web3js.org/libdocs/Wallet)：  

- [add](https://docs.web3js.org/libdocs/Wallet#add)：使用私钥或者账户对象添加一个账户到钱包中。
- [clear](https://docs.web3js.org/libdocs/Wallet#clear)：安全地清空钱包并移除其中的所有账户。**谨慎使用，因为该操作会删除本地钱包中的所有账户**。
- [create](https://docs.web3js.org/libdocs/Wallet#create)：在钱包中生成一个或多个账户。如果钱包已存在，它们并不会被覆盖。
- [decrypt](https://docs.web3js.org/libdocs/Wallet#decrypt)：解密keystore v3对象。
- [encrypt](https://docs.web3js.org/libdocs/Wallet#encrypt)：加密钱包中的所有账户到一个已加密的keystore v3对象中。
- [get](https://docs.web3js.org/libdocs/Wallet#get)：获取指定账户在钱包中的索引或其公钥地址。
- [load](https://docs.web3js.org/libdocs/Wallet#load)：从本地存储中导入钱包并对其解密。**注意**：仅浏览器支持。
- [remove](https://docs.web3js.org/libdocs/Wallet#remove)：从钱包中移除指定账户。
- [save](https://docs.web3js.org/libdocs/Wallet#save)：以字符串的形式将加密后的钱包存储到本地存储中。**注意**：仅浏览器支持。
- [getStorage](https://docs.web3js.org/libdocs/Wallet#getStorage)：获取浏览器的存储对象。

## 账户方法

下面罗列出`web3.th.accounts`包中提供的`Accounts`[方法](https://docs.web3js.org/libdocs/Wallet)： 

- [create](https://docs.web3js.org/libdocs/Accounts#create)：生成并返回一个包括私钥和公钥的Web3Account对象。在创建私钥时，它使用了一个经过审计的包`ethereum-cryptography/secp256k1`，该包是具有特定特性的加密安全随机数。了解更多：[https://www.npmjs.com/package/ethereum-cryptography#secp256k1-curve](https://www.npmjs.com/package/ethereum-cryptography#secp256k1-curve)
- [decrypt](https://docs.web3js.org/libdocs/Accounts#decrypt)：解密 v3 keystore JSON，并创建账户。
- [encrypt](https://docs.web3js.org/libdocs/Accounts#encrypt)：使用密码加密私钥并返回一个V3 JSON Keystore，详见[https://github.com/ethereum/wiki/wiki/Web3-Secret-Storage-Definition](https://github.com/ethereum/wiki/wiki/Web3-Secret-Storage-Definition)。
- [hashMessage](https://docs.web3js.org/libdocs/Accounts#hashMessage)：将给定的消息进行哈希处理。数据将被UTF-8 HEX解码并按以下方式封装：“\x19Ethereum Signed Message:\n” + 消息长度 + 消息，并使用keccak256进行哈希处理。
- [parseAndValidatePrivateKey](https://docs.web3js.org/libdocs/Accounts#parseAndValidatePrivateKey)：获取验证后的私钥 Uint8Array。注意：此功能不通过主web3包导出，因此要直接使用它，请从账户包中导入。
- [privateKeyToAccount](https://docs.web3js.org/libdocs/Accounts#privateKeyToAccount)：从私钥中获取账户。
- [privateKeyToAddress](https://docs.web3js.org/libdocs/Accounts#privateKeyToAddress)：从私钥中获取以太坊地址。
- [privateKeyToPublicKey](https://docs.web3js.org/libdocs/Accounts#privateKeyToPublicKey)：从私钥中获取公钥。
- [recover](https://docs.web3js.org/libdocs/Accounts#recover)：恢复用于签署给定数据的以太坊地址。
- [recoverTransaction](https://docs.web3js.org/libdocs/Accounts#recoverTransaction)：恢复用于签署给定RLP编码交易的以太坊地址。
- [sign](https://docs.web3js.org/libdocs/Accounts#sign)：使用私钥对给定的任意数据进行签名。
- [signTransaction](https://docs.web3js.org/libdocs/Accounts#signTransaction)：使用私钥对给定的以太坊交易进行签名。

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
