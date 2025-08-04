---
layout: post
title: 《纸上谈兵·solidity》第 7 课：Solidity 函数可见性和修饰器 —— public 和 private 不只是权限标签
tags: solidity
mermaid: false
math: false
---  

在 Solidity 中，函数的可见性不仅决定了“谁可以调用”，更深层地影响到合约之间的交互方式、函数的 ABI 暴露、安全性设计和 gas 成本。本课还将介绍如何使用函数修饰器（modifier）实现访问控制与逻辑封装。

---

## 一、函数可见性的四种类型

Solidity 中的函数（和状态变量）支持 4 种可见性：

| 可见性     | 外部调用 | 合约内部调用       | 派生合约调用 | ABI 导出 | 典型用途            |
| :--------- | :------- | :----------------- | :----------- | :------- | :------------------ |
| `public`   | ✅        | ✅                  | ✅            | ✅        | 用户或其他合约调用  |
| `external` | ✅        | ❌（需 `this.f()`） | ✅            | ✅        | 节省 gas 的入口函数 |
| `internal` | ❌        | ✅                  | ✅            | ❌        | 内部逻辑、继承使用  |
| `private`  | ❌        | ✅                  | ❌            | ❌        | 完全私有逻辑        |

### 示例代码：

```solidity
contract Visibility {
    // 可被任何人调用
    function publicFn() public pure returns (string memory) {
        return "public";
    }

    // 只能从外部调用：Visibility(address).externalFn()
    function externalFn() external pure returns (string memory) {
        return "external";
    }

    // 合约内 & 子合约可调用
    function internalFn() internal pure returns (string memory) {
        return "internal";
    }

    // 仅当前合约内部可调用
    function privateFn() private pure returns (string memory) {
        return "private";
    }
}
```

### 继承中的可见性

子合约可以：

- ✅ **继承并 `override`** `public` 与 `internal` 函数
- ❌ 无法 `override` 或访问 `private` 函数

```solidity
contract Base {
    function visible() internal virtual {}
    function secret() private {}
}

contract Child is Base {
    function useVisible() public {
        visible(); // ✅
        // secret(); // ❌ compile error
    }
}
```

### `external` 是不是更安全？

不是。`external` 函数依旧公开访问，只是：

- gas 成本更低（尤其是动态数组传参）
- 不能合约内部直接调用（除非使用 `this.` 前缀）

```solidity
function update(uint[] calldata data) external {
    // ...
}
```

---

## 二、修饰器（modifier）的作用

Modifier 是 Solidity 的语法糖，允许在函数执行前或后添加逻辑 —— **非常适合权限控制、状态检查、reentrancy 防御等场景**。

### 常见用途：

1. **权限控制**（如 onlyOwner）
2. **重入保护**
3. **状态锁定**
4. **函数执行顺序约束**

### 示例：访问控制修饰器

```solidity
modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}

function sensitiveAction() public onlyOwner {
    // 只有 owner 才能执行
}
```

- `_;` 表示“继续执行被修饰的函数”
- `modifier` 中的逻辑优先于主函数体执行。
- `modifier` 的执行是**链式调用**（按声明顺序，即从左往右执行），且可以在同一函数上附加多个 modifiers。

---

## 三、Foundry 示例

我们来编写一个带有函数可见性示例的测试用例：

### 合约：Visibility.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Visibility {
    address public owner = msg.sender;

    function publicFunc() public pure returns (string memory) {
        return "public";
    }

    function externalFunc() external pure returns (string memory) {
        return "external";
    }

    function internalFunc() internal pure returns (string memory) {
        return "internal";
    }

    function privateFunc() private pure returns (string memory) {
        return "private";
    }

    function callInternal() public pure returns (string memory) {
        return internalFunc();
    }

    function callPrivate() public pure returns (string memory) {
        return privateFunc();
    }
}
```
### 测试：test/Visibility.t.sol

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Visibility.sol";

contract VisibilityTest is Test {
    Visibility vis;

    function setUp() public {
        vis = new Visibility();
    }

    function testPublic() public {
        assertEq(vis.publicFunc(), "public");
    }

    function testExternal() public {
        // 只能外部调用
        string memory val = Visibility(address(vis)).externalFunc();
        assertEq(val, "external");
    }

    function testInternalAccess() public {
        // 内部函数间接调用
        assertEq(vis.callInternal(), "internal");
    }

    function testPrivateAccess() public {
        assertEq(vis.callPrivate(), "private");
    }
}
```

**执行测试命令：** 

```bash
➜  counter git:(main) ✗ forge test --match-path test/Visibility.t.sol -vvv   
[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 544.36ms
Compiler run successful!

Ran 4 tests for test/Visibility.t.sol:VisibilityTest
[PASS] testExternal() (gas: 10240)
[PASS] testInternalAccess() (gas: 10329)
[PASS] testPrivateAccess() (gas: 10285)
[PASS] testPublic() (gas: 10293)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 5.25ms (4.99ms CPU time)

Ran 1 test suite in 189.08ms (5.25ms CPU time): 4 tests passed, 0 failed, 0 skipped (4 total tests)
```

---

## 四、`modifier` 示例

