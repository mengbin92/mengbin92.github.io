---
layout: post
title: Foundry 实战：智能合约 Event 测试全攻略
tags: solidity
mermaid: false
math: false
---  

在 Solidity 开发中，`event` 是智能合约与链下系统交互的重要桥梁。在单元测试中验证事件的触发和参数正确性，是保证合约逻辑正确的关键环节。本文将结合 **Foundry**，全面讲解事件的测试方法，包括严格顺序匹配、顺序忽略，以及解码非 `indexed` 参数。

---

## 1. Foundry 测试单个事件

假设我们有一个简单的 Token 合约，`transfer` 函数会触发一个 `Transfer` 事件：

```solidity
contract Token {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function transfer(address to, uint256 amount) external {
        emit Transfer(msg.sender, to, amount);
    }

    function batchTransfer(address[] calldata recipients, uint256 amount) external {
        for (uint i = 0; i < recipients.length; i++) {
            emit Transfer(msg.sender, recipients[i], amount);
        }
    }
}
```

### 测试单个事件

在 Foundry 中，可以使用 `vm.expectEmit` 声明预期事件，再调用触发事件的函数：

```solidity
function testEmitTransfer() public {
    address to = address(0xBEEF);
    uint256 amount = 100;

    // 告诉 Foundry：我期望捕捉一个 Transfer 事件
    vm.expectEmit(true, true, false, true);

    // 写出期望事件
    emit Token.Transfer(address(this), to, amount);

    // 调用触发事件的函数
    token.transfer(to, amount);
}
```

#### 参数解释

`vm.expectEmit(checkTopic1, checkTopic2, checkTopic3, checkData)`

* `checkTopic1~3`：是否检查事件中 `indexed` 参数
* `checkData`：是否检查非 `indexed` 数据

通过这种方式，你可以灵活忽略不需要关注的参数。

---

## 2. 测试多个事件（严格顺序）

对于批量操作，可能会触发多个事件。以 `BatchToken` 为例：

```solidity
contract BatchToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function batchTransfer(address[] calldata recipients, uint256 amount) external {
        for (uint i = 0; i < recipients.length; i++) {
            emit Transfer(msg.sender, recipients[i], amount);
        }
    }
}
```

### 顺序匹配示例

```solidity
function testBatchTransferEmitsMultipleEvents() public {
    address ;
    recipients[0] = address(0xA11CE);
    recipients[1] = address(0xB0B);
    recipients[2] = address(0xCAro1);

    uint256 amount = 100;

    // 每个事件都需要单独 expectEmit
    vm.expectEmit(true, true, false, true);
    emit BatchToken.Transfer(address(this), recipients[0], amount);

    vm.expectEmit(true, true, false, true);
    emit BatchToken.Transfer(address(this), recipients[1], amount);

    vm.expectEmit(true, true, false, true);
    emit BatchToken.Transfer(address(this), recipients[2], amount);

    token.batchTransfer(recipients, amount);
}
```

⚠️ 注意：Foundry **严格按照事件顺序匹配**，如果顺序不一致，测试会失败。  

---

### 事件顺序错误示例

```solidity
vm.expectEmit(true, true, false, true);
emit BatchToken.Transfer(address(this), recipients[1], amount); // 顺序错误

vm.expectEmit(true, true, false, true);
emit BatchToken.Transfer(address(this), recipients[0], amount);

token.batchTransfer(recipients, amount);
```

运行时会报错：

```bash
...
[FAIL: log != expected log] testBatchTransferWrongOrder() (gas: 25687)
Traces:
  [25687] TokenTest::testBatchTransferWrongOrder()
    ├─ [0] VM::expectEmit(true, true, false, true)
    │   └─ ← [Return]
    ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x0000000000000000000000000000000000000B0b, amount: 100)
    ├─ [0] VM::expectEmit(true, true, false, true)
    │   └─ ← [Return]
    ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x00000000000000000000000000000000000A11cE, amount: 100)
    ├─ [0] VM::expectEmit(true, true, false, true)
    │   └─ ← [Return]
    ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x0000000000000000000000000000000000C0FFEE, amount: 100)
    ├─ [7727] Token::batchTransfer([0x00000000000000000000000000000000000A11cE, 0x0000000000000000000000000000000000000B0b, 0x0000000000000000000000000000000000C0FFEE], 100)
    │   ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x00000000000000000000000000000000000A11cE, amount: 100)
    │   ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x0000000000000000000000000000000000000B0b, amount: 100)
    │   ├─ emit Transfer(from: TokenTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], to: 0x0000000000000000000000000000000000C0FFEE, amount: 100)
    │   └─ ← [Stop]
    └─ ← [Revert] log != expected log
...
```

