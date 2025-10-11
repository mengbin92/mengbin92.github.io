---
layout: post
title: 《纸上谈兵·solidity》第 43 课：DeFi 实战(8) -- 利率曲线与资金池优化（动态利用率模型）
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解 **资金利用率（Utilization Rate, U）** 概念
* 掌握 **动态利率模型**（线性 / 分段 / 曲线）
* 通过代码实现利率自动调整机制
* 编写 **完整测试** 验证资金利用率、借贷利率、存款收益随资金变化的联动
* 对比 Compound / Aave 的利率曲线模型

---

## 2、资金利用率 (Utilization Rate)

借贷协议的核心指标：

$$
U = \frac{总借款量}{总存款量}
$$

* ( U = 0 )：没人借钱，池子闲置
* ( U = 1 )：全部资金被借出，流动性枯竭
* 实际上协议希望保持在某个 **目标区间（Optimal U）**，比如 80%

示意图：

| 状态    | 利用率 (U) | 借款利率 (R_b) | 存款利率 (R_d) | 说明          |
| ----- | ------- | ---------- | ---------- | ----------- |
| 低利用率区 | < 80%   | 较低（激励借款）   | 较低         | 池子资金多，鼓励借出  |
| 高利用率区 | > 80%   | 快速上升       | 上升         | 资金紧张，抑制过度借贷 |

---

## 3、动态利率模型（Interest Rate Model）

### 3.1 线性模型（Linear Model）

$$
R_b = R_{base} + U \times slope
$$

简单但不够灵活。

### 3.2 分段模型（Piecewise Model）

Compound、Aave 采用分段形式：

$$
R_b =
\begin{cases}
R_{base} + \frac{U}{U_{opt}} \times slope_1, & U \leq U_{opt} \
R_{base} + slope_1 + \frac{U - U_{opt}}{1 - U_{opt}} \times slope_2, & U > U_{opt}
\end{cases}
$$

存款利率则由借款利率乘以利用率再乘以储备系数得出：

$$
R_d = R_b \times U \times (1 - reserveFactor)
$$

---

## 4、Solidity 实现：动态利率模型

