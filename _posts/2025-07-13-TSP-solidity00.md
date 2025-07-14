---
layout: post
title: 《纸上谈兵·solidity》第 0 课：搭建 solidity 开发环境（三种方式）
tags: solidity
mermaid: false
math: false
---  

## 为什么你需要搭建环境？

写 Solidity 合约 ≠ 打开浏览器写点 JS。它更像嵌入式开发，要“部署到虚拟硬件”（即 EVM）中运行。你需要一个**能编译、部署、调试、测试的本地环境**。

我们将介绍 3 种主流方式，适合不同阶段的开发者：

| 工具链              | 特点            | 推荐人群          |
| :---------------- | :------------- | :------------- |
| Remix IDE        | 免安装、上手快       | 零基础新手、轻度实验    |
| Foundry          | 轻量级 CLI 工具，极快 | 喜欢终端操作、追求效率   |
| VSCode + Hardhat | 全功能工程化        | 想构建完整项目结构的开发者 |

## 方案一：Remix IDE（在线免安装）

### 优点：

* 免安装、浏览器即用
* 内置 Solidity 编译器和虚拟链
* 支持合约部署、调试、测试、调用

### 快速开始：

1. 打开 [https://remix.ethereum.org](https://remix.ethereum.org)
2. 新建一个 `.sol` 文件：

   ```solidity
   // SPDX-License-Identifier: MIT
   pragma solidity ^0.8.0;

   contract Hello {
       string public greet = "Hello, Solidity!";
   }
   ```
3. 点击左侧“Solidity 编译器” → Compile
4. 切换到 “部署 & 运行” 标签 → Deploy
5. 点击部署按钮 → 查看合约地址与变量

用它做实验、调试，**非常适合入门使用和教学演示**

## 方案二：Foundry（终端党的福音）

### 优点：

* 极快的编译和测试速度（比 Hardhat 快很多）
* 无需 Node.js
* 原生支持测试、Fuzzing、脚本、部署
* 社区活跃度高，适合写大型合约项目

### 安装步骤：

#### 1. 安装 Foundry

> 需要已安装 Git 和 curl，适用于 Mac/Linux/WSL

```bash
$ curl -L https://foundry.paradigm.xyz | bash
$ foundryup
```

Windows 用户建议使用 WSL + Ubuntu，或者使用 Scoop：

```bash
scoop install foundry
```

#### 2. 创建项目

```bash
forge init my-foundry-app
cd my-foundry-app
```

#### 3. 编写合约

编辑 `src/Hello.sol`：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Hello {
    function greet() public pure returns (string memory) {
        return "Hello, Foundry!";
    }
}
```

#### 4. 编译 & 测试

```bash
forge build
forge test
```

后续你可以使用 `forge script` 来部署合约、调用方法，还支持主流测试网。

## 方案三：VSCode + Hardhat（全功能开发框架）

### 优点：

* 支持 JS/TS 编写部署脚本与测试代码
* 支持本地链模拟（Hardhat Node）
* 有丰富插件系统和文档
* 适合构建完整 DApp 项目

### 安装步骤：

#### 1. 安装 Node.js 和 VSCode

* Node.js 推荐 v18+
* VSCode 安装官方 Solidity 插件

#### 2. 初始化项目

```bash
$ npm init -y
$ npm install --save-dev hardhat
$ npx hardhat
```

选择第一个：**Create a basic sample project**

目录结构大致如下：

```text
├── contracts/       // 合约代码
├── scripts/         // 部署/调用脚本
├── test/            // 单元测试
└── hardhat.config.js
```

#### 3. 编译合约

```bash
$ npx hardhat compile
```

#### 4. 启动本地节点并部署

```bash
$ npx hardhat node
$ npx hardhat run scripts/deploy.js --network localhost
```

Hardhat 是你通往“专业开发者”的必经之路。

## “纸上谈兵”提醒

| 环节       | 容易忽视的问题                                  |
| :----------- | :---------------------------------------- |
| Remix 部署    | 本质是部署在 JS 模拟链上，数据不会保留                    |
| Foundry 编译器 | 默认使用最新的 `solc`，可能与你目标版本不一致，需指定           |
| Hardhat 网络  | 默认运行在 localhost:8545，本地账户默认私钥是已知的，不要用于生产 |

## 总结

| 工具链       | 推荐程度  | 用途             |
| :--------- | :----- | :-------------- |
| Remix IDE | ⭐⭐⭐⭐  | 学习 / 快速测试      |
| Foundry   | ⭐⭐⭐⭐⭐ | 高效本地开发 / CI 测试 |
| Hardhat   | ⭐⭐⭐⭐⭐ | 完整项目开发 / 前端联调  |

## 你可以现在就做的事：

* 👉 打开 [Remix](https://remix.ethereum.org) 并写下你的第一个合约
* 👉 安装 Foundry 并 `forge init hello-world`
* 👉 准备第一个 Hardhat 项目 `npx hardhat`

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  
---