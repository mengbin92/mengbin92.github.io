---
layout: post
title: 教程：部署并与智能合约交互
tags: [blockchain, web3.js]
mermaid: false
math: false
---  

原文在[这里](https://docs.web3js.org/guides/smart_contracts/smart_contracts_guide)

## 介绍

在本教程中，我们将详细介绍将智能合约部署到以太坊网络，生成ABI，并使用web3.js版本4.x与智能合约进行交互的过程。我们将介绍以太坊、Solidity和web3.js的基本概念，并提供使用Ganache将简单的智能合约部署到测试网络的逐步指导。

## 概述

以下是我们在本教程中将要进行的步骤的高级概述：

1. 设置环境
2. 创建一个新的项目目录并初始化一个新的Node.js项目。
3. 编写智能合约的Solidity代码并将其保存到一个文件中。
4. 使用Solidity编译器编译Solidity代码并获取其ABI和字节码。
5. 设置web3.js库并连接到Ganache网络。
6. 使用web3.js将智能合约部署到Ganache网络。
7. 使用web3.js与智能合约进行交互。  

> TIP 
> **社区支持**：如果在遵循本指南时遇到任何问题或有任何疑问，不要犹豫，寻求帮助。我们友好的社区随时准备帮助您！加入我们的[Discord](https://discord.gg/F4NUfaCC)服务，前往 **\#web3js-general**频道，与其他开发者建立联系，获取您需要的支持。

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

## 步骤3：编写智能合约的Solidity代码并将其保存到文件中
在这一步，我们将编写智能合约的Solidity代码，并将其保存为我们项目目录中的文件。

在你的项目目录中创建一个名为`MyContract.sol`的新文件，并向其中添加以下Solidity代码：

```solidity 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MyContract {
	uint256 public myNumber;

	constructor(uint256 _myNumber) {
		myNumber = _myNumber;
	}

	function setMyNumber(uint256 _myNumber) public {
		myNumber = _myNumber;
	}
}
```

这个简单的智能合约定义了一个可以通过调用`setMyNumber`函数来设置的`myNumber`变量。  

## 步骤4：使用Solidity编译器编译Solidity代码，并获取其ABI和字节码

> 提示
> 或者，你可以使用类似于`npm i solc && npx solcjs MyContract.sol --bin --abi`的命令。然后将文件重命名为`MyContractBytecode.bin`和`MyContractAbi.json`，以便与本教程后面将使用的文件保持一致。更多关于solc-js的信息在[https://github.com/ethereum/solc-js](https://github.com/ethereum/solc-js)。

> 提示
> 如果你使用web3.js插件：[https://www.npmjs.com/package/web3-plugin-craftsman](https://www.npmjs.com/package/web3-plugin-craftsman)，你完全可以跳过手动编译Solidity代码的步骤，该插件会在内部编译Solidity代码，并使你能够直接从其Solidity代码与智能合约进行交互。

在这一步，我们将使用Solidity编译器（solc）来编译Solidity代码并生成编译后的代码。

首先，使用npm安装`solc`包。  

> 注意
> 指定一个与你在上面的.sol文件中指定的版本（使用`pragma solidity ^0.8.0;`）兼容的编译器版本：

```bash
$ npm i solc@0.8.0
```

接下来，在你的项目目录中创建一个名为`compile.js`的新文件，并向其中添加以下代码：

```javascript
// This code will compile smart contract and generate its ABI and bytecode
// Alternatively, you can use something like `npm i solc && npx solcjs MyContract.sol --bin --abi`

import solc from 'solc';
import path from 'path';
import fs from 'fs';

const fileName: string = 'MyContract.sol';
const contractName: string = 'MyContract';

// Read the Solidity source code from the file system
const contractPath: string = path.join(__dirname, fileName);
const sourceCode: string = fs.readFileSync(contractPath, 'utf8');

// solc compiler config
const input = {
	language: 'Solidity',
	sources: {
		[fileName]: {
			content: sourceCode,
		},
	},
	settings: {
		outputSelection: {
			'*': {
				'*': ['*'],
			},
		},
	},
};

// Compile the Solidity code using solc
const compiledCode = JSON.parse(solc.compile(JSON.stringify(input)));

// Get the bytecode from the compiled contract
const bytecode: string = compiledCode.contracts[fileName][contractName].evm.bytecode.object;

// Write the bytecode to a new file
const bytecodePath: string = path.join(__dirname, 'MyContractBytecode.bin');
fs.writeFileSync(bytecodePath, bytecode);

// Log the compiled contract code to the console
console.log('Contract Bytecode:\n', bytecode);

// Get the ABI from the compiled contract
const abi: any[] = compiledCode.contracts[fileName][contractName].abi;

// Write the Contract ABI to a new file
const abiPath: string = path.join(__dirname, 'MyContractAbi.json');
fs.writeFileSync(abiPath, JSON.stringify(abi, null, '\t'));

// Log the Contract ABI to the console
console.log('Contract ABI:\n', abi);
```  

这段代码从`MyContract.sol`文件中读取Solidity代码，使用`solc`进行编译，并为智能合约生成ABI和字节码。然后，它将字节码写入一个名为`MyContractBytecode.bin`的新文件，并将合约ABI写入`MyContractAbi.json`。并将它们记录到控制台。

运行以下命令来编译Solidity代码：  

```bash
$ npm compile.js
```  

如果一切正常，你应该会看到合约字节码和合约ABI都被记录到控制台。

> 提示
> 还有其他几种获取字节码和ABI的方法，比如使用Remix，在编译智能合约后检查编译详情（[https://remix-ide.readthedocs.io/en/latest/run.html#using-the-abi-with-ataddress](https://remix-ide.readthedocs.io/en/latest/run.html#using-the-abi-with-ataddress)）。

## 步骤5：设置web3.js并连接到Ganache网络

在这一步，我们将设置web3.js库并连接到Ganache网络。所以，如果你还没有运行Ganache，一定要运行。

首先，使用npm安装`web3`包：  

```bash
$ npm i web3
```  

接下来，在你的项目目录中创建一个名为`index.js`的新文件，并向其中添加以下代码：  

```javascript
import { Web3 } from 'web3';

// Set up a connection to the Ganache network
const web3: Web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));

// Log the current block number to the console
web3.eth
	.getBlockNumber()
	.then((result: number) => {
		console.log('Current block number: ' + result);
	})
	.catch((error: Error) => {
		console.error(error);
	});
```  

这段代码建立了与Ganache网络的连接，并将当前的区块号记录到控制台。

运行以下命令来测试连接：

```bash
$ node index.js
```

如果一切正常，你应该能在控制台看到当前的区块号。然而，如果你得到了一个错误，原因是`connect ECONNREFUSED 127.0.0.1:7545`，那么请再次检查你是否在本地的`7545`端口上运行Ganache。  

## 步骤6：使用web3.js将智能合约部署到Ganache网络

在这一步，我们将使用web3.js将智能合约部署到Ganache网络。

创建一个名为`deploy.js`的文件，并用以下代码填充它：  

```javascript
// For simplicity we use `web3` package here. However, if you are concerned with the size,
//	you may import individual packages like 'web3-eth', 'web3-eth-contract' and 'web3-providers-http'.
import { Web3 } from 'web3';
import fs from 'fs';
import path from 'path';

const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));

const bytecodePath: string = path.join(__dirname, 'MyContractBytecode.bin');
const bytecode: string = fs.readFileSync(bytecodePath, 'utf8');

const abi: any = require('./MyContractAbi.json');
const myContract: any = new web3.eth.Contract(abi);
myContract.handleRevert = true;

async function deploy(): Promise<void> {
	const providersAccounts: string[] = await web3.eth.getAccounts();
	const defaultAccount: string = providersAccounts[0];
	console.log('deployer account:', defaultAccount);

	const contractDeployer: any = myContract.deploy({
		data: '0x' + bytecode,
		arguments: [1],
	});

	const gas: number = await contractDeployer.estimateGas({
		from: defaultAccount,
	});
	console.log('estimated gas:', gas);

	try {
		const tx: any = await contractDeployer.send({
			from: defaultAccount,
			gas,
			gasPrice: 10000000000,
		});
		console.log('Contract deployed at address: ' + tx.options.address);

		const deployedAddressPath: string = path.join(__dirname, 'MyContractAddress.bin');
		fs.writeFileSync(deployedAddressPath, tx.options.address);
	} catch (error) {
		console.error(error);
	}
}

deploy();
```

这段代码从`MyContractBytecode.bin`文件中读取字节码，并使用ABI和字节码创建一个新的合约对象。作为一个可选步骤，它估计部署智能合约将使用的gas。然后，它将合约部署到Ganache网络。它还将地址保存在文件`MyContractAddress.bin`中，我们在与合约交互时将使用这个地址。

运行以下命令来部署智能合约：

```bash
$ node deploy.js
```

如果一切正常，你应该会看到如下内容：  

```javascript
Deployer account: 0xdd5F9948B88608a1458e3a6703b0B2055AC3fF1b
Estimated gas: 142748n
Contract deployed at address: 0x16447837D4A572d0a8b419201bdcD91E6e428Df1
```  

## 步骤7：使用web3.js与智能合约交互

在这一步，我们将使用web3.js在Ganache网络上与智能合约交互。

创建一个名为`interact.js`的文件，并用以下代码填充它：  

```javascript
import { Web3 } from 'web3';
import fs from 'fs';
import path from 'path';

// Set up a connection to the Ethereum network
const web3: Web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:7545'));

// Read the contract address from the file system
const deployedAddressPath: string = path.join(__dirname, 'MyContractAddress.bin');
const deployedAddress: string = fs.readFileSync(deployedAddressPath, 'utf8');

// Read the bytecode from the file system
const bytecodePath: string = path.join(__dirname, 'MyContractBytecode.bin');
const bytecode: string = fs.readFileSync(bytecodePath, 'utf8');

// Create a new contract object using the ABI and bytecode
const abi: any = require('./MyContractAbi.json');
const myContract: any = new web3.eth.Contract(abi, deployedAddress);
myContract.handleRevert = true;

async function interact(): Promise<void> {
	const providersAccounts: string[] = await web3.eth.getAccounts();
	const defaultAccount: string = providersAccounts[0];

	try {
		// Get the current value of my number
		const myNumber: string = await myContract.methods.myNumber().call();
		console.log('my number value: ' + myNumber);

		// Increment my number
		const receipt: any = await myContract.methods.setMyNumber(BigInt(myNumber) + 1n).send({
			from: defaultAccount,
			gas: 1000000,
			gasPrice: '10000000000',
		});
		console.log('Transaction Hash: ' + receipt.transactionHash);

		// Get the updated value of my number
		const myNumberUpdated: string = await myContract.methods.myNumber().call();
		console.log('my number updated value: ' + myNumberUpdated);
	} catch (error) {
		console.error(error);
	}
}

interact();
```  

这段代码使用`MyContract`对象与智能合约交互。它获取myNumber的当前值，增加它并更新它，然后获取它的更新值。它将`myNumber`的值和交易收据记录到控制台。

运行以下命令与智能合约交互：

```bash
$ node interact.js
```

如果一切正常，你应该会看到当前计数器值记录在控制台，然后是交易收据，然后是更新的计数器值。输出会像：  

```javascript
my number value: 1
Transaction Hash: 0x9825e2a2115896728d0c9c04c2deaf08dfe1f1ff634c4b0e6eeb2f504372f927
my number updated value: 2
```  

## 故障排除和错误

如果你在执行合约方法时遇到错误，如`myContract.methods.call`或`myContract.deploy.estimateGas()`，你可能会看到一个合约执行回滚错误，如：`value transfer did not complete from a contract execution reverted`

或者响应错误：ResponseError: Returned error: unknown field `input`, expected one of `from`, `to`, `gasPrice`, `maxFeePerGas`, `maxPriorityFeePerGas`, `gas`, `value`, `data`, `nonce`, `chainId`, `accessList`, `type`.

这可能是由于你连接的节点期望在你的合约中填充`data`属性，而不是输入，例如，这个问题会在使用Foundry的Anvil节点时发生。Web3版本>4.0.3在发送交易时总是填充`input`。要解决这个问题，可以在`Web3Config`中配置`contractDataInputFill`，或者在初始化你的合约时指定在`dataInputFill`中填充数据。另一种解决方法是在使用send或call方法时提供`data`。如果你想填充`data`和`input`，将属性设置为`both`。

以下是一些例子：  

```javascript
// Configuring Web3Context with `contractDataInputFill`
import { Web3Context } from 'web3-core';
import { Contract } from 'web3-eth-contract';

const expectedProvider = 'http://127.0.0.1:8545';
const web3Context = new Web3Context({
	provider: expectedProvider,
	config: { contractDataInputFill: 'data' }, //  all new contracts created to populate `data` field
});

const contract = new Contract(GreeterAbi, web3Context);

// data will now be populated when using the call method
const res = await contract.methods.greet().call();

// Another way to do this is to set it within the contract using `dataInputFill`

const contract = new Contract(
	erc721Abi,
	'0x1230B93ffd14F2F022039675fA3fc3A46eE4C701',
	{ gas: '123', dataInputFill: 'data' }, // methods will now be populating `data` field
);

// `data` will now be populated instead of `input`
contract.methods.approve('0x00000000219ab540356cBB839Cbe05303d7705Fa', 1).call();

// Another way to do this is to set `data` when calling methods

const contract = new Contract(erc721Abi, '0x1230B93ffd14F2F022039675fA3fc3A46eE4C701');

contract.methods
	.approve('0x00000000219ab540356cBB839Cbe05303d7705Fa', 1)
	.call({
		data: contract.methods.approve('0x00000000219ab540356cBB839Cbe05303d7705Fa', 1).encodeABI(),
	});
```  

## 结论

在本教程中，我们学习了如何生成智能合约的ABI和Bytecode，将其部署到以太坊网络，并使用web3.js版本4.x与其交互。

有了这些知识，你可以开始尝试编写智能合约，以便使用web3.js在以太坊网络上构建你的去中心化应用程序（dApps）。请记住，这只是开始，关于以太坊和web3.js还有很多需要学习的。所以，继续探索和建设，玩得开心！

## 提示和最佳实践

- 在将智能合约部署到主网之前，总是先在像Ganache这样的本地网络上测试你的智能合约。
- 使用最新版本的web3.js和Solidity，以利用最新的功能和安全补丁。
- 保护好你的私钥，永远不要与任何人分享。
- 谨慎使用gas限制和gas价格参数，以避免在交易费用上花费过多。
- 在将交易发送到网络之前，使用web3.js中的`estimateGas`函数来估算交易所需的gas。
- 使用事件来通知客户端应用程序关于智能合约状态的变化。
- 使用像Solhint这样的linter来检查常见的Solidity编码错误。

## 最后的想法

Web3.js版本4.x提供了一个强大且易于使用的接口，用于与以太坊网络交互和构建去中心化应用程序。并且它已经用TypeScript重写，但为了简化本教程，我们用JavaScript与它交互。

以太坊生态系统正在不断发展，总是有更多的东西需要学习和发现。当你继续发展你的技能和知识时，继续探索和尝试新的技术和工具，构建创新和去中心化的解决方案。  

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
