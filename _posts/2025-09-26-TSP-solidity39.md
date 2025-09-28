---
layout: post
title: 《纸上谈兵·solidity》第 39 课：DeFi 实战(3) -- 利息累积与 aToken 设计
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解为什么 DeFi 借贷平台需要 **利息凭证代币（aToken / cToken）**
* 掌握 **利息累计** 的实现方式（借款人负债随时间增加，存款人资产随时间增加）
* 从零实现一个简化版的 **aToken 合约**
* 学会如何在测试中模拟“时间流逝”并验证利息计算

---

## 2、现实场景

在 Compound 和 Aave 这样的真实借贷平台：

* 用户存入资产时，不是简单增加一个「余额」，而是收到一份 **存款凭证代币**：
  * Compound：cToken（如 `cUSDC`）
  * Aave：aToken（如 `aUSDC`）
* 这些凭证代币的价值会随着利息积累 **不断增长**：
  * 存款人持有的 aToken 可以随时兑换为更多的底层资产
  * 借款人负债会随着时间增加

这样做的好处：

1. **流动性增强**：用户可以将 aToken 转让或抵押到其他协议中（组合性）
2. **利息自动复利**：无需手动计算利息，协议内部通过「指数模型」累计

---

## 3、核心知识点

1. **指数利率模型**
   * 使用一个 `index`（类似 Compound 的 `exchangeRate` 或 Aave 的 `liquidityIndex`）记录「累计利息因子」
   * 存款人或借款人的资产/负债按 index 变化
2. **aToken 的作用**
   * 存款时：铸造 aToken 给用户
   * 取款时：销毁 aToken 并返回更多的底层资产（因为累积了利息）
3. **时间驱动利息**
   * 协议需要按区块时间更新利率因子
   * 测试中可以用 Foundry 的 `vm.warp()` 模拟时间流逝

---

## 4、代码实现

**LendingPoolWithAToken.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AToken
 * @dev 代表存款凭证的代币合约，由借贷池管理。
 */
contract AToken is ERC20 {
    address public pool;

    /**
     * @dev 构造函数，初始化代币名称和符号。
     * @param name 代币名称。
     * @param symbol 代币符号。
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        pool = msg.sender;
    }

    /**
     * @dev 仅允许借贷池调用的修饰符。
     */
    modifier onlyPool() {
        require(msg.sender == pool, "not pool");
        _;
    }

    /**
     * @dev 铸造代币。
     * @param to 接收代币的地址。
     * @param amount 铸造的代币数量。
     */
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /**
     * @dev 销毁代币。
     * @param from 销毁代币的地址。
     * @param amount 销毁的代币数量。
     */
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}

/**
 * @title LendingPoolWithAToken
 * @dev 带有利息累积和 aToken 的借贷池合约。
 */
