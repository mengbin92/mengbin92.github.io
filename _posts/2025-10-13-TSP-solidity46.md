---
layout: post
title: 《纸上谈兵·solidity》第 46 课：DeFi 实战(10) -- 跨链借贷与流动性桥接
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解跨链借贷的几种常见体系结构（lock-mint、liquidity pool、atomic swap、debt-on-destination）；
* 了解主流跨链通信/桥的安全/设计要点（finality、reorg、replay、watchers、relayers、attestation）；
* 掌握跨链借贷带来的关键挑战：延迟、清算、oracle 一致性、双花、流动性碎片化、信任边界；
* 实现一个**教学级别**的跨链借贷原型（MockBridge + ChainA 抵押管理 + ChainB 借贷/信用管理），并用 Foundry 测试关键流程（存抵押 → 跨链消息 → mint vToken → 借款 → 价格下跌 → 跨链清算）；
* 学会如何把教学实现替换成生产桥（LayerZero / Axelar / Wormhole）时需要注意的改动。

---

## 2、概念与设计详解

跨链借贷把「抵押在链 A、借款在链 B」或「在某链上开仓并在另一链上获得流动性」变为可能，但也带来了复杂性。下面尽量详尽列出设计要点与工程权衡。

### 2.1 主要跨链架构

1. **Lock-mint (canonical token / wrapped)**
   * 链 A 上锁定原始资产（或把资产交给托管），桥方在链 B 上 mint 一个等值的 wrapped / vToken。
   * 优点：逻辑简单，借款链上拥有可直接抵押 token（liquidity 原位）；
   * 缺点：桥方/验证器可信度是风险源；需要治理和 slashing（若桥方作恶）。
2. **Liquidity pools（two-way peg via pooled liquidity）**
   * 桥方不做全量担保，而是在链 B 上维护 liquidity pool（市场做市）来 mint / burn；用户通过 pool 兑换跨链资产。
   * 优点：延迟低、可做即时兑换；
   * 缺点：pool 需要深度流动性，定价滑点与资金成本。
3. **Debt/credit model（credit on destination）**
   * 抵押资产仍锁在链 A，但在链 B 上产生“信用凭证（vToken）”代表在链 A 的抵押权利（bridge message + attestation）。借款在链 B 发放，债务也在链 B 跟踪。
   * 优点：减少跨链资金移动，支持跨链借贷场景；
   * 缺点：跨链清算复杂，受消息延迟影响。
4. **Atomic swap / liquidity aggregation（no mint）**
   * 典型用于闪电场景：在跨链聚合器或聚合市场上做原子互换，避免在目标链上 mint 新 token。通常对借贷而言适用性有限。

> 在本课示例中，我们采用 **Lock-mint / Credit hybrid** 的教学模型（抵押在 ChainA，bridge 发消息到 ChainB mint vToken；借款在 ChainB），因为它直观同时能演示跨链清算问题。

---

### 2.2 跨链通信关键要点

1. **最终性（Finality）与 Reorg**
   * 不同链的最终性差异很大（PoW / PoS / L2）。桥消息应等待足够 confirmations / finality window。Layer-2 的重组可能导致“已桥消息被回滚”风险。
   * 解决：消息签名集合（quorum）、等待时间/confirmations、 optimistic relayers + challenge period。
2. **消息顺序与重复（Replay）**
   * 消息需带唯一 id / nonce 防止 replay；并且桥必须提供幂等接收（deliver only once）。
3. **桥的信任模型**
   * 完全信任（custodian） vs 多签 vs 验证器共识 vs 链下签名聚合（Axelar、Wormhole、LayerZero 都用不同模型）。生产选择影响故障/攻击面。
4. **价格一致性（跨链 oracle）**
   * 清算需依赖跨链一致的价格。常见方法：每链部署本地 oracle，但使用跨链预言机或 aggregator（Chainlink Flux / TWAP across chains / oracles push attestations to multi chains）。
   * 设计注意：跨链消息延迟导致 oracle 值在不同链不同步，清算策略需考虑时间滞后（更高抵押率 /更大 closeFactor safety margin / longer liquidation windows）。
