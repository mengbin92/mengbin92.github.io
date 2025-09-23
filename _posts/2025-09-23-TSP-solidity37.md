---
layout: post
title: 《纸上谈兵·solidity》第 37 课：DeFi 实战 -- 资金池与利率模型
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解借贷平台的 **资金池机制**
* 掌握 Aave / Compound 等平台的 **动态利率模型**
* 编写一个简化的 **带利率的借贷池合约**
* 使用 Foundry 编写测试，验证利率随资金利用率变化

---

## 2、知识点梳理

1. **资金池（Lending Pool）**  
   - 所有存款用户的资产进入一个共享池子  
   - 借款人从池子中提取资金  
   - 池子内资金利用率决定利率水平  
2. **资金利用率（Utilization Rate, U）**  
   \[
   U = \frac{总借款}{总存款}
   \]  
   - U 越高，说明池子资金越紧张，借款利率越高  
   - U 越低，说明资金富余，借款利率越低  
3. **利率模型（Interest Rate Model）**  
   - 基础利率（Base Rate）：当利用率接近 0 时的最低借款利率  
   - 斜率（Slope）：利用率上升时，利率增加的速度  
   - 最优利用率（Optimal Utilization）：一个转折点，超过该点后利率会陡增，防止资金池被借空  
4. **存款利率（Supply Rate）**  
   存款利率来自借款利息分配：  
   \[
   存款利率 = 借款利率 \times \frac{总借款}{总存款} \times (1 - 协议费率)
   \]  

---

## 3、资金池合约实现

**LendingPoolWithRate.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入 OpenZeppelin 的 ERC20 接口和安全转账工具
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LendingPoolWithRate
 * @dev 借贷池合约，支持动态利率计算。
 * 该合约允许用户存入和借出 ERC20 代币，并根据资金利用率动态调整借款利率。
 */
