---
layout: post
title: 《纸上谈兵·solidity》第 40 课：DeFi 实战(4) -- 风险控制与防护
tags: solidity
mermaid: false
math: false
---

## 1. 学习目标

* 理解借贷协议面临的核心安全风险
* 掌握如何在 Solidity 中防御常见攻击（如重入攻击、预言机操纵）
* 在资金安全与去中心化之间找到平衡

---

## 2. 核心知识点

1. **重入攻击（Reentrancy Attack）**
   * 攻击者通过合约回调，反复调用 `withdraw()` 等函数，导致重复转账。
   * 防御方法：
     * 使用 `ReentrancyGuard`（OpenZeppelin 提供）
     * 遵循 Checks-Effects-Interactions 模式
2. **预言机操纵（Oracle Manipulation）**
   * 攻击者通过闪电贷操纵交易对价格，导致借贷协议错误清算或套利。
   * 防御方法：
     * 使用去中心化预言机（如 Chainlink）
     * 设置价格更新延迟，避免瞬时波动影响
     * 采用多源价格聚合
3. **利率与资金池风险**
   * 资金池枯竭（借款率 100%）时，存款人无法提现。
   * 防御方法：
     * 设置借款上限（Reserve Factor）
     * 协议保留部分流动性

---

## 3. 合约实现：`LendingPoolWithProtection.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title 价格预言机接口
 * @notice 提供获取代币价格的功能
 */
interface IPriceOracle {
    /**
     * @notice 获取指定代币的当前价格
     * @param token 要查询价格的代币地址
     * @return 代币价格，以基础计价单位表示
     */
    function getPrice(address token) external view returns (uint256);
}

/**
 * @title 带保护机制的借贷池合约
 * @notice 允许用户存款、取款、借款和还款，包含重入保护和借款上限机制
 * @dev 使用ReentrancyGuard防止重入攻击，通过价格预言机获取资产价格
 */
contract LendingPoolWithProtection is ReentrancyGuard {
    using SafeERC20 for ERC20;

    /// @notice 存款事件，当用户存入资产时触发
    event Deposit(address indexed user, uint256 amount);
    /// @notice 取款事件，当用户取出资产时触发
    event Withdraw(address indexed user, uint256 amount);
    /// @notice 借款事件，当用户借出资产时触发
    event Borrow(address indexed user, uint256 amount);
    /// @notice 还款事件，当用户偿还借款时触发
    event Repay(address indexed user, uint256 amount);

    /// @notice 借贷池支持的ERC20资产
    ERC20 public immutable asset;
    /// @notice 价格预言机合约，用于获取资产价格
    IPriceOracle public immutable oracle;

    /// @notice 用户地址到存款金额的映射
    mapping(address => uint256) public deposits;
    /// @notice 用户地址到借款金额的映射
    mapping(address => uint256) public borrows;

    /// @notice 合约中总存款金额
    uint256 public totalDeposits;
    /// @notice 合约中总借款金额
    uint256 public totalBorrows;

    /// @notice 借款上限比例，基于总存款的百分比
    uint256 public constant BORROW_CAP = 80; // 最大 80% 资金可借出

    /**
     * @notice 构造函数，初始化借贷池
     * @param _asset 借贷池支持的ERC20代币地址
     * @param _oracle 价格预言机合约地址
     */
    constructor(address _asset, address _oracle) {
        asset = ERC20(_asset);
        oracle = IPriceOracle(_oracle);
    }

    /**
     * @notice 存款功能，用户将资产存入借贷池
     * @dev 使用nonReentrant修饰符防止重入攻击
     * @param amount 存款金额
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "invalid amount");
        asset.safeTransferFrom(msg.sender, address(this), amount);

        deposits[msg.sender] += amount;
        totalDeposits += amount;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice 借款功能，用户从借贷池借出资产
     * @dev 借款金额不能超过借款上限，使用nonReentrant修饰符防止重入攻击
     * @param amount 借款金额
     */
    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "invalid amount");
        uint256 cap = (totalDeposits * BORROW_CAP) / 100;
        require(totalBorrows + amount <= cap, "borrow cap reached");

        borrows[msg.sender] += amount;
        totalBorrows += amount;

        asset.safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    /**
     * @notice 还款功能，用户偿还借款
     * @dev 还款金额不能超过用户的借款总额，使用nonReentrant修饰符防止重入攻击
     * @param amount 还款金额
     */
    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "invalid amount");
        require(borrows[msg.sender] >= amount, "repay too much");

        asset.safeTransferFrom(msg.sender, address(this), amount);

        borrows[msg.sender] -= amount;
        totalBorrows -= amount;
        
        emit Repay(msg.sender, amount);
    }

    /**
     * @notice 取款功能，用户从借贷池取出存款
     * @dev 取款金额不能超过用户存款和合约可用流动性，使用nonReentrant修饰符防止重入攻击
     * @param amount 取款金额
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(deposits[msg.sender] >= amount, "not enough deposit");

        uint256 available = asset.balanceOf(address(this));
        require(amount <= available, "not enough liquidity");

        deposits[msg.sender] -= amount;
        totalDeposits -= amount;

        asset.safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice 获取资产当前价格
     * @dev 通过价格预言机查询资产价格
     * @return 资产当前价格
     */
    function getAssetPrice() external view returns (uint256) {
        return oracle.getPrice(address(asset));
    }
}
```

---

## 4. 测试代码：`LendingPoolWithProtection.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPoolWithProtection.sol";

