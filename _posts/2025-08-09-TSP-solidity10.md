---
layout: post
title: 《纸上谈兵·solidity》第 10 课：Solidity `fallback` / `receive` 函数 —— 合约如何收 ETH 和响应未知调用？
tags: solidity
mermaid: false
math: false
---  

在 Solidity 的世界里，大多数函数都有明确的名字、参数和用途。但还有两个比较特别的“隐形入口”函数：`receive()` 和 `fallback()`。
它们不需要（也不能）显式调用，却能在特定场景下自动触发，决定了一个合约**如何接收 ETH**，以及**如何应对未知调用**。

这节课，我们就来深入理解它们的触发机制、区别、常见风险，并通过 Foundry 实现完整的测试用例，验证各种交互场景。

---

## 1. 这两个函数是干嘛的？

**`receive()`**

* 专门用于接收 ETH 转账
* 必须是 `external payable`
* 仅在 `msg.data` 为空时触发

**`fallback()`**

* 用于处理**不存在的函数调用**，或者**带数据的 ETH 转账**
* 可以是 `payable` 或非 `payable`
* 在代理合约中，经常用来转发调用

> 可以理解成：
>
> * `receive` 是“收款专用”
> * `fallback` 是“万能接单员”，负责兜底处理各种不在菜单上的请求

---

## 2. 它们什么时候被调用？

用一个对照表最直观：

| 场景        | 是否有 `receive()` | 是否有 `fallback()` | 是否带数据 | 会触发          |
| --------- | --------------- | ---------------- | ----- | ------------ |
| ETH，无数据   | 有               | 任意               | 否     | `receive()`  |
| ETH，无数据   | 无               | `payable`        | 否     | `fallback()` |
| ETH，有数据   | 任意              | `payable`        | 是     | `fallback()` |
| ETH，有数据   | 任意              | 非 `payable`      | 是     | revert       |
| 无 ETH，有数据 | 任意              | 任意               | 是     | `fallback()` |

这样，你在测试时就可以根据表格预判合约的行为。

---

## 3. 不同转账方式的影响

不仅是函数本身的定义，调用方的转账方式也会影响触发情况和 gas 行为：

| 方法         | Gas 转发   | 失败时        | 返回值           | 常见用途              |
| ---------- | -------- | ---------- | ------------- | ----------------- |
| `transfer` | 2300 gas | revert     | 无             | 早期推荐，安全但已不再建议     |
| `send`     | 2300 gas | 返回 `false` | bool          | 不希望失败直接回滚的场景      |
| `call`     | 所有剩余 gas | 返回 `false` | (bool, bytes) | 推荐方式，灵活且可配 CEI 模式 |

在 EIP-1884 调整 gas 成本后，`transfer` 和 `send` 的 2300 gas 限制已经不能保证可靠执行，因此现在主流建议是用 `call`。

---

## 4. Foundry 实战

为了直观感受它们的触发规则，我们实现三个合约和一组测试。

### 发送方 `Sender.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Sender {
    function transferTo(address payable target) public payable {
        target.transfer(msg.value);
    }

    function sendTo(address payable target) public payable returns (bool) {
        return target.send(msg.value);
    }

    function callTo(address payable target) public payable returns (bool, bytes memory) {
        (bool success, bytes memory data) = target.call{value: msg.value}("");
        return (success, data);
    }

    function callWithData(address target, bytes calldata data) public payable returns (bool, bytes memory) {
        (bool success, bytes memory ret) = target.call{value: msg.value}(data);
        return (success, ret);
    }
}
```

### 接收方 `Receivers.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleReceiver {
    event GotReceive(address indexed sender, uint256 amount);
    event GotFallback(address indexed sender, uint256 amount, bytes data);

    receive() external payable {
        emit GotReceive(msg.sender, msg.value);
    }

    fallback() external payable {
        emit GotFallback(msg.sender, msg.value, msg.data);
    }
}

