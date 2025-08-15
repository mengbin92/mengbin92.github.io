---
layout: post
title: 《纸上谈兵·solidity》第 13 课：Solidity 低级调用 call/delegatecall/staticcall —— 直接和 EVM“对话”
tags: solidity
mermaid: false
math: false
--- 

## 1. 三种低级调用方式对比

| 调用方式           | 是否切换上下文（storage/msg.sender/msg.value） | 是否能改状态 | 特点与用途                   |
|:-------------- |:------------------------------------- |:------ |:----------------------- |
| `call`         | ✅ 切换到被调用合约                            | ✅      | 最通用的外部调用，可带 ETH，可调用任意函数 |
| `delegatecall` | ❌ 保持当前合约上下文                           | ✅      | 代理模式核心，让当前合约执行别人的代码     |
| `staticcall`   | ✅ 切换到被调用合约                            | ❌      | 安全读取外部数据，不改状态           |

> 记忆口诀：
>
> * **call**：切场景、能改状态。
> * **delegatecall**：不切场景、能改状态。
> * **staticcall**：切场景、不能改状态。

---

## 2. 原理解析

在 EVM 中，外部调用本质是一次 `CALL` 指令：

```txt
CALL(gas, to, value, in_offset, in_size, out_offset, out_size)
```

* **gas**：给被调用者的剩余 gas。
* **to**：目标地址。
* **value**：转账的 wei 数量。
* **in\_offset / in\_size**：内存中输入数据的位置和长度（ABI 编码后）。
* **out\_offset / out\_size**：输出数据存放位置和长度。

`delegatecall` 与 `call` 的主要区别是：

* `delegatecall` 不会更改 `msg.sender` 和 `msg.value`。
* 存储上下文（storage slot）不切换，直接写到当前合约。

`staticcall` 的底层指令是 `STATICCALL`，它会禁止在调用期间修改状态。

---

## 3. call 示例

**被调用合约：Callee.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Callee {
    uint256 public value;

    event ValueSet(uint256 newValue);

    function setValue(uint256 _v) external payable {
        value = _v;
        emit ValueSet(_v);
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}
```

**调用方合约：Caller.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Caller {
    // 通过 call 调用 setValue
    function callSetValue(address _callee, uint256 _v) external payable {
        (bool success, ) = _callee.call(
            abi.encodeWithSignature("setValue(uint256)", _v)
        );
        require(success, "call failed");
    }

    // 通过 staticcall 调用 getValue
    function callGetValue(address _callee) external view returns (uint256) {
        (, bytes memory data) = _callee.staticcall(
            abi.encodeWithSignature("getValue()")
        );
        return abi.decode(data, (uint256));
    }
}
```

---

## 4. delegatecall 示例（代理模式）

**逻辑合约：Logic.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Logic {
    uint256 public value;

    function setValue(uint256 _v) external {
        value = _v;
    }
}
```

**代理合约：Proxy.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Proxy {
    uint256 public value;

    function delegateSetValue(address _logic, uint256 _v) external {
        (bool success, ) = _logic.delegatecall(
            abi.encodeWithSignature("setValue(uint256)", _v)
        );
        require(success, "delegatecall failed");
    }
}
```

> **注意**：`Logic` 和 `Proxy` 必须有**完全一致的存储布局**，否则变量会错位（Storage Collision）。

---

## 5. Foundry 测试

`test/LowLevelCall.t.sol`：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Callee.sol";
import "../src/Caller.sol";
import "../src/Logic.sol";
import "../src/Proxy.sol";

contract LowLevelCallTest is Test {
    Callee callee;
    Caller caller;
    Logic logic;
    Proxy proxy;

    function setUp() public {
        callee = new Callee();
        caller = new Caller();
        logic = new Logic();
        proxy = new Proxy();
    }

    function testCallSetValue() public {
        caller.callSetValue(address(callee), 42);
        assertEq(callee.value(), 42);
    }

    function testStaticCallGetValue() public {
        caller.callSetValue(address(callee), 99);
        uint256 v = caller.callGetValue(address(callee));
        assertEq(v, 99);
    }

    function testDelegateCall() public {
        proxy.delegateSetValue(address(logic), 123);
        assertEq(proxy.value(), 123);
        assertEq(logic.value(), 0); // Logic 本身不变
    }
}
```

**执行测试命令：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/LowLevelCall.t.sol -vvv
[⠊] Compiling...
[⠊] Compiling 2 files with Solc 0.8.29
[⠒] Solc 0.8.29 finished in 1.91s
Compiler run successful!

Ran 3 tests for test/LowLevelCall.t.sol:LowLevelCallTest
[PASS] testCallSetValue() (gas: 39545)
[PASS] testDelegateCall() (gas: 41920)
[PASS] testStaticCallGetValue() (gas: 41426)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 11.37ms (7.34ms CPU time)

Ran 1 test suite in 616.04ms (11.37ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
```

---

## 6. 常见陷阱

- **call 未检查返回值**
    ```solidity
    addr.call(data); // ❌ 忽略 success
    ```

    必须：

    ```solidity
    (bool success, bytes memory ret) = addr.call(data);
    require(success, "call failed");
    ```
- **delegatecall 存储错乱**：如果 `Logic` 的第一个状态变量是 `address owner` 而 `Proxy` 是 `uint256 value`，那么写入会覆盖错误的 slot。
- **call 触发重入攻击**：外部调用前先更新状态（Checks-Effects-Interactions 模式）。
- **staticcall 不能修改状态**：调用改状态的函数会直接 revert。

---

## 7. 最佳实践

| 场景              | 推荐方式           | 原因              |
|:--------------- |:-------------- |:--------------- |
| 调用外部合约并可能携带 ETH | `call`         | 灵活，可同时发送数据和 ETH |
| 代理模式 / 可升级合约    | `delegatecall` | 保持存储一致，执行外部逻辑   |
| 只读查询外部合约数据      | `staticcall`   | 只读，避免误改状态       |

---

## 8. 总结

* **call**：像跨合同打电话，带钱和信息。
* **delegatecall**：让别人用你的钱包执行代码。
* **staticcall**：借别人的计算器算一算，不动任何钱。

低级调用是合约开发的“裸金属编程”，没有编译器的保护网，一旦出错，可能是**重入漏洞**、**资金丢失**或**数据错乱**。

**最重要的建议**：

* **始终检查 `success`**
* **先修改状态再外部调用**
* **代理模式要保持存储一致**

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