/**
 * @title MockERC20
 * @notice 用于测试的模拟ERC20代币合约
 * @dev 继承OpenZeppelin的ERC20实现，提供mint功能用于测试
 */
contract MockERC20 is ERC20 {
    /**
     * @notice 构造函数，初始化代币
     * @dev 铸造初始供应量给部署者
     */
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }

    /**
     * @notice 铸造代币
     * @dev 仅供测试使用，为指定地址铸造指定数量的代币
     * @param to 接收代币的地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockOracle
 * @notice 用于测试的模拟价格预言机合约
 * @dev 实现IPriceOracle接口，允许手动设置价格
 */
contract MockOracle is IPriceOracle {
    /// @notice 当前价格
    uint256 public price = 1e18;

    /**
     * @notice 获取代币价格
     * @dev 忽略token参数，返回固定价格
     * @param token 代币地址（未使用）
     * @return 当前设置的价格
     */
    function getPrice(address token) external view returns (uint256) {
        return price;
    }

    /**
     * @notice 设置新的价格
     * @dev 仅供测试使用，更新预言机价格
     * @param newPrice 新的价格值
     */
    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}

/**
 * @title LendingPoolWithProtectionTest
 * @notice 借贷池合约的完整测试套件
 * @dev 使用Forge测试框架测试LendingPoolWithProtection合约的所有功能
 */