contract WriterReceiver {
    uint256 public counter;
    event GotAny(address indexed sender, uint256 amount);

    receive() external payable {
        counter += 1;
        emit GotAny(msg.sender, msg.value);
    }

    fallback() external payable {
        counter += 1;
        emit GotAny(msg.sender, msg.value);
    }
}

contract NonPayableFallback {
    fallback() external {
        // 非 payable，不能收 ETH
    }
}
```

### 测试用例 `FallbackReceive.t.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Sender.sol";
import "../src/Receivers.sol";

contract FallbackReceiveTest is Test {
    Sender sender;
    SimpleReceiver simple;
    WriterReceiver writer;
    NonPayableFallback nonPayable;

    function setUp() public {
        sender = new Sender();
        simple = new SimpleReceiver();
        writer = new WriterReceiver();
        nonPayable = new NonPayableFallback();
        vm.deal(address(this), 10 ether);
    }

    function testTransferToSimpleReceiver() public {
        sender.transferTo{value: 1 ether}(payable(address(simple)));
        assertEq(address(simple).balance, 1 ether);
    }

    function testTransferToWriterReceiverFails() public {
        vm.expectRevert();
        sender.transferTo{value: 1 ether}(payable(address(writer)));
    }

    function testCallToWriterReceiverSucceeds() public {
        (bool ok, ) = sender.callTo{value: 1 ether}(payable(address(writer)));
        assertTrue(ok);
        assertEq(address(writer).balance, 1 ether);
        assertEq(writer.counter(), 1);
    }

    function testSendToWriterReceiverReturnsFalse() public {
        bool sent = sender.sendTo{value: 1 ether}(payable(address(writer)));
        assertFalse(sent);
        assertEq(address(writer).balance, 0);
    }

    function testCallTriggersReceiveWhenNoData() public {
        (bool ok, ) = sender.callTo{value: 1 ether}(payable(address(simple)));
        assertTrue(ok);
        assertEq(address(simple).balance, 1 ether);
    }

    function testCallWithDataTriggersFallback() public {
        bytes memory someData = abi.encodeWithSignature("nonexistent()");
        (bool ok, ) = sender.callWithData{value: 0}(address(simple), someData);
        assertTrue(ok);
    }

    function testCallToNonPayableFallbackWithValueFails() public {
        (bool ok, ) = sender.callTo{value: 1 ether}(payable(address(nonPayable)));
        assertFalse(ok);
    }
}
```

**执行测试：**  

```bash
➜  counter git:(main) ✗ forge test --match-path test/FallbackReceive.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 540.39ms
Compiler run successful!

Ran 7 tests for test/FallbackReceive.t.sol:FallbackReceiveTest
[PASS] testCallToNonPayableFallbackWithValueFails() (gas: 28887)
[PASS] testCallToWriterReceiverSucceeds() (gas: 55238)
[PASS] testCallTriggersReceiveWhenNoData() (gas: 31262)
[PASS] testCallWithDataTriggersFallback() (gas: 18734)
[PASS] testSendToWriterReceiverReturnsFalse() (gas: 30670)
[PASS] testTransferToSimpleReceiver() (gas: 29019)
[PASS] testTransferToWriterReceiverFails() (gas: 29210)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 4.74ms (5.49ms CPU time)

Ran 1 test suite in 212.40ms (4.74ms CPU time): 7 tests passed, 0 failed, 0 skipped (7 total tests)
```

---

## 5. 安全建议

1. **保持简洁**
   `receive()` 和 `fallback()` 中避免复杂逻辑，减少重入风险。
2. **优先使用 `call`**
   取代 `transfer` / `send`，并配合 **Checks-Effects-Interactions** 模式。
3. **代理合约专用场景**
   在代理合约里，`fallback()` 用于转发调用时，应配合 `delegatecall` 并严格控制可调用目标。

---

## 6. 小结

* `receive()` 专收无数据 ETH
* `fallback()` 兜底处理未知调用和带数据的 ETH
* 转账方式不同，触发函数和安全性差异很大
* 写测试是理解触发规则的最快方式

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