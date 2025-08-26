---
layout: post
title: 《纸上谈兵·solidity》第 19 课：Solidity 安全专题（二）—— 编译器特性与低级漏洞
tags: solidity
mermaid: false
math: false
---  

## 课程目标

* 理解 Solidity 编译器的存储布局机制
* 学会识别 **存储槽冲突、ABI 混淆攻击**
* 掌握 `selfdestruct` 等低级指令的风险
* 通过 Foundry 测试模拟攻击与验证

---

## 1、存储槽冲突（Storage Slot Collision）

Solidity 使用 32 字节为一个存储槽（storage slot）。在继承或代理合约模式下，如果新旧合约的状态变量定义不一致，就可能发生槽冲突，导致关键数据被覆盖。

### 示例：代理升级导致的槽冲突

```solidity
// V1
contract LogicV1 {
    uint256 public value;  // slot 0
}

// V2 (错误升级)
contract LogicV2 {
    address public owner;  // slot 0 （与 V1 的 value 冲突）
}
```

在升级后，`owner` 会直接读取到旧的 `value`，导致 **权限错乱**。

> **防御手段**：
>
> 1. 使用 `storage gap` 预留存储空间：
>
>   ```solidity
>   uint256[50] private __gap;
>   ```
> 2. 遵循 OpenZeppelin 的升级合约工具（`@openzeppelin/contracts-upgradeable`）。

---

## 2、ABI 混淆攻击

ABI 负责定义函数签名到 **函数选择器（4 字节）** 的映射。
攻击者可能利用选择器碰撞，让不同函数共享同一个选择器，从而调用到意料之外的逻辑。

### 示例：选择器碰撞

```solidity
contract Victim {
    function transfer(address to, uint256 amount) public {}
    function f123456789() public {}
}
```

不同函数签名哈希后的前 4 字节可能相同，导致 ABI 解码错误。
虽然概率极低（约 1/2^32^ ），但已被多次利用于攻击 ABI 解析库。

> **防御手段**：

* 使用最新 Solidity 编译器，避免 ABI 自动推导漏洞
* 避免函数名过长或构造极端签名
* 使用工具检测潜在冲突（如 Slither、Surya）

---

## 3、`selfdestruct` 的风险

`selfdestruct(address)` 指令会销毁合约，并强制向指定地址转账余额。
虽然 EIP-6049 已提出废弃 `selfdestruct`，但目前仍存在隐患：

1. **强制转账**：攻击者可以部署一个带余额的合约，并 `selfdestruct` 强行转账到任意合约，即使目标合约没写 `receive()`。
2. **代理合约被摧毁**：如果逻辑合约或代理被不慎写入 `selfdestruct`，可能彻底失效。

### 示例：强制转账绕过逻辑

```solidity
contract Victim {
    uint256 public balance;

    function deposit() external payable {
        balance += msg.value;
    }
}
```

即使 Victim 没有 `receive()`，攻击者仍可通过 `selfdestruct` 注入 ETH，导致 `balance` 与 `address(this).balance` 不一致，引发资金错账。

```solidity
contract Attacker {
    function attack(address payable target) external payable {
        selfdestruct(target);
    }
}
```

---

## 4、Foundry 实战测试

### 测试 1：存储槽冲突

**SlotLogicV1.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LogicV1 {
    uint256 public value; // slot 0
    function setValue(uint256 v) external {
        value = v;
    }
}
```

**SlotLogicV2.sol：**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LogicV2 {
    address public owner; // slot 0
    function setOwner(address o) external {
        owner = o;
    }
}
```

#### 测试文件 `test/SlotCollision.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SlotLogicV1.sol";
import "../src/SlotLogicV2.sol";

contract SlotCollisionTest is Test {
    LogicV1 v1;
    LogicV2 v2;

    function setUp() public {
        v1 = new LogicV1();
        v2 = LogicV2(address(v1)); // 模拟升级代理
    }

    function testCollision() public {
        v1.setValue(123);
        emit log_named_uint("Stored in V1.value", v1.value());

        // 直接读 slot 0 的原始值
        bytes32 raw = vm.load(address(v1), bytes32(uint256(0)));
        emit log_named_bytes32("Raw slot0 data", raw);

        // 解释为 address
        address fakeOwner = address(uint160(uint256(raw)));
        emit log_named_address("Interpreted as V2.owner", fakeOwner);
    }
}
```

**执行测试：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/SlotCollision.t.sol -vvv
[⠊] Compiling...
[⠢] Compiling 1 files with Solc 0.8.29
[⠆] Solc 0.8.29 finished in 1.13s
Compiler run successful!

Ran 1 test for test/SlotCollision.t.sol:SlotCollisionTest
[PASS] testCollision() (gas: 39104)
Logs:
  Stored in V1.value: 123
  Raw slot0 data: 0x000000000000000000000000000000000000000000000000000000000000007b
  Interpreted as V2.owner: 0x000000000000000000000000000000000000007B

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 6.49ms (1.14ms CPU time)
```

---

### 测试 2：强制转账

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Victim {
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract Attacker {
    function attack(address payable target) external payable {
        selfdestruct(target);
    }
}
```

#### 测试文件 `test/Selfdestruct.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Victim.sol";
import "../src/Attacker.sol";

contract SelfdestructTest is Test {
    Victim victim;
    Attacker attacker;

    function setUp() public {
        victim = new Victim();
        attacker = new Attacker();
    }

    function testForcedETH() public {
        emit log_named_uint("Victim balance before", victim.getBalance());

        attacker.attack{value: 1 ether}(payable(address(victim)));

        emit log_named_uint("Victim balance after", victim.getBalance());
    }
}
```

**执行测试：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/Selfdestruct.t.sol -vvv 
[⠊] Compiling...
[⠢] Compiling 2 files with Solc 0.8.29
[⠆] Solc 0.8.29 finished in 1.08s
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/VictimAttacker.sol:12:9:
   |
12 |         selfdestruct(target);
   |         ^^^^^^^^^^^^


Ran 1 test for test/Selfdestruct.t.sol:SelfdestructTest
[PASS] testForcedETH() (gas: 28393)
Logs:
  Victim balance before: 0
  Victim balance after: 1000000000000000000

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 6.99ms (646.87µs CPU time)

Ran 1 test suite in 345.96ms (6.99ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

输出显示 Victim 收到强制 ETH，哪怕它没有 `receive()`。

---

## 5、总结

本课揭示了 **Solidity 与 EVM 的底层隐患**：

1. **存储槽冲突** —— 升级合约的最大坑
2. **ABI 混淆** —— 极端但可能的攻击面
3. **selfdestruct** —— 强制转账与合约摧毁

开发者必须：

* 使用官方工具（OpenZeppelin Upgrades、Slither）检查
* 谨慎对待 ABI 与存储布局
* 避免在合约中随意调用 `selfdestruct`

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