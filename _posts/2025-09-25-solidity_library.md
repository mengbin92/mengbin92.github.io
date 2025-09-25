---
layout: post
title: Solidity Library 中的常见报错与设计思考
tags: solidity
mermaid: false
math: false
---  

在学习和使用 Solidity 时，很多人第一次接触 `library` 的时候，都会遇到这样的报错信息：

```javascript
TypeError: Name has to refer to a user-defined type
```

为什么会报这个错？为什么库函数经常被设计为使用 `storage` 引用？现在我们就通过一个实验来展示 `storage` 与 `memory` 的实际区别。

---

## 一、报错：`Name has to refer to a user-defined type`

在 Solidity 中，`library` 有两种典型的使用方式：

1. **直接调用库函数**
2. **通过 `using ... for` 给类型扩展方法**

第二种方式是大家常用的，例如：

```solidity
struct Data { uint value; }

library DataLib {
    function increment(Data storage self) public {
        self.value += 1;
    }
}

contract C {
    using DataLib for Data;

    Data public d;

    function test() public {
        d.increment(); // 自动传入 d
    }
}
```

但是，如果你写成：

```solidity
library DataLib {
    function increment(uint storage self) public { 
        self += 1;
    } 
}
```

编译时就会报错：

```javascript
TypeError: Name has to refer to a user-defined type
```

原因在于：**通过 `using ... for` 的库函数，第一个参数必须是用户自定义类型（struct 或 enum）**，而不能是 `uint`、`address` 等内置类型。

---

## 二、为什么库函数使用 `storage` 引用？

在 Solidity 中，参数有三种数据位置：

* `storage` —— 持久化存储在区块链上的数据
* `memory` —— 函数调用过程中的临时内存
* `calldata` —— 外部调用时的只读数据区

如果库函数参数写成 `memory`：

```solidity
function increment(Data memory self) public {
    self.value += 1;
}
```

调用时会复制一份数据，函数里对副本的修改不会影响合约状态。

而如果使用 `storage`：

```solidity
function increment(Data storage self) public {
    self.value += 1; // 直接修改合约里的状态
}
```

那么修改会直接作用在合约的存储上，符合大多数“扩展方法”的预期。

**好处：**

* 避免复制大型数据结构，节省 gas
* 语义更接近“对象方法”，调用时就像在修改原对象
* 确保对合约状态的修改是持久的

---

## 三、对比实验：`storage` vs `memory`

下面我们通过一个小实验来直观感受差异：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct Counter {
    uint count;
}

library CounterLib {
    // 使用 storage，能修改合约状态
    function incStorage(Counter storage self) public {
        self.count += 1;
    }

    // 使用 memory，只会修改副本，不影响状态
    function incMemory(
        Counter memory self
    ) public pure returns (Counter memory) {
        self.count += 1;
        return self;
    }
}

contract C {
    using CounterLib for Counter;

    Counter public counter;

    // 调用 storage 版本
    function callStorage() public {
        counter.incStorage();
    }

    // 调用 memory 版本
    function callMemory() public view {
        Counter memory temp = counter;
        temp = temp.incMemory(); // 只改了副本
        // counter 本身并没有被改变
    }

    function getCount() public view returns (uint) {
        return counter.count;
    }
}
```

### 测试过程

使用Foundry编写测试脚本 **Counter.t.sol**：  

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "../src/Counter.sol";

contract CTest is Test {
    C public counter;

    function setUp() public {
        counter = new C();
    }

    function testIncStorage() public {
        counter.callStorage();
        assertEq(counter.getCount(), 1);
    }

    function testIncMemory() public view {
        counter.callMemory();
        assertEq(counter.getCount(), 0);
    }
}
```

执行测试脚本：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/Counter.t.sol -vvv
[⠊] Compiling...
[⠔] Compiling 1 files with Solc 0.8.30
[⠒] Solc 0.8.30 finished in 430.02ms
Compiler run successful!

Ran 2 tests for test/Counter.t.sol:CTest
[PASS] testIncMemory() (gas: 13501)
[PASS] testIncStorage() (gas: 32255)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 3.19ms (1.03ms CPU time)

Ran 1 test suite in 155.29ms (3.19ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 四、总结

1. **报错原因**：
   `library` 扩展函数的第一个参数必须是用户自定义类型（`struct` 或 `enum`），否则会报错 *“Name has to refer to a user-defined type”*。
2. **为什么用 `storage`**：
   * `storage` 允许函数直接修改合约状态
   * 避免大数据复制，节省 gas
   * 语义更自然，像对象方法一样作用于原数据
3. **实验对比**：
   * `storage` 参数：修改持久化状态
   * `memory` 参数：只修改副本，不会影响状态

所以在设计库函数时，如果你希望修改合约的状态变量，必须使用 `storage` 引用；如果只是做临时计算，可以用 `memory` 或 `calldata`。

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