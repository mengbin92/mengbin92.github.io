---
layout: post
title: 从JSON工件推断合约类型（TypeScript）
tags: [blockchain, web3.js]
mermaid: false
math: false
---  

原文在[这里](https://docs.web3js.org/guides/smart_contracts/infer_contract_types)

> 提示
> 这篇文章是为**TypeScript**开发者准备的。所以，如果你在使用JavaScript，你不需要阅读这篇文章。然而，web3.js版本4.x已经用TypeScript重写了。我们鼓励你使用TypeScript的强类型特性。

Web3.js是一个用于与EVM区块链交互的流行库。它的一个关键特性是能够调用部署在区块链上的EVM智能合约。在这篇博客文章中，我们将展示如何在**TypeScript**中与智能合约交互，特别关注如何从JSON artifact文件推断类型。

在我们深入问题之前，让我们快速看一下问题。Web3.js提供了一个简单方便的方式来与Solidity合约交互。要使用Web3.js与Solidity合约交互，你需要知道合约的地址和合约的ABI（应用二进制接口）。ABI是包含合约中函数定义的JSON数据，包括它们的名称、输入参数和返回值。

Web3.js使用ABI类型来动态加载可用的方法和事件，但是TypeScript目前[不支持将JSON加载为const](https://github.com/microsoft/TypeScript/issues/32063)。如果你去[Playground链接](https://www.typescriptlang.org/play?#code/MYewdgzgLgBAhgIwJYwLwwNoCga5gbxz1wCIkwAHAVyghIC5MjjdCWWywoBTAJzDgAbACoBPCtwYwS0XuQDmJADTN20gQFtJjEpu4B9ZavYko47dNkKSxvAF8VagreKce-IWIlSZUOWEVHJ3U4LR8IUQ0EEEFDIKdTc3C-axcYO1sAXXi8XzgeAFkaRCRBJDMfMHAKOFFEQUkc0jNvHVBIPypgKBBeG2IHVTYOOCqwSJAqOkYAMyEIbibpcmpaKWwnYYTyABNuAA9uHalOxbTScncBESSdOB2d3m4IOiXXPR8QAHcwPiNg6QtCwke6PZ50NKDTbnZZgPaHY6MU5vXKXPjXLzA0FPF7-YK6ULAiASOF-FHNW7SbHg-pqKFqLZqTjwo5SOaCBbk2FXTyUkhUS4AJgArAA2PEJD46ABuQiojRhiVa0gFXBF4shWSWBLCOgAghQKLwQLLBBLckCfNxpdwuLTcPTWLYQWMJlM2fMziYVjRpkxoQDmQdWUjePKuW50bzlSCHjjXoqpdIZsaNOaTJa7nGaZCUYzvaSEScw178WiPDcY9TcRGk6YQOmOJmqdncbm0vmOLtg4iYOzOYryxi+aqoOrG+9CT5TfKJxaR0KxfaWBl2NlnXXhLxRhAZmTnc2SNbbVBl47nAXVn6NgzB1wo5Wsa2E4G699fn0I4fqxCnOfiJ2rhDtGT5gjWiZTjoxK2nsn6Kt+z7LgMWobpBVKCII3yjMAComJMUBXusHZ3jyj4+KO461mhJBzhSMYUUumprtq0D5NwRRQCUZQVDKSDcF8jZKsCMxUGA3RIOAZ45J2nCEYwN7sIBqL3hWmI+D+tEhLqlgkrBmlCepiHtgGZYqcO9GLuKVHaSCGiTHaX4LmqjF-ihJh1nAhrGjagn4XJ-q3oGwFkTo0QxPpdb6YeYVmkxLDriYrGFMUyDcaIlTVLU9S4U2fIiWJUASWAUlDM6PprPJxFBWZIGGWBL74h5wCgKJp6OVWRmucxqE2QgQjYdwADyMy+TQ-kKSwSkXDVIUqpZEXUVFTlji5dJuRwSXsSlpTlOlvH8YJh75eJkmqOeMnldeCUcHWezAEgGjzKNBG+kRJnbDNak6KOAAcC02UtFlcH9cXENdribRxXG7dOfECdqR2iSdxVndJZWUK9lXvUywVfS29X-USun7oGCEE8ZgWmaReP8vN1lElQCB+HA3RHAAanKOUJIeDEal18Xard3DAE8cALHqGFYWJXO5H5mMBYpJEPjTMWEz4gPAqroN4ODuSQ9taUZZQWUIA0h15UjhWnQMaOXvLE0AUrql8hp9PhMTcGky7nV0nmTvmcCvNq1mew7Bzgizu1gfzdruC66QdbkCL3Bi9wEuYV8A3PeNVVU8rfKq27Ogaz4Wv82DLGcclnGpTDOhjDUdSmzLdHCZbRUlY7dsVZg8dacCHzanLPcO3gU3cvnMZWAEwfSCXUEpDPscwH3eTV9DPHSNKcPmzGx1WyjNuld3V2C9RERROFQ9jfbucfdTfLT4EEEA1HyT+Ioy+r-rNc7ZvJDbwOgjC2BUO6o2Pl2DGI9V51h6JxQQABlKghpBDpWvi9Eed8cafWWpRF+wJ55zWcnzNa3VEpVy2r-Q2+14YHhAcjTuY90Y52xgWB+HUCZF0BA2N+Id4xIXsH7aq7Do7ENnrZeybV4K4NWuwVcAserAmZpAPcnsODD2vFgthk9NYgCvvg9WvDpBl1IQo8hbEoa13-g3E2ZtgF73btbQRECgJQM0awyBIi6r8K4SQFMIA0xGNjOTP8Qi87Ow4T4gxOgeiEOCfwimithE6PInTaJVI7KtTiUHL+Z8bLKN3HwAAYqmbOt8PGuK8aFPRZpfFxJMXI9aEMKGWL-ntdQmUm52LoQ40BTiHREEyPACAMB2jQAANxAA)并选择'.d.ts'，你可以检查带和不带`as const`的类型差异。  

```javascript
import { Contract, Web3 } from 'web3';
import ERC20 from './node_modules/@openzeppelin/contracts/build/contracts/ERC20.json';

(async function () {
  const web3 = new Web3('rpc url');

  const contract = new Contract(ERC20.abi, '0x7af963cF6D228E564e2A0aA0DdBF06210B38615D', web3);

  const holder = '0xa8F6eB216e26C1F7d924A801E46eaE0CE8ed1A0A';

  //Error because Contract doesn't know what methods exists
  const balance = await contract.methods.balanceOf(holder).call();
})();
```  

为了解决这个问题，你需要将abi复制到一个TypeScript文件中，如下所示：  

```typescript 
import {Contract, Web3} from 'web3';

const ERC20 = [
    ...
    // 'as const' is important part, without it typescript would create generic type and remove available methods from type
] as const;

(async function () {
  const web3 = new Web3('rpc url');

  const contract = new Contract(ERC20, '0x7af963cF6D228E564e2A0aA0DdBF06210B38615D', web3);

  const holder = '0xa8F6eB216e26C1F7d924A801E46eaE0CE8ed1A0A';

  //Works now
  const balance = await contract.methods.balanceOf(holder).call();
})();
```  

现在它可以工作了，但这也意味着当你升级你的npm依赖时，abi不再更新。为了解决这个问题，你可以使用一个自定义脚本，将合约的JSON artifact复制到一个TypeScript文件中作为一个const变量。这个脚本可以作为你的构建过程的一部分运行，这样TypeScript文件总是与合约ABI的最新版本保持同步。

脚本：

```typescript
import fs from 'fs';
import path from 'path';

//read destination directory submitted as first param
var destination = process.argv.slice(2)[0];

//read all contract artifacts from artifacts.json which should be in the directory from where script should be executed
const artifactContent = fs.readFileSync('./artifacts.json', 'utf-8');

const artifacts: string[] = JSON.parse(artifactContent);

(async function () {
  for (const artifact of artifacts) {
    let content;
    try {
      //try to import from node_modules
      content = JSON.stringify(await import(artifact));
    } catch (e) {
      //try to read as path on disc
      content = fs.readFileSync(artifact, 'utf-8');
    }
    const filename = path.basename(artifact, '.json');
    //create and write typescript file
    fs.writeFileSync(path.join(destination, filename + '.ts'), `const artifact = ${content.trimEnd()} as const; export default artifact;`);
  }
})();
```  

要使用这个脚本，只需在你的项目根目录下创建一个`artifacts.json`文件，其中包含你正在使用的所有工件。  

```json
[
	"@openzeppelin/contracts/build/contracts/ERC20.json",
	"@openzeppelin/contracts/build/contracts/ERC1155.json",
	"./build/contracts/MyContract.json"
]
```  

然后执行脚本：  

```bash
$ node -r ts-node/register <script name>.ts <destination>
```  

然后你可以在你的代码中使用那些生成的文件：  

```javascript
import { Contract, ContractAbi, Web3 } from 'web3';
import ERC20 from './artifacts/ERC20';

(async function () {
  const web3 = new Web3('https://goerli.infura.io/v3/fd1f29ab70844ef48e644489a411d4b3');

  const contract = new Contract(ERC20.abi as ContractAbi, '0x7af963cF6D228E564e2A0aA0DdBF06210B38615D', web3);

  const holder = '0xa8F6eB216e26C1F7d924A801E46eaE0CE8ed1A0A';

  const balance = await contract.methods.balanceOf(holder).call();
  const ticker = await contract.methods.symbol().call();

  console.log(`${holder} as ${balance.toString()} ${ticker} tokens`);
})();
```  

你可以在[https://github.com/web3/web3-contract-types-example](https://github.com/web3/web3-contract-types-example)查看完整的示例。  

> 提示
> 你可以使用一个叫做`web3-plugin-craftsman`的web3.js插件来编译和保存ABI和ByteCode。你可以在这里找到更多信息：[https://www.npmjs.com/package/web3-plugin-craftsman#save-the-compilation-result](https://www.npmjs.com/package/web3-plugin-craftsman#save-the-compilation-result)

> 提示
> 如果你正在使用Hardhat开发智能合约，你可以使用[@chainsafe/hardhat-ts-artifact-plugin](https://github.com/ChainSafe/hardhat-ts-artifacts-plugin)来为每个工件生成包含类型化ABI JSON的typescript文件。

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
