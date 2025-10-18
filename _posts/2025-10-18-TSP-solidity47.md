---
layout: post
title: 《纸上谈兵·solidity》第 47 课：DeFi 实战(11) -- 治理代币 & 激励机制（Tokenomics & Governance）
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

通过本课你将掌握：

* 治理代币（Governance Token）的**设计目标与现实角色**；
* 去中心化治理结构（Governor + Timelock + Proposal）；
* 流动性激励与收益分配机制（Liquidity Mining、Staking、Fee Redistribution）；
* 如何用 Solidity 实现一个**治理代币 + 投票治理系统 + 协议收入分配模型**；
* 理解激励滥用、投票集中化、DAO 决策延迟等现实问题。

---

## 2、核心概念与现实机制详解

### 2.1 治理代币（Governance Token）

**定义**：治理代币是 DeFi 协议中用来代表**治理权、收益权或投票权**的加密资产。
持有者可以对协议的参数、资金使用、升级提案等进行投票或提案。

常见模型：

| 协议           | 治理代币 | 特点                                 |
| ------------ | ---- | ---------------------------------- |
| **Compound** | COMP | 每区块发放激励，按借贷量分配；投票决定参数（利率模型、资产列表等）  |
| **Aave**     | AAVE | 质押（Safety Module）提供保险功能，参与治理，赚取协议费 |
| **Curve**    | CRV  | 投票锁仓 (veCRV) 模型，决定激励分配、治理提案        |
| **MakerDAO** | MKR  | 承担清算风险；治理 DAI 的利率、抵押物比例等           |

**关键思路**：治理代币 ≠ 股权；它是治理机制的燃料。

经济模型要设计为：

* 激励长期持有者；
* 抑制短期投机；
* 维持系统稳定。

---

### 2.2 Tokenomics（代币经济模型）

核心维度：

1. **分配机制**
   * **Liquidity Mining（流动性挖矿）**：向借贷双方或流动性提供者发放代币；
   * **Treasury / Reserve**：保留部分代币作为协议储备、开发基金；
   * **Staking / 锁仓激励**：长期锁定代币获得更高收益或投票权（veToken 模型）。
2. **价值捕获机制**
   * 协议费分配（如：利息的 10% 分配给治理金库）；
   * 代币回购（Buyback & Burn）；
   * 保险基金收益（Safety Module）。
3. **投票权机制**
   * 每个治理代币 = 一票；
   * 锁仓时间越长，投票权越大（veToken 模型）；
   * 或采用“代表投票”（Delegation）。
4. **治理执行机制**
   * Proposal → Voting → Timelock → Execution；
   * 投票通过的提案在延时后由执行合约（TimelockController）调用协议函数；
   * 防止紧急攻击或治理闪电贷。

---

### 2.3 DAO 与治理流程（以 Aave/Compound 为例）

1. **提案（Proposal）**：由满足条件（持有一定代币）的用户发起；
2. **投票（Voting）**：代币持有人按持币比例投票；
3. **通过阈值（Quorum）**：达到最低票数或通过率；
4. **延时执行（Timelock）**：通过后等待 N 天执行；
5. **执行（Execution）**：由 Timelock 合约调用协议合约的修改函数。

---

## 3、最小化治理系统（Simplified Governance System）

我们来构建一个简单但完整的治理代币与 DAO：

### 系统组成

1. `GovToken`：ERC20 代币 + 委托投票（类似 COMP token 模式）；
2. `LendingProtocol`：已有借贷系统的一部分（这里仅示意接口，如设置费率）；
3. `Governor`：管理提案、投票与执行；
4. `Timelock`：治理提案延时执行；
5. `RewardDistributor`：根据用户借贷活动发放治理代币奖励。

---

### 3.1 `GovToken.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title GovToken
 * @author DeFi Protocol Team
 * @notice 治理代币合约，继承 ERC20Votes 功能，支持投票治理
 * @dev 该合约实现了 ERC20Votes 标准，允许代币持有者参与协议治理
 *      代币可以通过奖励分发器进行铸造，用于激励用户参与协议
 */
