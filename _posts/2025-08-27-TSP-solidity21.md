---
layout: post
title: 《纸上谈兵·solidity》第 21 课：Gas 优化与成本分析 —— 写出便宜的智能合约
tags: solidity
mermaid: false
math: false
---  

## 课程目标

* 理解智能合约的主要 **Gas 消耗来源**
* 掌握常见的 **优化技巧与模式**
* 通过 Foundry 对比 **优化前后 Gas 成本**
* 建立“写出高效合约”的思维框架

---

## 1、Gas 的构成

在 EVM 中，Gas 主要分为三类：

1. **计算消耗**：算术运算、函数调用等
2. **存储消耗**：对 `storage` 的读写最昂贵
3. **交易消耗**：部署合约、转账、事件日志

其中最关键的是 **storage 写入**，单次写入约 20,000 gas（如果从 0 改为非 0）。

---

## 2、优化点概览

| 优化点                                 | 建议做法                               | 原因            |
| ----------------------------------- | ---------------------------------- | ------------- |
| 存储变量访问                              | 先读入 memory 变量，再多次使用                | 减少重复 SLOAD 成本 |
| `storage` vs `memory` vs `calldata` | 尽量使用 `calldata` 作为函数参数             | 最便宜，避免复制      |
| 变量打包                                | 将多个 `uint128` 合并到一个 `uint256` slot | 节省存储槽         |
| 固定长度数组                              | 用 `bytes32` 替代 `string`/`bytes`    | 减少动态存储开销      |
| 循环                                  | 避免无限增长数组迭代                         | 每次循环线性增加 Gas  |
| 事件                                  | 只记录必要字段                            | 日志存储在链上也要付费   |
| External call                       | 批处理、懒执行                            | 减少重复调用        |

---

## 3、常见优化技巧

### 1. 避免重复 SLOAD

```solidity
// 差的写法
function bad(uint256 x) external {
    for (uint i = 0; i < 10; i++) {
        storageVar += x;
    }
}

// 优化写法
function good(uint256 x) external {
    uint256 tmp = storageVar;
    for (uint i = 0; i < 10; i++) {
        tmp += x;
    }
    storageVar = tmp;
}
```

> 在循环中访问 `storage` 十次，成本远高于一次写回。

---

### 2. 使用 `calldata` 代替 `memory`

```solidity
// 差的写法
function sum(uint256[] memory arr) external pure returns (uint256 s) {
    for (uint i = 0; i < arr.length; i++) {
        s += arr[i];
    }
}

// 优化写法
function sum(uint256[] calldata arr) external pure returns (uint256 s) {
    for (uint i = 0; i < arr.length; i++) {
        s += arr[i];
    }
}
```

`memory` 会复制数组，而 `calldata` 直接引用，节省大量 gas。

---

### 3. 变量打包

```solidity
// 差的写法
struct Bad {
    uint128 a;
    uint128 b;
    uint128 c;
}

// 优化写法（两个 slot -> 一个 slot）
struct Good {
    uint128 a;
    uint128 b;
    uint256 c;
}
```

Solidity 会将多个小于 256bit 的变量打包进一个存储槽。

---

### 4. 事件优化

```solidity
// 差的写法
event Deposit(address indexed user, uint256 amount, string memo);

// 优化写法
event Deposit(address indexed user, uint256 amount);
```

`string` 会额外消耗存储空间，除非业务必须，尽量避免。

---

## 4、Foundry 实战：Gas 对比测试

### 合约：未优化 vs 优化

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BadContract {
    uint256 public value;

    function addMany(uint256 x) external {
        for (uint i = 0; i < 10; i++) {
            value += x; // 每次都访问 storage
        }
    }
}

contract GoodContract {
    uint256 public value;

    function addMany(uint256 x) external {
        uint256 tmp = value;
        for (uint i = 0; i < 10; i++) {
            tmp += x;
        }
        value = tmp; // 只写一次 storage
    }
}
```

---

### 测试：比较 Gas 消耗

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Gas.sol";

contract GasTest is Test {
    BadContract bad;
    GoodContract good;

    function setUp() public {
        bad = new BadContract();
        good = new GoodContract();
    }

    function testGasBad() public {
        bad.addMany(1);
    }

    function testGasGood() public {
        good.addMany(1);
    }
}
```

执行测试：

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/Gas.t.sol --gas-report -vvv 

[⠊] Compiling...
[⠒] Compiling 2 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 506.84ms
Compiler run successful!

Ran 2 tests for test/Gas.t.sol:GasTest
[PASS] testGasBad() (gas: 53693)
[PASS] testGasGood() (gas: 51716)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 3.57ms (894.88µs CPU time)

╭----------------------------------+-----------------+-------+--------+-------+---------╮
| src/Gas.sol:BadContract Contract |                 |       |        |       |         |
+=======================================================================================+
| Deployment Cost                  | Deployment Size |       |        |       |         |
|----------------------------------+-----------------+-------+--------+-------+---------|
| 152487                           | 489             |       |        |       |         |
|----------------------------------+-----------------+-------+--------+-------+---------|
|                                  |                 |       |        |       |         |
|----------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                    | Min             | Avg   | Median | Max   | # Calls |
|----------------------------------+-----------------+-------+--------+-------+---------|
| addMany                          | 48203           | 48203 | 48203  | 48203 | 1       |
╰----------------------------------+-----------------+-------+--------+-------+---------╯

╭-----------------------------------+-----------------+-------+--------+-------+---------╮
| src/Gas.sol:GoodContract Contract |                 |       |        |       |         |
+========================================================================================+
| Deployment Cost                   | Deployment Size |       |        |       |         |
|-----------------------------------+-----------------+-------+--------+-------+---------|
| 153147                            | 492             |       |        |       |         |
|-----------------------------------+-----------------+-------+--------+-------+---------|
|                                   |                 |       |        |       |         |
|-----------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                     | Min             | Avg   | Median | Max   | # Calls |
|-----------------------------------+-----------------+-------+--------+-------+---------|
| addMany                           | 46257           | 46257 | 46257  | 46257 | 1       |
╰-----------------------------------+-----------------+-------+--------+-------+---------╯


Ran 1 test suite in 6.50ms (3.57ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 5、进阶优化策略

1. **批处理**：合并多次转账为一次
2. **懒执行**：只在必要时更新状态变量（例如延迟结算）
3. **预计算**：在链下完成复杂运算，把结果上链
4. **库函数优化**：使用 `unchecked {}` 避免多余溢出检查（适合已知安全场景）

---

## 6、总结

* Gas 优化的关键：**减少 storage 写入，避免不必要的复制，合理打包变量**
* 使用 Foundry 的 `--gas-report` 工具可以直观对比优化效果
* 优化要 **兼顾安全与可读性**，不要为省 gas 牺牲合约清晰度

---

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