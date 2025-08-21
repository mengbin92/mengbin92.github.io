---
layout: post
title: 《纸上谈兵·solidity》第 17 课：合约设计模式实战（二）—— Access Control 与权限管理
tags: solidity
mermaid: false
math: false
--- 

## 引言

在区块链合约中，**权限管理**是核心问题之一。
如果权限控制不当，可能导致：

* 任何人都能修改关键参数（严重漏洞）
* 单点管理员（Owner）被盗号，合约失控
* 合约升级、资金管理失误，导致灾难性损失

因此，本课将深入探讨 **多种权限控制模式**，并通过实战示例，演示如何安全地在 Solidity 中实现访问控制。

---

## 1. 基础模式：Ownable（单一管理员）

OpenZeppelin 提供了最简单的权限控制合约 **Ownable**，其核心是一个 `owner` 地址：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    uint256 public funds;

    function deposit() external payable {
        funds += msg.value;
    }

    // 只有 owner 才能提款
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        require(amount <= funds, "Not enough funds");
        funds -= amount;
        to.transfer(amount);
    }
}
```

特点：

* 简单直观，一个人掌控全局
* 适合小项目、个人实验
* **缺点**：单点故障，如果 `owner` 私钥丢失，合约彻底失控

---

## 2. 多角色模式：AccessControl

在复杂系统中，不同功能需要 **不同的角色**。例如：

* `ADMIN_ROLE`：分配权限
* `MINTER_ROLE`：铸造代币
* `PAUSER_ROLE`：紧急暂停

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract TokenWithRoles is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // 部署者是管理员
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        // 执行铸币逻辑
    }
}
```

特点：

* 灵活，支持多个角色
* 每个角色都可以分配、撤销
* 更适合团队开发和长期运行的项目

---

## 3. 高级模式：多签与时间锁

### 多签（Multisig）

* 多个管理员必须 **共同签署**，交易才会执行
* 避免单点失误

常见方案：Gnosis Safe

### 时间锁（Timelock）

* 关键操作必须延迟执行（如 24 小时）
* 给社区留出监督时间
* 常见于 DAO、治理合约

---

## 4. Foundry 实战

我们通过 Foundry 测试，来模拟权限误配与攻击场景。

### 合约：Vault.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Vault is Ownable, AccessControl {
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    uint256 public funds;

    constructor() Ownable(msg.sender){
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function deposit() external payable {
        funds += msg.value;
    }

    // 使用角色控制提款
    function withdraw(address payable to, uint256 amount) external onlyRole(WITHDRAW_ROLE) {
        require(amount <= funds, "Not enough funds");
        funds -= amount;
        to.transfer(amount);
    }
}
```

---

### 测试：AccessControl.t.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";

contract AccessControlTest is Test {
    Vault vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vault = new Vault();
        vm.deal(address(this), 10 ether);
        vault.deposit{value: 5 ether}();
    }

    function testUnauthorizedWithdrawFails() public {
        vm.prank(bob);
        vm.expectRevert(); // bob 没有权限
        vault.withdraw(payable(bob), 1 ether);
        
        assertEq(bob.balance, 0 ether);
    }

    function testGrantRoleAndWithdraw() public {
        // 授权 alice
        vault.grantRole(vault.WITHDRAW_ROLE(), alice);

        vm.prank(alice);
        vault.withdraw(payable(alice), 1 ether);

        assertEq(alice.balance, 1 ether);
    }
}
```

运行测试：

```bash
# 如果没有安装 openzepplin ，需要先安装
➜  tutorial git:(main) ✗ forge install OpenZeppelin/openzeppelin-contracts
➜  tutorial git:(main) ✗ forge test --match-path test/AccessControl.t.sol -vvv

[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 525.35ms
Compiler run successful!

Ran 2 tests for test/AccessControl.t.sol:AccessControlTest
[PASS] testGrantRoleAndWithdraw() (gas: 81767)
[PASS] testUnauthorizedWithdrawFails() (gas: 14751)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 9.24ms (3.14ms CPU time)

Ran 1 test suite in 169.06ms (9.24ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

### 题外话  

**为什么不用把 alice 和 bob 地址设置成 `address(0x1)` 和 `address(0x2)` 呢？**

在 EVM 里 **低号地址**（0x1 \~ 0x9）被保留为 **预编译合约地址**（precompiles），比如：

* `0x1` → `ecrecover`
* `0x2` → `sha256`
* `0x3` → `ripemd160`
* `0x4` → `identity`
* …

所以当我们让 `alice = 0x1` 并调用 `vault.withdraw(payable(alice), 1 ether)` 的时候，资金就被转到了 **预编译合约** 上，结果触发了 `PrecompileOOG`（Out Of Gas on precompile）然后报错。


---

## 5. 总结与最佳实践

1. **Ownable 模式**：适合简单项目，但存在单点风险
2. **AccessControl 模式**：灵活，支持多角色，适合生产环境
3. **多签 + 时间锁**：治理类合约的必备组合，确保安全与透明
4. **开发建议**：

   * 避免把所有权限交给一个账户
   * 核心操作应结合多签或时间锁
   * 测试中要模拟权限误配与攻击，确保安全性

---

💡本课我们掌握了合约中 **权限管理的多种模式**，并结合 Foundry 测试演示了实际效果。
下一课（第 18 课），我们将进入更复杂的 **代理 + 插件化架构（Diamond Standard / EIP-2535）**，探索模块化合约的进化形态。

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