contract LendingPoolWithProtectionTest is Test {
    /// @notice 测试用的ERC20代币
    MockERC20 public token;
    /// @notice 测试用的价格预言机
    MockOracle public oracle;
    /// @notice 被测试的借贷池合约
    LendingPoolWithProtection public pool;

    /// @notice 测试用户地址
    address owner = address(this);
    address user1 = address(0x123);
    address user2 = address(0x234);
    address user3 = address(0x345);

    /// @notice 借款上限常量
    uint256 constant BORROW_CAP = 80;

    /// @notice 测试事件声明
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);

    /**
     * @notice 测试设置函数
     * @dev 在每个测试运行前执行，初始化测试环境
     */
    function setUp() public {
        // 部署测试合约
        token = new MockERC20();
        oracle = new MockOracle();
        pool = new LendingPoolWithProtection(address(token), address(oracle));

        // 分配代币给测试用户
        token.transfer(user1, 1000 ether);
        token.transfer(user2, 1000 ether);
        token.transfer(user3, 1000 ether);

        // 授权池子操作代币
        vm.startPrank(user1);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // ============ 存款测试 ============

    /**
     * @notice 测试成功存款场景
     * @dev 验证存款后状态正确更新，事件正确触发
     */
    function test_Deposit_Success() public {
        vm.startPrank(user1);

        uint256 initialBalance = token.balanceOf(user1);
        uint256 depositAmount = 100 ether;

        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount);

        pool.deposit(depositAmount);

        // 验证状态更新
        assertEq(pool.deposits(user1), depositAmount);
        assertEq(pool.totalDeposits(), depositAmount);
        assertEq(token.balanceOf(user1), initialBalance - depositAmount);
        assertEq(token.balanceOf(address(pool)), depositAmount);

        vm.stopPrank();
    }

    /**
     * @notice 测试存款零金额时的回退
     * @dev 验证合约拒绝零金额存款
     */
    function test_RevertWhen_Deposit_ZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("invalid amount");
        pool.deposit(0);

        vm.stopPrank();
    }

    /**
     * @notice 测试多用户存款场景
     * @dev 验证多个用户存款时总存款和用户存款正确更新
     */
    function test_Deposit_MultipleUsers() public {
        // 用户1存款
        vm.prank(user1);
        pool.deposit(100 ether);
        assertEq(pool.deposits(user1), 100 ether);

        // 用户2存款
        vm.prank(user2);
        pool.deposit(200 ether);
        assertEq(pool.deposits(user2), 200 ether);

        // 验证总存款
        assertEq(pool.totalDeposits(), 300 ether);
        assertEq(token.balanceOf(address(pool)), 300 ether);
    }

    // ============ 取款测试 ============

    /**
     * @notice 测试成功取款场景
     * @dev 验证取款后状态正确更新，事件正确触发
     */
    function test_Withdraw_Success() public {
        vm.startPrank(user1);

        // 先存款
        pool.deposit(100 ether);

        uint256 initialPoolBalance = token.balanceOf(address(pool));
        uint256 withdrawAmount = 50 ether;

        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user1, withdrawAmount);

        pool.withdraw(withdrawAmount);

        // 验证状态更新
        assertEq(pool.deposits(user1), 50 ether);
        assertEq(pool.totalDeposits(), 50 ether);
        assertEq(
            token.balanceOf(address(pool)),
            initialPoolBalance - withdrawAmount
        );

        vm.stopPrank();
    }

    /**
     * @notice 测试取款超过存款金额时的回退
     * @dev 验证合约拒绝超额取款
     */
    function test_RevertWhen_Withdraw_InsufficientDeposit() public {
        vm.startPrank(user1);

        pool.deposit(100 ether);

        vm.expectRevert("not enough deposit");
        pool.withdraw(150 ether);

        vm.stopPrank();
    }

    /**
     * @notice 测试取款超过合约流动性时的回退
     * @dev 验证当合约流动性不足时拒绝取款
     */
    function test_RevertWhen_Withdraw_InsufficientLiquidity() public {
        vm.startPrank(user1);
        pool.deposit(100 ether);
        vm.stopPrank();

        // 用户2借款，消耗流动性
        vm.prank(user2);
        pool.borrow(80 ether);

        // 用户1尝试提取超过可用流动性的金额
        vm.prank(user1);
        vm.expectRevert("not enough liquidity");
        pool.withdraw(50 ether); // 池子只有20 ether流动性
    }

    /**
     * @notice 测试全额取款场景
     * @dev 验证用户可以取回全部存款
     */
    function test_Withdraw_AllDeposit() public {
        vm.startPrank(user1);

        pool.deposit(100 ether);
        pool.withdraw(100 ether);

        assertEq(pool.deposits(user1), 0);
        assertEq(pool.totalDeposits(), 0);
        assertEq(token.balanceOf(user1), 1000 ether); // 余额恢复

        vm.stopPrank();
    }

    // ============ 借款测试 ============

    /**
     * @notice 测试成功借款场景
     * @dev 验证借款后状态正确更新，事件正确触发
     */
    function test_Borrow_Success() public {
        // 用户1存款提供流动性
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.startPrank(user2);

        uint256 borrowAmount = 50 ether;

        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit Borrow(user2, borrowAmount);

        pool.borrow(borrowAmount);

        // 验证状态更新
        assertEq(pool.borrows(user2), borrowAmount);
        assertEq(pool.totalBorrows(), borrowAmount);
        assertEq(token.balanceOf(user2), 1000 ether + borrowAmount);

        vm.stopPrank();
    }

    /**
     * @notice 测试借款零金额时的回退
     * @dev 验证合约拒绝零金额借款
     */
    function test_RevertWhen_Borrow_ZeroAmount() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        vm.expectRevert("invalid amount");
        pool.borrow(0);
    }

    /**
     * @notice 测试超过借款上限时的回退
     * @dev 验证合约拒绝超过借款上限的借款请求
     */
    function test_RevertWhen_Borrow_CapLimit() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.startPrank(user2);

        // 借款达到上限 (80% of 100 = 80 ether)
        pool.borrow(80 ether);

        // 尝试再借1 wei，应该失败
        vm.expectRevert("borrow cap reached");
        pool.borrow(1);

        vm.stopPrank();
    }

    /**
     * @notice 测试多用户在借款上限内借款
     * @dev 验证多个用户可以共享借款额度
     */
    function test_Borrow_MultipleUsersUnderCap() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        // 用户2借款
        vm.prank(user2);
        pool.borrow(40 ether);
        assertEq(pool.borrows(user2), 40 ether);

        // 用户3借款
        vm.prank(user3);
        pool.borrow(40 ether);
        assertEq(pool.borrows(user3), 40 ether);

        // 验证总借款
        assertEq(pool.totalBorrows(), 80 ether);
        assertEq(
            pool.totalBorrows(),
            (pool.totalDeposits() * BORROW_CAP) / 100
        );
    }

    /**
     * @notice 测试无流动性时的借款回退
     * @dev 验证当合约没有足够代币时借款失败
     */
    function test_RevertWhen_Borrow_NoLiquidity() public {
        // 没有存款，直接借款
        vm.prank(user1);
        vm.expectRevert(); // 由于余额不足，transfer会失败
        pool.borrow(10 ether);
    }

    // ============ 还款测试 ============

    /**
     * @notice 测试成功还款场景
     * @dev 验证还款后状态正确更新，事件正确触发
     */
    function test_Repay_Success() public {
        // 设置借款
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        pool.borrow(50 ether);

        vm.startPrank(user2);

        uint256 repayAmount = 30 ether;

        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit Repay(user2, repayAmount);

        pool.repay(repayAmount);

        // 验证状态更新
        assertEq(pool.borrows(user2), 20 ether);
        assertEq(pool.totalBorrows(), 20 ether);
        assertEq(token.balanceOf(user2), 1000 ether + 50 ether - repayAmount);

        vm.stopPrank();
    }

    /**
     * @notice 测试还款零金额时的回退
     * @dev 验证合约拒绝零金额还款
     */
    function test_RevertWhen_Repay_ZeroAmount() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        pool.borrow(50 ether);

        vm.prank(user2);
        vm.expectRevert("invalid amount");
        pool.repay(0);
    }

    /**
     * @notice 测试超额还款时的回退
     * @dev 验证合约拒绝超过借款金额的还款
     */
    function test_RevertWhen_Repay_ExcessAmount() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        pool.borrow(50 ether);

        vm.prank(user2);
        vm.expectRevert("repay too much");
        pool.repay(60 ether);
    }

    /**
     * @notice 测试全额还款场景
     * @dev 验证用户可以全额偿还借款
     */
    function test_Repay_FullRepayment() public {
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        pool.borrow(50 ether);

        vm.prank(user2);
        pool.repay(50 ether);

        assertEq(pool.borrows(user2), 0);
        assertEq(pool.totalBorrows(), 0);
    }

    // ============ 借款上限逻辑测试 ============

    /**
     * @notice 测试借款上限计算
     * @dev 验证不同存款金额下的借款上限计算正确
     */
    function test_BorrowCap_Calculation() public {
        // 测试不同存款金额下的借款上限计算
        vm.prank(user1);
        pool.deposit(123.456 ether);

        uint256 expectedCap = (123.456 ether * BORROW_CAP) / 100;

        vm.prank(user2);
        pool.borrow(expectedCap);

        assertEq(pool.totalBorrows(), expectedCap);
    }

    /**
     * @notice 测试存款变化后的借款上限
     * @dev 验证新增存款后借款上限正确更新
     */
    function test_BorrowCap_AfterDepositChange() public {
        // 初始存款和借款
        vm.prank(user1);
        pool.deposit(100 ether);

        vm.prank(user2);
        pool.borrow(80 ether); // 达到上限

        // 增加存款，借款上限应该提高
        vm.prank(user3);
        pool.deposit(100 ether);

        // 现在可以借更多
        vm.prank(user2);
        pool.borrow(80 ether); // 再借80，总共160

        assertEq(pool.totalBorrows(), 160 ether);
        assertEq(pool.totalBorrows(), (200 ether * BORROW_CAP) / 100);
    }

    // ============ 价格预言机测试 ============

    /**
     * @notice 测试获取资产价格功能
     * @dev 验证价格预言机集成正常工作
     */
    function test_GetAssetPrice() public {
        uint256 price = pool.getAssetPrice();
        assertEq(price, 1e18);

        // 测试价格更新
        oracle.setPrice(1.5e18);
        price = pool.getAssetPrice();
        assertEq(price, 1.5e18);
    }

    // ============ 边缘情况测试 ============

    /**
     * @notice 测试复杂交互场景
     * @dev 模拟真实使用场景，验证合约在各种操作组合下的正确性
     */
    function test_Complex_Scenario() public {
        // 复杂场景：多个用户存款、借款、还款、取款

        // 用户1存款
        vm.prank(user1);
        pool.deposit(200 ether);

        // 用户2借款
        vm.prank(user2);
        pool.borrow(100 ether);

        // 用户3存款
        vm.prank(user3);
        pool.deposit(100 ether);

        // 用户2部分还款
        vm.prank(user2);
        pool.repay(50 ether);

        // 用户3借款
        vm.prank(user3);
        pool.borrow(40 ether);

        // 用户1取款
        vm.prank(user1);
        pool.withdraw(100 ether);

        // 验证最终状态
        assertEq(pool.deposits(user1), 100 ether);
        assertEq(pool.deposits(user3), 100 ether);
        assertEq(pool.borrows(user2), 50 ether);
        assertEq(pool.borrows(user3), 40 ether);
        assertEq(pool.totalDeposits(), 200 ether);
        assertEq(pool.totalBorrows(), 90 ether);

        // 验证借款上限
        uint256 currentCap = (pool.totalDeposits() * BORROW_CAP) / 100;
        assertTrue(pool.totalBorrows() <= currentCap);
    }

    /**
     * @notice 测试最大借款上限利用率
     * @dev 验证合约在达到最大借款上限时的行为
     */
    function test_Maximum_BorrowCap_Utilization() public {
        // 测试完全利用借款上限的情况
        vm.prank(user1);
        pool.deposit(1000 ether);

        vm.prank(user2);
        pool.borrow(800 ether);

        assertEq(pool.totalBorrows(), 800 ether);
        assertEq(
            pool.totalBorrows(),
            (pool.totalDeposits() * BORROW_CAP) / 100
        );
    }
}
```  

**执行测试**：

```bash
➜  defi git:(master) ✗ forge test --match-path test/LendingPoolWithProtection.t.sol -vvv
[⠊] Compiling...
[⠔] Compiling 2 files with Solc 0.8.29
[⠑] Solc 0.8.29 finished in 1.48s
Compiler run successful with warnings:
Warning (5667): Unused function parameter. Remove or comment out the variable name to silence this warning.
  --> test/LendingPoolWithProtection.t.sol:47:23:
   |