**InterestRateModel.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 动态利率模型（Compound风格）
/// @notice 实现基于资金利用率的动态利率计算，包含分段利率机制
/// @dev 使用 RAY (1e27) 精度进行定点数运算，避免浮点数精度问题
contract InterestRateModel {
    /// @notice RAY 精度常量，用于利率计算（1e27）
    uint256 public constant RAY = 1e27;
    
    /// @notice 基础利率，资金利用率较低时的最低利率
    uint256 public baseRate;
    
    /// @notice 前半段斜率，资金利用率在目标值以下时的利率增长斜率
    uint256 public slope1;
    
    /// @notice 后半段斜率，资金利用率超过目标值时的利率增长斜率
    uint256 public slope2;
    
    /// @notice 目标资金利用率阈值，超过此值后利率斜率变化
    uint256 public optimalUtil;
    
    /// @notice 协议准备金比例，从借款利息中抽取作为协议收入
    uint256 public reserveFactor;

    /// @notice 构造函数，初始化利率模型参数
    /// @param _baseRate 基础利率（RAY精度，如 0.02e27 表示 2%）
    /// @param _slope1 前半段斜率（RAY精度）
    /// @param _slope2 后半段斜率（RAY精度）
    /// @param _optimalUtil 目标资金利用率（RAY精度，如 0.8e27 表示 80%）
    /// @param _reserveFactor 协议准备金比例（RAY精度，如 0.1e27 表示 10%）
    constructor(
        uint256 _baseRate,
        uint256 _slope1,
        uint256 _slope2,
        uint256 _optimalUtil,
        uint256 _reserveFactor
    ) {
        baseRate = _baseRate;
        slope1 = _slope1;
        slope2 = _slope2;
        optimalUtil = _optimalUtil;
        reserveFactor = _reserveFactor;
    }

    /// @notice 计算当前资金利用率
    /// @dev 资金利用率 = 总借款 / 总存款
    /// @param totalDeposits 总存款量（wei单位）
    /// @param totalBorrows 总借款量（wei单位）
    /// @return 资金利用率（RAY精度，如 0.5e27 表示 50%）
    function utilizationRate(uint256 totalDeposits, uint256 totalBorrows) public pure returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrows * RAY) / totalDeposits;
    }

    /// @notice 计算借款利率
    /// @dev 采用分段利率模型：
    ///      - 当资金利用率 ≤ 目标值时：基础利率 + (当前利用率 * 前半段斜率) / 目标利用率
    ///      - 当资金利用率 > 目标值时：基础利率 + 前半段斜率 + (超额部分 * 后半段斜率) / (1 - 目标利用率)
    /// @param totalDeposits 总存款量（wei单位）
    /// @param totalBorrows 总借款量（wei单位）
    /// @return 借款利率（RAY精度）
    function borrowRate(uint256 totalDeposits, uint256 totalBorrows) public view returns (uint256) {
        uint256 U = utilizationRate(totalDeposits, totalBorrows);
        
        if (U <= optimalUtil) {
            // 低利用率阶段：线性增长
            return baseRate + (U * slope1) / optimalUtil;
        } else {
            // 高利用率阶段：加速增长以激励还款
            uint256 excess = U - optimalUtil;
            uint256 extra = (excess * slope2) / (RAY - optimalUtil);
            return baseRate + slope1 + extra;
        }
    }

    /// @notice 计算存款利率
    /// @dev 存款利率 = 借款利率 × 资金利用率 × (1 - 准备金比例)
    ///      计算过程分步进行以避免算术溢出
    /// @param totalDeposits 总存款量（wei单位）
    /// @param totalBorrows 总借款量（wei单位）
    /// @return 存款利率（RAY精度）
    function depositRate(uint256 totalDeposits, uint256 totalBorrows) public view returns (uint256) {
        uint256 U = utilizationRate(totalDeposits, totalBorrows);
        uint256 borrow = borrowRate(totalDeposits, totalBorrows);
        
        // 分步计算避免算术溢出：
        // ((borrow * U) / RAY) * (RAY - reserveFactor) / RAY
        uint256 numerator = borrow * U;
        uint256 temp = numerator / RAY;  // 先除以一个 RAY 降低数值大小
        return (temp * (RAY - reserveFactor)) / RAY;
    }
}
```

---

## 5、Foundry 测试：验证动态利率模型

**InterestRateModelTest.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InterestRateModel.sol";

/// @title 利率模型测试合约
/// @notice 使用 Foundry 测试框架对利率模型进行完整测试
contract InterestRateModelTest is Test {
    InterestRateModel model;

    /// @notice 测试前置设置，部署利率模型合约
    function setUp() public {
        model = new InterestRateModel(
            0.02e27,   // baseRate = 2%
            0.1e27,    // slope1 = 10%
            0.6e27,    // slope2 = 60%
            0.8e27,    // optimalUtil = 80%
            0.1e27     // reserveFactor = 10%
        );
    }

    /// @notice 测试资金利用率计算正确性
    function testUtilizationRate() public view {
        uint256 U = model.utilizationRate(1000 ether, 500 ether);
        // 1000 ether 存款，500 ether 借款，利用率应为 50%
        assertApproxEqRel(U, 0.5e27, 1e15); // 允许 1e-15 的相对误差
    }

    /// @notice 测试低资金利用率下的借款利率
    function testBorrowRate_LowUtilization() public view {
        uint256 rate = model.borrowRate(1000 ether, 200 ether);
        // 20% 利用率下的预期计算：
        // 基础利率 2% + (20% × 10%) / 80% = 2% + 2.5% = 4.5%
        assertApproxEqRel(rate, 0.045e27, 1e15);
    }

    /// @notice 测试高资金利用率下的借款利率
    function testBorrowRate_HighUtilization() public view {
        uint256 rate = model.borrowRate(1000 ether, 950 ether);
        // 高利用率（95%）时利率应该显著上升
        assertGt(rate, 0.1e27); // 应该大于 10%
    }

    /// @notice 测试存款利率随资金利用率上升而增加
    function testDepositRateRisesWithUtilization() public view{
        uint256 lowU = model.depositRate(1000 ether, 200 ether);  // 20% 利用率
        uint256 highU = model.depositRate(1000 ether, 950 ether); // 95% 利用率
        // 高利用率时的存款利率应该高于低利用率时
        assertGt(highU, lowU);
    }

    /// @notice 测试利率随资金利用率变化的单调性
    function testRatesScaleCorrectly() public view{
        uint256 u1 = model.utilizationRate(1000 ether, 100 ether);  // 10% 利用率
        uint256 u2 = model.utilizationRate(1000 ether, 900 ether);  // 90% 利用率
        uint256 r1 = model.borrowRate(1000 ether, 100 ether);       // 低利用率利率
        uint256 r2 = model.borrowRate(1000 ether, 900 ether);       // 高利用率利率
        
        // 验证资金利用率正确排序
        assertLt(u1, u2);
        // 验证借款利率正确排序（高利用率对应高利率）
        assertLt(r1, r2);
    }

    /// @notice 测试准备金比例对存款利率的影响
    function testDepositRateAccountsForReserveFactor() public view {
        uint256 borrowRate = model.borrowRate(1000 ether, 800 ether);
        uint256 depositRate = model.depositRate(1000 ether, 800 ether);
        
        // 存款利率应该小于借款利率（因为扣除了 10% 的准备金）
        assertLt(depositRate, borrowRate);
        // 存款利率应该大于 0
        assertGt(depositRate, 0);
    }
    
    /// @notice 测试边界情况和极端场景
    function testEdgeCases() public view{
        // 测试零存款情况
        uint256 rate1 = model.depositRate(0, 0);
        // 测试零借款情况
        uint256 rate2 = model.depositRate(1000 ether, 0);
        // 测试 100% 资金利用率情况
        uint256 rate3 = model.depositRate(1000 ether, 1000 ether);
        
        // 零存款时利率应为 0
        assertEq(rate1, 0);
        // 零借款时存款利率应为 0
        assertEq(rate2, 0);
        // 100% 利用率时存款利率应大于 0
        assertGt(rate3, 0);
    }
    
    /// @notice 测试利率模型参数的正确性
    function testModelParameters() public view {
        // 验证合约参数是否正确设置
        assertEq(model.baseRate(), 0.02e27);
        assertEq(model.slope1(), 0.1e27);
        assertEq(model.slope2(), 0.6e27);
        assertEq(model.optimalUtil(), 0.8e27);
        assertEq(model.reserveFactor(), 0.1e27);
        assertEq(model.RAY(), 1e27);
    }
}
```