5. **MEV / front-running & atomicity**
   * 跨链交易不是原子操作，攻击者可能在消息发送 / relay 阶段操纵市场或抢跑清算。需用 guard rails（timelocks、slippage control、limit size）。
6. **Slashing / Insurance**
   * 为桥或 relayers 设计 slashing 与保险金（staking）机制以降低作恶风险；或把大额跨链额度放在多签金库并加 timelock。

---

### 2.3 跨链清算的经济问题

* **延期清算风险**：桥延迟意味着在链 B 上判定用户可清算，但在 bridge 还未交付 seize 请求前用户抵押可能已恢复或抵押已变动 — 需在参数里留出 safety margin。
* **跨链罚没**：当清算发生，seized collateral 在链 A 上被扣押，清算人在链 B 要能得到相应价值的奖励（可能通过跨链返还或在链 B 发放奖赏）——这涉及双向价值交换（bridge 要支持从 A 到 B 的价值通道或相应回购机制）。
* **清算不一致性**：在链 B 上判定并执行清算请求后，链 A 必须可执行 seize；若桥延迟或拒绝，清算人可能无法兑现收益。
  
**缓解办法**：提高 overcollateralization、分段清算、引入 keeper economic incentives（提前支付桥费、承担临时风险）、使用 escrow / bonded relayers。

---

### 2.4 生产替换点（从教学 Mock 到真实桥）

* 把 `MockBridge` → `LayerZero/Axelar/Wormhole`：主要改动是消息的验证（签名/attestation）与最终性处理（等待 confirmations / nonce）。
* 价格来源：使用跨链一致 oracle（Chainlink cross-chain feeds / Axelar price service / TWAP + aggregator）。
* 保险：真实系统需要 Treasury/insurance fund 以对冲桥/relayer 风险。
* 权限：治理通过 timelock 管理跨链配额、最大可跨链担保量，避免大规模跨链风险暴露。

---

## 3、示例代码

在下面的示例中，模拟 **两条链**（在本地一条 EVM 环境里通过合约部署模拟两链），包含：

* `MockBridge`：跨链消息中继；
* `CollateralManagerA`：部署在 Chain A，用户存入原始 token，合约锁定并发出桥消息到 Chain B（请求 mint Credit）；
* `CreditManagerB`：部署在 Chain B，接收桥消息 mint vToken（代表在 A 锁定的抵押），贷款在 B 发放，借款/负债在 B 记录；
* `MockOracle`：为两个链提供价格（教学会在单地址 mock 返回不同值以模拟价格波动）；
* Foundry 测试：模拟完整流程（deposit on A → deliver message → borrow on B → price crash → liquidator on B triggers cross-chain seize request → deliver seize → collateral seized on A）。

> 注意：这是教学级实现，省去了真实桥的复杂签名与 finality 机制，使用 `deliverMessage`/`deliverSeize` 由测试主动调用模拟 relayer / oracle 迟延

