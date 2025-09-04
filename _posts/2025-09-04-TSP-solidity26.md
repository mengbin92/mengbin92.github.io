---
layout: post
title: 《纸上谈兵·solidity》第 26 课：借贷合约简化实现
tags: solidity
mermaid: false
math: false
---  

## 1、学习目标

1. 理解 **借贷协议核心机制**：存款、借款、还款、清算
2. 掌握 **抵押率（Collateral Factor）** 的风险控制方法
3. 学会实现一个最小版 **Compound/Aave 借贷池**

---

## 2、合约设计要点

* 用户存入 **ETH** 作为抵押
* 用户可以借出 **ERC20 稳定币（如 DAI）**
* 设置 **抵押率（Collateral Factor）**，保证抵押物 > 借款
* 借款人债务随时间增长（利息按年化利率计算）
* 当抵押不足时，可以被 **清算（Liquidation）**

---

## 3、合约实现 `SimpleLending.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimpleLending - 带利息的简化版借贷池
/// @notice 仅用于教学演示，不能用于生产环境
/// @dev 该合约实现了基本的借贷功能，包括抵押、借款、还款和清算
interface IERC20 {
    /// @notice 转账函数
    /// @param to 接收地址
    /// @param amount 转账金额
    /// @return 是否成功
    function transfer(address to, uint amount) external returns (bool);

    /// @notice 从指定地址转账
    /// @param from 转出地址
    /// @param to 接收地址
    /// @param amount 转账金额
    /// @return 是否成功
    function transferFrom(address from, address to, uint amount) external returns (bool);

    /// @notice 查询余额
    /// @param account 查询地址
    /// @return 余额
    function balanceOf(address account) external view returns (uint);

    /// @notice 铸造代币
    /// @param to 接收地址
    /// @param amount 铸造金额
    function mint(address to, uint amount) external;
}

