---
layout: post
title: 《纸上谈兵·solidity》第 41 课：DeFi 实战(5) -- 协议费与治理
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解协议费（Protocol Fees）的来源、类型与记账方式  
* 理解协议金库（Treasury）的角色与取款分配模式  
* 掌握去中心化治理（On-chain Governance / DAO）的基本模型、风险与缓解手段  
* 从零实现一个简化版的 **费用收集 → Treasury → 治理参数变更** 流程（含 timelock）  
* 使用 Foundry 编写测试，验证费用累积与治理变更（例如修改 `reserveFactor`）

---

## 2、概念详解（尽可能详细、贴近现实）

### 2.1 协议费（Protocol Fees）—— 来源与形式

协议费是 DeFi 协议获取收入、支持开发和治理的核心手段。常见来源有：

1. **利息分成（Reserve/Protocol Reserve）**  
   - 在借贷协议中，借款人支付利息（BorrowInterest）。从这笔利息中，协议常取出一部分（称为 `reserveFactor` 或 protocol fee）进入金库（Treasury）。  
   - 例：借款利率 10%，协议抽 10% → 协议实际得到 1%（10% * 10%），剩下 9% 给存款人。
2. **交易费 / 兑换费 / 池子手续费**  
   - 在 AMM 或跨换功能中，交易者支付手续费（swap fee），协议可以把一部分用于协议收入（例如 Curve 将手续费用于奖励或治理收益）。
3. **清算激励中的协议份额**  
   - 清算发生时，清算奖励的一小部分可能被协议金库抽取（协议收益 + 奖励清算员）。
4. **借贷/闪电贷手续费**  
   - 协议对闪电贷、借贷操作收手续费，直接进入金库或留作回购/质押等用途。
5. **罚金 / 违约费用 / 提案罚没**  
   - 特定操作（如提交恶意提案）可能导致保证金被罚没，进入金库。

---

### 2.2 协议金库（Treasury）—— 职能与管理方式

**核心职能**：

- 收集协议收入（reserve、手续费等）
- 支付协议开销（开发、审计、奖励、补贴）
- 作为治理决策的资金来源（资助提案通过后支付）
- 作为紧急缓冲 / 保险金（抵抗亏损）

**常见治理与资金流向**：

- **拨款（Grant）**：DAO 提案批准后，Treasury 向项目或承包方拨款。
- **回购 + 锁仓（Buyback & Burn / ve-model）**：用协议收入回购治理代币并销毁或锁定（提高 token 值、减少流动性）。
- **分红 / 股息**：把部分收益直接分配给治理 token 持有者（较罕见，受法律监管影响）。

**金库的安全设计要点**：

- 多签（multisig）或时锁（timelock）控制大额提现（最常见）  
- 透明会计（on-chain balance + events）  
- 最小权限原则（Treasury可执行的动作由治理决定）  
- 可以配置 emergency guardian（宕机/紧急开关）

---

### 2.3 收益会计（How to Accrue & Track Fees）

实现上要回答两个问题：**什么时候把收益算到金库？** 和 **如何记账？**

1. **即时抽取（On-Accrual）**  
   - 在利息结算或交易发生时，直接把协议份额转入金库或记录到 `reserves` 变量。优势：会计直观；劣势：每次写入增加 gas。
2. **定期结算（Periodic Accrual / Harvest）**  
   - 协议把应收的收益记录为“应收项”，由 keeper 或治理定期调用 `harvest()` 将收益转入 Treasury。优势：节省 gas（把多笔转账合并）；劣势：需要 keeper 和激励。
3. **指数 / 流水线模型（例如 Aave 的 Reserves）**  
   - 使用 index/accumulators，把协议应得的份额作为指数调整，实际转入由 `withdrawReserves()` 驱动。适合高并发、规模化的协议。

**记账字段示例**：

- `uint256 totalReserves`：累计到 Treasury 的总额（on-chain accounting）
- `mapping(address => uint256) accruedFees`：按资产/市场拆分（对 multi-asset 协议）
- `treasuryAddress`：实际托管资金地址（通常为多签或 timelock）

---

### 2.4 治理（Governance）—— 模型与要素

治理是把对协议参数、金库资金使用、升级、紧急措施等决策权下放给社区/代币持有者。主要构件：