---

## 3. 忽略事件顺序（只验证存在性）

如果不关心顺序，可以使用 `vm.recordLogs()` + `vm.getRecordedLogs()` 手动检查事件：

```solidity
vm.recordLogs();
token.batchTransfer(recipients, amount);
Vm.Log[] memory entries = vm.getRecordedLogs();

// 遍历日志，验证事件存在
bool foundAlice;
for (uint i = 0; i < entries.length; i++) {
    bytes32 expectedSig = keccak256("Transfer(address,address,uint256)");
    assertEq(entries[i].topics[0], expectedSig);
    address to = address(uint160(uint256(entries[i].topics[2])));
    if (to == recipients[0]) foundAlice = true;
}
assertTrue(foundAlice, "Alice not found");
```

这种方式不依赖顺序，非常适合批量事件或异步事件验证。

---

## 4. 解码非 indexed 参数（data）

事件的非 `indexed` 参数会存放在 `data` 字段，需要用 `abi.decode` 解码：

```solidity
for (uint i = 0; i < entries.length; i++) {
    // 解码 indexed 参数
    address from = address(uint160(uint256(entries[i].topics[1])));
    address to   = address(uint160(uint256(entries[i].topics[2])));

    // 解码 data
    uint256 decodedAmount = abi.decode(entries[i].data, (uint256));

    assertEq(decodedAmount, amount);
}
```

这样就能同时验证 **indexed** 和 **非 indexed** 参数。

完整的测试文件内容如下：  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    Token token;

    function setUp() public {
        token = new Token();
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function testEmitTransfer() public {
        address to = address(0xBEEF);
        uint256 amount = 100;

        // 告诉 Foundry：我期望捕捉一个 Transfer 事件
        vm.expectEmit(true, true, false, true);

        // 写出期望事件
        emit Token.Transfer(address(this), to, amount);

        // 调用触发事件的函数
        token.transfer(to, amount);
    }

    function testBatchTransferEmitsMultipleEvents() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0xA11CE);
        recipients[1] = address(0xB0B);
        recipients[2] = address(0xC0FFEE);

        uint256 amount = 100;

        // 每个事件都需要单独 expectEmit
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[0], amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[1], amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[2], amount);

        token.batchTransfer(recipients, amount);
    }

    function testBatchTransferWrongOrder() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0xA11CE);
        recipients[1] = address(0xB0B);
        recipients[2] = address(0xC0FFEE);

        uint256 amount = 100;

        // 每个事件都需要单独 expectEmit
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[1], amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[0], amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), recipients[2], amount);

        token.batchTransfer(recipients, amount);
    }

    function testBatchTransferIgnoreOrder() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0xA11CE);
        recipients[1] = address(0xB0B);
        recipients[2] = address(0xC0FFEE);

        uint256 amount = 100;

        // 开始记录日志
        vm.recordLogs();

        // 执行函数
        token.batchTransfer(recipients, amount);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 3, "Should emit 3 events");

        // keccak256("Transfer(address,address,uint256)")
        bytes32 expectedSig = keccak256("Transfer(address,address,uint256)");

        bool foundAlice;
        for (uint i = 0; i < entries.length; i++) {
            assertEq(entries[i].topics[0], expectedSig);

            // indexed 参数
            address from = address(uint160(uint256(entries[i].topics[1])));
            address to = address(uint160(uint256(entries[i].topics[2])));

            // 非 indexed 参数
            uint256 decodedAmount = abi.decode(entries[i].data, (uint256));

            emit log_named_address("to", to);
            emit log_named_uint("decodedAmount", decodedAmount);

            assertEq(from, address(this), "Wrong sender");
            assertEq(decodedAmount, amount, "Wrong amount");

            assertEq(entries[i].topics[0], expectedSig);
            if (to == recipients[0]) foundAlice = true;
        }
        assertTrue(foundAlice, "Alice not found");

    }
}
```

---

## 5. 总结

* `vm.expectEmit` 适合严格顺序匹配的事件测试。
* `vm.recordLogs` + `getRecordedLogs` 适合忽略顺序或复杂验证。
* 非 indexed 参数需要 `abi.decode` 解码。
* Foundry 的事件测试灵活强大，可适应各种场景：单个事件、多事件、顺序敏感或顺序无关。

通过掌握这些技巧，我们就可以在 Foundry 中高效、精准地验证 Solidity 合约事件逻辑，保证合约行为与预期一致。

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