---
layout: post
title: 《纸上谈兵·solidity》第 27 课：DAO 治理合约（去中心化自治组织）
tags: solidity
mermaid: false
math: false
---  

## 1、学习目标

1. 理解 **DAO 的核心理念**：由代币持有人共同治理
2. 学习实现 **提案（Proposal）+ 投票（Voting）+ 执行（Execution）** 流程
3. 引入 **治理代币（Governance Token）**，绑定投票权
4. 学习 **时间锁 Timelock**，防止恶意提案被立即执行

---

## 2、DAO 合约设计要点

* **治理代币**：每个代币 = 1 票
* **提案 Proposal**：由用户提交，包含目标地址 + 执行数据
* **投票 Voting**：代币持有人按比例投票，投票期内可投
* **执行 Execution**：提案通过后，由合约调用目标合约
* **时间锁 Timelock**：执行需等待一段时间（例如 2 天）

---

## 3、示例合约 `SimpleDAO.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimpleDAO - 简化版 DAO 治理合约
/// @notice 教学演示用，不可用于生产

interface IERC20 {
    function balanceOf(address account) external view returns (uint);
}

contract SimpleDAO {
    IERC20 public governanceToken;
    uint public proposalCount;
    uint public constant VOTING_PERIOD = 3 days;   // 投票期
    uint public constant TIMELOCK_DELAY = 2 days;  // 执行延迟
    uint public constant QUORUM = 100e18;          // 最低投票总数（100 票）

    enum ProposalState { Active, Defeated, Succeeded, Queued, Executed }

    struct Proposal {
        address proposer;
        address target;
        bytes data;
        string description;
        uint voteFor;
        uint voteAgainst;
        uint startTime;
        uint endTime;
        uint eta; // Estimated Time for execution
        ProposalState state;
    }

    mapping(uint => Proposal) public proposals;
    mapping(uint => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint id, address proposer, string description);
    event Voted(uint id, address voter, bool support, uint weight);
    event ProposalQueued(uint id, uint eta);
    event ProposalExecuted(uint id);

    constructor(address _token) {
        governanceToken = IERC20(_token);
    }

    /// @notice 创建提案
    function propose(address target, bytes calldata data, string calldata description) external {
        proposalCount++;
        proposals[proposalCount] = Proposal({
            proposer: msg.sender,
            target: target,
            data: data,
            description: description,
            voteFor: 0,
            voteAgainst: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            eta: 0,
            state: ProposalState.Active
        });

        emit ProposalCreated(proposalCount, msg.sender, description);
    }

    /// @notice 投票
    function vote(uint proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime, "voting not started");
        require(block.timestamp <= proposal.endTime, "voting ended");
        require(!hasVoted[proposalId][msg.sender], "already voted");

        uint weight = governanceToken.balanceOf(msg.sender);
        require(weight > 0, "no voting power");

        if (support) {
            proposal.voteFor += weight;
        } else {
            proposal.voteAgainst += weight;
        }

        hasVoted[proposalId][msg.sender] = true;
        emit Voted(proposalId, msg.sender, support, weight);
    }

    /// @notice 投票结果检查，并进入 Timelock 队列
    function queue(uint proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "voting not ended");
        require(proposal.state == ProposalState.Active, "not active");

        if (proposal.voteFor <= proposal.voteAgainst || proposal.voteFor < QUORUM) {
            proposal.state = ProposalState.Defeated;
        } else {
            proposal.state = ProposalState.Queued;
            proposal.eta = block.timestamp + TIMELOCK_DELAY;
            emit ProposalQueued(proposalId, proposal.eta);
        }
    }

    /// @notice 执行提案
    function execute(uint proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.Queued, "not queued");
        require(block.timestamp >= proposal.eta, "timelock not expired");

        (bool success, ) = proposal.target.call(proposal.data);
        require(success, "execution failed");

        proposal.state = ProposalState.Executed;
        emit ProposalExecuted(proposalId);
    }
}
```

---

## 4、测试文件 test/SimpleDAO.t.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleDAO.sol";

/// @notice 简单的治理代币 (ERC20-like)
contract GovernanceToken is IERC20 {
    string public name = "GovToken";
    string public symbol = "GOV";
    uint8 public decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    function mint(address to, uint amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @notice 被治理的目标合约（DAO 将控制它）
contract TargetContract {
    uint public value;

    function setValue(uint _value) external {
        value = _value;
    }
}

contract SimpleDAOTest is Test {
    GovernanceToken public gov;
    SimpleDAO public dao;
    TargetContract public target;

    address alice = address(0x123);
    address bob = address(0x234);

    function setUp() public {
        gov = new GovernanceToken();
        dao = new SimpleDAO(address(gov));
        target = new TargetContract();

        // 给 Alice 和 Bob 铸造治理代币
        gov.mint(alice, 100e18);
        gov.mint(bob, 50e18);
    }

    /// @notice 测试完整的提案生命周期
    function testProposalLifecycle() public {
        vm.startPrank(alice);

        // Alice 提出一个提案：调用 target.setValue(42)
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        dao.propose(address(target), data, "Set value to 42");

        vm.stopPrank();

        // Alice 投支持票
        vm.startPrank(alice);
        dao.vote(1, true);
        vm.stopPrank();

        // Bob 投反对票
        vm.startPrank(bob);
        dao.vote(1, false);
        vm.stopPrank();

        // 快进 3 天，投票结束
        vm.warp(block.timestamp + 3 days + 1);

        // 进入 Timelock 队列
        dao.queue(1);

        // 立即执行应失败（需要 timelock）
        vm.expectRevert();
        dao.execute(1);

        // 再快进 2 天
        vm.warp(block.timestamp + 2 days);

        // 执行提案
        dao.execute(1);

        // 验证目标合约的值已被修改
        assertEq(target.value(), 42);
    }
}
```  

执行测试：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/SimpleDAO.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 551.36ms
Compiler run successful!

Ran 1 test for test/SimpleDAO.t.sol:SimpleDAOTest
[PASS] testProposalLifecycle() (gas: 416882)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 5.95ms (2.33ms CPU time)

Ran 1 test suite in 165.45ms (5.95ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 5、本课总结

* DAO 合约的基本三步：**提案 → 投票 → 执行**
* 引入 **时间锁（Timelock）** 防止提案立即执行
* 结合治理代币，DAO 就能实现 **链上自治决策**
* 真实项目中，DAO 还会增加：代理投票、提案执行脚本、资金库控制等


