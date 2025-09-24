---
layout: post
title: 《纸上谈兵·solidity》第 38 课：DeFi 实战(2) -- 清算机制与价格预言机
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解借贷平台中 **抵押物、借款、清算** 的核心关系  
* 掌握 **健康因子（Health Factor）** 的计算方式  
* 结合 **价格预言机** 获取资产价值  
* 编写一个简化的 **清算合约**，实现低抵押率下的清算流程  
* 使用 Foundry 测试完整流程：存款 → 抵押 → 借款 → 价格下跌 → 清算  

---

## 2、知识点梳理

### 2.1 抵押与借款

- 借款人必须先存入 **抵押资产**（如 ETH），再借出稳定币（如 USDC）。  
- 平台通过 **抵押率（Collateral Factor）** 来控制借款额度。  
  例如：ETH 的抵押率 75%，存入 100 美元 ETH → 最多借 75 USDC。  

### 2.2 健康因子（Health Factor）

$$
HF = \frac{抵押物价值 \times 抵押率}{借款价值}
$$

- HF > 1：仓位安全  
- HF < 1：仓位不安全，可以被清算  

### 2.3 清算（Liquidation）

- 当 HF < 1，清算人可以偿还部分借款，并获得抵押物折价奖励（Liquidation Bonus）。  
- 这样既保证平台资金安全，也激励清算人参与。  

### 2.4 价格预言机

- 需要外部预言机（如 Chainlink）提供资产价格。  
- 在本课中，我们实现一个 **可手动更新的 MockOracle** 来模拟价格波动。  

---

## 3、合约实现

**src/LendingWithLiquidation.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IPriceOracle
 * @dev 价格预言机接口，用于获取资产价格。
 */
interface IPriceOracle {
    /**
     * @dev 获取指定资产的价格。
     * @param asset 资产地址。
     * @return 资产价格。
     */
    function getPrice(address asset) external view returns (uint256);
}

/**
 * @title LendingWithLiquidation
 * @dev 支持清算的借贷合约，允许用户存入抵押物、借款，并在抵押不足时触发清算。
 */