1. **治理代币（Governance Token）**  
   - 常采用 ERC20，带票权（`ERC20Votes`）或锁仓模型（`veToken`）。  
   - 分配方案非常重要（团队锁期、社区空投、初始流动性、基金会持有）。
2. **投票模型**  
   - **One-token-one-vote**：直接按持仓计票（简单但易被 whale 或流动性池操纵）。  
   - **Delegated voting（代表制）**：代币持有者可以委托自己的票给代表（Compound 的 COMP）。  
   - **Vote-escrow (ve) 模型**：锁仓获得可投票权且锁期更长获得更高权重（Curve veCRV、Convex incentives）。能提高长期治理稳定性，但复杂。
3. **提案与执行流程（典型 on-chain 流程）**  
   - A. 提案（Propose）：达到提案门槛（threshold）才能提交。  
   - B. 排队（Queue / Timelock）：提案通过投票后进入 timelock 阶段（防止闪电升级），在 timelock 到期后可执行。  
   - C. 执行（Execute）：在 timelock 后调用合约函数修改参数或转账给 Treasury。  
   - D. 紧急暂停（Pause / Guardian）：某些关键功能可能有单独的紧急管理员（guardian）能快速中断协议以防灾。
4. **关键治理参数**  
   - 提案门槛（propose threshold）  
   - 最低投票率 / 通过率（quorum / quorumVotes / voteThreshold）  
   - Timelock 时长（安全延迟）  
   - 紧急管理员权限范围

---

### 2.5 风险、攻击向量与缓解

1. **治理攻击（Governance Takeover）**  
   - 攻击者通过购买大量治理代币或借贷/flash-loan 获取投票权，推动恶意提案（转移金库）。  
   - 缓解：timelock（>= 24-72h）、提案门槛、委托/锁仓要求、禁止紧急转账单次操作、交易多签。
2. **Voter Apathy（选民冷漠）**  
   - 少数人长期控制投票结果。缓解：激励投票（bribes/fees）、降低投票门槛但设置 quorum。
3. **Flash-vote / Flash-loan 投票**  
   - 攻击者用 flash loan 暂时持有代币并投票。缓解：使用锁仓投票或投票权需委托前一段时间的快照（snapshot delay），或禁止即时投票。
4. **Timelock 被滥用**  
   - Timelock 延迟太短或者被治理合约本身控制。缓解：增加多签/分权、设定 guardian、治理代币锁仓、独立 timelock合约。
5. **金库滥用 / 提款漏洞**  
   - 若 Treasury 接口不受限制，提案可直接把资金取走。缓解：把 Treasury 的“支付能力”受限于 governance proposal 的多步流程或多签确认。

---

### 2.6 常见实际设计模式（优缺点比较）

- **模式 A：直接入金 Treasury（简单）**  
  - 优点：实现简单，易于审计。  
  - 缺点：治理拿钱太容易，需严格治理流程。
- **模式 B：储备 + 回购（protocol buybacks）**：协议收入先存在 Treasury，然后定期回购治理代币并销毁/锁仓（增加代币稀缺性）。  
  - 优点：提升代币价值
  - 缺点：需要流动性和市场操作。
- **模式 C：分裂金库（多金库）**：按目的拆分金库（开发基金、保险金、生态基金），每个金库有不同的权限和 timelock。  
  - 优点：更细粒度管理
  - 缺点：实现复杂，治理成本上升。

---

## 3、合约实现（示例）

实现一个**能被测试的最小链路**：

1. LendingPool 在应收利息时把 `reserveFactor` 的份额记入 `reserves`（on-accrual）。  
2. FeeCollector / Treasury 合约持有这些资产。  
3. 简单的 GovernorStub（带 timelock）允许治理修改 `reserveFactor` 并从 Treasury 提取资金（需 timelock 后执行）。

下面代码只是个**安全简化版本**，去掉复杂的 OpenZeppelin Governor 依赖，使用一个非常简化的治理模型（`propose -> queue -> execute`，用简单投票模拟或由测试直接触发投票通过）。重点验证 **费用流 & Timelock 执行**。

### 3.1 LendingPoolWithFees.sol（仅展示关键函数）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Treasury Interface
 * @notice Interface for Treasury contract that collects protocol fees
 */
