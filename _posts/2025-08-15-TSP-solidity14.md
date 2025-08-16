---
layout: post
title: 《纸上谈兵·solidity》第 14 课：Solidity 中的可升级合约模式 —— 从代理合约到透明代理、UUPS 与安全陷阱
tags: solidity
mermaid: false
math: false
---  

## 1、可升级的必要性与问题

### 1. 区块链合约不可变的特性

* 在区块链上部署的合约代码是**永久存储**的，不可直接更改或删除。
* 这种不可变性保障了去中心化和安全性，但也意味着：
  * 一旦有 bug，无法直接修改。
  * 一旦需要新增功能，只能重新部署一个新版本。

### 2. 部署新合约迁移 vs 升级逻辑合约

* **部署新合约迁移**
  * 需要将旧合约中的状态数据（余额、映射等）迁移到新合约。
  * 迁移过程复杂、易出错、消耗大量 gas。
  * 用户需要更新交互地址，容易引起混乱。
* **升级逻辑合约**
  * 通过代理模式保留原有存储，替换逻辑实现。
  * 用户交互地址不变，数据原地保留。
  * 只需在升级时注意存储布局一致性。

---

## 2、可升级合约的核心思想

* **问题**：合约一旦部署，代码无法更改。
* **解决方案**：将合约分为 **代理合约（Proxy）** 和 **逻辑合约（Implementation）**。
  * 代理合约：存储状态变量，转发调用给逻辑合约。
  * 逻辑合约：包含可执行代码。
* **关键技术**：`delegatecall`，在代理合约中使用 `delegatecall` 调用逻辑合约的函数，使得代码在代理的存储上下文中执行。

---

## 3、代理模式的工作原理

### 1. delegatecall 复习

```solidity
(bool success, bytes memory data) = implementation.delegatecall(msg.data);
```

* `delegatecall` 会在**当前合约的存储和上下文**中执行目标合约的代码。
* 状态变量读写会影响代理合约，而不是逻辑合约。

### 2. 存储布局一致性

* 代理合约和逻辑合约必须保持**相同的状态变量声明顺序和类型**，否则会出现数据错位。

---

## 4、常见可升级合约模式

### 1. 透明代理（Transparent Proxy）

* EIP-1967 标准。
* 普通用户调用逻辑合约函数；管理员调用代理的管理函数（升级逻辑合约地址）。
* 优点：简单、被广泛支持（OpenZeppelin Proxy）。
* 缺点：管理逻辑和业务逻辑混在同一个合约中，稍显冗余。

### 2. UUPS（Universal Upgradeable Proxy Standard）

* EIP-1822 标准。
* 升级逻辑放在逻辑合约自身，由 `upgradeTo` 函数完成。
* 优点：代理合约更轻量，升级逻辑可定制。
* 缺点：升级安全完全依赖逻辑合约实现，容易被错误实现破坏。

### 3. Beacon Proxy

* 使用一个 Beacon 合约统一存储逻辑合约地址，多个代理共享升级源。
* 适合多实例共享逻辑的场景。

---

## 5、可升级合约的安全陷阱

| 风险点                | 说明                                               | 解决方案                                            |
| :-------------------- | :------------------------------------------------- | :-------------------------------------------------- |
| **存储布局冲突**      | 升级后逻辑合约的变量顺序、类型不一致，导致数据错位 | 遵循固定的变量追加规则，避免删除或更改类型          |
| **初始化漏洞**        | 新逻辑合约的构造函数不会被代理调用                 | 使用 `initializer` 修饰的初始化函数，防止重复初始化 |
| **delegatecall 风险** | 调用外部不可信合约可能破坏存储                     | 严格控制升级权限，禁止不可信代码执行 delegatecall   |
| **权限丢失**          | 升级过程中可能被替换成恶意逻辑                     | 使用多签或 Timelock 控制升级                        |

---

## 6、Foundry 实现示例