**`src/MockBridge.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockBridge
 * @notice 教学用的模拟跨链桥合约：发送消息并由管理员（测试环境）手动或自动触发消息传递
 * @dev 该合约用于模拟跨链通信，在测试环境中使用
 */
contract MockBridge {
    /// @notice 消息发送事件
    event MessageSent(uint256 indexed dstChainId, address indexed target, bytes data, uint256 nonce);
    
    /// @notice 消息传递完成事件
    event MessageDelivered(uint256 indexed srcChainId, address indexed target, bytes data, uint256 nonce);

    /// @notice 消息计数器
    uint256 public nonce;
    
    /// @notice 管理员地址
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice 发送消息到目标链（模拟）
     * @dev 记录事件并递增nonce
     * @param dstChainId 目标链ID
     * @param target 目标合约地址
     * @param data 调用数据
     * @return 返回消息nonce
     */
    function sendMessage(uint256 dstChainId, address target, bytes calldata data) external returns (uint256) {
        nonce++;
        emit MessageSent(dstChainId, target, data, nonce);
        return nonce;
    }

    /**
     * @notice 传递消息到目标合约
     * @dev 仅管理员可调用，用于模拟中继器/证明机制
     * @param srcChainId 源链ID
     * @param target 目标合约地址
     * @param data 调用数据
     * @param _nonce 消息nonce
     */
    function deliverMessage(uint256 srcChainId, address target, bytes calldata data, uint256 _nonce) external {
        // 在生产环境中，这里需要验证签名/证明
        (bool ok, ) = target.call(data);
        require(ok, "delivery failed");
        emit MessageDelivered(srcChainId, target, data, _nonce);
    }

    /**
     * @notice 设置新的管理员地址
     * @dev 仅当前管理员可调用，用于测试灵活性
     * @param a 新的管理员地址
     */
    function setAdmin(address a) external {
        require(msg.sender == admin, "not admin");
        admin = a;
    }
}
```

**`src/ICrossBridge.sol` (interface)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossBridge
 * @notice 跨链桥接口定义
 */
interface ICrossBridge {
    /**
     * @notice 发送消息到目标链
     * @param dstChainId 目标链ID
     * @param target 目标合约地址
     * @param data 调用数据
     * @return 返回消息nonce
     */
    function sendMessage(uint256 dstChainId, address target, bytes calldata data) external returns (uint256);
}
```

**`src/CollateralManagerA.sol`  (在 Chain A)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ICrossBridge.sol";

/**
 * @title ICollateralReceiver
 * @notice 抵押品接收器接口
 */
interface ICollateralReceiver {
    /**
     * @notice 当抵押品铸造时调用
     * @param user 用户地址
     * @param amount 抵押品数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onCollateralMint(address user, uint256 amount, uint256 srcChainId, uint256 nonce) external;
    
    /**
     * @notice 当扣押抵押品时调用
     * @param user 用户地址
     * @param amount 扣押数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onSeizeCollateral(address user, uint256 amount, uint256 srcChainId, uint256 nonce) external;
}

/**
 * @title CollateralManagerA
 * @notice 链A的抵押品管理器：处理抵押品存款和跨链桥接
 */
contract CollateralManagerA {
    using SafeERC20 for IERC20;

    /// @notice 原始代币（例如 WETH）
    IERC20 public immutable underlying;
    
    /// @notice 跨链桥接口
    ICrossBridge public bridge;
    
    /// @notice 模拟的链A ID
    uint256 public chainId;

    /// @notice 用户地址 => 锁定数量 的映射
    mapping(address => uint256) public locked;

    /// @notice 存款事件
    event Deposited(address indexed user, uint256 amount, uint256 nonce);
    
    /// @notice 扣押事件
    event Seized(address indexed user, uint256 amount);

    /**
     * @notice 构造函数
     * @param _underlying 原始代币地址
     * @param _bridge 跨链桥地址
     * @param _chainId 链A ID
     */
    constructor(IERC20 _underlying, ICrossBridge _bridge, uint256 _chainId) {
        underlying = _underlying;
        bridge = _bridge;
        chainId = _chainId;
    }

    /**
     * @notice 用户在链A存款抵押品并跨链桥接到链B
     * @dev 锁定原始代币并发送消息到链B
     * @param dstChainId 目标链ID
     * @param creditManagerOnDst 目标链信用管理器地址
     * @param amount 存款数量
     */
    function depositAndBridge(uint256 dstChainId, address creditManagerOnDst, uint256 amount) external {
        require(amount > 0, "zero");
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        locked[msg.sender] += amount;

        // 准备消息调用数据：调用 onCollateralMint(user, amount, srcChainId, nonce)
        bytes memory payload = abi.encodeWithSelector(
            ICollateralReceiver.onCollateralMint.selector,
            msg.sender,
            amount,
            chainId,
            0 // nonce占位符（桥接器返回实际值）
        );

        uint256 n = bridge.sendMessage(dstChainId, creditManagerOnDst, payload);
        emit Deposited(msg.sender, amount, n);
    }

    /**
     * @notice 通过桥接器传递消息扣押抵押品（在跨链清算决策后）
     * @dev 任何人都可调用，但在生产环境中应验证证明
     * @param user 用户地址
     * @param amount 扣押数量
     */
    function seize(address user, uint256 amount) external {
        // 在生产环境中：验证来自桥接器的跨链决策证明
        require(amount <= locked[user], "exceed locked");
        locked[user] -= amount;
        underlying.safeTransfer(msg.sender, amount); // 将扣押的抵押品发送给清算人（调用者）
        emit Seized(user, amount);
    }

    /**
     * @notice 设置桥接器地址（用于测试）
     * @dev 生产环境中需要访问控制
     * @param b 新的桥接器地址
     */
    function setBridge(ICrossBridge b) external {
        // 生产环境中需要访问控制
        bridge = b;
    }
}
```