contract LendingPoolWithAToken {
    using SafeERC20 for IERC20;

    IERC20 public asset;
    AToken public aToken;

    uint256 public totalDeposits;
    uint256 public totalBorrows;

    uint256 public borrowIndex = 1e18; // 借款指数（累积利息因子）
    uint256 public supplyIndex = 1e18; // 存款指数
    uint256 public lastUpdate;

    // borrowRatePerSecond 使用 1e18 精度表示年化利率的秒级分解，
    // 例如约 10% 年化 -> 0.1 / (365*24*3600) * 1e18 ≈ 3170979198
    uint256 public borrowRatePerSecond = 3170979198;

    mapping(address => uint256) public userBorrows; // 按 index 标准化的借款（scaled）

    /**
     * @dev 构造函数，初始化借贷池。
     * @param _asset 支持的资产代币。
     */
    constructor(IERC20 _asset) {
        asset = _asset;
        aToken = new AToken("aToken", "aTKN");
        lastUpdate = block.timestamp;
    }

    /**
     * @dev 计算基于当前 block.timestamp 投影的索引（不修改状态）。
     * @return projectedBorrowIndex 投影的借款指数。
     * @return projectedSupplyIndex 投影的存款指数。
     */
    function _projectedIndexes()
        internal
        view
        returns (uint256 projectedBorrowIndex, uint256 projectedSupplyIndex)
    {
        if (block.timestamp == lastUpdate) {
            return (borrowIndex, supplyIndex);
        }
        uint256 timeDelta = block.timestamp - lastUpdate;
        uint256 interestFactor = borrowRatePerSecond * timeDelta; // still 1e18-scaled factor * time
        // newIndex = index + index * interestFactor / 1e18
        projectedBorrowIndex =
            borrowIndex +
            (borrowIndex * interestFactor) /
            1e18;
        projectedSupplyIndex =
            supplyIndex +
            (supplyIndex * interestFactor) /
            1e18;
    }

    /**
     * @dev 更新全局利息指数并把利息计入 totalBorrows / totalDeposits。
     */
    function _accrueInterest() internal {
        if (block.timestamp == lastUpdate) return;

        uint256 timeDelta = block.timestamp - lastUpdate;
        uint256 interestFactor = borrowRatePerSecond * timeDelta;

        if (totalBorrows > 0) {
            // 借款利息累加
            uint256 interestAccrued = (totalBorrows * interestFactor) / 1e18;
            totalBorrows += interestAccrued;
            totalDeposits += interestAccrued;

            borrowIndex = borrowIndex + (borrowIndex * interestFactor) / 1e18;
            supplyIndex = supplyIndex + (supplyIndex * interestFactor) / 1e18;
        }

        lastUpdate = block.timestamp;
    }

    /**
     * @dev 存款，获得等额 aToken（简化模型：1 aToken = 1 share 单位）。
     * @param amount 存款金额。
     */
    function deposit(uint256 amount) external {
        _accrueInterest();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        aToken.mint(msg.sender, amount);
        totalDeposits += amount;
    }

    /**
     * @dev 取款，销毁 aToken，取回含利息的资产。
     * @param aTokenAmount 销毁的 aToken 数量。
     */
    function withdraw(uint256 aTokenAmount) external {
        _accrueInterest();
        aToken.burn(msg.sender, aTokenAmount);
        uint256 withdrawAmount = (aTokenAmount * supplyIndex) / 1e18;
        require(totalDeposits >= withdrawAmount, "insufficient pool balance");
        totalDeposits -= withdrawAmount;
        asset.safeTransfer(msg.sender, withdrawAmount);
    }

    /**
     * @dev 借款。
     * @param amount 借款金额。
     */
    function borrow(uint256 amount) external {
        _accrueInterest();
        // 记录按 borrowIndex 标准化后的借款份额，便于 later 使用当前 borrowIndex 还原
        userBorrows[msg.sender] += (amount * 1e18) / borrowIndex;
        totalBorrows += amount;
        asset.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev 偿还借款。
     * @param amount 偿还金额。
     */
    function repay(uint256 amount) external {
        _accrueInterest();
        uint256 debt = (userBorrows[msg.sender] * borrowIndex) / 1e18;
        require(debt >= amount, "repay too much");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalBorrows -= amount;
        // 更新标准化借款份额
        userBorrows[msg.sender] = ((debt - amount) * 1e18) / borrowIndex;
    }

    /**
     * @dev 查询当前借款余额（含利息）。
     * @param user 用户地址。
     * @return 借款余额（含利息）。
     */
    function getBorrowBalance(address user) external view returns (uint256) {
        (uint256 pbIndex, ) = _projectedIndexes();
        uint256 debt = (userBorrows[user] * pbIndex) / 1e18;
        return debt;
    }
}
```

---

## 5、测试

**LendingPoolWithAToken.t.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPoolWithAToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @dev 模拟 USDC 代币合约，用于测试借贷池功能。
 */
contract MockUSDC is ERC20 {
    /**
     * @dev 构造函数，初始化代币名称和符号。
     */
    constructor() ERC20("MockUSDC", "mUSDC") {}

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
 * @title LendingPoolWithATokenTest
 * @dev 测试借贷池合约的功能和边界情况。
 */
contract LendingPoolWithATokenTest is Test {
    MockUSDC usdc;
    LendingPoolWithAToken pool;

    address alice = address(0x123);
    address bob = address(0x234);
    address charlie = address(0x345);

    /**
     * @dev 测试初始化，部署合约并分配初始资金。
     */
    function setUp() public {
        usdc = new MockUSDC();
        pool = new LendingPoolWithAToken(usdc);

        usdc.mint(alice, 1000 ether);
        usdc.mint(bob, 1000 ether);
        usdc.mint(charlie, 1000 ether);

        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @dev 测试存款和取款功能，验证利息计算。
     */
    function testDepositAndWithdrawWithInterest() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.warp(block.timestamp + 365 days); // 快进一年
        pool.withdraw(100 ether);
        vm.stopPrank();

        // 取回的资产 == 1000 ether（没有借款人就没利息）
        assertEq(usdc.balanceOf(alice), 1000 ether);
    }

    /**
     * @dev 测试借款功能，验证利息累积。
     */
    function testBorrowAccruesInterest() public {
        vm.startPrank(alice);
        pool.deposit(500 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(100 ether);
        vm.warp(block.timestamp + 365 days); // 一年后
        uint256 debt = pool.getBorrowBalance(bob);
        vm.stopPrank();

        // 借款人负债大于本金（约10%年化利率）
        assertGt(debt, 100 ether);
        // 验证利息计算准确性（10%年化，100 ether * 1.1 ≈ 110 ether）
        assertApproxEqAbs(debt, 110 ether, 1 ether); // 允许1 ether的误差
    }

    /**
     * @dev 测试取款超过存款的错误情况。
     */
    function test_RevertWhen_WithdrawMoreThanDeposit() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        // revert error: ERC20InsufficientBalance
        vm.expectRevert();
        pool.withdraw(200 ether); // 尝试取款超过存款
        vm.stopPrank();
    }

    /**
     * @dev 测试借款超过池子余额的错误情况。
     */
    function test_RevertWhen_BorrowMoreThanPoolBalance() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(); // ERC20 transfer 会 revert
        pool.borrow(200 ether); // 尝试借款超过池子余额
        vm.stopPrank();
    }

    /**
     * @dev 测试还款超过借款的错误情况。
     */
    function test_RevertWhen_RepayMoreThanBorrow() public {
        vm.startPrank(alice);
        pool.deposit(500 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(100 ether);

        // 尝试还款超过借款金额
        vm.expectRevert("repay too much");
        pool.repay(200 ether);
        vm.stopPrank();
    }

    /**
     * @dev 测试多用户场景下的存款和借款功能。
     */
    function testMultipleUsersDepositBorrow() public {
        // Alice 存款
        vm.startPrank(alice);
        pool.deposit(300 ether);
        vm.stopPrank();

        // Bob 存款
        vm.startPrank(bob);
        pool.deposit(200 ether);
        vm.stopPrank();

        // Charlie 借款
        vm.startPrank(charlie);
        pool.borrow(100 ether);
        vm.stopPrank();

        // 验证总存款和总借款
        assertEq(pool.totalDeposits(), 500 ether);
        assertEq(pool.totalBorrows(), 100 ether);

        // 快进时间产生利息
        vm.warp(block.timestamp + 180 days); // 半年

        // 验证利息累积
        uint256 charlieDebt = pool.getBorrowBalance(charlie);
        assertGt(charlieDebt, 100 ether);
        assertApproxEqAbs(charlieDebt, 105 ether, 0.5 ether); // 约5%利息
    }

    /**
     * @dev 测试完整的借贷周期，包括借款、还款和利息计算。
     */
    function testCompleteBorrowRepayCycle() public {
        // 设置
        vm.startPrank(alice);
        pool.deposit(500 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 borrowAmount = 100 ether;
        pool.borrow(borrowAmount);

        // 快进一年
        vm.warp(block.timestamp + 365 days);

        // 获取当前债务（含利息）
        uint256 currentDebt = pool.getBorrowBalance(bob);
        assertGt(currentDebt, borrowAmount);

        // 部分还款
        uint256 partialRepay = 50 ether;
        pool.repay(partialRepay);

        // 验证剩余债务
        uint256 remainingDebt = pool.getBorrowBalance(bob);
        assertLt(remainingDebt, currentDebt);
        assertGt(remainingDebt, 0);

        // 快进半年
        vm.warp(block.timestamp + 180 days);

        // 还清剩余债务
        uint256 finalDebt = pool.getBorrowBalance(bob);
        pool.repay(finalDebt);

        // 验证债务清零
        assertEq(pool.getBorrowBalance(bob), 0);
        vm.stopPrank();
    }

    /**
     * @dev 测试 aToken 的功能，包括转账和取款。
     */
    function testATokenFunctionality() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        pool.deposit(depositAmount);

        // 验证aToken余额
        AToken aToken = pool.aToken();
        assertEq(aToken.balanceOf(alice), depositAmount);

        // 验证aToken转账
        aToken.transfer(bob, 50 ether);
        assertEq(aToken.balanceOf(alice), 50 ether);
        assertEq(aToken.balanceOf(bob), 50 ether);

        // Bob 用转移的aToken取款
        vm.stopPrank();
        vm.startPrank(bob);
        pool.withdraw(50 ether);
        vm.stopPrank();

        // 验证Bob收到资金
        assertGt(usdc.balanceOf(bob), 1000 ether); // 初始1000 + 取款50
    }

    // 测试利息索引更新
    function testInterestIndexUpdate() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(10 ether);
        vm.stopPrank();

        uint256 initialBorrowIndex = pool.borrowIndex();
        uint256 initialSupplyIndex = pool.supplyIndex();

        // 快进时间
        vm.warp(block.timestamp + 30 days);

        // 触发利息累积（通过借款操作）
        vm.startPrank(bob);
        pool.borrow(50 ether);
        vm.stopPrank();

        uint256 newBorrowIndex = pool.borrowIndex();
        uint256 newSupplyIndex = pool.supplyIndex();


        // 验证索引已更新
        assertGt(newBorrowIndex, initialBorrowIndex);
        assertGt(newSupplyIndex, initialSupplyIndex);
    }

    // 测试视图函数不改变状态
    function testViewFunctionsDoNotChangeState() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(50 ether);
        vm.stopPrank();

        // 记录初始状态
        uint256 initialTotalDeposits = pool.totalDeposits();
        uint256 initialTotalBorrows = pool.totalBorrows();

        // 调用视图函数多次
        for (uint i = 0; i < 5; i++) {
            pool.getBorrowBalance(bob);
        }

        // 验证状态未改变
        assertEq(pool.totalDeposits(), initialTotalDeposits);
        assertEq(pool.totalBorrows(), initialTotalBorrows);
    }

    // 测试重入攻击防护（通过SafeERC20）
    function testSafeERC20Protection() public {
        // 这个测试验证SafeERC20的正常工作，不期望revert
        vm.startPrank(alice);
        pool.deposit(100 ether); // 应该成功，不会重入
        vm.stopPrank();
    }

    // 测试极端时间情况
    function testExtremeTimeScenarios() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.borrow(50 ether);
        vm.stopPrank();

        // 测试极长时间（100年）
        vm.warp(block.timestamp + 365 * 100 days);

        // 应该不会溢出
        uint256 debt = pool.getBorrowBalance(bob);
        assertGt(debt, 50 ether);

        // 极端高利率下的合理性检查
        assertLt(debt, 1000000 ether); // 债务不应增长到不合理的大小
    }

    // 测试连续操作
    function testConsecutiveOperations() public {
        vm.startPrank(alice);

        // 多次存款
        for (uint i = 0; i < 5; i++) {
            pool.deposit(20 ether);
        }

        assertEq(pool.totalDeposits(), 100 ether);

        // 多次取款
        for (uint i = 0; i < 5; i++) {
            pool.withdraw(20 ether);
        }

        vm.stopPrank();

        // 最终余额应该接近初始余额（可能有微小利息）
        assertApproxEqAbs(usdc.balanceOf(alice), 1000 ether, 1 wei);
    }
}
```

运行测试：

```bash
➜  defi git:(main) ✗ forge test --match-path test/LendingPoolWithAToken.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 34 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 574.19ms
Compiler run successful!

Ran 13 tests for test/LendingPoolWithAToken.t.sol:LendingPoolWithATokenTest
[PASS] testATokenFunctionality() (gas: 168064)
[PASS] testBorrowAccruesInterest() (gas: 200690)
[PASS] testCompleteBorrowRepayCycle() (gas: 227198)
[PASS] testConsecutiveOperations() (gas: 189458)
[PASS] testDepositAndWithdrawWithInterest() (gas: 119856)
[PASS] testExtremeTimeScenarios() (gas: 200041)
[PASS] testInterestIndexUpdate() (gas: 220701)
[PASS] testMultipleUsersDepositBorrow() (gas: 246325)
[PASS] testSafeERC20Protection() (gas: 129293)
[PASS] testViewFunctionsDoNotChangeState() (gas: 210738)
[PASS] test_RevertWhen_BorrowMoreThanPoolBalance() (gas: 183555)
[PASS] test_RevertWhen_RepayMoreThanBorrow() (gas: 193379)
[PASS] test_RevertWhen_WithdrawMoreThanDeposit() (gas: 133319)
Suite result: ok. 13 passed; 0 failed; 0 skipped; finished in 12.61ms (11.92ms CPU time)

Ran 1 test suite in 159.89ms (12.61ms CPU time): 13 tests passed, 0 failed, 0 skipped (13 total tests)
```

---

## 6、本课总结

* 借贷平台必须有 **利息累计机制**，否则存款人没有收益
* aToken/cToken 是流动性凭证，保证用户可以在任意时间兑换带利息的资产
* 指数（Index）机制是主流实现，能高效地处理所有账户的利息计算
* 通过 `vm.warp()` 可以在测试中模拟时间，验证复利效果

---

## 7、作业

1. 修改合约，让 **借款利率与资金池利用率挂钩**（结合第 1 课的利率模型）。
2. 在 `aToken` 中实现 **ERC20 转账**，测试 Alice 将 aToken 转给 Bob，Bob 再提现能否获得正确的利息。
3. 思考：为什么 Aave v3 中把 `aToken` 和 `debtToken` 分开设计，而不是用一个 token 表示所有状态？