contract SimpleLending {
    /// @notice 稳定币合约地址
    IERC20 public stablecoin; 

    /// @notice 抵押率，75%
    uint public constant COLLATERAL_FACTOR = 75;

    /// @notice 清算阈值，80%
    uint public constant LIQUIDATION_THRESHOLD = 80;

    /// @notice 年化利率，5% (0.05 * 1e18)
    uint public constant INTEREST_RATE_PER_YEAR = 5e16;

    /// @notice 一年的秒数
    uint public constant SECONDS_PER_YEAR = 365 days;

    /// @notice 账户信息结构体
    struct Account {
        uint collateralETH; // 抵押 ETH
        uint debt;          // 借款本金 + 利息
        uint lastAccrued;   // 上次计息时间
    }

    /// @notice 用户账户映射
    mapping(address => Account) public accounts;

    // 事件
    /// @notice 抵押事件
    event Deposit(address indexed user, uint amount);

    /// @notice 借款事件
    event Borrow(address indexed user, uint amount);

    /// @notice 还款事件
    event Repay(address indexed user, uint amount);

    /// @notice 清算事件
    event Liquidate(address indexed liquidator, address indexed user, uint repayAmount);

    /// @notice 计息事件
    event AccrueInterest(address indexed user, uint newDebt);

    /// @notice 构造函数
    /// @param stablecoinAddr 稳定币合约地址
    constructor(address stablecoinAddr) {
        stablecoin = IERC20(stablecoinAddr);
    }

    /// @notice 内部函数：计息
    /// @dev 根据时间计算利息并更新债务
    /// @param user 用户地址
    function _accrueInterest(address user) internal {
        Account storage account = accounts[user];
        if (account.debt == 0) {
            account.lastAccrued = block.timestamp;
            return;
        }

        uint elapsed = block.timestamp - account.lastAccrued;
        if (elapsed == 0) return;

        uint interest = (account.debt * INTEREST_RATE_PER_YEAR * elapsed) / (SECONDS_PER_YEAR * 1e18);
        account.debt += interest;
        account.lastAccrued = block.timestamp;

        emit AccrueInterest(user, account.debt);
    }

    /// @notice 存入 ETH 作为抵押
    /// @dev 用户可以通过此函数存入 ETH 作为抵押
    function depositCollateral() external payable {
        accounts[msg.sender].collateralETH += msg.value;
        if (accounts[msg.sender].lastAccrued == 0) {
            accounts[msg.sender].lastAccrued = block.timestamp;
        }
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice 借款
    /// @dev 用户可以通过此函数借款
    /// @param amount 借款金额
    function borrow(uint amount) external {
        _accrueInterest(msg.sender);

        Account storage account = accounts[msg.sender];
        require(account.collateralETH > 0, "no collateral");

        uint maxBorrow = (account.collateralETH * COLLATERAL_FACTOR) / 100;
        require(account.debt + amount <= maxBorrow, "exceeds borrow limit");

        account.debt += amount;
        stablecoin.mint(msg.sender, amount);

        emit Borrow(msg.sender, amount);
    }

    /// @notice 还款
    /// @dev 用户可以通过此函数还款
    /// @param amount 还款金额
    function repay(uint amount) external {
        _accrueInterest(msg.sender);

        Account storage account = accounts[msg.sender];
        require(account.debt >= amount, "repay too much");

        require(stablecoin.transferFrom(msg.sender, address(this), amount), "transfer failed");
        account.debt -= amount;

        emit Repay(msg.sender, amount);
    }

    /// @notice 清算
    /// @dev 清算人可以通过此函数清算用户的抵押
    /// @param user 被清算的用户地址
    function liquidate(address user) external {
        _accrueInterest(user);

        Account storage account = accounts[user];
        require(account.debt > 0, "no debt");

        uint collateralValue = account.collateralETH;
        uint threshold = (collateralValue * LIQUIDATION_THRESHOLD) / 100;
        require(account.debt > threshold, "healthy position");

        uint repayAmount = account.debt;
        require(stablecoin.transferFrom(msg.sender, address(this), repayAmount), "transfer failed");

        account.debt = 0;
        uint seizedETH = account.collateralETH;
        account.collateralETH = 0;

        payable(msg.sender).transfer(seizedETH);

        emit Liquidate(msg.sender, user, repayAmount);
    }

    /// @notice 查询抵押率
    /// @dev 返回用户的抵押率
    /// @param user 用户地址
    /// @return 抵押率
    function getCollateralRatio(address user) external view returns (uint) {
        Account memory account = accounts[user];
        if (account.debt == 0) return type(uint).max;
        return (account.collateralETH * 100) / account.debt;
    }
}
```

---

## 4、测试文件 `test/SimpleLending.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleLending.sol";

/// @title MockStablecoin - 模拟稳定币合约
/// @notice 用于测试 SimpleLending 合约的模拟稳定币
contract MockStablecoin {
    string public name = "Mock DAI";
    string public symbol = "mDAI";
    uint8 public decimals = 18;

    /// @notice 账户余额映射
    mapping(address => uint) public balanceOf;

    /// @notice 授权额度映射
    mapping(address => mapping(address => uint)) public allowance;

    /// @notice 转账事件
    event Transfer(address indexed from, address indexed to, uint value);

    /// @notice 授权事件
    event Approval(address indexed owner, address indexed spender, uint value);

    /// @notice 铸造代币
    /// @param to 接收地址
    /// @param amount 铸造金额
    function mint(address to, uint amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice 授权额度
    /// @param spender 授权地址
    /// @param amount 授权金额
    /// @return 是否成功
    function approve(address spender, uint amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice 转账
    /// @param to 接收地址
    /// @param amount 转账金额
    /// @return 是否成功
    function transfer(address to, uint amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance too low");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice 从授权地址转账
    /// @param from 转出地址
    /// @param to 接收地址
    /// @param amount 转账金额
    /// @return 是否成功
    function transferFrom(address from, address to, uint amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance too low");
        require(allowance[from][msg.sender] >= amount, "allowance too low");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @title SimpleLendingTest - SimpleLending 合约的测试
/// @notice 测试 SimpleLending 合约的功能
contract SimpleLendingTest is Test {
    /// @notice 模拟稳定币合约
    MockStablecoin dai;

    /// @notice SimpleLending 合约
    SimpleLending lending;

    /// @notice 测试用户 Alice
    address alice = address(0x123);

    /// @notice 测试用户 Bob
    address bob   = address(0x234);

    /// @notice 初始化测试环境
    function setUp() public {
        dai = new MockStablecoin();
        lending = new SimpleLending(address(dai));

        // 给 Bob 一些 mDAI 用于清算 + 授权
        dai.mint(bob, 1000 ether);
        vm.prank(bob);
        dai.approve(address(lending), type(uint).max);

        // 给 Alice/Bob 充值 ETH（Alice 要抵押 1 ETH）
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    /// @notice 测试抵押和借款功能
    function testDepositAndBorrow() public {
        vm.startPrank(alice);
        lending.depositCollateral{value: 1 ether}();
        lending.borrow(0.5 ether);
        uint ratio = lending.getCollateralRatio(alice);
        assertGt(ratio, 75);
        vm.stopPrank();
    }

    /// @notice 测试还款功能
    function testRepayDebt() public {
        vm.startPrank(alice);
        lending.depositCollateral{value: 1 ether}();
        lending.borrow(0.5 ether);
        dai.approve(address(lending), type(uint).max);
        lending.repay(0.5 ether);
        vm.stopPrank();

        ( , uint debtAfter, ) = lending.accounts(alice);
        assertEq(debtAfter, 0);
    }

    /// @notice 测试清算功能
    function testLiquidation() public {
        // 抵押 1 ETH，借到上限 0.75 ETH
        vm.startPrank(alice);
        lending.depositCollateral{value: 1 ether}();
        lending.borrow(0.75 ether);
        vm.stopPrank();

        // 利息 5%/年，2 年后：0.75 * (1 + 0.05*2) = 0.825 > 清算阈值 0.8
        vm.warp(block.timestamp + 2 * 365 days);

        // Bob 清算
        vm.prank(bob);
        lending.liquidate(alice);

        (uint collAfter, uint debtAfter, ) = lending.accounts(alice);
        assertEq(debtAfter, 0);
        assertEq(collAfter, 0);
    }

    /// @notice 测试利息计算功能
    function testInterestAccrual() public {
        vm.startPrank(alice);
        lending.depositCollateral{value: 1 ether}();
        lending.borrow(0.5 ether);
        vm.warp(block.timestamp + 365 days);
        // 触发一次计息（0 转账也会进 _accrueInterest）
        lending.repay(0);
        vm.stopPrank();

        (, uint debtWithInterest, ) = lending.accounts(alice);
        assertGt(debtWithInterest, 0.5 ether);
    }
}
```

执行测试：

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/SimpleLending.t.sol -vvv 

[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 564.08ms
Compiler run successful!

Ran 4 tests for test/SimpleLending.t.sol:SimpleLendingTest
[PASS] testDepositAndBorrow() (gas: 123240)
[PASS] testInterestAccrual() (gas: 141413)
[PASS] testLiquidation() (gas: 139901)
[PASS] testRepayDebt() (gas: 143832)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 1.58ms (1.42ms CPU time)

Ran 1 test suite in 156.32ms (1.58ms CPU time): 4 tests passed, 0 failed, 0 skipped (4 total tests)
```

---

## 5、本课总结

* 学习了 **借贷协议的最小核心机制**（存款、借款、还款、清算）
* 实现了 **利息累积模型**（债务随时间增长）
* 测试覆盖了 **计息 → 借款 → 还款 → 清算** 全流程
* 通过 **资金流转图** 直观理解了借贷逻辑

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