contract GovToken is ERC20Votes {
    /**
     * @notice 构造函数，初始化治理代币
     * @dev 铸造 1,000,000 个代币给部署者，并设置 EIP712 域名
     */
    constructor()
        ERC20("Governance Token", "GOV")
        EIP712("Governance Token", "1")
    {
        _mint(msg.sender, 1_000_000e18);
    }

    /**
     * @notice 铸造新代币用于奖励分发
     * @dev 该函数允许外部合约铸造代币，主要用于奖励分发器
     * @param to 接收代币的地址
     * @param amount 铸造的代币数量
     * @custom:security 在实际部署中，应该添加访问控制，只允许特定的分发器合约调用
     */
    function mint(address to, uint256 amount) external {
        // 在实际部署中，应该添加访问控制，只允许特定的分发器合约调用
        _mint(to, amount);
    }
}
```

---

### 3.2 `SimpleGovernor.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

/**
 * @title SimpleGovernor
 * @author DeFi Protocol Team
 * @notice 简化的治理合约，基于 OpenZeppelin Governor 实现
 * @dev 该合约实现了基本的治理功能，包括提案创建、投票和简单计数
 *      使用 ERC20Votes 代币进行投票，支持提案阈值和法定人数要求
 */
contract SimpleGovernor is Governor, GovernorCountingSimple, GovernorVotes {
    /**
     * @notice 构造函数，初始化治理合约
     * @param _token 用于投票的 ERC20Votes 代币合约
     */
    constructor(
        IVotes _token
    ) Governor("SimpleGovernor") GovernorVotes(_token) {}

    /**
     * @notice 获取投票延迟时间
     * @dev 提案创建后需要等待的区块数
     * @return 投票延迟时间（区块数）
     */
    function votingDelay() public pure override returns (uint256) {
        return 1; // 1 block
    }

    /**
     * @notice 获取投票期间长度
     * @dev 投票开始后持续的时间（区块数）
     * @return 投票期间长度（区块数）
     */
    function votingPeriod() public pure override returns (uint256) {
        return 45818; // ~1 week
    }

    /**
     * @notice 获取法定人数要求
     * @dev 提案通过所需的最小投票权数量
     * @param 提案ID（未使用，但需要保持函数签名一致）
     * @return 法定人数要求（代币数量）
     */
    function quorum(uint256) public pure override returns (uint256) {
        return 100e18; // 100 GOV
    }

    /**
     * @notice 获取提案阈值
     * @dev 创建提案所需的最小投票权数量
     * @return 提案阈值（代币数量）
     */
    function proposalThreshold() public pure override returns (uint256) {
        return 10e18;
    }
}
```

---

### 3.3 `RewardDistributor.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GovToken.sol";

/**
 * @title RewardDistributor
 * @author DeFi Protocol Team
 * @notice 奖励分发器合约，用于记录用户活动并分发治理代币奖励
 * @dev 该合约允许协议记录用户活动，累积奖励，并允许用户领取治理代币
 *      只有指定的协议地址可以调用 accrue 函数来记录奖励
 */
