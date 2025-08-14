---
layout: post
title: 《纸上谈兵·solidity》第 12 课：Solidity 函数选择器与 ABI 编码原理
tags: solidity
mermaid: false
math: false
--- 

在以太坊的世界里，**合约函数调用不是“直接调用函数”，而是发送一段经过 ABI 编码的二进制数据**。这些数据不仅包含了调用哪个函数的信息，还包括函数参数的序列化内容。理解 ABI 编码与函数选择器，可以帮助我们：

- 调试交易数据（从原始 `data` 解读调用意图）
- 手写低级调用（`call` / `delegatecall`）
- 分析合约安全问题（例如函数签名冲突）

---

## 1. 什么是函数选择器（Function Selector）

**函数选择器**是函数调用数据的前 4 个字节，用来标识调用的是哪一个函数。  
它的生成方式是：

```txt
selector = keccak256("函数名(参数类型列表)") 前 4 个字节
```

例如：

```solidity
function transfer(address to, uint256 amount) public;
```

计算：

```txt
keccak256("transfer(address,uint256)") 
= 0xa9059cbb...
selector = 0xa9059cbb
```

**作用**：当 EVM 收到一笔交易时，会查看 `msg.data` 的前 4 个字节，通过函数选择器找到匹配的函数，然后解码后续数据作为参数。

---

## 2. ABI 编码流程

ABI（Application Binary Interface）规定了参数如何序列化。以 `transfer(address,uint256)` 调用为例：

1. 计算函数选择器：
   ```txt
   0xa9059cbb
   ```
2. 按 ABI 规则编码参数：
   * `address` 类型是 20 字节，要补齐到 32 字节（左填充 0）
   * `uint256` 类型是 32 字节（大端序，左填充 0）
3. 拼接：
   ```txt
   data = 0xa9059cbb
           000000000000000000000000<to地址20字节>
           000000000000000000000000000000000000000000000000<amount>
   ```
---

## 3. Solidity 中的函数选择器使用

我们可以通过 Solidity 内置属性获取函数选择器：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SelectorExample {
    function getSelector() public pure returns (bytes4) {
        return this.transfer.selector;
    }

    function transfer(address to, uint256 amount) public pure returns (bool) {
        return true;
    }
}
```

---

## 4. 使用 Foundry 验证 ABI 编码

我们用 Foundry 写一个测试，验证 ABI 编码是否正确。

**src/SelectorExample.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SelectorExample {
    function transfer(address to, uint256 amount) public pure returns (bool) {
        return true;
    }
}
```

**test/SelectorExample.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/SelectorExample.sol";

contract SelectorExampleTest is Test {
    SelectorExample example;

    function setUp() public {
        example = new SelectorExample();
    }

    function testSelector() public {
        bytes4 selector = example.transfer.selector;
        assertEq(selector, bytes4(keccak256("transfer(address,uint256)")));
    }

    function testABIEncoding() public {
        address to = address(0x123);
        uint256 amount = 100;

        bytes memory encoded = abi.encodeWithSelector(
            example.transfer.selector,
            to,
            amount
        );

        emit log_bytes(encoded);
    }
}
```

运行：

```bash
➜  counter git:(main) ✗ forge test --match-path test/SelectorExample.t.sol -vvv
[⠊] Compiling...
[⠆] Compiling 1 files with Solc 0.8.29
[⠰] Solc 0.8.29 finished in 1.26s
Compiler run successful with warnings:
Warning (5667): Unused function parameter. Remove or comment out the variable name to silence this warning.
 --> src/SelectorExample.sol:5:23:
  |
5 |     function transfer(address to, uint256 amount) public pure returns (bool) {
  |                       ^^^^^^^^^^

Warning (5667): Unused function parameter. Remove or comment out the variable name to silence this warning.
 --> src/SelectorExample.sol:5:35:
  |
5 |     function transfer(address to, uint256 amount) public pure returns (bool) {
  |                                   ^^^^^^^^^^^^^^


Ran 2 tests for test/SelectorExample.t.sol:SelectorExampleTest
[PASS] testABIEncoding() (gas: 5278)
Logs:
  0xa9059cbb00000000000000000000000000000000000000000000000000000000000001230000000000000000000000000000000000000000000000000000000000000064

[PASS] testSelector() (gas: 5512)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 8.14ms (2.12ms CPU time)

Ran 1 test suite in 438.24ms (8.14ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

输出的 `log_bytes` 会显示完整的 ABI 编码结果。

---

## 5. 低级调用与函数选择器

有时我们需要使用 `call` 来调用其他合约的函数：

```solidity
(bool success, bytes memory data) = target.call(
    abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        to,
        amount
    )
);
```

* `abi.encodeWithSelector`：手动指定函数选择器
* `abi.encodeWithSignature`：直接用签名字符串计算选择器

---

## 6. 安全注意事项

1. **函数签名冲突：** 不同函数如果签名哈希的前 4 个字节相同（极低概率），可能导致调用混淆。
2. **低级调用缺乏类型检查：** 使用 `call` 时不会检查参数类型是否匹配，需谨慎验证输入。
3. **解码风险：** 用 `abi.decode` 时必须确保数据格式正确，否则会 revert。

---

## 总结

* **函数选择器**是调用函数的“身份证”
* **ABI 编码**定义了参数如何序列化
* 熟悉函数选择器和 ABI 编码，可以进行底层调试、合约互操作以及安全分析

**练习建议：**

1. 计算几个常见 ERC20 函数的选择器
2. 用 Foundry 编写测试，验证 `abi.encodeWithSelector` 与手工拼接结果一致
3. 尝试用低级调用向一个已部署的 ERC20 发送交易

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