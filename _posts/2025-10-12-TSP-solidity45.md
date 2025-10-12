---
layout: post
title: 《纸上谈兵·solidity》第 45 课：DeFi 实战(9) -- 利息累积与结算机制（可复利）
tags: solidity
mermaid: false
math: false
--- 

## 1、学习目标

* 清楚区分 **利息计算的几种方法**（简单利息 / 离散复利 / 指数连续复利）及各自的利弊  
* 理解并掌握 **index-based（借款/存款指数）** 的利息会计方法（可扩展到多资产）  
* 从零实现：**借款指数（borrowIndex）/ 存款指数（supplyIndex）**、按秒累积利息、按比例分配协议储备（reserve）  
* 使用 Foundry 测试：模拟时间流逝、验证借款人负债、存款人收益、协议储备累积与还款行为

---

## 2、概念介绍

在现实的借贷协议里，利息并不是“每个用户单独按时间往账上写利息”，而是用**公用索引（index）**高效记录利息增长，然后按需用索引换算账户余额。这样做能极大节省 gas 并避免对每个用户频繁写状态。

### 2.1 三种常见的利息模型

1. **简单利息（Simple interest）**  
   - 公式：`interest = principal * rate * time`。  
   - 优点：直观、易计算；缺点：没有复利（对长期利息不准确）。
2. **离散复利（Discrete compounding）**  
   - 在不同时点（如每秒、每天）把利息加入本金，再计算下一周期利息。  
   - 常见实现：以每秒为步长累加（近似连续复利）。利率按秒分割：`r_per_sec = annual_r / seconds_per_year`，每秒做 `principal *= (1 + r_per_sec)`。  
   - 优点：实现简单、近似连续；缺点：每秒更新对链上实现会消耗 gas（因此通常用 index 记录）。
3. **连续复利（Continuous compounding）**  
   - 通过 `exp(r * t)` 精确表示连续复利。链上实现需浮点/exp 库，复杂且 gas 贵。  
   - 在实际协议里通常用**离散复利但步长（timeDelta）可变**的方式近似连续复利。

### 2.2 Index-based 会计（核心思想）

- **borrowIndex (BI)**：记录“借款单位余额随时间增长的倍数”（开始为 1e18）。借款人的实际债务 = `scaledBorrow[user] * BI / 1e18`。当用户借入 `amount` 时，记录 `scaledBorrowIncrease = amount * 1e18 / BI`。之后不需要每秒更新用户状态。
- **supplyIndex (SI)**：记录“存款单位随时间增长的倍数”。aToken（或 share）记录为 `shares`，用户的实际底层资产 = `shares * SI / 1e18`。存款时 `shares = amount * 1e18 / SI`。

优点：只要维护全局索引（两个数）和用户的 scaled 值，就能做到对所有用户的利息进行**懒惰计算（on-demand）**，极为高效。

### 2.3 利息分配与协议储备（Reserve）

- 借款人生成的利息应被分成：**一部分留给出借人（Depositors）**，**一部分作为协议收入（reserve）**（由 `reserveFactor` 决定）。  
- 会计流程（常见离散时间步）：  
  1. 计算 `interestAccrued = totalBorrows * borrowRatePerSecond * deltaTime`  
  2. `reservePortion = interestAccrued * reserveFactor`  
  3. `toDepositors = interestAccrued - reservePortion`  
  4. 更新 `totalBorrows += interestAccrued`；`totalReserves += reservePortion`；`totalDeposits += toDepositors`（或通过 supplyIndex 更新使得 aToken 持有者能看到收益）。

### 2.4 利率的粒度与时间分辨率

- 在链上我们通常使用**按秒利率（ratePerSecond）**：`ratePerSecond = annualRate / SECONDS_PER_YEAR`，并以整数精度（1e18）表示小数。  
- `deltaTime` 使用 `block.timestamp` 差值。测试中用 `vm.warp()` 模拟时间推进。

---

## 3、实现 —— index-based 利息累积（单市场）

下面实现一个教学、可运行的合约：**LendingPoolInterestAccrual.sol**。  
要点：  
- 使用 `borrowIndex` / `supplyIndex`（1e18 精度），按秒更新；  
- 用户借款按 `scaledBorrow` 存储；存款按 `aToken` shares 记录（`shares = amount * 1e18 / supplyIndex`）；  
- 每次 deposit / withdraw / borrow / repay 都会触发 `_accrueInterest()`，但你也可以由 keeper 定期调用以减少每次 gas（见作业）。  