contract LendingPoolWithRate {
    using SafeERC20 for IERC20;

    // 借贷池支持的资产（ERC20 代币）
    IERC20 public asset;

    // 总存款量
    uint256 public totalDeposits;
    // 总借款量
    uint256 public totalBorrows;

    // 用户存款映射（地址 => 存款量）
    mapping(address => uint256) public deposits;
    // 用户借款映射（地址 => 借款量）
    mapping(address => uint256) public borrows;

    // 利率模型参数
    uint256 public baseRate = 2e16;       // 基础利率（2%）
    uint256 public slope = 10e16;         // 斜率（10%）
    uint256 public optimalUtilization = 80e16; // 最优资金利用率（80%）
    uint256 public constant ONE = 1e18;   // 1e18 表示 100%（用于计算）

    /**
     * @dev 构造函数，初始化借贷池的资产。
     * @param _asset 借贷池支持的 ERC20 代币地址。
     */
    constructor(IERC20 _asset) {
        asset = _asset;
    }

    /**
     * @dev 存款函数：用户将资产存入借贷池。
     * @param amount 存款数量。
     */
    function deposit(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
    }

    /**
     * @dev 借款函数：用户从借贷池借出资产。
     * @param amount 借款数量。
     */
    function borrow(uint256 amount) external {
        require(totalDeposits - totalBorrows >= amount, "insufficient liquidity");
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        asset.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev 计算当前资金利用率（借款量 / 存款量）。
     * @return 资金利用率（百分比，以 1e18 表示 100%）。
     */
    function getUtilization() public view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrows * ONE) / totalDeposits;
    }

    /**
     * @dev 计算动态借款利率。
     * @return 借款利率（百分比，以 1e18 表示 100%）。
     */
    function getBorrowRate() public view returns (uint256) {
        uint256 utilization = getUtilization();
        if (utilization <= optimalUtilization) {
            return baseRate + (utilization * slope) / optimalUtilization;
        } else {
            uint256 excess = utilization - optimalUtilization;
            return baseRate + slope + (excess * slope) / (ONE - optimalUtilization);
        }
    }

    /**
     * @dev 计算存款利率（协议抽取 10% 利息）。
     * @return 存款利率（百分比，以 1e18 表示 100%）。
     */
    function getSupplyRate() public view returns (uint256) {
        if (totalDeposits == 0) return 0;
        uint256 borrowRate = getBorrowRate();
        return (borrowRate * totalBorrows * 90) / (totalDeposits * 100);
    }
}
```

---

## 4、Foundry 测试

**LendingPoolWithRateTest.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPoolWithRate.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev 模拟 ERC20 代币合约，用于测试。
 */
contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    /**
     * @dev 铸造代币。
     * @param to 接收代币的地址。
     * @param amount 铸造的代币数量。
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title LendingPoolWithRateTest
 * @dev 测试借贷池合约的功能，包括存款、借款和利率计算。
 */
contract LendingPoolWithRateTest is Test {
    LendingPoolWithRate pool;
    MockERC20 usdc;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    /**
     * @dev 初始化测试环境，部署 MockERC20 和 LendingPoolWithRate 合约。
     */
    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        pool = new LendingPoolWithRate(IERC20(address(usdc)));

        usdc.mint(alice, 1000 ether);
        usdc.mint(bob, 1000 ether);
        usdc.mint(charlie, 1000 ether);
    }

    /**
     * @dev 测试存款量为零时的行为。
     */
    function testDepositZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 0);
        pool.deposit(0);
        vm.stopPrank();

        assertEq(pool.deposits(alice), 0);
        assertEq(pool.totalDeposits(), 0);
    }

    /**
     * @dev 测试借款量为零时的行为。
     */
    function testBorrowZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(0);
        vm.stopPrank();

        assertEq(pool.borrows(bob), 0);
        assertEq(pool.totalBorrows(), 0);
    }

    /**
     * @dev 测试存款和借款利率的变化逻辑。
     */
    function testDepositAndBorrowRateChange() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        // 初始 U=0，利率接近 baseRate
        assertApproxEqAbs(pool.getBorrowRate(), 0.02 ether, 0.001 ether);

        // Bob 借走 500，U=50%
        vm.startPrank(bob);
        pool.borrow(500 ether);
        vm.stopPrank();
        assertGt(pool.getBorrowRate(), 0.02 ether);

        // Bob 再借 300，U=80%，接近 optimal
        vm.startPrank(bob);
        pool.borrow(300 ether);
        vm.stopPrank();
        uint256 rateAt80 = pool.getBorrowRate();

        // 再借 100，U=90%，利率应大幅上升
        vm.startPrank(bob);
        pool.borrow(100 ether);
        vm.stopPrank();
        uint256 rateAt90 = pool.getBorrowRate();

        assertGt(rateAt90, rateAt80);
    }

    /**
     * @dev 测试多个用户同时操作的情况
     */
    function testMultipleUsers() public {
        // 三个用户分别存款
        vm.startPrank(alice);
        usdc.approve(address(pool), 500 ether);
        pool.deposit(500 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 300 ether);
        pool.deposit(300 ether);
        vm.stopPrank();

        vm.startPrank(charlie);
        usdc.approve(address(pool), 200 ether);
        pool.deposit(200 ether);
        vm.stopPrank();

        assertEq(pool.totalDeposits(), 1000 ether);

        // 多个用户借款
        vm.startPrank(alice);
        pool.borrow(200 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(300 ether);
        vm.stopPrank();

        vm.startPrank(charlie);
        pool.borrow(400 ether);
        vm.stopPrank();

        assertEq(pool.totalBorrows(), 900 ether);
    }

    /**
     * @dev 测试存款利率的计算逻辑。
     */
    function testSupplyRate() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(500 ether); // U=50%
        vm.stopPrank();

        uint256 supplyRate = pool.getSupplyRate();
        assertGt(supplyRate, 0); // 存款人应该获得收益
    }

    /**
     * @dev 测试资金利用率为100%时的利率。
     */
    function testFullUtilizationRate() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(1000 ether); // U=100%
        vm.stopPrank();

        uint256 borrowRate = pool.getBorrowRate();
        assertGt(borrowRate, 0.02 ether); // 利率应显著高于基础利率
    }

    /**
     * @dev 测试资金利用率为0%的情况
     */
    function testZeroUtilization() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        // 不进行任何借款，资金利用率为0%
        assertEq(pool.getUtilization(), 0);
        
        // 借款利率应该等于基础利率
        assertEq(pool.getBorrowRate(), pool.baseRate());
        
        // 存款利率应该为0
        assertEq(pool.getSupplyRate(), 0);
    }

    /**
     * @dev 测试利率计算的数学边界
     */
    function testRateCalculationEdgeCases() public {
        // 测试空池情况
        assertEq(pool.getUtilization(), 0);
        assertEq(pool.getBorrowRate(), pool.baseRate());
        assertEq(pool.getSupplyRate(), 0);

        // 存入极小金额测试除法边界
        vm.startPrank(alice);
        usdc.approve(address(pool), 1);
        pool.deposit(1);
        vm.stopPrank();

        // 即使只有1 wei，利率计算也不应该revert
        pool.getBorrowRate();
        pool.getSupplyRate();
    }

    /**
     * @dev 测试在空池状态下借款
     */
    function test_RevertWhen_BorrowFromEmptyPool() public {
        vm.startPrank(alice);
        // 不存入任何资金，直接尝试借款
        vm.expectRevert("insufficient liquidity");
        pool.borrow(100 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试借款超过存款量时的错误处理。
     */
    function test_RevertWhen_BorrowExceedsDeposit() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000 ether);
        pool.deposit(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        // 尝试借出超过可用流动性的金额
        vm.expectRevert("insufficient liquidity");
        pool.borrow(1001 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试无批准情况下的存款
     */
    function test_RevertWhen_DepositWithoutApproval() public {
        vm.startPrank(alice);
        // 不进行approve，直接存款
        vm.expectRevert(); // SafeERC20 会revert
        pool.deposit(100 ether);
        vm.stopPrank();
    }
}
```

