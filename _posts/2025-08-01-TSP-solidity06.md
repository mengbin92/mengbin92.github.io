---
layout: post
title: 《纸上谈兵·solidity》第 6 课：Solidity 数据存储布局 —— memory、storage、calldata 傻傻分不清？
tags: solidity
mermaid: false
math: false
---  

在 Solidity 编程中，变量的“声明”远远不只是类型和名字，更关键的是 —— 存储位置（data location）。错误使用 `memory`、`storage` 或 `calldata` 不仅影响正确性，更直接影响 **gas 成本、安全性和语义一致性**。

本课将深入讲解三种关键存储类型，并通过 **Foundry 实例演示**数据的读写、传递与修改行为。

---

## 一、三大存储位置概述

| 存储位置   | 生命周期             | 读写权限 | 读/写成本       | 应用场景                            |
| :--------- | :------------------- | :------- | :-------------- | :---------------------------------- |
| `storage`  | 合约永久状态变量     | 可读可写 | 读/写都昂贵    | 状态变量、长期持久化存储            |
| `memory`   | 函数调用期间有效     | 可读可写 | 便宜（RAM式） | 局部变量、中间临时处理              |
| `calldata` | 函数外部调用参数只读 | 只读     | 极便宜        | external 函数的参数（特别适合数组） |

---

## 二、状态变量（storage）

* 所有 `state variable` 都自动存储在 `storage` 中。
* 是 Solidity 最昂贵的存储类型，因为它对应 EVM 中的持久化状态存储（State Trie）。

```solidity
contract Example {
    uint[] public values; // 默认在 storage 中

    function update() public {
        values.push(1); // 直接修改 storage
    }
}
```

* 可以通过 `storage` 引用函数参数或局部变量，但此时是**指针引用**。

```solidity
function modify(uint[] storage arr) internal {
    arr[0] = 42; // 直接修改原始数组
}
```

---

## 三、memory 临时数据区

* 用于函数中的临时变量和参数拷贝。
* 生命周期仅在函数调用期间。
* 在调用时创建，在返回时销毁。
* 写入和读取比 `storage` 更便宜，但数据不会持久。

```solidity
function copy(uint[] memory data) public pure returns (uint) {
    data[0] = 123; // 修改的是 memory 中的副本
    return data[0];
}
```

使用 memory 时，变量是“值传递”或“拷贝引用”，不会影响 storage 中原始数据。

---

## 四、实验：storage vs memory 修改对比

```solidity
contract DataTest {
    uint[] public data;

    constructor() {
        data.push(1);
        data.push(2);
        data.push(3);
    }

    // 修改副本（不改变原始 storage）
    function updateMemory() public view returns (uint[] memory) {
        uint[] memory temp = data;
        temp[0] = 99;
        return temp; // 原始 data 不变
    }

    // 修改 storage 变量本身
    function updateStorage() public {
        uint[] storage temp = data;
        temp[0] = 88;
    }
}
```

---

### Foundry 测试用例

```solidity
contract StorageTest is Test {
    DataTest dt;

    function setUp() public {
        dt = new DataTest();
    }

    function testUpdateMemoryDoesNotAffectStorage() public {
        uint[] memory result = dt.updateMemory();
        assertEq(result[0], 99);                // 复制体被改
        assertEq(dt.data(0), 1);                // storage 未改
    }

    function testUpdateStorageAffectsState() public {
        dt.updateStorage();
        assertEq(dt.data(0), 88);               // 状态变量被改变
    }
}
```
---

## 五、calldata 外部调用参数（只读）

* 函数参数在 `external` 函数中默认使用 `calldata`。
* 它是最便宜的内存类型。
* 只读，不可修改。
* 通常用于接收大量数组或字符串的函数。

```solidity
function readOnly(uint[] calldata data) external pure returns (uint) {
    // 编译失败
    data[0] = 10;
    return data[0]; // 不能修改 data
}
```

当你写 `external` 函数且带有数组参数时，推荐使用 `calldata`：

```solidity
function sum(uint[] calldata nums) external pure returns (uint) {
    return nums[0] + nums[1];
}
```

优势：

* 不能修改，更安全
* gas 成本更低（比 memory 少一次复制）

不支持写入或 push/pop：

```solidity
// 编译失败
function fail(uint[] calldata nums) external {
    nums[0] = 1; // 不能修改 calldata
}
```

---

## 六、测试演示（Foundry 示例）

**src/DataLocation.sol**:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DataLocation {
    uint[] public store;

    function storeToMemory() public view returns (uint[] memory) {
        uint[] memory temp = new uint[](store.length);
        for (uint i = 0; i < store.length; i++) {
            temp[i] = store[i];
        }
        return temp;
    }

    function storeFromCalldata(uint[] calldata input) external {
        store = input; // 拷贝 calldata 到 storage
    }

    function getCalldata(uint[] calldata input) external pure returns (uint) {
        return input[0]; // 只能读，不能写
    }
}
```

**test/DataLocation.t.sol**:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/DataLocation.sol";

contract DataLocationTest is Test {
    DataLocation dl;

    function setUp() public {
        dl = new DataLocation();
    }

    function testMemoryCopy() public {
        uint[] memory input;
        input = new uint[](1);
        input[0] = 10;

        dl.storeFromCalldata(input);

        uint[] memory result = dl.storeToMemory();
        assertEq(result[0], 10);
    }

    function testGetCalldata() public view {
        uint[] memory arr;
        arr = new uint[](1);
        arr[0] = 42;

        uint val = dl.getCalldata(arr); 
        assertEq(val, 42);
    }
}
```

执行结果：  

```bash
$ ➜  counter git:(main) ✗ forge test --match-path test/DataLocation.t.sol  -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 535.07ms
Compiler run successful!

Ran 2 tests for test/DataLocation.t.sol:DataLocationTest
[PASS] testGetCalldata() (gas: 10033)
[PASS] testMemoryCopy() (gas: 57458)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 4.60ms (2.16ms CPU time)

Ran 1 test suite in 182.96ms (4.60ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 七、小结对比

| 特性     | storage  | memory       | calldata     |
| :------- | :------- | :----------- | :----------- |
| 生命周期 | 永久存储 | 函数调用期间 | 函数调用期间 |
| 可修改性 | 是       | 是           | 否           |
| gas 成本 | 高       | 中           | 低           |
| 使用场景 | 状态变量 | 临时变量     | 外部参数传入 |

---

## 八、建议实践

* **函数参数能用 `calldata` 就用 `calldata`**，尤其是 external 函数，能节省大量 Gas。
* **避免误用 storage 引用**，会导致原始状态被意外修改。
* **了解深浅拷贝行为**，能避免修改副本却期望原始数据变化的误解。

---

## 小练习

1. 实现一个函数，接受 calldata 数组，复制到 memory 并排序。
2. 编写 storage 引用和 memory 副本操作对比函数，配合 Foundry 测试验证行为。
3. 编写一个结构体数组操作合约，理解不同位置之间的行为差异。

---

## 下一课导读

《第 7 课：Solidity 函数可见性和修饰器 —— public 和 private 不只是权限标签》

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
