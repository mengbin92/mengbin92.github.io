---
layout: post
title: 《纸上谈兵·solidity》第 42 课：DeFi 实战(6) -- 跨资产借贷与多市场支持
tags: solidity
mermaid: false
math: false
---

## 1. 学习目标

* 理解为什么借贷协议必须支持**多种资产**而不是单一代币。
* 掌握**市场（Market）**的概念：每个资产拥有独立的借贷池、利率模型、抵押参数。
* 学习 **跨资产借贷** 的关键逻辑：抵押物与借款资产之间的价值评估。
* 实现一个**多市场借贷平台原型**，允许用户用 A 代币抵押，借出 B 代币。

---

## 2. 背景与概念

### 2.1 为什么需要多资产支持？

单资产借贷（例如只能抵押 ETH 借出 ETH）意义不大。现实需求是：

* 用户抵押 **稳定资产（如 USDC、stETH）** → 借出 **高风险资产（如 WETH、WBTC）** 做投资。
* 用户抵押 **波动性资产（如 ETH）** → 借出 **稳定币** 进行流动性操作或现实消费。
* 借贷平台的 TVL（总锁仓量）越多，吸引力越大，而 TVL 的来源就是多样化资产的引入。

### 2.2 市场（Market）的抽象

在 Compound/Aave 里，每个资产都有一个独立的市场：

* 独立的资金池（Cash、Borrow、Reserves）。
* 独立的利率曲线（基于 Utilization 计算）。
* 独立的参数（抵押因子、清算阈值、储备金比例）。

用户视角：

* 我可以存 USDC → 得到利息（变成 aUSDC）。
* 我可以存 ETH → 抵押借出 USDC。
* 每个市场单独计息，但用户的整体借贷头寸由**价格预言机**整合评估。

### 2.3 跨资产借贷

跨资产借贷的本质是：

1. 用户抵押资产 `C`（Collateral）。
2. 用户想借出资产 `B`（Borrow）。
3. 协议需要比较 **抵押物价值** 与 **借款价值**。

公式：

```text
Collateral Value × Collateral Factor ≥ Borrow Value
```

其中：

* `Collateral Value` 通过 **预言机价格 × 抵押数量** 计算。
* `Collateral Factor` 是风险折扣（如 ETH = 75%，USDC = 90%）。
* `Borrow Value` 同样由预言机计算。

---

## 3. 合约设计思路

我们将扩展之前的 `LendingPool`，加入 **Market 管理**：

* `struct Market`

  * `IERC20 token` → 市场的资产。
  * `uint256 collateralFactor` → 抵押因子。
  * `uint256 totalDeposits`
  * `uint256 totalBorrows`
* `mapping(address => mapping(address => uint256)) userDeposits`
* `mapping(address => mapping(address => uint256)) userBorrows`

这里第一层 `address` 表示市场资产，第二层表示用户。

---

## 4. 核心合约示例

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Price Oracle Interface
 * @notice Provides price data for tokens
 */
interface IPriceOracle {
    /**
     * @notice Get the price of a token
     * @param token The token address to get price for
     * @return The price of the token, scaled by 1e18
     */
    function getPrice(address token) external view returns (uint256);
}

/**
 * @title MultiMarketLending
 * @notice A multi-market lending protocol supporting multiple collateral assets
 * @dev This contract allows users to deposit collateral and borrow against it across multiple markets
 */