执行测试：

```bash
➜  defi git:(main) ✗ forge test --match-path test/LendingPoolWithRate.t.sol -vvv
[⠊] Compiling...
[⠔] Compiling 1 files with Solc 0.8.30
[⠒] Solc 0.8.30 finished in 483.09ms
Compiler run successful!

Ran 11 tests for test/LendingPoolWithRate.t.sol:LendingPoolWithRateTest
[PASS] testBorrowZeroAmount() (gas: 116664)
[PASS] testDepositAndBorrowRateChange() (gas: 191775)
[PASS] testDepositZeroAmount() (gas: 42655)
[PASS] testFullUtilizationRate() (gas: 148140)
[PASS] testMultipleUsers() (gas: 303127)
[PASS] testRateCalculationEdgeCases() (gas: 123003)
[PASS] testSupplyRate() (gas: 166296)
[PASS] testZeroUtilization() (gas: 115394)
[PASS] test_RevertWhen_BorrowExceedsDeposit() (gas: 104728)
[PASS] test_RevertWhen_BorrowFromEmptyPool() (gas: 16808)
[PASS] test_RevertWhen_DepositWithoutApproval() (gas: 21030)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 5.46ms (15.34ms CPU time)

Ran 1 test suite in 148.13ms (5.46ms CPU time): 11 tests passed, 0 failed, 0 skipped (11 total tests)
```

---

## 5、本课总结

* 借贷平台核心是 **资金池** → 存款 & 借款共享同一池子
* **资金利用率 U** 决定资金紧张程度
* 利率曲线 = **基础利率 + 利用率 × 斜率**
* 存款利率来源于借款利息，协议可抽取部分作为费用
* 我们实现了一个简化的动态利率模型，和现实 DeFi 平台思路一致

---

## 6、作业

1. 修改合约，支持 **多种资产** 的存款 / 借款池（类似 Aave 的 Pool）。
2. 在合约中加入 **协议费累积逻辑**（记录协议收入）。
3. 思考：如果要支持「浮动利率借贷凭证」（aToken/cToken），应该在存款时如何设计？

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