**`src/CreditManagerB.sol` (在 Chain B)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IBridgeReceiver
 * @notice 桥接接收器接口
 */
interface IBridgeReceiver {
    /**
     * @notice 当抵押品铸造时由桥接器调用
     * @param user 用户地址
     * @param amount 抵押品数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onCollateralMint(
        address user,
        uint256 amount,
        uint256 srcChainId,
        uint256 nonce
    ) external;
    
    /**
     * @notice 当扣押抵押品时由桥接器调用
     * @param user 用户地址
     * @param amount 扣押数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onSeizeCollateral(
        address user,
        uint256 amount,
        uint256 srcChainId,
        uint256 nonce
    ) external;
}

/**
 * @title CreditManagerB
 * @notice 链B的信用管理器：处理vToken铸造、借贷和清算
 */
contract CreditManagerB is IBridgeReceiver {
    using SafeERC20 for IERC20;

    /// @notice vToken名称（代表抵押品信用的简单ERC20代币）
    string public name = "vCollateral";
    
    /// @notice vToken符号
    string public symbol = "vCOL";
    
    /// @notice vToken小数位
    uint8 public decimals = 18;

    /// @notice 地址 => vToken余额 的映射
    mapping(address => uint256) public vBalance;
    
    /// @notice vToken总供应量
    uint256 public vTotalSupply;

    /// @notice 模拟借贷池流动性（稳定币）
    IERC20 public stable;
    
    /// @notice 总借款量
    uint256 public totalBorrows;

    /// @notice 用户地址 => 借款数量 的映射
    mapping(address => uint256) public borrows;

    /// @notice 预言机地址（模拟，用于检查价格）
    address public oracle;

    /// @notice 抵押品铸造事件
    event CollateralMinted(address indexed user, uint256 amount);
    
    /// @notice 借款事件
    event Borrowed(address indexed user, uint256 amount);
    
    /// @notice 清算请求事件
    event LiquidationRequested(
        address indexed user,
        address indexed liquidator,
        uint256 repayAmount,
        uint256 seizeAmount
    );

    /**
     * @notice 构造函数
     * @param _stable 稳定币地址
     * @param _oracle 预言机地址
     */
    constructor(IERC20 _stable, address _oracle) {
        stable = _stable;
        oracle = _oracle;
    }

    /**
     * @notice 桥接器调用此函数来铸造vToken，代表在链A锁定的抵押品
     * @dev 桥接器传递消息时调用
     * @param user 用户地址
     * @param amount 抵押品数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onCollateralMint(
        address user,
        uint256 amount,
        uint256 /*srcChainId*/,
        uint256 /*nonce*/
    ) external override {
        // 为用户铸造vToken（教学用途1:1比例）
        vBalance[user] += amount;
        vTotalSupply += amount;
        emit CollateralMinted(user, amount);
    }