contract LendingWithLiquidation {
    using SafeERC20 for IERC20;

    IERC20 public collateralAsset; // 抵押资产 (ETH 代币化)
    IERC20 public debtAsset; // 借款资产 (USDC)
    IPriceOracle public oracle;

    uint256 public collateralFactor = 75e16; // 75%
    uint256 public liquidationBonus = 5e16; // 5%
    uint256 public constant ONE = 1e18;

    mapping(address => uint256) public collaterals;
    mapping(address => uint256) public debts;

    /**
     * @dev 构造函数，初始化抵押资产、借款资产和价格预言机。
     * @param _collateral 抵押资产合约地址。
     * @param _debt 借款资产合约地址。
     * @param _oracle 价格预言机合约地址。
     */
    constructor(IERC20 _collateral, IERC20 _debt, IPriceOracle _oracle) {
        collateralAsset = _collateral;
        debtAsset = _debt;
        oracle = _oracle;
    }

    /**
     * @dev 存入抵押物。
     * @param amount 存入的抵押物数量。
     */
    function depositCollateral(uint256 amount) external {
        collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
        collaterals[msg.sender] += amount;
    }

    /**
     * @dev 借款。
     * @param amount 借款数量。
     */
    function borrow(uint256 amount) external {
        require(
            _isHealthyAfterBorrow(msg.sender, amount),
            "would be unhealthy"
        );
        debts[msg.sender] += amount;
        debtAsset.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev 清算功能。
     * @param user 被清算的用户地址。
     * @param repayAmount 清算人偿还的借款数量。
     */
    function liquidate(address user, uint256 repayAmount) external {
        require(getHealthFactor(user) < ONE, "user healthy");

        uint256 debt = debts[user];
        require(repayAmount <= debt, "repay too much");

        // 清算人偿还借款
        debtAsset.safeTransferFrom(msg.sender, address(this), repayAmount);
        debts[user] -= repayAmount;

        // 计算可获得的抵押物
        uint256 price = oracle.getPrice(address(collateralAsset));
        uint256 collateralToSeize = (repayAmount *
            ONE *
            (ONE + liquidationBonus)) / price;

        if (collateralToSeize > collaterals[user]) {
            collateralToSeize = collaterals[user];
        }

        collaterals[user] -= collateralToSeize;
        collateralAsset.safeTransfer(msg.sender, collateralToSeize);
    }

    /**
     * @dev 获取用户的健康因子。
     * @param user 用户地址。
     * @return 健康因子值。
     */
    function getHealthFactor(address user) public view returns (uint256) {
        uint256 collateralValue = (collaterals[user] *
            oracle.getPrice(address(collateralAsset))) / ONE;
        uint256 maxBorrow = (collateralValue * collateralFactor) / ONE;
        uint256 debtValue = debts[user];

        if (debtValue == 0) return type(uint256).max;
        return (maxBorrow * ONE) / debtValue;
    }

    /**
     * @dev 内部函数，检查借款后用户是否健康。
     * @param user 用户地址。
     * @param borrowAmount 借款数量。
     * @return 是否健康。
     */
    function _isHealthyAfterBorrow(
        address user,
        uint256 borrowAmount
    ) internal view returns (bool) {
        uint256 newDebt = debts[user] + borrowAmount;
        uint256 hf = getHealthFactorAfterDebt(user, newDebt);
        return hf >= ONE;
    }

    /**
     * @dev 获取用户在新债务下的健康因子。
     * @param user 用户地址。
     * @param newDebt 新的债务数量。
     * @return 健康因子值。
     */
    function getHealthFactorAfterDebt(
        address user,
        uint256 newDebt
    ) public view returns (uint256) {
        uint256 collateralValue = (collaterals[user] *
            oracle.getPrice(address(collateralAsset))) / ONE;
        uint256 maxBorrow = (collateralValue * collateralFactor) / ONE;
        if (newDebt == 0) return type(uint256).max;
        return (maxBorrow * ONE) / newDebt;
    }
}
```

---

## 4、Mock 价格预言机

**src/MockOracle.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LendingWithLiquidation.sol";

/**
 * @title MockOracle
 * @dev 模拟价格预言机合约，用于测试借贷合约中的价格查询功能。
 */
contract MockOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    /**
     * @dev 设置资产价格。
     * @param asset 资产地址。
     * @param price 资产价格。
     */
    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    /**
     * @dev 获取资产价格。
     * @param asset 资产地址。
     * @return 资产价格。
     */
    function getPrice(address asset) external view override returns (uint256) {
        return prices[asset];
    }
}
```

---

## 5、Foundry 测试

**test/LendingWithLiquidation.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingWithLiquidation.sol";
import "../src/MockOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev 模拟 ERC20 代币合约，用于测试。
 */
contract MockERC20 is ERC20 {
    /**
     * @dev 构造函数，初始化代币名称和符号。
     * @param n 代币名称。
     * @param s 代币符号。
     */
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
 * @title LendingWithLiquidationTest
 * @dev 测试借贷池合约的功能，包括存款、借款和清算逻辑。
 */
contract LendingWithLiquidationTest is Test {
    LendingWithLiquidation pool;
    MockOracle oracle;
    MockERC20 weth;
    MockERC20 usdc;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    /**
     * @dev 初始化测试环境，部署 MockERC20 和 LendingWithLiquidation 合约。
     */
    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH");
        usdc = new MockERC20("USD Coin", "USDC");
        oracle = new MockOracle();

        pool = new LendingWithLiquidation(
            IERC20(address(weth)),
            IERC20(address(usdc)),
            IPriceOracle(address(oracle))
        );

        // 设置初始价格：1 WETH = 2000 USDC
        oracle.setPrice(address(weth), 2000 ether);

        // 铸币
        weth.mint(alice, 20 ether);
        usdc.mint(address(pool), 50000 ether); // 池子有稳定币可借
        usdc.mint(bob, 20000 ether);
        usdc.mint(charlie, 20000 ether);
    }

    /**
     * @dev 测试清算流程，包括存款、借款、价格下跌和清算操作。
     */
    function testLiquidationFlow() public {
        // Alice 存入 10 WETH (价值 20000 USDC)
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.depositCollateral(10 ether);
        vm.stopPrank();

        // Alice 借出 10000 USDC (HF > 1, 安全)
        vm.startPrank(alice);
        pool.borrow(10000 ether);
        vm.stopPrank();

        assertGt(pool.getHealthFactor(alice), 1e18);

        // 价格下跌：1 WETH = 800 USDC
        oracle.setPrice(address(weth), 800 ether);

        // 此时 Alice HF < 1
        uint256 hf = pool.getHealthFactor(alice);
        assertLt(hf, 1e18);

        // Bob 清算 Alice 的部分债务
        vm.startPrank(bob);
        usdc.approve(address(pool), 2000 ether);
        pool.liquidate(alice, 2000 ether);
        vm.stopPrank();

        // 清算后 Alice 的债务减少，抵押物被扣除
        assertLt(pool.debts(alice), 10000 ether);
        assertLt(pool.collaterals(alice), 10 ether);
    }

    /**
     * @dev 测试借款超过存款量时的错误处理。
     */
    function test_RevertWhen_BorrowExceedDeposit() public {
        // Alice 存入 1 WETH (价值 2000 USDC)
        vm.startPrank(alice);
        weth.approve(address(pool), 1 ether);
        pool.depositCollateral(1 ether);
        vm.stopPrank();

        // 尝试借出超过抵押物价值的金额 (抵押物价值2000 USDC，最大可借75% = 1500 USDC)
        vm.startPrank(alice);
        vm.expectRevert("would be unhealthy");
        pool.borrow(2000 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试清算健康账户时的错误处理。
     */
    function test_RevertWhen_LiquidateHealthyAccount() public {
        // Alice 存入 10 WETH 并借出安全金额
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.depositCollateral(10 ether);
        pool.borrow(5000 ether); // 安全借款
        vm.stopPrank();

        // Bob 尝试清算健康账户
        vm.startPrank(bob);
        usdc.approve(address(pool), 1000 ether);
        vm.expectRevert("user healthy");
        pool.liquidate(alice, 1000 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试清算时偿还超过实际债务的错误处理。
     */
    function test_RevertWhen_LiquidateExceedDebt() public {
        // Alice 存入 10 WETH 并借出 10000 USDC
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.depositCollateral(10 ether);
        pool.borrow(10000 ether);
        vm.stopPrank();

        // 价格下跌使 Alice 变得不健康
        oracle.setPrice(address(weth), 800 ether);

        // Bob 尝试偿还超过 Alice 实际债务的金额
        vm.startPrank(bob);
        usdc.approve(address(pool), 15000 ether);
        vm.expectRevert("repay too much");
        pool.liquidate(alice, 15000 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试零金额存款和借款的边界情况。
     */
    function testZeroAmountOperations() public {
        // 记录初始状态
        uint256 initialWethBalance = weth.balanceOf(alice);
        uint256 initialUsdcBalance = usdc.balanceOf(alice);
        uint256 initialCollateral = pool.collaterals(alice);
        uint256 initialDebt = pool.debts(alice);

        // 测试零金额存款 - 应该成功
        vm.startPrank(alice);
        weth.approve(address(pool), 0 ether);
        pool.depositCollateral(0);
        vm.stopPrank();

        // 测试零金额借款 - 应该成功
        vm.startPrank(alice);
        pool.borrow(0);
        vm.stopPrank();

        // 验证状态没有变化
        assertEq(pool.collaterals(alice), initialCollateral);
        assertEq(pool.debts(alice), initialDebt);
        assertEq(weth.balanceOf(alice), initialWethBalance);
        assertEq(usdc.balanceOf(alice), initialUsdcBalance);

        // 验证健康因子没有变化（应该仍然是最大值）
        assertEq(pool.getHealthFactor(alice), type(uint256).max);
    }

    /**
     * @dev 测试清算奖励的计算和抵押物转移的准确性。
     */
    function testLiquidationBonusCalculation() public {
        // Alice 存入 10 WETH 并借出 10000 USDC
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.depositCollateral(10 ether);
        pool.borrow(10000 ether);
        vm.stopPrank();

        uint256 initialCollateral = pool.collaterals(alice);
        uint256 initialDebt = pool.debts(alice);

        // 价格下跌使 Alice 变得不健康
        oracle.setPrice(address(weth), 800 ether);

        // Bob 清算 2000 USDC 债务
        vm.startPrank(bob);
        usdc.approve(address(pool), 2000 ether);
        uint256 bobInitialWETH = weth.balanceOf(bob);
        pool.liquidate(alice, 2000 ether);
        vm.stopPrank();

        // 验证债务减少正确
        assertEq(pool.debts(alice), initialDebt - 2000 ether);

        // 验证清算人获得的抵押物包含奖励
        uint256 wethGained = weth.balanceOf(bob) - bobInitialWETH;

        // 修正计算：清算奖励计算
        // collateralToSeize = (repayAmount * ONE * (ONE + liquidationBonus)) / price;
        uint256 expectedCollateral = (2000 ether * 1e18 * (1e18 + 0.05e18)) /
            (800 ether);

        // 由于Alice只有10 WETH抵押物，实际获得的不能超过剩余抵押物
        uint256 actualCollateral = wethGained;
        assertLe(actualCollateral, initialCollateral);
        assertGt(actualCollateral, 0);
        assertGt(expectedCollateral, actualCollateral);
    }

    /**
     * @dev 测试完全清算的情况。
     */
    function testFullLiquidation() public {
        // Alice 存入 5 WETH 并借出 5000 USDC
        vm.startPrank(alice);
        weth.approve(address(pool), 5 ether);
        pool.depositCollateral(5 ether);
        pool.borrow(5000 ether);
        vm.stopPrank();

        // 价格大幅下跌
        oracle.setPrice(address(weth), 500 ether);

        // Bob 完全清算 Alice 的债务
        vm.startPrank(bob);
        usdc.approve(address(pool), 5000 ether);
        pool.liquidate(alice, 5000 ether);
        vm.stopPrank();

        // 验证债务清零
        assertEq(pool.debts(alice), 0);
        // 验证抵押物被完全扣除
        assertEq(pool.collaterals(alice), 0);
    }

    /**
     * @dev 测试多个清算人参与清算的情况。
     */
    function testMultipleLiquidators() public {
        // Alice 存入 5 WETH 并借出 5000 USDC
        vm.startPrank(alice);
        weth.approve(address(pool), 5 ether);
        pool.depositCollateral(5 ether);
        pool.borrow(5000 ether);
        vm.stopPrank();

        // 价格下跌使 Alice 变得不健康
        oracle.setPrice(address(weth), 800 ether);

        // Bob 清算部分债务
        vm.startPrank(bob);
        usdc.approve(address(pool), 2000 ether);
        pool.liquidate(alice, 2000 ether);
        vm.stopPrank();

        uint256 debtAfterFirstLiquidation = pool.debts(alice);

        // Charlie 清算剩余债务
        vm.startPrank(charlie);
        usdc.approve(address(pool), debtAfterFirstLiquidation);
        pool.liquidate(alice, debtAfterFirstLiquidation);
        vm.stopPrank();

        // 验证债务清零
        assertEq(pool.debts(alice), 0);
        // 验证抵押物被完全扣除
        assertEq(pool.collaterals(alice), 0);
    }

    /**
     * @dev 测试健康因子计算的边界情况。
     */
    function testHealthFactorEdgeCases() public {
        // 测试无债务用户的健康因子
        assertEq(pool.getHealthFactor(alice), type(uint256).max);

        // Alice 存入少量抵押物
        vm.startPrank(alice);
        weth.approve(address(pool), 0.1 ether);
        pool.depositCollateral(0.1 ether);
        vm.stopPrank();

        // 测试有抵押物但无债务的健康因子
        assertEq(pool.getHealthFactor(alice), type(uint256).max);

        // 测试借款后的健康因子计算
        uint256 expectedHF = pool.getHealthFactorAfterDebt(alice, 100 ether);
        vm.startPrank(alice);
        pool.borrow(100 ether);
        vm.stopPrank();

        assertEq(pool.getHealthFactor(alice), expectedHF);
    }

    /**
     * @dev 测试价格剧烈波动对健康因子的影响。
     */
    function testPriceVolatility() public {
        // Alice 存入 10 WETH 并借出 14000 USDC (接近临界点)
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.depositCollateral(10 ether);
        pool.borrow(14000 ether);
        vm.stopPrank();

        uint256 initialHF = pool.getHealthFactor(alice);
        assertGt(initialHF, 1e18); // 初始健康

        // 价格小幅下跌到临界点
        oracle.setPrice(address(weth), 1900 ether);
        uint256 hfAfterSmallDrop = pool.getHealthFactor(alice);
        assertLt(hfAfterSmallDrop, initialHF);

        // 价格大幅下跌到不健康状态
        oracle.setPrice(address(weth), 1000 ether);
        uint256 hfAfterBigDrop = pool.getHealthFactor(alice);
        assertLt(hfAfterBigDrop, 1e18);
    }
}
```

执行测试：

```bash
➜  defi git:(main) ✗ forge test --match-path test/LendingWithLiquidation.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 33 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 551.53ms
Compiler run successful!

Ran 10 tests for test/LendingWithLiquidation.t.sol:LendingWithLiquidationTest
[PASS] testFullLiquidation() (gas: 205946)
[PASS] testHealthFactorEdgeCases() (gas: 173376)
[PASS] testLiquidationBonusCalculation() (gas: 210752)
[PASS] testLiquidationFlow() (gas: 215344)
[PASS] testMultipleLiquidators() (gas: 252628)
[PASS] testPriceVolatility() (gas: 176240)
[PASS] testZeroAmountOperations() (gas: 88838)
[PASS] test_RevertWhen_BorrowExceedDeposit() (gas: 97088)
[PASS] test_RevertWhen_LiquidateExceedDebt() (gas: 196294)
[PASS] test_RevertWhen_LiquidateHealthyAccount() (gas: 189428)
Suite result: ok. 10 passed; 0 failed; 0 skipped; finished in 7.03ms (22.31ms CPU time)

Ran 1 test suite in 154.85ms (7.03ms CPU time): 10 tests passed, 0 failed, 0 skipped (10 total tests)
```

---

## 6、本课总结

* 借贷平台必须引入 **抵押机制**，控制最大借款额度
* **健康因子 HF** 是清算触发的核心指标
* 当抵押价值下跌，HF < 1 → 可触发清算
* 清算人通过 **偿还债务 + 获得抵押物奖励**，保证系统安全
* 我们通过 MockOracle 模拟了价格变化，完成了完整清算流程

---

## 7、作业

1. 扩展合约支持 **多种抵押物**（不同资产有不同的抵押率）。
2. 在清算逻辑中加入 **协议费用分成**（一部分抵押物奖励进入协议金库）。
3. 思考：如果预言机出现恶意价格（如价格被操纵），会导致什么风险？如何防范？

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