interface ITreasury {
    /**
     * @notice Collect protocol fees from lending pool
     * @param token The token address to collect
     * @param amount The amount of tokens to collect
     */
    function collect(address token, uint256 amount) external;
}

/**
 * @title Lending Pool With Fees
 * @notice A lending pool that collects protocol fees on interest payments
 * @dev Implements basic deposit/borrow functionality with protocol fee collection
 */
contract LendingPoolWithFees {
    using SafeERC20 for IERC20;

    /// @notice The underlying asset token
    IERC20 public immutable asset;
    
    /// @notice The treasury contract for fee collection
    ITreasury public treasury;

    /// @notice Total amount deposited in the pool
    uint256 public totalDeposits;
    
    /// @notice Total amount borrowed from the pool
    uint256 public totalBorrows;

    /**
     * @notice Reserve factor in basis points (0..10000 = 0%..100%)
     * @dev 1000 = 10% of interest goes to treasury
     */
    uint256 public reserveFactorBps = 1000;
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS = 10000;

    /// @notice Mapping of user addresses to their deposit amounts
    mapping(address => uint256) public deposits;
    
    /// @notice Mapping of user addresses to their borrow amounts
    mapping(address => uint256) public borrows;

    /**
     * @notice Emitted when a user deposits assets
     * @param user The address of the depositor
     * @param amt The amount deposited
     */
    event Deposit(address indexed user, uint256 amt);
    
    /**
     * @notice Emitted when a user borrows assets
     * @param user The address of the borrower
     * @param amt The amount borrowed
     */
    event Borrow(address indexed user, uint256 amt);
    
    /**
     * @notice Emitted when interest is paid
     * @param user The address paying interest
     * @param interest The total interest amount paid
     * @param reservePortion The portion of interest sent to treasury
     */
    event InterestPaid(address indexed user, uint256 interest, uint256 reservePortion);

    /**
     * @notice Initialize the lending pool
     * @param _asset The ERC20 token used as underlying asset
     * @param _treasury The treasury contract for fee collection
     */
    constructor(IERC20 _asset, ITreasury _treasury) {
        asset = _asset;
        treasury = _treasury;
    }

    /**
     * @notice Deposit assets into the lending pool
     * @param amount The amount of assets to deposit
     * @dev Transfers tokens from sender to contract and updates deposit balances
     */
    function deposit(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Borrow assets from the lending pool
     * @param amount The amount of assets to borrow
     * @dev Checks available liquidity and transfers tokens to borrower
     */
    function borrow(uint256 amount) external {
        require(totalDeposits - totalBorrows >= amount, "no liquidity");
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        asset.safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    /**
     * @notice Pay interest on borrowed assets
     * @param interestAmount The amount of interest to pay
     * @dev Splits interest between protocol treasury and lenders based on reserve factor
     */
    function payInterest(uint256 interestAmount) external {
        require(borrows[msg.sender] > 0, "no debt");
        asset.safeTransferFrom(msg.sender, address(this), interestAmount);

        // Calculate protocol's share of interest
        uint256 reservePortion = (interestAmount * reserveFactorBps) / BPS;
        uint256 toLenders = interestAmount - reservePortion;

        // Transfer protocol share to treasury
        asset.approve(address(treasury), reservePortion);
        treasury.collect(address(asset), reservePortion);

        // Distribute remaining interest to lenders (simplified - just add to total deposits)
        totalDeposits += toLenders;

        emit InterestPaid(msg.sender, interestAmount, reservePortion);
    }

    /**
     * @notice Update the reserve factor
     * @param newBps New reserve factor in basis points (0-10000)
     * @dev In production, this should be restricted to governance only
     */
    function setReserveFactor(uint256 newBps) external {
        // In real implementation: require(msg.sender == governance, "only governance");
        require(newBps <= BPS, "invalid bps");
        reserveFactorBps = newBps;
    }
}
```

说明：

* `payInterest` 模拟利息支付并把 `reserveFactor` 的份额通过 `treasury.collect()` 转到 Treasury（Treasure 接口将做转账处理）。
* `setReserveFactor` 在真实合约里应由治理合约通过 timelock 调用；示例保留简化接口以便测试展示治理流程。

---

### 3.2 Treasury.sol（最小实现，带 timelock 支付函数）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Protocol Treasury
 * @notice Manages protocol fee collection and disbursement
 * @dev Funds can only be withdrawn by timelock or guardian for security
 */
contract Treasury {
    using SafeERC20 for IERC20;

    /// @notice Address with authority to approve fund withdrawals (governance/timelock)
    address public timelock;
    
    /// @notice Emergency guardian address for recovery scenarios
    address public guardian;

    /**
     * @notice Emitted when fees are collected from protocol contracts
     * @param token The token that was collected
     * @param amount The amount collected
     */
    event Collected(address indexed token, uint256 amount);
    
    /**
     * @notice Emitted when funds are withdrawn from treasury
     * @param to The recipient address
     * @param token The token withdrawn
     * @param amount The amount withdrawn
     */
    event Withdrawn(address indexed to, address indexed token, uint256 amount);

    /**
     * @notice Initialize the treasury contract
     * @param _timelock The timelock contract address (governance)
     * @param _guardian The guardian address for emergency operations
     */
    constructor(address _timelock, address _guardian) {
        timelock = _timelock;
        guardian = _guardian;
    }

    /**
     * @notice Collect protocol fees from lending pools or other contracts
     * @param token The token address to collect
     * @param amount The amount of tokens to collect
     * @dev Caller must have approved this contract to spend the tokens
     */
    function collect(address token, uint256 amount) external {
        // Transfer tokens from the calling contract to treasury
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Collected(token, amount);
    }

    /**
     * @notice Withdraw funds from treasury
     * @param to The recipient address
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @dev Only callable by timelock or guardian
     */
    function withdraw(address to, address token, uint256 amount) external {
        require(msg.sender == timelock || msg.sender == guardian, "not allowed");
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(to, token, amount);
    }

    /**
     * @notice Update the timelock address
     * @param _timelock The new timelock address
     * @dev Only callable by current guardian or timelock
     */
    function setTimelock(address _timelock) external {
        require(msg.sender == guardian || msg.sender == timelock, "not allowed");
        timelock = _timelock;
    }
}
```

说明：

* `collect`：协议把已批准的 token 从协议合约转入 Treasury。这个简单流程保证资金在链上并可被治理控制。
* `withdraw`：仅允许 `timelock`（代表治理）或 `guardian`（紧急权限）调用支出。

---

### 3.3 TimelockStub.sol（最简 Timelock）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Timelock Stub Contract
 * @notice Simplified timelock for testing governance operations
 * @dev This is a minimal implementation for testing, not production use
 */
contract TimelockStub {
    /// @notice Administrator address with queueing privileges
    address public admin;
    
    /// @notice Minimum delay before queued transactions can execute
    uint256 public delay; // seconds

    /**
     * @notice Transaction data structure
     * @param target The target contract address
     * @param data The calldata to execute
     * @param value The ETH value to send
     * @param eta The timestamp after which transaction can execute
     * @param executed Whether the transaction has been executed
     */
    struct Tx {
        address target;
        bytes data;
        uint256 value;
        uint256 eta; // execute after
        bool executed;
    }

    /// @notice Array of queued transactions
    Tx[] public queued;

    /**
     * @notice Emitted when a transaction is queued
     * @param txId The transaction ID in the queue
     * @param target The target contract address
     * @param eta The execution timestamp
     */
    event QueueTx(uint256 indexed txId, address target, uint256 eta);
    
    /**
     * @notice Emitted when a transaction is executed
     * @param txId The transaction ID that was executed
     */
    event ExecuteTx(uint256 indexed txId);

    /**
     * @notice Initialize the timelock
     * @param _admin The administrator address
     * @param _delay The minimum execution delay in seconds
     */
    constructor(address _admin, uint256 _delay) {
        admin = _admin;
        delay = _delay;
    }

    /**
     * @notice Queue a transaction for future execution
     * @param target The target contract address
     * @param data The calldata to execute
     * @param value The ETH value to send
     * @param eta The timestamp after which transaction can execute
     * @dev Only callable by admin
     */
    function queue(address target, bytes calldata data, uint256 value, uint256 eta) external {
        require(msg.sender == admin, "not admin");
        queued.push(Tx({target: target, data: data, value: value, eta: eta, executed: false}));
        emit QueueTx(queued.length - 1, target, eta);
    }

    /**
     * @notice Execute a queued transaction
     * @param txId The transaction ID to execute
     * @dev Transaction must be past its execution timestamp
     */
    function execute(uint256 txId) external payable {
        Tx storage t = queued[txId];
        require(!t.executed, "executed");
        require(block.timestamp >= t.eta, "too early");
        (bool ok, ) = t.target.call{value: t.value}(t.data);
        require(ok, "call failed");
        t.executed = true;
        emit ExecuteTx(txId);
    }

    /**
     * @notice Get the number of queued transactions
     * @return The length of the queued transactions array
     */
    function queuedLength() external view returns (uint256) {
        return queued.length;
    }
}
```

说明：

* 这是教学版的 timelock：治理（admin）先 queue(tx,target,data,eta)，在 `eta` 之后可执行，模拟真实 timelock 的时延保护。

---

## 4、Foundry 测试（示例）

`ProtocolFeesAndGovernance.t.sol`，测试以下功能：

1. 模拟借款利息支付，验证 `reserveFactor` 的份额最终被 `Treasury` 收到。
2. 模拟“治理提案（由 admin 提交到 Timelock）”来修改 `reserveFactor` 并在 timelock 到期后执行，从而验证治理流程影响协议参数。
3. 测试 Treasury `withdraw` 需由 Timelock 执行（安全检查）。

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPoolWithFees.sol";
import "../src/Treasury.sol";
import "../src/TimelockStub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock ERC20 Token
 * @notice Test token for protocol testing
 */
contract MockToken is ERC20 {
    /**
     * @notice Initialize mock token with initial supply
     */
    constructor() ERC20("MockUSD", "mUSD") {
        _mint(msg.sender, 1_000_000 ether);
    }
    
    /**
     * @notice Mint tokens to specified address
     * @param to The recipient address
     * @param amt The amount to mint
     */
    function mintTo(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/**
 * @title Protocol Fees and Governance Test Suite
 * @notice Comprehensive tests for lending pool fee mechanism and governance operations
 */
contract ProtocolFeesAndGovernanceTest is Test {
    MockToken token;
    Treasury treasury;
    TimelockStub timelock;
    LendingPoolWithFees pool;

    address deployer = address(this); // test contract acts as deployer/admin
    address alice = address(0x1);
    address bob = address(0x2);

    /**
     * @notice Set up test environment
     * @dev Deploys all contracts and funds test accounts
     */
    function setUp() public {
        token = new MockToken();
        // deploy timelock with admin = address(this)
        timelock = new TimelockStub(address(this), 1 days);
        // deploy treasury with timelock as controller
        treasury = new Treasury(address(timelock), address(this));
        pool = new LendingPoolWithFees(IERC20(address(token)), ITreasury(address(treasury)));

        // fund alice/bob
        token.mintTo(alice, 1000 ether);
        token.mintTo(bob, 1000 ether);

        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice Test protocol fee collection mechanism
     * @dev Verifies that interest payments are correctly split between treasury and lenders
     */
    function testReserveAccrualAndTreasuryCollect() public {
        // Alice deposits 100
        vm.prank(alice);
        pool.deposit(100 ether);

        // Bob borrows 50
        vm.prank(bob);
        pool.borrow(50 ether);

        // Bob pays interest = 10
        vm.prank(bob);
        token.mintTo(bob, 10 ether);
        token.approve(address(pool), 10 ether);
        vm.prank(bob);
        pool.payInterest(10 ether);

        // reserveFactor default 10% (1000 bps) => reservePortion = 1
        // Treasury should have received 1 token
        assertEq(token.balanceOf(address(treasury)), 1 ether);
    }

    /**
     * @notice Test governance parameter update via timelock
     * @dev Verifies reserve factor can be updated through governance process
     */
    function testGovernanceChangeReserveFactorViaTimelock() public {
        // initial reserveFactor
        assertEq(pool.reserveFactorBps(), 1000);

        // prepare calldata to call pool.setReserveFactor(2000)
        bytes memory data = abi.encodeWithSelector(LendingPoolWithFees.setReserveFactor.selector, uint256(2000));

        // queue via timelock (admin = this test contract)
        uint256 eta = block.timestamp + 1 days + 1;
        timelock.queue(address(pool), data, 0, eta);

        // fast-forward to eta
        vm.warp(eta + 1);

        // execute via timelock (timelock will call pool.setReserveFactor(2000))
        timelock.execute(0);

        // verify change
        assertEq(pool.reserveFactorBps(), 2000);
    }

    /**
     * @notice Test treasury withdrawal access control
     * @dev Verifies only timelock can withdraw funds from treasury
     */
    function testTreasuryWithdrawRequiresTimelock() public {
        // Collect some funds first
        vm.prank(bob);
        pool.deposit(100 ether);
        vm.prank(bob);
        pool.borrow(50 ether);
        vm.prank(bob);
        token.mintTo(bob, 10 ether);
        vm.prank(bob);
        token.approve(address(pool), 10 ether);
        vm.prank(bob);
        pool.payInterest(10 ether);

        // Treasury has 1 token
        assertEq(token.balanceOf(address(treasury)), 1 ether);

        // Direct withdraw by non-timelock should fail
        vm.prank(alice);
        vm.expectRevert();
        treasury.withdraw(alice, address(token), 1 ether);

        // Queue withdraw via timelock: call treasury.withdraw(alice, token, 1)
        bytes memory data = abi.encodeWithSelector(Treasury.withdraw.selector, alice, address(token), 1 ether);
        uint256 eta = block.timestamp + 1 days + 1;
        timelock.queue(address(treasury), data, 0, eta);

        // warp and execute
        vm.warp(eta + 1);
        timelock.execute(0);

        // Alice started with 1000 ether and received 1 ether from treasury
        assertEq(token.balanceOf(alice), 1001 ether);
    }
}
```

**执行测试**：

```bash
➜  defi git:(master) ✗ forge test --match-path test/ProtocolFeesAndGovernance.t.sol -vvv
[⠊] Compiling...
[⠔] Compiling 4 files with Solc 0.8.29
[⠒] Solc 0.8.29 finished in 1.44s
Compiler run successful!

Ran 3 tests for test/ProtocolFeesAndGovernance.t.sol:ProtocolFeesAndGovernanceTest
[PASS] testGovernanceChangeReserveFactorViaTimelock() (gas: 190634)
[PASS] testReserveAccrualAndTreasuryCollect() (gas: 252323)
[PASS] testTreasuryWithdrawRequiresTimelock() (gas: 448244)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 6.94ms (4.58ms CPU time)

Ran 1 test suite in 466.02ms (6.94ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
```

---

## 5、总结

1. **协议费来源**：利息分成、交易手续费、清算分成、闪电贷费等 —— 每一种都有不同的会计与分配方式。
2. **Treasury 是协议的经济中枢**，应当可被治理控制，但对提取与支出进行时延与审计：多签 + timelock 是最普遍的保护手段。
3. **治理模型**：代币分配、投票模型、提案门槛、quorum、timelock、紧急管理员 —— 每项设计都会影响中心化程度与安全性。
4. **攻击面**：治理被夺取、闪电贷投票、投票冷漠、提案经济攻击 —— 需要通过 timelock、锁仓投票、投票快照与分权等机制缓解。
5. **工程实践建议**：把金库逻辑写清楚（谁能调用？什么情况下花费？），并把所有关键动作放到 timelock 阶段；在测试中模拟治理流程与恶意情景（flash loans / bribery）以发现漏洞。

---

## 6、作业

1. 把 `LendingPoolWithFees` 的 `payInterest` 改为按时间自动累积利息（结合第 3 课的 index），并确保 `reserveFactor` 的份额正确计入 Treasury（即把 periodic 收益转成 on-chain collect）。
2. 给 `TimelockStub` 增加 `cancel` 功能（允许 admin 在执行前取消排队），并写测试验证。
3. 设计一套治理代币分配方案（不少于 3 个分发池：团队、社区空投、流动性挖矿），并写出 token vesting 的大致参数（锁期 / 线性解锁 / cliff）。
4. 写一篇短文讨论「ve模型 vs one-token-one-vote」的优缺点（不少于 400 字），并给出本项目如果采用 ve 该如何修改（大致改动点）。

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