测试结果示例：

```bash
➜  defi git:(master) ✗ forge test --match-path test/InterestRateModelTest.t.sol -vvv
[⠊] Compiling...
[⠃] Compiling 38 files with Solc 0.8.29
[⠊] Solc 0.8.29 finished in 1.86s
Compiler run successful!

Ran 8 tests for test/InterestRateModelTest.t.sol:InterestRateModelTest
[PASS] testBorrowRate_HighUtilization() (gas: 17135)
[PASS] testBorrowRate_LowUtilization() (gas: 17470)
[PASS] testDepositRateAccountsForReserveFactor() (gas: 21654)
[PASS] testDepositRateRisesWithUtilization() (gas: 26140)
[PASS] testEdgeCases() (gas: 30775)
[PASS] testModelParameters() (gas: 21719)
[PASS] testRatesScaleCorrectly() (gas: 25605)
[PASS] testUtilizationRate() (gas: 10411)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 8.80ms (9.80ms CPU time)

Ran 1 test suite in 516.20ms (8.80ms CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)
```
---

## 6、优化与扩展思路

| 模型类型         | 特点         | 使用项目           | 优缺点        |
| ------------ | ---------- | -------------- | ---------- |
| 线性模型         | 简单、平滑      | 早期协议           | 响应滞后，调节不敏感 |
| 分段模型         | 精细控制高利用区   | Compound, Aave | 实用性强，已成标准  |
| 曲线模型（指数、log） | 连续调整       | 一些研究型协议        | 计算复杂、不可预测  |
| 自适应模型        | 利用率随时间调整参数 | Aave v3        | 智能、复杂度高    |

**实战优化建议：**

1. **自动再平衡**：当利用率过高时，动态提高借款利率，引导还款；
2. **资金池隔离**：不同资产采用不同利率曲线；
3. **治理参数**：通过 DAO 投票修改利率参数；
4. **费率上限**：防止极端市场时利率飙升。

---

## 7、本课总结

| 要点         | 内容                       |
| ---------- | ------------------------ |
| **资金利用率**  | 衡量资金使用效率的核心指标            |
| **动态利率模型** | 平衡出借人收益与借款人成本            |
| **分段利率曲线** | DeFi 主流实现（Aave、Compound） |
| **协议优化方向** | 利率自调、隔离池、治理参数            |

---

## 8、课后作业

1. 修改 `InterestRateModel`，支持 **三段式利率模型**（低、中、高利用率区）
2. 在借贷合约中集成 `InterestRateModel`，让借款利率动态变化
3. 尝试为协议添加一个 `updateInterestRates()` 周期更新机制（按区块时间累积利息）