47 |     function getPrice(address token) external view returns (uint256) {
   |                       ^^^^^^^^^^^^^


Ran 21 tests for test/LendingPoolWithProtection.t.sol:LendingPoolWithProtectionTest
[PASS] test_BorrowCap_AfterDepositChange() (gas: 210930)
[PASS] test_BorrowCap_Calculation() (gas: 158634)
[PASS] test_Borrow_MultipleUsersUnderCap() (gas: 203696)
[PASS] test_Borrow_Success() (gas: 167095)
[PASS] test_Complex_Scenario() (gas: 266056)
[PASS] test_Deposit_MultipleUsers() (gas: 146024)
[PASS] test_Deposit_Success() (gas: 109991)
[PASS] test_GetAssetPrice() (gas: 20283)
[PASS] test_Maximum_BorrowCap_Utilization() (gas: 156214)
[PASS] test_Repay_FullRepayment() (gas: 140551)
[PASS] test_Repay_Success() (gas: 179424)
[PASS] test_RevertWhen_Borrow_CapLimit() (gas: 163477)
[PASS] test_RevertWhen_Borrow_NoLiquidity() (gas: 21630)
[PASS] test_RevertWhen_Borrow_ZeroAmount() (gas: 104147)
[PASS] test_RevertWhen_Deposit_ZeroAmount() (gas: 17316)
[PASS] test_RevertWhen_Repay_ExcessAmount() (gas: 163176)
[PASS] test_RevertWhen_Repay_ZeroAmount() (gas: 162940)
[PASS] test_RevertWhen_Withdraw_InsufficientDeposit() (gas: 101963)
[PASS] test_RevertWhen_Withdraw_InsufficientLiquidity() (gas: 165013)
[PASS] test_Withdraw_AllDeposit() (gas: 91461)
[PASS] test_Withdraw_Success() (gas: 118505)
Suite result: ok. 21 passed; 0 failed; 0 skipped; finished in 6.10ms (9.91ms CPU time)

Ran 1 test suite in 460.54ms (6.10ms CPU time): 21 tests passed, 0 failed, 0 skipped (21 total tests)
```

---

## 5. 总结

* 借贷协议面临的核心风险：
  * **重入攻击**：防御手段是 `nonReentrant` 与 CEI 模式
  * **预言机操纵**：防御手段是去中心化预言机 + 时间加权价格
  * **流动性风险**：防御手段是借款上限（Borrow Cap）
* 本课通过合约实现和测试，展示了如何在代码层面加固协议安全性。

---

## 6. 课后作业

1. 在合约中引入 **闪电贷攻击测试**，模拟 Uniswap 价格操纵。
2. 修改 `MockOracle`，让价格在短时间内波动，测试协议能否被利用清算。
3. 增加一个协议费参数，让清算时部分奖励归协议所有。

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