> 说明：演示合约只支持单资产市场，但索引逻辑可按市场切分扩展到多市场。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AToken
 * @notice 简单的存款凭证代币
 * @dev Mint/burn 操作只能由借贷池调用
 */
contract AToken is ERC20 {
    address public pool;

    /**
     * @notice 构造函数，初始化 aToken
     * @param name_ aToken 名称
     * @param symbol_ aToken 符号
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        pool = msg.sender;
    }

    /**
     * @notice 修饰符，限制只有借贷池可以调用
     */
    modifier onlyPool() {
        require(msg.sender == pool, "not pool");
        _;
    }

    /**
     * @notice 向用户铸造 aToken
     * @dev 只能由借贷池调用
     * @param to 接收代币的地址
     * @param amount 铸造的代币数量
     */
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /**
     * @notice 从用户处销毁 aToken
     * @dev 只能由借贷池调用
     * @param from 销毁代币的地址
     * @param amount 销毁的代币数量
     */
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}

/**
 * @title LendingPoolInterestAccrual
 * @notice 带利息累积机制的借贷池实现
 * @dev 实现类似 Compound 的利息累积机制和准备金机制
 */
contract LendingPoolInterestAccrual {
    using SafeERC20 for IERC20;

    /// @notice 底层资产代币
    IERC20 public immutable asset;
    
    /// @notice 代表存款的 aToken
    AToken public immutable aToken;

    // 会计变量
    /// @notice 总存入的底层代币（包括分配给存款人的利息）
    uint256 public totalDeposits;
    
    /// @notice 总未偿还借款
    uint256 public totalBorrows;
    
    /// @notice 累计的协议准备金（以底层代币计）
    uint256 public totalReserves;

    /// @notice 用户的缩放借款：scaledBorrow = actualBorrow * 1e18 / borrowIndex
    mapping(address => uint256) public scaledBorrow;

    // 利息指数（1e18 精度）
    /// @notice 当前借款指数，用于利息计算
    uint256 public borrowIndex = 1e18;
    
    /// @notice 当前存款指数，用于利息计算
    uint256 public supplyIndex = 1e18;
    
    /// @notice 最后一次利息累积的时间戳
    uint256 public lastAccrualTimestamp;

    // 利息参数
    /// @notice 年化借款利率（1e18 精度，例如 0.10e18 = 10%）
    uint256 public annualBorrowRate;
    
    /// @notice 每年秒数，用于利息计算
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    
    /// @notice 准备金因子，基点制（1000 = 10%）
    uint256 public reserveFactorBps = 1000;
    
    /// @notice 基点分母（10000 = 100%）
    uint256 public constant BPS = 10000;

    // 事件
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 shares, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Accrue(uint256 interestAccrued, uint256 reservesAdded, uint256 newBorrowIndex, uint256 newSupplyIndex);

    /**
     * @notice 构造函数，初始化借贷池
     * @param _asset 底层资产代币
     * @param name_ aToken 名称
     * @param symbol_ aToken 符号
     * @param _annualBorrowRate 年化借款利率（1e18 精度）
     * @param _reserveFactorBps 准备金因子，基点制
     */
    constructor(
        IERC20 _asset,
        string memory name_,
        string memory symbol_,
        uint256 _annualBorrowRate,
        uint256 _reserveFactorBps
    ) {
        asset = _asset;
        aToken = new AToken(name_, symbol_);
        annualBorrowRate = _annualBorrowRate;
        reserveFactorBps = _reserveFactorBps;
        lastAccrualTimestamp = block.timestamp;
    }

    // --------------------------------------
    // 视图函数
    // --------------------------------------

    /**
     * @notice 获取当前借款余额（包含应计利息）
     * @param user 借款人地址
     * @return 包含利息的当前借款余额
     */
    function borrowBalanceCurrent(address user) public view returns (uint256) {
        return (scaledBorrow[user] * borrowIndex) / 1e18;
    }

    /**
     * @notice 获取当前存款余额（包含应计利息）
     * @param user 存款人地址
     * @return 包含利息的当前存款余额
     */
    function supplyBalanceCurrent(address user) public view returns (uint256) {
        uint256 shares = aToken.balanceOf(user);
        return (shares * supplyIndex) / 1e18;
    }

    /**
     * @notice 计算资金池当前的资金利用率
     * @return 资金利用率（1e18 精度）
     */
    function utilizationRate() public view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrows * 1e18) / totalDeposits;
    }

    /**
     * @notice 获取资金池当前可用流动性
     * @return 可用于借款的可用流动性
     */
    function availableLiquidity() public view returns (uint256) {
        return totalDeposits - totalBorrows;
    }

    // --------------------------------------
    // 核心利息累积逻辑
    // --------------------------------------

    /**
     * @notice 内部函数，累积利息并更新指数
     * @dev 在任何状态改变操作前都应调用此函数
     */
    function _accrueInterest() internal {
        uint256 nowTs = block.timestamp;
        uint256 delta = nowTs - lastAccrualTimestamp;
        if (delta == 0) return;
        lastAccrualTimestamp = nowTs;

        if (totalBorrows == 0 && totalDeposits == 0) {
            // 没有活动，只更新时间戳
            return;
        }

        // 计算每秒借款利率（1e18 精度）
        uint256 ratePerSecond = annualBorrowRate / SECONDS_PER_YEAR;

        // 计算新的借款指数：borrowIndex *= (1 + ratePerSecond * delta)
        uint256 interestFactor = (ratePerSecond * delta); // 1e18 精度
        uint256 newBorrowIndex = borrowIndex + (borrowIndex * interestFactor) / 1e18;

        // 计算在 delta 时间内产生的利息：totalBorrows * ratePerSecond * delta / 1e18
        uint256 interestAccrued = (totalBorrows * ratePerSecond * delta) / 1e18;

        // 准备金部分
        uint256 reservePortion = (interestAccrued * reserveFactorBps) / BPS;

        // 计算每秒存款利率
        uint256 utilization = 0;
        if (totalDeposits > 0) {
            utilization = (totalBorrows * 1e18) / totalDeposits; // 1e18 精度
        }
        // supplyRatePerSecond = ratePerSecond * utilization * (1 - reserveFactor)
        uint256 tmp = (ratePerSecond * utilization) / 1e18; // 1e18 * 1e18 / 1e18 => 1e18 精度
        uint256 supplyRatePerSecond = (tmp * (BPS - reserveFactorBps)) / BPS; // 1e18 精度

        uint256 newSupplyIndex = supplyIndex + (supplyIndex * supplyRatePerSecond * delta) / 1e18;

        // 应用会计变更
        // 总借款增加利息部分
        totalBorrows += interestAccrued;

        // 准备金增加
        totalReserves += reservePortion;

        // 存款人获得利息减去准备金部分，增加到池子流动性中
        uint256 toDepositors = interestAccrued - reservePortion;
        if (toDepositors > 0) {
            totalDeposits += toDepositors;
        }

        borrowIndex = newBorrowIndex;
        supplyIndex = newSupplyIndex;

        emit Accrue(interestAccrued, reservePortion, borrowIndex, supplyIndex);
    }

    // --------------------------------------
    // 用户操作（每个操作都会先更新指数）
    // --------------------------------------

    /**
     * @notice 存款函数
     * @param amount 存款数量
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "invalid amount");
        _accrueInterest();

        // 转入底层资产
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // 按当前 supplyIndex 比例铸造份额
        // shares = amount * 1e18 / supplyIndex
        uint256 shares = (amount * 1e18) / supplyIndex;
        aToken.mint(msg.sender, shares);

        totalDeposits += amount;

        emit Deposit(msg.sender, amount, shares);
    }

    /**
     * @notice 取款函数
     * @param shares 取款的份额数量
     */
    function withdraw(uint256 shares) external {
        require(shares > 0, "invalid shares");
        _accrueInterest();

        uint256 underlying = (shares * supplyIndex) / 1e18;
        require(underlying <= totalDeposits, "insufficient pool");

        aToken.burn(msg.sender, shares);
        totalDeposits -= underlying;

        asset.safeTransfer(msg.sender, underlying);

        emit Withdraw(msg.sender, shares, underlying);
    }

    /**
     * @notice 借款函数
     * @param amount 借款数量
     */
    function borrow(uint256 amount) external {
        require(amount > 0, "invalid amount");
        _accrueInterest();

        // 简单抵押检查：这个教学合约要求存款人=借款人
        // 在生产环境中必须评估跨资产抵押；这里我们只要求池子有足够流动性
        require(totalDeposits - totalBorrows >= amount, "insufficient liquidity");

        // 增加缩放借款：scaled += amount * 1e18 / borrowIndex
        uint256 scaledAdd = (amount * 1e18) / borrowIndex;
        scaledBorrow[msg.sender] += scaledAdd;
        totalBorrows += amount;

        asset.safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    /**
     * @notice 还款函数
     * @param amount 还款数量
     */
    function repay(uint256 amount) external {
        require(amount > 0, "invalid amount");
        _accrueInterest();

        uint256 debt = (scaledBorrow[msg.sender] * borrowIndex) / 1e18;
        require(debt > 0, "no debt");

        uint256 pay = amount;
        if (amount > debt) pay = debt;

        asset.safeTransferFrom(msg.sender, address(this), pay);

        // 更新缩放借款
        uint256 newDebt = debt - pay;
        if (newDebt == 0) {
            scaledBorrow[msg.sender] = 0;
        } else {
            scaledBorrow[msg.sender] = (newDebt * 1e18) / borrowIndex;
        }

        totalBorrows -= pay;

        // 还款增加池子流动性（我们认为还款直接增加 totalDeposits）
        totalDeposits += pay;

        emit Repay(msg.sender, pay);
    }

    // --------------------------------------
    // 管理函数
    // --------------------------------------

    /**
     * @notice 设置年化借款利率
     * @dev 在生产环境中使用时间锁/治理
     * @param _annualBorrowRate 新的年化借款利率
     */
    function setAnnualBorrowRate(uint256 _annualBorrowRate) external {
        annualBorrowRate = _annualBorrowRate;
    }

    /**
     * @notice 设置准备金因子
     * @dev 在生产环境中使用时间锁/治理
     * @param _bps 新的准备金因子（基点）
     */
    function setReserveFactorBps(uint256 _bps) external {
        require(_bps <= BPS, "invalid bps");
        reserveFactorBps = _bps;
    }
}
```

---

## 4、Foundry 测试

**测试目的**：

* 验证 index 计算逻辑（借款指数 / 存款指数）随着时间增长；
* 验证借款人负债随时间增加（近似按年化利率）；
* 验证存款人能获得扣除 `reserveFactor` 后的利息；
* 验证 `totalReserves` 正确累积。

**测试文件**：`LendingPoolInterestAccrual.t.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPoolInterestAccrual.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuff bal");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[from] >= amount, "insuff");
        require(allowance[from][msg.sender] >= amount, "no allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract InterestAccrualTest is Test {
    MockERC20 token;
    LendingPoolInterestAccrual pool;

    address alice = address(0x1); // 存款人
    address bob = address(0x2); // 借款人
    address admin = address(0x3); // 管理员

    function setUp() public {
        token = new MockERC20("MockUSD", "mUSD");

        // 年化借款利率 = 10% => 0.10 ether
        uint256 annualRate = 0.10 ether;
        // 准备金因子 10% (1000 bps)
        pool = new LendingPoolInterestAccrual(
            IERC20(address(token)),
            "aMockUSD",
            "aMUSD",
            annualRate,
            1000
        );

        // 分配资金
        token.mint(alice, 5000 ether);
        token.mint(bob, 3000 ether);
        token.mint(admin, 1000 ether);

        // 批准池子操作
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(admin);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // 基础功能测试
    function testBasicDepositAndWithdraw() public {
        // 测试存款
        vm.prank(alice);
        pool.deposit(1000 ether);

        assertEq(pool.totalDeposits(), 1000 ether);
        assertEq(token.balanceOf(alice), 4000 ether);
        assertEq(
            pool.aToken().balanceOf(alice),
            (1000 ether * 1e18) / pool.supplyIndex()
        );

        // 测试取款
        uint256 shares = pool.aToken().balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(shares);

        assertEq(pool.totalDeposits(), 0);
        assertApproxEqAbs(token.balanceOf(alice), 5000 ether, 1e16); // 允许微小误差
    }

    function testBasicBorrowAndRepay() public {
        // 先存款
        vm.prank(alice);
        pool.deposit(2000 ether);

        // 测试借款
        vm.prank(bob);
        pool.borrow(1000 ether);

        assertEq(pool.totalBorrows(), 1000 ether);
        assertEq(token.balanceOf(bob), 4000 ether); // 3000初始 + 1000借款

        // 测试还款
        vm.prank(bob);
        pool.repay(1000 ether);

        assertEq(pool.totalBorrows(), 0);
        assertEq(pool.borrowBalanceCurrent(bob), 0);
    }

    // 利息累积测试
    function testInterestAccrualOverTime() public {
        // Alice 存款 1000
        vm.prank(alice);
        pool.deposit(1000 ether);

        // Bob 借款 500
        vm.prank(bob);
        pool.borrow(500 ether);

        uint256 initialBorrowIndex = pool.borrowIndex();
        uint256 initialSupplyIndex = pool.supplyIndex();

        // 快进一年
        vm.warp(block.timestamp + 365 days);

        // 触发利息累积
        vm.prank(alice);
        pool.deposit(1 ether);

        uint256 newBorrowIndex = pool.borrowIndex();
        uint256 newSupplyIndex = pool.supplyIndex();

        // 验证指数增长
        assertGt(newBorrowIndex, initialBorrowIndex);
        assertGt(newSupplyIndex, initialSupplyIndex);

        // Bob 的债务应该增加约 10%
        uint256 bobDebt = pool.borrowBalanceCurrent(bob);
        assertApproxEqAbs(bobDebt, 550 ether, 1e17); // 约550，允许1.7%误差

        // 验证准备金累积
        assertGt(pool.totalReserves(), 0);
    }

    // 边界测试
    function testZeroAmountOperations() public {
        // 测试零金额存款
        vm.prank(alice);
        vm.expectRevert("invalid amount");
        pool.deposit(0);

        // 测试零金额取款
        vm.prank(alice);
        vm.expectRevert("invalid shares");
        pool.withdraw(0);

        // 测试零金额借款
        vm.prank(bob);
        vm.expectRevert("invalid amount");
        pool.borrow(0);

        // 测试零金额还款
        vm.prank(bob);
        vm.expectRevert("invalid amount");
        pool.repay(0);
    }

    function testInsufficientLiquidity() public {
        // Alice 存款 1000
        vm.prank(alice);
        pool.deposit(1000 ether);

        // Bob 尝试借超过可用流动性的金额
        vm.prank(bob);
        vm.expectRevert("insufficient liquidity");
        pool.borrow(1001 ether);
    }

    function testInsufficientDeposits() public {
        // Alice 存款 1000
        vm.prank(alice);
        pool.deposit(1000 ether);

        // Alice 尝试取超过她存款的金额
        uint256 excessShares = (1001 ether * 1e18) / pool.supplyIndex();
        vm.prank(alice);
        vm.expectRevert("insufficient pool");
        pool.withdraw(excessShares);
    }

    function testNoDebtRepay() public {
        // Bob 尝试还款但没有债务
        vm.prank(bob);
        vm.expectRevert("no debt");
        pool.repay(100 ether);
    }

    // 多用户场景测试
    function testMultipleUsers() public {
        // 多个用户存款
        vm.prank(alice);
        pool.deposit(1000 ether);

        vm.prank(admin);
        pool.deposit(500 ether);

        assertEq(pool.totalDeposits(), 1500 ether);

        // 多个用户借款
        vm.prank(bob);
        pool.borrow(800 ether);

        assertEq(pool.totalBorrows(), 800 ether);
        assertEq(pool.availableLiquidity(), 700 ether);

        // 验证利用率
        uint256 utilization = pool.utilizationRate();
        uint256 expected = (uint256(800 ether) * 1e18) / uint256(1500 ether);
        assertApproxEqAbs(utilization, expected, 1e16);
    }

    // 超额还款测试
    function testOverRepayment() public {
        // 设置
        vm.prank(alice);
        pool.deposit(1000 ether);

        vm.prank(bob);
        pool.borrow(500 ether);

        // Bob 尝试超额还款
        vm.prank(bob);
        pool.repay(600 ether); // 只应收取实际债务金额

        assertEq(pool.totalBorrows(), 0);
        assertEq(pool.borrowBalanceCurrent(bob), 0);

        // Bob 应该只被扣除实际债务金额（3000 初始 + 500 借款 - 500 还款 = 3000）
        assertApproxEqAbs(token.balanceOf(bob), 3000 ether, 1e16);
    }

    // 管理员功能测试
    function testAdminFunctions() public {
        // 测试设置借款利率
        uint256 newRate = 0.15 ether; // 15%
        pool.setAnnualBorrowRate(newRate);
        assertEq(pool.annualBorrowRate(), newRate);

        // 测试设置准备金因子
        uint256 newReserveFactor = 2000; // 20%
        pool.setReserveFactorBps(newReserveFactor);
        assertEq(pool.reserveFactorBps(), newReserveFactor);

        // 测试无效的准备金因子
        vm.expectRevert("invalid bps");
        pool.setReserveFactorBps(10001); // 超过100%
    }

    // 极端情况测试
    function testHighUtilization() public {
        // Alice 存款
        vm.prank(alice);
        pool.deposit(1000 ether);

        // Bob 借几乎全部资金
        vm.prank(bob);
        pool.borrow(999 ether);

        // 验证高利用率
        uint256 utilization = pool.utilizationRate();
        assertGt(utilization, 0.99 ether); // 利用率 > 99%

        // 快进时间累积利息
        vm.warp(block.timestamp + 30 days);

        // 触发利息累积
        vm.prank(alice);
        pool.deposit(1 ether);

        // 验证利息正确累积
        assertGt(pool.totalBorrows(), 999 ether);
        assertGt(pool.totalDeposits(), 1000 ether);
    }

    // 视图函数测试
    function testViewFunctions() public {
        // 初始状态检查
        assertEq(pool.utilizationRate(), 0);
        assertEq(pool.availableLiquidity(), 0);

        // 存款后检查
        vm.prank(alice);
        pool.deposit(1000 ether);

        assertEq(pool.utilizationRate(), 0);
        assertEq(pool.availableLiquidity(), 1000 ether);
        assertEq(pool.supplyBalanceCurrent(alice), 1000 ether);

        // 借款后检查
        vm.prank(bob);
        pool.borrow(500 ether);

        uint256 utilization = pool.utilizationRate();
        assertApproxEqAbs(utilization, 0.5 ether, 1e16); // 约50%
        assertEq(pool.availableLiquidity(), 500 ether);
        assertEq(pool.borrowBalanceCurrent(bob), 500 ether);
    }
}
```

**重要测试说明**：

* 测试使用 `vm.warp()` 快速推进时间并通过一次交易（deposit/repay）触发 `_accrueInterest()`；实际生产中可由 keeper 定期调用全局 `accrue()` 或在每次用户交互时调用。
* `assertApproxEqAbs` 用于允许少量整数舍入误差（微小的 rounding）。

执行测试：  

```bash
➜  defi git:(main) ✗ forge test --match-path test/LendingPoolInterestAccrual.t.sol  -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 513.88ms
Compiler run successful!

Ran 12 tests for test/LendingPoolInterestAccrual.t.sol:InterestAccrualTest
[PASS] testAdminFunctions() (gas: 23968)
[PASS] testBasicBorrowAndRepay() (gas: 178727)
[PASS] testBasicDepositAndWithdraw() (gas: 126616)
[PASS] testHighUtilization() (gas: 260831)
[PASS] testInsufficientDeposits() (gas: 137902)
[PASS] testInsufficientLiquidity() (gas: 140535)
[PASS] testInterestAccrualOverTime() (gas: 265547)
[PASS] testMultipleUsers() (gas: 251870)
[PASS] testNoDebtRepay() (gas: 19149)
[PASS] testOverRepayment() (gas: 178234)
[PASS] testViewFunctions() (gas: 212301)
[PASS] testZeroAmountOperations() (gas: 22277)
Suite result: ok. 12 passed; 0 failed; 0 skipped; finished in 11.49ms (9.09ms CPU time)

Ran 1 test suite in 154.45ms (11.49ms CPU time): 12 tests passed, 0 failed, 0 skipped (12 total tests)
```

---

## 5、本课总结

* Index-based 会计是链上可扩展、高效的利息累积实现方式（借款人按 `borrowIndex`，存款人按 `supplyIndex`）。
* 在实现时必须同时维护：**借款索引（borrowIndex）**、**存款索引（supplyIndex）**、**scaled 用户余额**、**协议储备（reserve）**。
* 利率与索引的数值精度、时间步长、以及每次 `accrue` 的触发策略都直接影响协议经济行为与 gas 成本。
* 测试要以时间跳变为主线、同时校验借款人、存款人和协议金库三方的数值一致性。

---

## 6、作业

1. **把池子与外部 `InterestRateModel` 对接**：让 `annualBorrowRate` 不再固定，而是从 `InterestRateModel.borrowRate(totalDeposits, totalBorrows)` 获取（注意精度换算）。写测试验证动态利率生效。
2. **优化 `accrue` 的调用策略**：实现 `accrueIfNeeded(address user)`，仅在必要时（如 borrow/repay）触发或由 keeper 定期触发并计费。比较每次触发 vs keeper 模式的 gas 差异。
3. **改成多市场实现**：把索引/会计逻辑扩展到每个资产市场（`mapping(address => Market)`），并保证 `getTotalBorrowValue` 与 `getTotalSupplyValue` 的一致性。
4. **高频利率变动压力测试**：编写脚本模拟利率在短时间内剧烈上下波动，检查索引更新是否稳定（防止错配/重入/算术异常）。