contract RewardDistributor {
    /// @notice 治理代币合约地址
    GovToken public gov;

    /// @notice 协议地址，只有该地址可以调用 accrue 函数
    address public protocol;

    /// @notice 用户累积的奖励映射
    mapping(address => uint256) public accrued;

    /**
     * @notice 构造函数，初始化奖励分发器
     * @param _gov 治理代币合约地址
     * @param _protocol 协议地址，用于权限控制
     */
    constructor(GovToken _gov, address _protocol) {
        gov = _gov;
        protocol = _protocol;
    }

    /**
     * @notice 记录用户活动并累积治理代币奖励
     * @dev 只有协议地址可以调用此函数，用于记录用户参与协议活动
     * @param user 用户地址
     * @param value 奖励的治理代币数量
     * @custom:security 只有 protocol 地址可以调用此函数
     */
    function accrue(address user, uint256 value) external {
        require(msg.sender == protocol, "not protocol");
        accrued[user] += value;
    }

    /**
     * @notice 领取累积的治理代币奖励
     * @dev 用户调用此函数来领取之前累积的所有奖励
     *      领取后，用户的累积奖励会被重置为 0
     * @custom:security 用户只能领取自己的奖励
     */
    function claim() external {
        uint256 amount = accrued[msg.sender];
        require(amount > 0, "no rewards");
        accrued[msg.sender] = 0;
        gov.mint(msg.sender, amount);
    }
}
```

> 说明：
> 该 RewardDistributor 可挂接在借贷逻辑里，例如用户借贷时按借款量累积 GOV 奖励，从而实现“流动性挖矿”模式。

---

## 4、测试示例：治理与奖励流

用 Foundry 编写测试验证完整流程：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovToken.sol";
import "../src/SimpleGovernor.sol";
import "../src/RewardDistributor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title GovernanceTest
 * @author DeFi Protocol Team
 * @notice 治理系统测试合约，测试奖励分发和投票流程
 * @dev 该测试合约验证治理代币的奖励分发机制和治理投票功能
 *      包括代币铸造、奖励累积、投票权委托和提案创建等核心功能
 */
contract GovernanceTest is Test {
    /// @notice 治理代币合约
    GovToken gov;

    /// @notice 时间锁控制器（测试中未使用，但保留用于未来扩展）
    TimelockController timelock;

    /// @notice 简化治理合约
    SimpleGovernor governor;

    /// @notice 奖励分发器合约
    RewardDistributor distributor;

    /// @notice 测试用户 Alice
    address alice = address(0x1);

    /// @notice 测试用户 Bob
    address bob = address(0x2);

    /**
     * @notice 测试设置函数，初始化所有合约和测试环境
     * @dev 部署所有必要的合约，设置测试用户，并分配初始代币
     */
    function setUp() public {
        gov = new GovToken();
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(this);
        executors[0] = address(this);

        timelock = new TimelockController(
            1 days,
            proposers,
            executors,
            address(this)
        );
        governor = new SimpleGovernor(gov);
        distributor = new RewardDistributor(gov, address(this));

        // give alice some tokens and delegate votes
        gov.transfer(alice, 50 ether); // give alice 50 tokens
        vm.prank(alice);
        gov.delegate(alice);
    }

    /**
     * @notice 测试奖励分发和投票流程的完整功能
     * @dev 该测试验证以下流程：
     *      1. 协议为用户累积奖励
     *      2. 用户领取奖励代币
     *      3. 用户创建治理提案
     *      4. 验证提案状态
     */
    function testRewardAndVoteFlow() public {
        // accrue rewards
        distributor.accrue(alice, 100 ether);
        vm.prank(alice);
        distributor.claim();

        assertEq(gov.balanceOf(alice), 150 ether); // 50 ether initial + 100 ether reward

        // advance block so voting power is available for proposal
        vm.roll(block.number + 1);

        // alice creates proposal
        vm.startPrank(alice);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mockAction()");

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Update parameter"
        );
        assertEq(uint256(governor.state(proposalId)), 0); // Pending
        vm.stopPrank();
    }

    /**
     * @notice 测试奖励分发器的基本功能
     * @dev 验证奖励累积和领取机制
     */
    function testRewardDistributorBasic() public {
        // 测试累积奖励
        distributor.accrue(alice, 50 ether);
        assertEq(distributor.accrued(alice), 50 ether);

        // 测试多次累积
        distributor.accrue(alice, 30 ether);
        assertEq(distributor.accrued(alice), 80 ether);

        // 测试领取奖励
        uint256 aliceBalanceBefore = gov.balanceOf(alice);
        vm.prank(alice);
        distributor.claim();

        assertEq(gov.balanceOf(alice), aliceBalanceBefore + 80 ether);
        assertEq(distributor.accrued(alice), 0);
    }

    /**
     * @notice 测试奖励分发器的权限控制
     * @dev 验证只有协议地址可以调用 accrue 函数
     */
    function testRewardDistributorAccessControl() public {
        // 非协议地址调用应该失败
        vm.prank(bob);
        vm.expectRevert("not protocol");
        distributor.accrue(alice, 50 ether);

        // 协议地址调用应该成功
        distributor.accrue(alice, 50 ether);
        assertEq(distributor.accrued(alice), 50 ether);
    }

    /**
     * @notice 测试无奖励时的领取行为
     * @dev 验证用户在没有累积奖励时无法领取
     */
    function testClaimWithNoRewards() public {
        vm.prank(alice);
        vm.expectRevert("no rewards");
        distributor.claim();
    }

    /**
     * @notice 测试治理合约的基本参数
     * @dev 验证投票延迟、投票期间、法定人数和提案阈值
     */
    function testGovernorParameters() public view {
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 45818);
        assertEq(governor.quorum(0), 100e18);
        assertEq(governor.proposalThreshold(), 10e18);
    }

    /**
     * @notice 测试提案创建权限
     * @dev 验证只有满足提案阈值的用户才能创建提案
     */
    function testProposalCreationPermissions() public {
        // 给 Bob 少量代币，不满足提案阈值
        gov.transfer(bob, 5 ether); // 5 tokens < 10 ether threshold
        vm.prank(bob);
        gov.delegate(bob);

        vm.roll(block.number + 1);

        // Bob 尝试创建提案应该失败
        vm.startPrank(bob);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mockAction()");

        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Test proposal");
        vm.stopPrank();
    }

    /**
     * @notice 测试投票权委托功能
     * @dev 验证代币持有者可以委托投票权
     */
    function testVoteDelegation() public {
        // 给 Bob 一些代币
        gov.transfer(bob, 20 ether);

        // Bob 委托给自己
        vm.prank(bob);
        gov.delegate(bob);

        // 验证投票权
        vm.roll(block.number + 1);
        assertEq(gov.getVotes(bob), 20 ether);

        // Bob 委托给 Alice
        vm.prank(bob);
        gov.delegate(alice);

        vm.roll(block.number + 1);
        assertEq(gov.getVotes(alice), 50 ether + 20 ether); // Alice 原有 + Bob 委托
        assertEq(gov.getVotes(bob), 0);
    }

    /**
     * @notice 测试提案状态转换
     * @dev 验证提案从 Pending 到 Active 的状态变化
     */
    function testProposalStateTransition() public {
        // 推进区块确保投票权可用
        vm.roll(block.number + 1);

        // Alice 创建提案
        vm.startPrank(alice);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mockAction()");

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Test proposal"
        );
        vm.stopPrank();

        // 初始状态应该是 Pending
        assertEq(uint256(governor.state(proposalId)), 0); // Pending

        // 推进投票延迟 + 1 个区块，应该变为 Active
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), 1); // Active
    }

    /**
     * @notice 测试多用户奖励分发
     * @dev 验证多个用户可以独立累积和领取奖励
     */
    function testMultipleUsersRewards() public {
        // 给 Bob 一些代币
        gov.transfer(bob, 20 ether);
        vm.prank(bob);
        gov.delegate(bob);

        // 为两个用户累积奖励
        distributor.accrue(alice, 100 ether);
        distributor.accrue(bob, 50 ether);

        // 验证累积奖励
        assertEq(distributor.accrued(alice), 100 ether);
        assertEq(distributor.accrued(bob), 50 ether);

        // Alice 领取奖励
        uint256 aliceBalanceBefore = gov.balanceOf(alice);
        vm.prank(alice);
        distributor.claim();
        assertEq(gov.balanceOf(alice), aliceBalanceBefore + 100 ether);
        assertEq(distributor.accrued(alice), 0);

        // Bob 的奖励应该保持不变
        assertEq(distributor.accrued(bob), 50 ether);

        // Bob 领取奖励
        uint256 bobBalanceBefore = gov.balanceOf(bob);
        vm.prank(bob);
        distributor.claim();
        assertEq(gov.balanceOf(bob), bobBalanceBefore + 50 ether);
        assertEq(distributor.accrued(bob), 0);
    }

    /**
     * @notice 测试复杂提案场景
     * @dev 验证包含多个目标和操作的提案
     */
    function testComplexProposal() public {
        vm.roll(block.number + 1);

        vm.startPrank(alice);
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        // 第一个操作：调用 mockAction
        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mockAction()");

        // 第二个操作：调用另一个函数
        targets[1] = address(this);
        values[1] = 0;
        calldatas[1] = abi.encodeWithSignature("anotherMockAction()");

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Complex proposal"
        );
        vm.stopPrank();

        assertEq(uint256(governor.state(proposalId)), 0); // Pending
    }

    /**
     * @notice 测试边界情况：零奖励
     * @dev 验证累积零奖励的行为
     */
    function testZeroRewardAccrual() public {
        distributor.accrue(alice, 0);
        assertEq(distributor.accrued(alice), 0);

        vm.prank(alice);
        vm.expectRevert("no rewards");
        distributor.claim();
    }

    /**
     * @notice 测试大额奖励
     * @dev 验证大额奖励的累积和领取
     */
    function testLargeReward() public {
        uint256 largeAmount = 1000000 ether; // 100万代币
        distributor.accrue(alice, largeAmount);

        uint256 aliceBalanceBefore = gov.balanceOf(alice);
        vm.prank(alice);
        distributor.claim();

        assertEq(gov.balanceOf(alice), aliceBalanceBefore + largeAmount);
        assertEq(distributor.accrued(alice), 0);
    }

    /**
     * @notice 模拟提案执行的目标函数
     * @dev 这是一个空的测试函数，用于模拟提案要执行的操作
     */
    function mockAction() external pure {}

    /**
     * @notice 另一个模拟提案执行的目标函数
     * @dev 用于测试复杂提案场景
     */
    function anotherMockAction() external pure {}
}
```

