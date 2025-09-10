---
layout: post
title: 《纸上谈兵·solidity》第 32 课：DeFi 基础合约
tags: solidity
mermaid: false
math: false
---  

## 学习目标

通过本课学习，你将掌握：

1. 理解 DeFi 的核心组成部分
2. 实现 **Staking / Farming 合约**
3. 理解 **AMM（自动做市商）** 的基本原理，并实现一个简化版 DEX
4. 了解 **借贷合约** 的基本逻辑

---

## 1. DeFi 的基本组成

DeFi（去中心化金融）是区块链最活跃的应用场景，核心合约一般分为：

* **代币合约**（ERC20 / ERC721 等）
* **Staking / Farming**（激励流动性、挖矿奖励）
* **DEX（去中心化交易所）**
* **Lending（借贷协议）**
* **衍生品 / 稳定币**

在本课，我们会实战实现前三个基础模块。

---

## 2. Staking 合约（质押奖励）

### 原理

用户把 **代币 A** 存入合约，获得奖励（一般是代币 B）。

* 存入时记录数量和时间
* 奖励按区块/时间线性计算
* 用户可随时领取奖励或取回本金

### 示例代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking {
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate = 100; // 每秒奖励数量
    mapping(address => uint256) public staked;
    mapping(address => uint256) public lastUpdate;
    mapping(address => uint256) public rewards;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function stake(uint256 amount) external {
        _updateReward(msg.sender);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        _updateReward(msg.sender);
        staked[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
    }

    function claimReward() external {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);
    }

    function _updateReward(address account) internal {
        if (account != address(0)) {
            uint256 timeDiff = block.timestamp - lastUpdate[account];
            rewards[account] += staked[account] * rewardRate * timeDiff / 1e18;
            lastUpdate[account] = block.timestamp;
        }
    }
}
```

👉 这里的 `rewardRate` 简化处理了，实际项目会结合总奖励池、质押总量动态计算。

---

## 3. 简化版 AMM（自动做市商）

### 原理

Uniswap V2 的核心公式是：

$$
x \times y = k
$$

* 用户提供两种代币（A & B）到池子
* 任意一边增加，另一边必须减少保持 `k` 不变
* 手续费作为 LP（流动性提供者）的奖励

### 示例代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAMM {
    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
    }

    function swapAforB(uint256 amountIn) external returns (uint256 amountOut) {
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        uint256 newReserveA = reserveA + amountIn;
        // x*y=k => amountOut = reserveB - (k / newReserveA)
        uint256 k = reserveA * reserveB;
        amountOut = reserveB - (k / newReserveA);
        reserveA = newReserveA;
        reserveB -= amountOut;
        tokenB.transfer(msg.sender, amountOut);
    }
}
```

👉 这是 **最小可运行版本**，省略了手续费、LP Token 等。你可以扩展它来模拟 Uniswap 的完整逻辑。

---

## 4. 借贷合约基础逻辑

### 原理

* 用户存入抵押物（Collateral）
* 可以借出另一种代币
* 抵押率不足时，会触发清算

### 简化逻辑

```solidity
// Pseudo code
deposit(collateral)  
borrow(asset)  
repay(asset)  
liquidate(user)  // 当抵押价值 < 借出价值 * 安全因子
```

完整实现涉及 **价格预言机、清算机制、抵押率参数**，后面课程会专门深入。

简化版的实现可以参照[前文](./2025-09-02-TSP-solidity25.md)。

---

## 5. 本课总结

* 你学习了 **Staking 奖励机制**
* 实现了 **简化版 AMM**
* 理解了 **借贷合约的核心逻辑**

这三个模块是 DeFi 世界的基石，之后的 DEX、借贷协议、流动性挖矿、稳定币，都是在这些基本模式上扩展出来的。  

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