contract MultiMarketLending is ReentrancyGuard {
    /**
     * @notice Market configuration structure
     * @dev Collateral factor is scaled by FACTOR_BASE (10000 = 100%)
     */
    struct Market {
        IERC20 token;           // The ERC20 token for this market
        uint256 collateralFactor; // Collateral factor scaled by FACTOR_BASE
        uint256 totalDeposits;  // Total amount deposited in this market
        uint256 totalBorrows;   // Total amount borrowed from this market
        bool isListed;          // Whether this market is active
    }

    /// @notice Mapping from token address to market configuration
    mapping(address => Market) public markets;
    
    /// @notice Mapping from (token, user) to deposit amount
    mapping(address => mapping(address => uint256)) public userDeposits;
    
    /// @notice Mapping from (token, user) to borrow amount
    mapping(address => mapping(address => uint256)) public userBorrows;

    /// @notice Mapping from user to list of tokens they have deposited as collateral
    mapping(address => address[]) public userCollateralTokens;
    
    /// @notice Mapping from user to list of tokens they have borrowed
    mapping(address => address[]) public userBorrowTokens;

    /// @notice The price oracle contract used for price feeds
    IPriceOracle public oracle;
    
    /// @notice Base value for collateral factor calculations (10000 = 100%)
    uint256 public constant FACTOR_BASE = 10000;

    /**
     * @notice Contract constructor
     * @param _oracle The address of the price oracle contract
     */
    constructor(address _oracle) {
        oracle = IPriceOracle(_oracle);
    }

    /**
     * @notice Add a new market to the protocol
     * @dev Only callable by anyone in this implementation (consider adding access control)
     * @param token The ERC20 token address for the new market
     * @param collateralFactor The collateral factor for this market (scaled by FACTOR_BASE)
     */
    function addMarket(address token, uint256 collateralFactor) external {
        require(!markets[token].isListed, "already exists");
        markets[token] = Market({
            token: IERC20(token),
            collateralFactor: collateralFactor,
            totalDeposits: 0,
            totalBorrows: 0,
            isListed: true
        });
    }

    /**
     * @notice Deposit tokens as collateral
     * @dev Uses nonReentrant modifier to prevent reentrancy attacks
     * @param token The token address to deposit
     * @param amount The amount of tokens to deposit
     */
    function deposit(address token, uint256 amount) external nonReentrant {
        Market storage m = markets[token];
        require(m.isListed, "market not exist");

        // Transfer tokens from user to contract
        m.token.transferFrom(msg.sender, address(this), amount);

        // If this is user's first deposit of this token, add to collateral list
        if (userDeposits[token][msg.sender] == 0) {
            userCollateralTokens[msg.sender].push(token);
        }

        // Update user deposit and market totals
        userDeposits[token][msg.sender] += amount;
        m.totalDeposits += amount;
    }

    /**
     * @notice Borrow tokens against collateral
     * @dev Uses nonReentrant modifier to prevent reentrancy attacks
     * @param token The token address to borrow
     * @param amount The amount of tokens to borrow
     */
    function borrow(address token, uint256 amount) external nonReentrant {
        Market storage m = markets[token];
        require(m.isListed, "market not exist");

        // Check if user has sufficient collateral to borrow
        require(
            _canBorrow(msg.sender, token, amount),
            "insufficient collateral"
        );

        // If this is user's first borrow of this token, add to borrow list
        if (userBorrows[token][msg.sender] == 0) {
            userBorrowTokens[msg.sender].push(token);
        }
        
        // Update market and user borrow amounts
        m.totalBorrows += amount;
        userBorrows[token][msg.sender] += amount;
        
        // Transfer borrowed tokens to user
        m.token.transfer(msg.sender, amount);
    }

    /**
     * @notice Internal function to check if a user can borrow specified amount
     * @dev Calculates total collateral value and compares with existing + new borrow value
     * @param user The address of the user
     * @param borrowToken The token the user wants to borrow
     * @param amount The amount the user wants to borrow
     * @return True if user can borrow, false otherwise
     */
    function _canBorrow(
        address user,
        address borrowToken,
        uint256 amount
    ) internal view returns (bool) {
        // Calculate the value of the requested borrow
        uint256 borrowValue = (oracle.getPrice(borrowToken) * amount) / 1e18;

        uint256 totalCollateralValue = 0;

        // Calculate total collateral value from all deposited tokens
        address[] memory tokens = userCollateralTokens[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 depositAmount = userDeposits[token][user];
            if (depositAmount == 0) continue;

            uint256 price = oracle.getPrice(token);
            // Apply collateral factor to get borrowable value
            uint256 value = (((depositAmount * price) / 1e18) *
                markets[token].collateralFactor) / FACTOR_BASE;
            totalCollateralValue += value;
        }

        // Calculate current borrow value from all borrowed tokens
        uint256 currentBorrowValue = 0;
        address[] memory borrowTokens = userBorrowTokens[user];
        for (uint256 i = 0; i < borrowTokens.length; i++) {
            address token = borrowTokens[i];
            uint256 borrowAmt = userBorrows[token][user];
            if (borrowAmt == 0) continue;

            uint256 price = oracle.getPrice(token);
            currentBorrowValue += (borrowAmt * price) / 1e18;
        }

        // Check if collateral covers existing + new borrows
        return totalCollateralValue >= currentBorrowValue + borrowValue;
    }
}
```

---

## 5. 测试场景

**MultiMarketLending.t.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiMarketLending.sol";

/**
 * @title Mock ERC20 Token
 * @notice Mock implementation of ERC20 for testing purposes
 * @dev Simulates ERC20 token behavior without external dependencies
 */
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    /**
     * @notice Initialize mock token with name and symbol
     * @param _name Token name
     * @param _symbol Token symbol
     */
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /**
     * @notice Transfer tokens to a specified address
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Approve spender to transfer tokens on behalf of msg.sender
     * @param spender The address allowed to spend
     * @param amount The amount allowed to spend
     * @return success Whether the approval was successful
     */
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another using allowance
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "no allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Mint new tokens to specified address
     * @dev Only for testing - creates tokens out of thin air
     * @param to The address to receive minted tokens
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title Mock Price Oracle
 * @notice Mock implementation of price oracle for testing
 * @dev Allows setting arbitrary prices for testing different scenarios
 */
contract MockOracle is IPriceOracle {
    /// @notice Mapping from token address to price
    mapping(address => uint256) public prices;

    /**
     * @notice Set price for a token
     * @param token The token address
     * @param price The price to set (scaled by 1e18)
     */
    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    /**
     * @notice Get price for a token
     * @param token The token address
     * @return The current price of the token (scaled by 1e18)
     */
    function getPrice(address token) external view override returns (uint256) {
        return prices[token];
    }
}

/**
 * @title MultiMarketLending Test Suite
 * @notice Comprehensive test suite for MultiMarketLending contract
 * @dev Uses Foundry testing framework with cheat codes
 */
contract MultiMarketLendingTest is Test {
    /// @notice The lending contract being tested
    MultiMarketLending lending;
    
    /// @notice Mock ETH token for testing
    MockERC20 ethToken;
    
    /// @notice Mock USDC token for testing
    MockERC20 usdcToken;
    
    /// @notice Mock price oracle for testing
    MockOracle oracle;

    /// @notice Test user address 1
    address user1 = address(0x123);
    
    /// @notice Test user address 2
    address user2 = address(0x234);

    /**
     * @notice Set up test environment before each test
     * @dev Deploys contracts, sets up markets, and initializes test data
     */
    function setUp() public {
        oracle = new MockOracle();
        lending = new MultiMarketLending(address(oracle));

        ethToken = new MockERC20("Mock ETH", "mETH");
        usdcToken = new MockERC20("Mock USDC", "mUSDC");

        // Set prices: ETH = $2000, USDC = $1
        oracle.setPrice(address(ethToken), 2000 ether);
        oracle.setPrice(address(usdcToken), 1 ether);

        // Add markets with collateral factors
        lending.addMarket(address(ethToken), 7500); // ETH collateral factor = 75%
        lending.addMarket(address(usdcToken), 9000); // USDC collateral factor = 90%

        // Mint tokens to users and contract
        ethToken.mint(user1, 10 ether);
        usdcToken.mint(address(lending), 10_000 ether); // Provide liquidity to pool
    }

    /**
     * @notice Test basic deposit functionality
     * @dev Verifies that users can deposit tokens and balances are updated correctly
     */
    function test_Deposit() public {
        vm.startPrank(user1);
        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);
        vm.stopPrank();

        assertEq(lending.userDeposits(address(ethToken), user1), 1 ether);
    }

    /**
     * @notice Test borrowing within collateral limits
     * @dev Verifies users can borrow up to their collateral limit
     */
    function test_Borrow_WithinLimit() public {
        vm.startPrank(user1);

        // Deposit 1 ETH as collateral
        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);

        // Borrow up to limit: $2000 * 75% = $1500 USDC
        lending.borrow(address(usdcToken), 1500 ether);
        vm.stopPrank();

        assertEq(lending.userBorrows(address(usdcToken), user1), 1500 ether);
        assertEq(usdcToken.balanceOf(user1), 1500 ether);
    }

    /**
     * @notice Test borrowing beyond collateral limits reverts
     * @dev Verifies that borrowing beyond collateral limits fails as expected
     */
    function test_RevertWhen_Borrow_ExceedLimit() public {
        vm.startPrank(user1);

        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);

        // Attempt to borrow $2000 USDC (exceeds $1500 limit)
        vm.expectRevert();
        lending.borrow(address(usdcToken), 2000 ether);

        vm.stopPrank();
    }

    /**
     * @notice Test multiple users have independent accounts
     * @dev Verifies that user positions don't interfere with each other
     */
    function test_MultipleUsers_Independent() public {
        vm.startPrank(user1);
        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);
        lending.borrow(address(usdcToken), 1000 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        ethToken.mint(user2, 2 ether);
        ethToken.approve(address(lending), 2 ether);
        lending.deposit(address(ethToken), 2 ether);
        lending.borrow(address(usdcToken), 2000 ether);
        vm.stopPrank();

        assertEq(lending.userBorrows(address(usdcToken), user1), 1000 ether);
        assertEq(lending.userBorrows(address(usdcToken), user2), 2000 ether);
    }

    /**
     * @notice Test sequential borrowing with limit enforcement
     * @dev Verifies that second borrow attempt respects cumulative borrowing
     */
    function test_When_BorrowSecondTime_ExceedsLimit() public {
        vm.startPrank(user1);

        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);

        // First borrow: 1000 USDC
        lending.borrow(address(usdcToken), 1000 ether);

        // Second borrow: 600 USDC, total = 1600 > 1500 limit
        vm.expectRevert();
        lending.borrow(address(usdcToken), 600 ether);

        vm.stopPrank();
    }

    /**
     * @notice Test operations on non-existent markets revert
     * @dev Verifies proper error handling for invalid market operations
     */
    function test_RevertWhen_NonExistentMarket() public {
        MockERC20 fake = new MockERC20("Fake", "FAKE");

        vm.startPrank(user1);
        fake.mint(user1, 100 ether);
        fake.approve(address(lending), 100 ether);

        vm.expectRevert("market not exist");
        lending.deposit(address(fake), 100 ether);

        vm.stopPrank();
    }

    /**
     * @notice Test borrowing with multiple collateral types
     * @dev Verifies collateral value calculation across multiple asset types
     */
    function test_RevertWhen_MultiCollateralBorrow() public {
        vm.startPrank(user1);

        // Deposit 1 ETH ($2000, 75%) + 1000 USDC ($1000, 90%)
        ethToken.approve(address(lending), 1 ether);
        lending.deposit(address(ethToken), 1 ether);

        usdcToken.mint(user1, 1000 ether);
        usdcToken.approve(address(lending), 1000 ether);
        lending.deposit(address(usdcToken), 1000 ether);

        // Total collateral value = 2000*0.75 + 1000*0.9 = 1500 + 900 = $2400
        // Borrow 2000 USDC should succeed
        lending.borrow(address(usdcToken), 2000 ether);

        // Borrow additional 500 USDC should fail (2400 < 2500)
        vm.expectRevert();
        lending.borrow(address(usdcToken), 500 ether);

        vm.stopPrank();
    }
}
```