执行测试：  

```bash
➜  defi git:(master) ✗ forge test --match-path test/SimpleGovernor.t.sol -vvv
[⠊] Compiling...
[⠘] Compiling 1 files with Solc 0.8.30
[⠃] Solc 0.8.30 finished in 1.73s
Compiler run successful!

Ran 12 tests for test/SimpleGovernor.t.sol:GovernanceTest
[PASS] testClaimWithNoRewards() (gas: 13592)
[PASS] testComplexProposal() (gas: 79907)
[PASS] testGovernorParameters() (gas: 9772)
[PASS] testLargeReward() (gas: 69381)
[PASS] testMultipleUsersRewards() (gas: 211130)
[PASS] testProposalCreationPermissions() (gas: 140005)
[PASS] testProposalStateTransition() (gas: 79027)
[PASS] testRewardAndVoteFlow() (gas: 126945)
[PASS] testRewardDistributorAccessControl() (gas: 44705)
[PASS] testRewardDistributorBasic() (gas: 75545)
[PASS] testVoteDelegation() (gas: 195965)
[PASS] testZeroRewardAccrual() (gas: 19806)
Suite result: ok. 12 passed; 0 failed; 0 skipped; finished in 7.38ms (15.24ms CPU time)

Ran 1 test suite in 348.72ms (7.38ms CPU time): 12 tests passed, 0 failed, 0 skipped (12 total tests)
```

