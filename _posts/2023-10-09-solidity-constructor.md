---
layout: post
title: solidity 合约入门 
tags: solidity
mermaid: false
math: false
---  

## 入门合约1

下面是一个简单的 Solidity 合约示例，它实现了一个简单的数字存储合约，允许用户设置和获取一个整数值。这个合约将帮助你了解 Solidity 合约的基本结构和语法。

```solidity 
// 指定 Solidity 的版本
pragma solidity ^0.8.0;

// 定义一个合约
contract SimpleStorage {
    // 声明一个状态变量，用于存储整数值
    uint256 private storedData;

    // 定义一个事件，用于记录状态变量的变化
    event ValueChanged(uint256 newValue);

    // 合约构造函数，在部署合约时执行一次，用于初始化状态变量
    constructor() {
        storedData = 0;
    }

    // 设置整数值的函数，只有合约的拥有者可以调用
    function set(uint256 newValue) public {
        storedData = newValue;
        emit ValueChanged(newValue);
    }

    // 获取整数值的函数，可以被任何人调用
    function get() public view returns (uint256) {
        return storedData;
    }
}
```

在这个示例中，我们创建了一个名为 `SimpleStorage` 的合约。这个合约包括以下要点：

1. 使用 `pragma solidity` 指令指定 Solidity 的版本。
2. 声明了一个名为 `storedData` 的状态变量，用于存储整数值。这个变量是私有的，只能在合约内部访问。
3. 定义了一个 `ValueChanged` 事件，用于记录状态变量的变化。
4. 在构造函数中，将 `storedData` 初始化为 0。
5. 实现了一个 `set` 函数，允许合约的拥有者设置整数值，并触发 `ValueChanged` 事件。
6. 实现了一个 `get` 函数，允许任何人查看存储的整数值。

要使用这个合约，你需要执行以下步骤：

1. 部署合约：使用以太坊钱包或 Solidity 开发工具，将这个合约部署到以太坊网络上。
2. 设置值：使用合约的拥有者地址调用 `set` 函数，设置存储的整数值。
3. 获取值：任何人都可以使用 `get` 函数查看存储的整数值。

这只是一个非常简单的示例，但它涵盖了 Solidity 合约的基本结构，包括状态变量、构造函数、函数、事件等。你可以根据需要扩展这个示例，创建更复杂的智能合约。注意，智能合约的开发需要谨慎，特别是在处理资金和重要数据时，请务必小心编写和测试代码。

## 入门合约2

下面的合约实现了一个简单的数字投票系统。合约允许用户为不同的候选人投票，并且可以查询每个候选人的得票数。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 声明一个智能合约
contract SimpleVoting {
    // 声明候选人结构体
    struct Candidate {
        uint256 id;
        string name;
        uint256 voteCount;
    }

    // 使用数组存储候选人列表
    Candidate[] public candidates;

    // 用于存储每个地址的投票记录
    mapping(address => bool) public voters;

    // 添加候选人
    function addCandidate(string memory _name) public {
        // 检查调用者是否已投票
        require(!voters[msg.sender], "You can only add one candidate.");

        uint256 candidateId = candidates.length;
        candidates.push(Candidate(candidateId, _name, 0));
        voters[msg.sender] = true;
    }

    // 进行投票
    function vote(uint256 _candidateId) public {
        // 检查调用者是否已投票
        require(!voters[msg.sender], "You can only vote once.");

        // 检查候选人是否存在
        require(_candidateId < candidates.length, "Candidate does not exist.");

        // 增加候选人的得票数
        candidates[_candidateId].voteCount++;

        // 标记调用者已投票
        voters[msg.sender] = true;
    }

    // 查询候选人的得票数
    function getVotes(uint256 _candidateId) public view returns (uint256) {
        require(_candidateId < candidates.length, "Candidate does not exist.");
        return candidates[_candidateId].voteCount;
    }
}
```

这个合约包括以下主要部分：

1. 候选人结构体 `Candidate`：包括候选人的ID、姓名和得票数。
2. 候选人列表 `candidates`：用于存储候选人的数组。
3. 投票者记录 `voters`：用于记录哪些地址已经投票，防止重复投票。
4. `addCandidate` 函数：允许任何地址添加候选人。
5. `vote` 函数：允许任何地址投票给特定的候选人。
6. `getVotes` 函数：允许查询特定候选人的得票数。

合约的调用者可以通过调用函数来添加候选人、投票和查询候选人的得票数。这只是一个非常简单的示例，用于演示 Solidity 合约的基本构建块。在实际应用中，你可以根据需求扩展和优化合约。确保在以太坊测试网络上进行测试和部署合约，以确保其正常运行。  

## 使用 Remix 进行调试

Remix IDE 是一个基于 Web 的区块链智能合约开发环境，它提供了许多有用的功能，包括智能提示（代码补全）功能，以帮助开发者更高效地编写 Solidity 智能合约。智能提示可以在你输入代码时，自动显示可能的选项，从而加速代码编写和减少错误。

以下是如何在 Remix IDE 中调试智能合约的步骤：

1. **打开 Remix IDE**：
   访问 Remix IDE 的网站：https://remix.ethereum.org/
2. **创建或打开合约**：
   在 Remix IDE 中，你可以创建新的合约或打开已有的合约文件。选择左侧菜单栏中的 "File Explorer"，然后点击 "Open" 按钮，选择你的 Solidity 合约文件，或者点击 "Create" 创建一个新的合约文件。
3. **选择 Solidity 版本**：
   在左上角的选择框中，选择你要使用的 Solidity 版本。选择一个你熟悉的版本，通常会是最新的版本。
4. **编写代码**：
   在代码编辑区域中，开始编写 Solidity 智能合约。当你输入代码的时候，智能提示会自动弹出。
5. **保存合约**：
   在完成代码编写后，记得点击左上角的保存按钮，将合约保存到 Remix IDE 的本地存储中。
6. **运行合约**：
   一旦合约编写完成，你可以使用 Remix IDE 提供的 "Deploy & run transactions" 功能来部署和测试你的合约。

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
