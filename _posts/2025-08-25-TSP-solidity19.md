---
layout: post
title: 《纸上谈兵·solidity》第 19 课：安全专题（一）—— 常见攻击手法与防御
tags: solidity
mermaid: false
math: false
--- 

## 引言

区块链合约的“代码即法律”带来了强大的确定性，但同时也意味着：

* **一旦部署 → 无法修改 → 错误就是永久漏洞**
* **区块链是对抗性环境 → 每一行代码都可能被利用**

安全漏洞不是小概率事件，而是合约生命周期内的必然风险。在这节课程中，我们聚焦于三大常见攻击手法：

1. **重入攻击（Reentrancy）**
2. **抢跑攻击（Front-running / MEV）**
3. **拒绝服务攻击（DoS with Gas / Unexpected Revert）**

---

## 1. 重入攻击（Reentrancy）

### 历史案例

* **2016 年 The DAO 攻击**：利用重入漏洞，攻击者反复提取资金，造成 **6000 万美元** 损失，直接导致以太坊社区分叉出 ETH 与 ETC。
* **2022 年 Fei Rari 攻击**：Rari Capital 的资金池因重入漏洞被盗，损失超 **8000 万美元**。

### 攻击原理

调用外部合约时，执行流可能会“回流”到调用方，导致逻辑在状态更新前被重复执行。

```solidity
function withdraw(uint _amount) external {
    require(balances[msg.sender] >= _amount, "Not enough");
    (bool ok, ) = payable(msg.sender).call{value: _amount}(""); // 外部调用
    require(ok);
    balances[msg.sender] -= _amount; // ❌ 状态更新过晚
}
```

### 安全写法

```solidity
function withdraw(uint _amount) external {
    require(balances[msg.sender] >= _amount, "Not enough");
    balances[msg.sender] -= _amount; // ✅ 先修改状态
    (bool ok, ) = payable(msg.sender).call{value: _amount}("");
    require(ok, "Transfer failed");
}
```

或者使用 **OpenZeppelin ReentrancyGuard**：

```solidity
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SafeVault is ReentrancyGuard {
    mapping(address => uint) public balances;

    function withdraw(uint _amount) external nonReentrant {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
    }
}
```

---

## 2. 抢跑攻击（Front-running / MEV）

### 历史案例

* **2018 Bancor DEX**：部分交易因抢跑而被操纵，用户损失严重。
* **NFT 铸造抢跑**：热门 NFT 发布时，Bot 抢先提交交易，普通用户无法获得稀缺 Token。

### 攻击原理

区块链交易在进入区块之前会进入 **内存池（Mempool）**，攻击者可以观察并提前插队：

* **Sandwich 攻击**：攻击者在用户交易前买入，用户推动价格上升，攻击者再卖出获利。
* **拍卖狙击**：攻击者在最后时刻提交 Gas 更高的出价，让用户交易失败。

### 防御策略

* **Commit-Reveal 模式**：用户先提交 `hash(secret)`，等到揭示阶段再公布真实数据。
* **批量结算（Batch Auction）**：将一批订单同时撮合，避免逐笔执行带来的顺序优势。
* **链下撮合 → 链上结算**：部分 DEX 采用 off-chain orderbook 模式，减少抢跑。

---

## 3. 拒绝服务攻击（DoS）

### 攻击案例

* **2016 年 GovernMental 合约**：合约要求循环给所有用户退款，某些用户地址拒收 ETH，导致整个退款失败。
* **Gas 消耗攻击**：攻击者提供极大输入数据，迫使交易消耗掉区块 Gas 上限。

### 攻击原理

* **Push 式分发**：合约主动给所有用户转账，一旦有一个用户地址拒绝收款 → 整体失败。
* **Gas 陷阱**：攻击者故意制造复杂输入，消耗合约调用者的 Gas。

### 防御策略

* **Pull over Push**：用户主动领取奖励，避免循环转账。
* **try/catch**：忽略个别失败，继续执行。
* **Gas 上限控制**：避免外部调用消耗过多 Gas。

---

## 4. Foundry 实战：重入攻击与修复

在[之前的课程](./2025-08-19-TSP-solidity16.md)中，我们通过 **Check-Effects-Interactions** 的方式来避免冲入攻击。现在，我们使用 **ReentrancyGuard** 来修复合约。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SafeVictim is ReentrancyGuard {
    mapping(address => uint) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint _amount) external nonReentrant {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] -= _amount;
        (bool ok,) = payable(msg.sender).call{value: _amount}("");
        require(ok);
    }
}
```

### Foundry 测试

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SafeVictim.sol";
import "../src/Attacker.sol";

contract SafeVictimTest is Test {
    SafeVictim safe;
     Attacker attacker;

    function setUp() public {
        safe = new SafeVictim();
        attacker = new Attacker(address(safe));

        vm.deal(address(this), 10 ether);
    }

    function testSafeWithdraw() public {
    // 攻击者尝试攻击
    vm.deal(address(attacker), 1 ether);

    vm.expectRevert(); // 攻击应该失败
    attacker.attack{value: 1 ether}();
    }

    receive() external payable {}
}
```

**执行测试：**  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/SafeVictim.t.sol -vvv

[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 513.05ms
Compiler run successful!

Ran 1 test for test/SafeVictim.t.sol:SafeVictimTest
[PASS] testSafeWithdraw() (gas: 49870)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 5.86ms (1.28ms CPU time)

Ran 1 test suite in 165.82ms (5.86ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 5. 开发者 Checklist

在写合约时，建议遵循以下安全清单：

* ✅ **状态更新在前，外部调用在后**
* ✅ **使用 Pull over Push 模式**
* ✅ **对外部调用使用 try/catch**
* ✅ **限制 Gas 消耗，避免循环调用**
* ✅ **考虑交易顺序安全性（MEV 防御）**
* ✅ **写攻击性测试（Red Team Testing）**

---

## 6. 小练习

1. 修改本课的 `Victim.sol`，让它变为安全版本（提示：CEI 原则）。
2. 实现一个简单的 **Commit-Reveal 拍卖合约**，防止抢跑。
3. 写一个 DoS 攻击合约，使得某个分发函数无法执行。

---

## 总结

* **Reentrancy**：调用外部合约前要更新状态，必要时使用 ReentrancyGuard。
* **Front-running**：交易顺序是透明的，敏感逻辑要用 Commit-Reveal 或批量结算。
* **DoS**：避免循环外部调用，转账用 Pull 模式。

**核心理念**：

> 在区块链世界，攻击者永远在等着你写错一行代码。

---

下一课（第 19 课）：我们将探讨 **编译器特性与低级漏洞（Slot 冲突、ABI 混淆、Selfdestruct）** —— 这些“看不见的陷阱”比逻辑错误更难察觉，却可能致命。


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