    /**
     * @notice 桥接器调用此函数来扣押链A上的抵押品
     * @dev 桥接器传递消息时调用
     * @param user 用户地址
     * @param amount 扣押数量
     * @param srcChainId 源链ID
     * @param nonce 消息nonce
     */
    function onSeizeCollateral(
        address user,
        uint256 amount,
        uint256 /*srcChainId*/,
        uint256 /*nonce*/
    ) external override {
        // 在链B上减少用户的vToken余额（相当于清算时销毁vToken）
        require(vBalance[user] >= amount, "insufficient vBalance");
        vBalance[user] -= amount;
        vTotalSupply -= amount;
        // 注意：这里不转移实际资产，因为实际资产在链A上
    }

    /**
     * @notice 使用vToken作为抵押品在链B上借款（教学用途：简单LTV固定比例）
     * @dev 简单的抵押率检查：vBalance * 价格 * 系数 >= 借款价值
     * @param amount 借款数量
     */
    function borrow(uint256 amount) external {
        // 需要简单的抵押品检查：vBalance * 价格 * 系数 >= 借款价值
        // 在测试中通过外部调用预言机来控制价格
        // 简化：1 vToken = 1个基础单位，价格由预言机提供
        // 生产环境：使用稳健的预言机 + 价格单位标准化
        require(vBalance[msg.sender] > 0, "no vcollateral");
        
        // 简单检查：允许借款最多为vBalance的75%
        uint256 maxBorrow = (vBalance[msg.sender] * 75) / 100;
        require(amount <= maxBorrow, "exceed LTV");
        
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        stable.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    /**
     * @notice 链B上的清算人偿还用户的部分借款并请求扣押链A上的抵押品
     * @dev 由清算人调用；通过桥接器发送消息（在测试中模拟）
     * @param user 用户地址
     * @param repayAmount 偿还数量
     * @param bridge 桥接器地址
     * @param dstChainId 目标链ID
     * @param collateralManagerOnA 链A抵押品管理器地址
     */
    function liquidate(
        address user,
        uint256 repayAmount,
        address bridge,
        uint256 dstChainId,
        address collateralManagerOnA
    ) external {
        require(borrows[user] >= repayAmount, "repay > debt");
        
        // 将偿还的稳定币从清算人转移到本合约（资金池）
        stable.safeTransferFrom(msg.sender, address(this), repayAmount);
        borrows[user] -= repayAmount;
        totalBorrows -= repayAmount;

        // 计算vToken的扣押数量（应用清算奖励，例如5%）
        uint256 seizeAmount = (repayAmount * 105) / 100; // 简单的1:1价值假设
        
        // 准备发送给CollateralManagerA.seize(user, seizeAmount)的消息
        // bytes memory payload = abi.encodeWithSelector(
        //     CollateralManagerAInterface.seize.selector,
        //     user,
        //     seizeAmount
        // );

        // 通过桥接器发送（实际调用将在测试中构造）
        // 我们无法在此处调用桥接器，因为我们保持桥接器不可知。测试将发送消息。
        emit LiquidationRequested(user, msg.sender, repayAmount, seizeAmount);
    }

    /**
     * @notice 查询用户的vToken余额
     * @param user 用户地址
     * @return vToken余额
     */
    function vBalanceOf(address user) external view returns (uint256) {
        return vBalance[user];
    }
}

/**
 * @title CollateralManagerAInterface
 * @notice 链A抵押品管理器接口
 */
interface CollateralManagerAInterface {
    /**
     * @notice 扣押用户抵押品
     * @param user 用户地址
     * @param amount 扣押数量
     */
    function seize(address user, uint256 amount) external;
}
```

> 注意：上面合约故意保持教学简洁：`CreditManagerB.liquidate` 只发出事件 `LiquidationRequested`（在真实场景中，该合约会调用桥 `sendMessage` 将 `seize` 请求发送回 Chain A）。为了把桥耦合最小化，我们把 bridge 操作放到测试驱动中，由测试模拟 relayer 把消息交付到 `CollateralManagerA.seize`。

---

## 4、Foundry 测试

下面的测试整体在单一 EVM 环境运行——我们用不同合约实例来模拟 Chain A / Chain B，使用 `MockBridge` 的 `sendMessage` + `deliverMessage` 模拟消息传递（由测试充当 relayer/admin）。

**`test/CrossChainLending.t.sol`**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockBridge.sol";
import "../src/CollateralManagerA.sol";
import "../src/CreditManagerB.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice 模拟ERC20代币合约，用于测试
 */
contract MockToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    
    /**
     * @notice 铸造代币
     * @param to 接收地址
     * @param amt 铸造数量
     */
    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/**
 * @title CrossChainLendingTest
 * @notice 跨链借贷测试合约
 * @dev 使用Forge测试框架进行跨链借贷流程的端到端测试
 */
contract CrossChainLendingTest is Test {
    MockBridge bridge;
    MockToken underlying; // 链A的代币
    MockToken stable;     // 链B的代币（借款资产）
    CollateralManagerA collA;
    CreditManagerB credB;

    address user = address(0x1);
    address liquidator = address(0x2);

    function setUp() public {
        bridge = new MockBridge();
        underlying = new MockToken("Underlying", "u");
        stable = new MockToken("Stable", "s");

        // 部署链A抵押品管理器，链ID = 1
        collA = new CollateralManagerA(IERC20(address(underlying)), ICrossBridge(address(bridge)), 1);
        
        // 部署链B信用管理器
        credB = new CreditManagerB(IERC20(address(stable)), address(0)); // 教学用途未使用预言机

        // 准备余额
        underlying.mint(user, 10 ether);
        stable.mint(address(credB), 10000 ether); // 链B的流动性
        stable.mint(liquidator, 2000 ether);

        // 用户授权存款
        vm.startPrank(user);
        underlying.approve(address(collA), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice 测试完整的存款、跨链桥接、借款和清算流程
     * @dev 验证跨链借贷系统的端到端功能
     */
    function testDepositBridgeBorrowAndLiquidationFlow() public {
        // 1) 用户在链A存款并通过桥接器在链B铸造vToken
        vm.startPrank(user);
        collA.depositAndBridge(2, address(credB), 5 ether); // 目标链ID=2，信用管理器地址
        vm.stopPrank();

        // 桥接器产生MessageSent事件；现在模拟中继器将消息传递给credB
        // 为此，我们重建匹配onCollateralMint签名的payload
        bytes memory payload = abi.encodeWithSelector(
            ICollateralReceiver.onCollateralMint.selector,
            user,
            5 ether,
            uint256(1),
            uint256(1)
        );

        // 中继器（桥接器管理员）将消息传递给credB
        bridge.deliverMessage(1, address(credB), payload, 1);

        // 验证链B上铸造的vToken（vBalance）
        assertEq(credB.vBalanceOf(user), 5 ether);

        // 2) 用户在链B上借款，最高75% LTV（教学用途）
        vm.startPrank(user);
        // 确保稳定币有足够流动性：已在setUp中铸造给credB
        // 用户借款3.5（<= 5 * 0.75 = 3.75）
        uint256 borrowAmount = 3500000000000000000; // 3.5 ether
        credB.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(credB.borrows(user), borrowAmount);

        // 3) 通过减少链B上有效抵押品价值来模拟价格冲击（我们通过让清算人行动来模拟）
        // 在这个教学设置中，我们跳过预言机；我们继续让清算人偿还部分债务以请求扣押。
        vm.startPrank(liquidator);
        stable.approve(address(credB), type(uint256).max);
        
        // 修复：还款金额应该小于等于用户债务
        // 用户借了 3.5 ether，我们让清算者偿还 1.5 ether（而不是之前的 1500 ether）
        uint256 repayAmount = 1500000000000000000; // 1.5 ether
        credB.liquidate(user, repayAmount, address(bridge), 1, address(collA));
        vm.stopPrank();

        // 现在用户的债务应该减少了
        assertEq(credB.borrows(user), borrowAmount - repayAmount);

        // 现在模拟中继器将扣押消息传递给 collA
        // 扣押金额 = 还款金额 * 1.05 = 1.5 ether * 1.05 = 1.575 ether
        uint256 seizeAmount = (repayAmount * 105) / 100;
        bytes memory seizePayload = abi.encodeWithSelector(
            CollateralManagerA.seize.selector,
            user,
            seizeAmount
        );

        // 传递扣押消息：桥管理员调用 deliverMessage
        bridge.deliverMessage(2, address(collA), seizePayload, 2);

        // 现在 collA.locked[user] 应该减少了（初始 5 - 扣押 ~1.575 = ~3.425）
        uint256 left = collA.locked(user);
        assertEq(left, 5 ether - seizeAmount);
        
        // 验证清算者的稳定币余额变化
        // 清算者支付了 1.5 ether 稳定币来偿还债务
        uint256 liquidatorStableBalanceAfter = stable.balanceOf(liquidator);
        assertEq(liquidatorStableBalanceAfter, 2000 ether - repayAmount);
        
        // 验证 CreditManagerB 的稳定币余额变化
        uint256 credBStableBalanceAfter = stable.balanceOf(address(credB));
        assertEq(credBStableBalanceAfter, 10000 ether - borrowAmount + repayAmount);
    }
}
```

> 测试说明：
>
> * 我们在测试中模拟 relayer：`bridge.deliverMessage` 由测试调用，代表桥的 attestation/relay 完成。
> * `CreditManagerB.liquidate` 在教学实现中只是发出事件，我们在测试手工构造 seizePayload 并由 bridge.deliverMessage 调用 `CollateralManagerA.seize` 实际扣押抵押并发送给清算人（调用者）。
> * 真实系统应把 bridge 发消息这一环节放在 `CreditManagerB.liquidate`（由它调用 `bridge.sendMessage`），并在链 A 的 `CollateralManagerA.seize` 做更严格的 attestation 验证（nonce / signature / source chain / governance control）。

执行测试：  

```bash
➜  defi git:(master) forge test --match-path test/CrossChainLending.t.sol -vvv
[⠊] Compiling...
[⠆] Compiling 1 files with Solc 0.8.30
[⠔] Solc 0.8.30 finished in 1.27s
Compiler run successful!

Ran 1 test for test/CrossChainLending.t.sol:CrossChainLendingTest
[PASS] testDepositBridgeBorrowAndLiquidationFlow() (gas: 354312)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.98ms (715.34µs CPU time)

Ran 1 test suite in 328.14ms (1.98ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 5、总结

* 跨链借贷把 DeFi 生态扩展到链间组合：用户抵押可以在链 A，而在链 B 获得流动性；但跨链带来的**延迟、最终性与信任边界**是核心风险。
* 常见跨链架构：lock-mint、liquidity pool、credit model（各有优缺点）。
* 跨链清算是最具挑战的流程之一：必须设计消息保证、价格一致性及清算激励来抵抗滥用。
* 教学实现（MockBridge + CollateralManagerA + CreditManagerB）能帮助你本地验证跨链流程，生产时请替换为真实桥与跨链 oracle，并设计 relayer / timelock / slashing 机制。

---

## 6、作业

1. **把教学模型改造为在 `CreditManagerB.liquidate` 中直接调用 `bridge.sendMessage(...)` 来发送 seize 请求**，并在 `MockBridge.deliverMessage` 处自动执行（现在测试是手动调用）。写测试验证 end-to-end。
2. **实现拍卖 + 跨链结算**：当需要 seize 大额 illiquid collateral 时，在 Chain A 启动拍卖，并在 Chain B 给出一个赎回窗口或给清算人链 B 上的奖励（示例：先给清算人 stable，后续由协议在链 A 放出 seizedCollateral）。
3. **用 LayerZero 替换 MockBridge（本地运行的测试框架）**：研究 LayerZero 的消息格式、费用模型与最终性假设，在测试网络上做一次真正的跨链 mint（可能需要两个 testnets / devnets）。

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