执行测试：  

```bash
➜  defi git:(master) ✗ forge test --match-path test/MultiMarketLending.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.29
[⠑] Solc 0.8.29 finished in 1.50s
Compiler run successful!

Ran 7 tests for test/MultiMarketLending.t.sol:MultiMarketLendingTest
[PASS] test_Borrow_WithinLimit() (gas: 305862)
[PASS] test_Deposit() (gas: 154597)
[PASS] test_MultipleUsers_Independent() (gas: 507254)
[PASS] test_RevertWhen_Borrow_ExceedLimit() (gas: 181121)
[PASS] test_RevertWhen_MultiCollateralBorrow() (gas: 418155)
[PASS] test_RevertWhen_NonExistentMarket() (gas: 933374)
[PASS] test_When_BorrowSecondTime_ExceedsLimit() (gas: 317027)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 1.74ms (2.83ms CPU time)

Ran 1 test suite in 429.38ms (1.74ms CPU time): 7 tests passed, 0 failed, 0 skipped (7 total tests)
```

---

## 6. 总结

本课重点：

* 借贷平台真正的价值在于 **多资产 + 跨市场**。
* 每个资产市场独立存在，但通过价格预言机和抵押因子实现统一的风险控制。
* 跨资产借贷的核心是 **抵押价值 ≥ 借款价值**。
* 为简化课程，我们先实现框架，后续课程可逐步扩展清算、利率模型、治理参数。

---

## 7. 作业

1. 补充一个 **多资产借贷（抵押 ETH 借 USDC + WBTC）** 的测试
2. 思考：
   * 为什么 USDC 的抵押因子（90%）高于 ETH（75%）？
   * 在真实协议中，哪些资产会有更低的抵押因子？

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