在我们的测试用例中，实现思路如下：  

* `Proxy` 只保存 `implementation` 和 `admin`
* 所有逻辑数据存在一个单独的 `Storage` 合约
* `Logic` 通过固定的 `slot` 读取数据

**这个也是OpenZeppelin UUPS/Transparent Proxy 的核心思路**

### 0. 存储合约  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Storage {
    uint256 private _value;

    function setValue(uint256 value) public {
        _value = value;
    }

    function getValue() public view returns (uint256) {
        return _value;
    }
}
```

### 1. 逻辑合约 V1

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Storage.sol";

contract LogicV1 {
    Storage public store;

    constructor(address _store) {
        store = Storage(_store);
    }

    function setValue(uint256 _value) public {
        store.setValue(_value);
    }

    function getValue() public view returns (uint256) {
        return store.getValue();
    }
}
```

### 2. 逻辑合约 V2（新增函数）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Storage.sol";
import "./LogicV1.sol";

contract LogicV2 is LogicV1 {
    constructor(address _store) LogicV1(_store) {}

    function increment() public {
        uint256 current = store.getValue();
        store.setValue(current + 1); // 使用 getter + setter
    }

}
```

### 3. 代理合约

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Proxy {
    address public implementation;
    address public admin;

    constructor(address _impl) {
        implementation = _impl;
        admin = msg.sender;
    }

    function upgradeTo(address _newImpl) public {
        require(msg.sender == admin, "Not admin");
        implementation = _newImpl;
    }

    fallback() external payable {
        address impl = implementation;
        require(impl != address(0), "No implementation");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
```

### 4. Foundry 测试

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LogicV1.sol";
import "../src/LogicV2.sol";
import "../src/Proxy.sol";
import "../src/Storage.sol";

contract UpgradeTest is Test {
    LogicV1 logicV1;
    Proxy proxy;
    Storage store;

    function setUp() public {
        store = new Storage();
        logicV1 = new LogicV1(address(store));
        proxy = new Proxy(address(logicV1));
    }

    function testUpgrade() public {
        LogicV1 proxyAsV1 = LogicV1(address(proxy));
        proxyAsV1.setValue(42);
        assertEq(proxyAsV1.getValue(), 42);

        LogicV2 logicV2 = new LogicV2(address(store));
        proxy.upgradeTo(address(logicV2));

        LogicV2 proxyAsV2 = LogicV2(address(proxy));
        proxyAsV2.increment();
        assertEq(proxyAsV2.getValue(), 43);
    }
}
```

**执行测试命令：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/UpgradeTest.t.sol -vvv
[⠊] Compiling...
[⠢] Compiling 5 files with Solc 0.8.29
[⠰] Solc 0.8.29 finished in 1.21s
Compiler run successful!

Ran 1 test for test/UpgradeTest.t.sol:UpgradeTest
[PASS] testUpgrade() (gas: 376528)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 10.86ms (3.15ms CPU time)

Ran 1 test suite in 355.58ms (10.86ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 6、可升级合约的最佳实践

1. **使用 OpenZeppelin Upgrades 插件** 生成安全的代理和逻辑合约。
2. **存储变量追加原则**：升级时只能新增状态变量到末尾。
3. **升级权限保护**：多签 + Timelock 防止管理员私自升级。
4. **充分测试**：用 Foundry 编写升级前后数据一致性测试。

---

## 7、扩展阅读：什么是 storage slot

* 在以太坊 EVM 中，每个合约的状态变量存储在 **固定的存储槽（storage slot）** 中。
* 每个 slot 是 32 字节大小，Solidity 按声明顺序分配变量到 slot。
* 在 **代理合约模式**下，逻辑合约通过 `delegatecall` 操作的是 **代理合约的 storage slot**，所以逻辑合约和代理合约的变量 slot 不能冲突，否则会覆盖状态。

简单来说，**slot 就是状态变量在合约存储中的编号位置**。

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