---

## 5、设计延伸与思考

### 5.1 veToken 模型（Curve 风格）

* 用户可锁仓治理代币（1 周 - 4 年）；
* 锁仓时间越长，投票权越大；
* 激励可根据投票权发放（veBoost）；
* 缺点：复杂、锁定灵活性差；
* 优点：促进长期治理与稳定性。

### 5.2 Fee Redistribution

借贷协议的手续费（如借款利息的 10%）可进入 Treasury：

* 50% 用于回购/销毁治理代币；
* 30% 分配给质押者（staking pool）；
* 20% 用于开发基金。

### 5.3 治理风险与攻击

| 问题      | 风险          | 缓解策略                          |
| ------- | ----------- | ----------------------------- |
| 闪电贷治理攻击 | 攻击者瞬时借入代币投票 | 采用 Snapshot / DelegateLock 机制 |
| 投票冷漠    | 投票率低，治理失灵   | 代理投票 / 激励投票                   |
| 延时执行过长  | 决策响应慢       | 紧急治理模块                        |
| 协议分叉治理  | 社区意见分裂      | Timelock + off-chain signal   |

---

## 6、总结

通过本课，你可以理解并掌握：

* 治理代币的意义、作用与设计方法；
* 去中心化治理的完整链路（Proposal → Vote → Timelock → Execute）；
* 激励分配机制（流动性挖矿、治理奖励、Fee 分配）；
* 如何在 Solidity 中快速实现一个最小可用的治理系统；
* 现实中 DAO 治理与经济模型的主要风险与改进方向。

---

## 7、作业（实践挑战）

1. **将本治理模块接入你的借贷平台**：
   * 在每次借款/还款时调用 `RewardDistributor.accrue()`；
   * 允许用户通过 `claim()` 获取代币激励。
2. **在 Governor 合约中加入“修改利率模型参数”的提案执行逻辑**，模拟社区决策。
3. **实现 veToken 模型**：用户锁仓代币获得投票权和收益，锁期越长权重越高。

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