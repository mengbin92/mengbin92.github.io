---
layout: post
title: 《纸上谈兵·solidity》第 11 课：Solidity 错误处理与异常机制 —— 让合约优雅地失败 
tags: solidity
mermaid: false
math: false
--- 

在 Solidity 智能合约开发中，**失败并不可怕**，可怕的是失败后状态不明确、资金不安全、调用方摸不着头脑。EVM 的一个重要特性是：当合约执行中发生错误时，**会回滚所有状态更改**，并退还未使用的 Gas。因此，正确使用错误处理机制，能够让合约在异常情况下**安全地停止**，而不是留下一地鸡毛。

---

### 一、 三种主要的错误处理方式

| 语句                          | 用途                 | 特点                                           |
|:--------------------------- |:------------------ |:-------------------------------------------- |
| `require(condition, "msg")` | 检查外部输入、函数前置条件      | 条件不满足时抛错并回滚，退还剩余 Gas，带错误信息                   |
| `revert("msg")`             | 主动触发错误并中断执行        | 常用于多层逻辑判断中提前退出                               |
| `assert(condition)`         | 检查内部不变量（invariant） | 条件为 `false` 时触发 Panic 错误，消耗所有剩余 Gas，表示严重逻辑错误 |

---

### 二、 自定义错误（Custom Error）

Solidity 0.8.4 引入了 **Custom Error**，可以用来代替 `require`/`revert` 的字符串错误信息，优势是 **更节省 Gas**。

```solidity
error Unauthorized(address caller);
error InsufficientBalance(uint256 available, uint256 required);
```

触发方法：

```solidity
if (msg.sender != owner) {
    revert Unauthorized(msg.sender);
}
```

---

### 三、 错误触发后的状态回滚

* **原子性**：Solidity 中一次交易内的所有状态修改要么全部生效，要么全部回滚。
* **资金安全**：如果中途发生 `require`/`revert`/`assert` 抛错，之前的转账、变量修改统统不生效。
* **多步操作**：需要考虑调用链上其他合约的回滚影响。

---

### 四、 Foundry 示例

**src/Bank.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Bank {
    mapping(address => uint256) public balances;
    address public owner;

    error Unauthorized(address caller);
    error InsufficientBalance(uint256 available, uint256 required);

    constructor() {
        owner = msg.sender;
    }

    function deposit() external payable {
        require(msg.value > 0, "Deposit must be > 0");
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        uint256 bal = balances[msg.sender];
        if (bal < amount) {
            revert InsufficientBalance(bal, amount);
        }
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function emergencyWithdraw() external {
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender);
        }
        payable(owner).transfer(address(this).balance);
    }

    function internalCheck() external pure {
        // 如果条件不满足，将触发 Panic(uint256) 错误
        assert(false);
    }
}
```

**test/Bank.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Bank.sol";

contract BankTest is Test {
    Bank bank;
    address user1 = address(0x123);
    address user2 = address(0x456);

    function setUp() public {
        bank = new Bank();
        vm.deal(user1, 5 ether);
        vm.deal(user2, 2 ether);
    }

    function testDeposit() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user1), 1 ether);
    }

    function testWithdrawSuccess() public {
        vm.startPrank(user1);
        bank.deposit{value: 2 ether}();
        bank.withdraw(1 ether);
        assertEq(bank.balances(user1), 1 ether);
        vm.stopPrank();
    }

    function testWithdrawFail_CustomError() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Bank.InsufficientBalance.selector,
                0,
                1 ether
            )
        );
        bank.withdraw(1 ether);
    }

    function testEmergencyWithdrawFail_Unauthorized() public {
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Bank.Unauthorized.selector,
                user2
            )
        );
        bank.emergencyWithdraw();
    }

    function testAssertPanic() public {
        vm.expectRevert(); // Panic(uint256) is a generic revert for assert
        bank.internalCheck();
    }
}
```

**执行测试：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/Bank.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 2 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 528.49ms
Compiler run successful!

Ran 5 tests for test/Bank.t.sol:BankTest
[PASS] testAssertPanic() (gas: 8270)
[PASS] testDeposit() (gas: 42157)
[PASS] testEmergencyWithdrawFail_Unauthorized() (gas: 14240)
[PASS] testWithdrawFail_CustomError() (gas: 14957)
[PASS] testWithdrawSuccess() (gas: 51239)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 4.35ms (2.73ms CPU time)

Ran 1 test suite in 207.34ms (4.35ms CPU time): 5 tests passed, 0 failed, 0 skipped (5 total tests)
```

---

### 五、 安全建议

1. **外部输入用 `require` 检查**，防止无效参数进入业务逻辑。
2. **多分支逻辑中可用 `revert` 提前退出**，保持代码可读性。
3. **关键不变量用 `assert` 保证**，若断言失败说明合约存在漏洞。
4. **推荐使用 Custom Error** 代替字符串错误信息，节省部署和执行 Gas。
5. **测试必须覆盖失败场景**，验证合约在异常情况下的安全性和可预期行为。

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