### 合约：ModifierVault.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ModifierVault {
    address public owner;
    uint public balance;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function deposit() public payable {
        balance += msg.value;
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(balance);
        balance = 0;
    }
}
```

### 测试：test/ModifierVault.t.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import "../src/ModifierVault.sol";

contract ModifierTest is Test {
    ModifierVault vault;
    address alice = address(0x1);
    address bob = address(0x2);

    // 添加 receive 用于接收 ETH
    receive() external payable {}

    function setUp() public {
        vault = new ModifierVault();
        vm.deal(alice, 1 ether);
    }

    function testOnlyOwnerCanWithdraw() public {
        // alice 向 vault 存款
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        // 使用合约拥有者 address(this) 执行提款
        vault.withdraw();

        // 验证余额清零
        assertEq(vault.balance(), 0);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        vm.prank(bob);
        vm.expectRevert("Not owner"); // 或自定义错误选择器
        vault.withdraw();
    }
}
```

**执行测试命令：**  

```bash
➜  counter git:(main) ✗ forge test --match-path test/ModifierVault.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 558.83ms
Compiler run successful!

Ran 2 tests for test/ModifierVault.t.sol:ModifierTest
[PASS] testOnlyOwnerCanWithdraw() (gas: 36840)
[PASS] test_RevertWhen_NonOwnerWithdraws() (gas: 13505)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 5.30ms (1.59ms CPU time)

Ran 1 test suite in 190.26ms (5.30ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 五、`pure` 和 `view` 函数修饰符 —— 状态访问语义的标识

在 Solidity 中，函数除了权限可见性（`public` / `private` 等），还可以声明它们对状态变量的访问行为。这就是 `pure` 和 `view` 修饰符的用途：

| 修饰符   | 能否读取状态变量 | 能否修改状态变量 | 能否发送交易 | 示例用途             |
| :------- | :--------------- | :--------------- | :----------- | :------------------- |
| `pure`   | ❌                | ❌                | ❌            | 数学运算，纯逻辑函数 |
| `view`   | ✅                | ❌                | ❌            | 查询、只读状态       |
| 无修饰符 | ✅                | ✅                | ✅            | 默认允许任何操作     |

### `pure` 修饰符：完全不接触状态的函数

`pure` 修饰符用于标记那些 **不读取也不修改任何合约状态（包括 `msg.sender`, `block.timestamp` 等）** 的函数。

```solidity
function add(uint a, uint b) public pure returns (uint) {
    return a + b;
}
```

**特性**：

* 编译器静态检查，不允许访问任何状态变量或全局变量
* 理论上可以在链下完全复现，无需部署或调用链上数据

### `view` 修饰符：只读函数

`view` 表示该函数 **读取状态变量，但不允许写入（修改）状态**。

```solidity
uint public totalSupply = 100;

function getSupply() public view returns (uint) {
    return totalSupply;
}
```

**特性**：

* 常用于 getter 函数
* 只能读取状态，不能写入
* 使用 view 函数是读取链上状态数据的标准方法

### 编译器强制规则举例

```solidity
uint public counter = 0;

function get() public pure returns (uint) {
    return counter; // ❌ 编译器报错：pure 函数不能读取状态变量
}

function read() public view returns (uint) {
    return counter; // ✅ 允许读取
}

function write() public {
    counter += 1; // ✅ 可读可写
}
```

### 测试示例（Foundry）

**合约：`src/MathLib.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MathLib {
    uint public base = 10;

    function addPure(uint a, uint b) public pure returns (uint) {
        return a + b;
    }

    function addView(uint x) public view returns (uint) {
        return base + x;
    }
}
```

**测试代码：`test/MathLib.t.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MathLib.sol";

contract MathTest is Test {
    MathLib math;

    function setUp() public {
        math = new MathLib();
    }

    function testPureAdd() public view {
        assertEq(math.addPure(2, 3), 5);
    }

    function testViewAdd() public view {
        assertEq(math.addView(5), 15);
    }
}
```

**执行测试**：  

```bash
➜  counter git:(main) ✗ forge test --match-path test/MathLib.t.sol -vvv      
[⠊] Compiling...
[⠒] Compiling 2 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 534.57ms
Compiler run successful!

Ran 2 tests for test/MathLib.t.sol:MathTest
[PASS] testPureAdd() (gas: 9940)
[PASS] testViewAdd() (gas: 11665)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 5.33ms (3.01ms CPU time)

Ran 1 test suite in 189.73ms (5.33ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 六、函数可见性的设计建议

| 场景                                 | 建议使用   | 原因                                             |
| :----------------------------------- | :--------- | :----------------------------------------------- |
| 用户或外部合约调用的入口函数         | `external` | 节省 gas，明确只供外部访问                       |
| 需要外部也可内部复用的函数           | `public`   | 可在合约内部和外部同时调用                       |
| 仅合约内部或子合约调用的辅助函数     | `internal` | 控制作用域，避免被误用或暴露接口                 |
| 私有状态修改/校验/哈希计算等内部逻辑 | `private`  | 强限制，仅当前合约可访问，增强封装性             |
| 不访问任何状态或区块变量，仅进行计算 | `pure`     | 完全独立，节省 gas，适用于纯逻辑计算             |
| 读取状态变量或全局上下文（如 block） | `view`     | 只读合约状态，不能修改，适用于查询或只读函数场景 |

---

## 七、课后练习

1. 编写一个 `Bank` 合约，要求只有 `owner` 能调用 `withdraw()`。
2. 在 `Bank` 合约中添加一个 `internal` 函数来计算利息。
3. 使用 Foundry 为这两个函数编写测试用例，确保权限控制生效。

---

## 下一课预告

**第 8 课：Solidity 中的继承与接口 —— 模块化不是“复制粘贴”的借口**

在下一课中，我们将学习 Solidity 中的合约继承、接口、抽象合约等代码复用机制，掌握智能合约的模块化和解耦技巧。

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