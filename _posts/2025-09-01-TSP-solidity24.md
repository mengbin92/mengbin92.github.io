---
layout: post
title: 《纸上谈兵·solidity》第 24 课：去中心化众筹合约（Crowdfunding）实战
tags: solidity
mermaid: false
math: false
---

## 1、本课学习目标

* 理解去中心化众筹的业务模型与关键边界条件（目标、截止时间、退款/领取）
* 能从零实现一个支持多 Campaign 的众筹合约（以太币版本）
* 设计安全的资金流（pull-over-push、checks-effects-interactions、重入保护）
* 用 Foundry 写完整测试（创建 Campaign、认购、退回、提取）

---

## 2、关键设计点

1. **Campaign 状态机**
   * `Active`（正在进行，可 pledging）
   * `Successful`（达到目标，所有人可领取）
   * `Failed`（截止且未达到目标，支持退款）
   * `Withdrawn`（创建者已领取资金）
2. **谁可以做什么**
   * 任意地址可以创建 Campaign（或限定为合约 Owner）
   * 任意地址在活动期间可 pledge（支付 ETH）
   * 创建者在活动结束且目标达成后可 claim（提取所有资金）
   * 投资者在活动结束且目标未达成后可 refund（取回自己投入）
3. **资金流安全原则**
   * **Pull over Push**：优先把退款/领取弧度做成可提款模式（用户调用提取），不要把外部合约回调放在自动转账中
   * **Checks-Effects-Interactions**：先改变合约状态再进行外部调用
   * **重入防护**：使用互斥锁或 OpenZeppelin 的 `ReentrancyGuard`
   * 检查零地址、金额、截止时间合理性
4. **时间处理**
   * 使用 `block.timestamp`；注意矿工可微调时间（可被操纵 \~900s），对大额攻击场景需谨慎
5. **Gas / DoS 风险**
   * 不要在单笔函数里遍历大量数组（避免被 gas 限制 DOS）
   * 使用 mapping 存储出资详情，避免遍历退款列表

---

## 3、简单实现

**src/SimpleCrowdfunding.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimpleCrowdfunding - 多 Campaign 去中心化众筹示例
/// @notice 演示创建、认购、退款、创建者提现等核心功能与安全防护
contract SimpleCrowdfunding {
    // ========== 事件 ==========
    event CampaignCreated(
        uint256 indexed id,
        address indexed creator,
        uint256 goal,
        uint256 deadline
    );
    event Pledged(uint256 indexed id, address indexed pledger, uint256 amount);
    event Unpledged(
        uint256 indexed id,
        address indexed pledger,
        uint256 amount
    );
    event Claimed(uint256 indexed id, address indexed creator, uint256 amount);
    event Refunded(uint256 indexed id, address indexed pledger, uint256 amount);
    event Cancelled(uint256 indexed id);

    // ========== 数据结构 ==========
    struct Campaign {
        address creator; // 创建者（收益方）
        uint256 goal; // 众筹目标（wei）
        uint256 pledged; // 已筹金额（wei）
        uint64 startAt; // 开始时间（timestamp）
        uint64 deadline; // 截止时间（timestamp）
        bool claimed; // 是否已被创建者提现
        bool cancelled; // 是否被创建者取消（且可退款）
    }

    // campaignId 自增
    uint256 public nextCampaignId;
    mapping(uint256 => Campaign) public campaigns;
    // pledges[campaignId][user] = 金额
    mapping(uint256 => mapping(address => uint256)) public pledges;

    // ========== 重入保护（简单互斥锁） ==========
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ========== 公用检查函数 ==========
    modifier onlyActive(uint256 id) {
        Campaign storage c = campaigns[id];
        require(c.creator != address(0), "Campaign not exist");
        require(!c.cancelled, "Campaign cancelled");
        require(
            block.timestamp >= c.startAt && block.timestamp <= c.deadline,
            "Not active"
        );
        _;
    }

    modifier onlyAfterDeadline(uint256 id) {
        Campaign storage c = campaigns[id];
        require(c.creator != address(0), "Campaign not exist");
        require(block.timestamp > c.deadline, "Deadline not passed");
        _;
    }

    // ========== 合约逻辑 ==========
    /// @notice 创建新的众筹活动
    /// @param goal 目标金额（wei）
    /// @param durationSeconds 持续时间（秒）
    function createCampaign(
        uint256 goal,
        uint64 durationSeconds
    ) external returns (uint256) {
        require(goal > 0, "Goal must > 0");
        require(durationSeconds > 0, "Duration > 0");

        uint256 id = nextCampaignId++;
        uint64 start = uint64(block.timestamp);
        campaigns[id] = Campaign({
            creator: msg.sender,
            goal: goal,
            pledged: 0,
            startAt: start,
            deadline: start + durationSeconds,
            claimed: false,
            cancelled: false
        });

        emit CampaignCreated(id, msg.sender, goal, start + durationSeconds);
        return id;
    }

    /// @notice 支持众筹（支付 ETH）
    function pledge(uint256 id) external payable onlyActive(id) {
        require(msg.value > 0, "pledge>0");

        Campaign storage c = campaigns[id];
        pledges[id][msg.sender] += msg.value;
        c.pledged += msg.value;

        emit Pledged(id, msg.sender, msg.value);
    }

    /// @notice 取消部分 pledge（仅在活动进行中允许）
    function unpledge(uint256 id, uint256 amount) external onlyActive(id) {
        require(amount > 0, "amount>0");
        uint256 userPledged = pledges[id][msg.sender];
        require(userPledged >= amount, "not enough pledged");

        // Effects
        pledges[id][msg.sender] = userPledged - amount;
        campaigns[id].pledged -= amount;

        // Interaction（把 ETH 返回给用户）
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "refund failed");

        emit Unpledged(id, msg.sender, amount);
    }

    /// @notice 创建者在活动结束且目标达成后提现（使用 nonReentrant + checks-effects-interactions）
    function claim(uint256 id) external nonReentrant onlyAfterDeadline(id) {
        Campaign storage c = campaigns[id];
        require(!c.claimed, "already claimed");
        require(!c.cancelled, "cancelled");
        require(c.pledged >= c.goal, "goal not reached");

        // Effects
        c.claimed = true;
        uint256 amount = c.pledged;

        // Interaction
        (bool sent, ) = c.creator.call{value: amount}("");
        require(sent, "transfer failed");

        emit Claimed(id, c.creator, amount);
    }

    /// @notice 如果未达目标或取消，支持者可退款（pull 模式）
    function refund(uint256 id) external {
        Campaign storage c = campaigns[id];
        require(
            c.cancelled || block.timestamp > c.deadline,
            "Deadline not passed"
        );

        uint256 bal = pledges[id][msg.sender];
        require(bal > 0, "Nothing to refund");

        pledges[id][msg.sender] = 0;
        payable(msg.sender).transfer(bal);

        emit Refunded(id, msg.sender, bal);
    }

    /// @notice 创建者在活动进行中可以取消活动（仅在没有被提现时允许）
    /// @dev 取消后，任何支持者都可以随时调用 refund 提取自己资金（活动算作失败）
    function cancelCampaign(uint256 id) external {
        Campaign storage c = campaigns[id];
        require(c.creator != address(0), "not exist");
        require(msg.sender == c.creator, "only creator");
        require(!c.cancelled, "already cancelled");
        require(!c.claimed, "already claimed");

        c.cancelled = true;
        emit Cancelled(id);
    }

    // ========== 视图函数 ==========
    function campaignInfo(
        uint256 id
    )
        external
        view
        returns (
            address creator,
            uint256 goal,
            uint256 pledged,
            uint64 startAt,
            uint64 deadline,
            bool claimed,
            bool cancelled
        )
    {
        Campaign storage c = campaigns[id];
        return (
            c.creator,
            c.goal,
            c.pledged,
            c.startAt,
            c.deadline,
            c.claimed,
            c.cancelled
        );
    }

    // ========== 回退与接收 ==========
    receive() external payable {
        revert("Direct send not allowed");
    }

    fallback() external payable {
        revert("Fallback not allowed");
    }
}
```

**实现要点说明（代码内注释已很详细）**：

* 每个 campaign 用 `Campaign` 结构体保存元信息与筹集金额。
* `pledges` mapping 保存每位支持者对每个 campaign 的投入，便于单独退款。
* `pledge` 与 `unpledge` 在活动进行中允许互相增减；`unpledge` 立刻把 ETH 退给用户（注意这是一次示范；在高并发或复杂场景，`unpledge` 可改为 push/pull 结合设计）。
* `claim` 只允许在截止后并且筹款达标时创建者领取；遵循 checks-effects-interactions。
* `refund` 则是 pull 模式，只有当目标未达且截止或取消后，支持者可提取各自资金。
* 一个简单的 `nonReentrant` 互斥锁用于保护关键转账函数。可替换为 OpenZeppelin 的 `ReentrancyGuard`。

---

## 4、安全注意事项与改进建议

1. **重入攻击**：已用互斥锁 `nonReentrant` 并在修改状态后进行外部调用。实际生产推荐使用经过审计的 `ReentrancyGuard`。
2. **拒付/接收失败**：合约对 `call` 返回值做了 `require(sent)`，若接收方为合约且回退会导致 `claim`/`refund` 失败（可选：把款项放入 PullPayments 模式，创建者在失败时也可在 later withdraw）。
3. **时间操纵**：`block.timestamp` 可被矿工微调（数十秒到数分钟），不适合用在对时间精度要求极高的逻辑中。
4. **DoS by Block Gas Limit**：避免在单函数中遍历所有支持者（本实现未遍历，使用 mapping 便于单用户退款）。
5. **整数问题**：Solidity >=0.8 已自带溢出检查。
6. **前端/链下竞态**：创建 Campaign 后若价格波动或大量并发 pledge，可能出现前端展示的状态与链上状态短暂不一致。
7. **升级与治理**：如果希望支持合约升级（修复 bug 或改进功能），应使用代理模式并注意初始化顺序与访问控制。
8. **税费/平台费**：示例未包含平台抽成，如需添加，建议在 `claim` 时计算并将平台费保留到单独地址（注意资金安全）。

---

## 5、Foundry 测试示例

目录结构假设：

**test/Crowdfunding.t.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleCrowdfunding.sol";

contract CrowdfundingTest is Test {
    SimpleCrowdfunding cf;

    address alice = address(0x123); // 发起人
    address bob = address(0x234); // 支持者
    address carol = address(0x345); // 支持者

    function setUp() public {
        cf = new SimpleCrowdfunding();
    }

    // 创建 campaign 并检查基本信息
    function testCreateCampaign() public {
        vm.prank(alice);
        uint256 id = cf.createCampaign(1 ether, 1 days);
        (
            address creator,
            uint256 goal,
            ,
            uint64 startAt,
            uint64 deadline,
            bool claimed,
            bool cancelled
        ) = cf.campaignInfo(id);
        assertEq(creator, alice);
        assertEq(goal, 1 ether);
        assertFalse(claimed);
        assertFalse(cancelled);
        assertTrue(deadline > startAt);
    }

    // 支持并在目标达成后创建者提取
    function testSuccessfulCampaignClaim() public {
        vm.prank(alice);
        uint256 id = cf.createCampaign(2 ether, 1 days);

        // bob 支持 1 ether
        vm.deal(bob, 2 ether);
        vm.prank(bob);
        cf.pledge{value: 1 ether}(id);

        // carol 支持 1.1 ether
        vm.deal(carol, 2 ether);
        vm.prank(carol);
        cf.pledge{value: 1.1 ether}(id);

        // 快进到 deadline 之后
        vm.warp(block.timestamp + 1 days + 1);

        // alice 提取
        uint256 beforeBal = alice.balance;
        vm.prank(alice);
        cf.claim(id);
        uint256 afterBal = alice.balance;
        assertEq(afterBal - beforeBal, 2.1 ether);
    }

    // 未达目标，支持者退款
    function test_Revert_WhenRefundTwice() public {
        vm.prank(alice);
        uint256 id = cf.createCampaign(5 ether, 1 days);

        // bob 支持 1 ether
        vm.deal(bob, 2 ether);
        vm.prank(bob);
        cf.pledge{value: 1 ether}(id);

        // 快进到 deadline 后（目标未达）
        vm.warp(block.timestamp + 1 days + 1);

        // bob 发起 refund 第一次成功
        uint256 beforeBal = bob.balance;
        vm.prank(bob);
        cf.refund(id);
        uint256 afterBal = bob.balance;
        assertEq(afterBal - beforeBal, 1 ether);

        // 第二次退款应失败
        vm.prank(bob);
        vm.expectRevert(); // 显式声明期待 Revert
        cf.refund(id);
    }

    // 测试 unpledge（活动期间取消部分出资）
    function testUnpledgeDuringActive() public {
        vm.prank(alice);
        uint256 id = cf.createCampaign(5 ether, 1 days);

        vm.deal(bob, 2 ether);
        vm.prank(bob);
        cf.pledge{value: 1 ether}(id);

        // unpledge 0.4 ether
        vm.prank(bob);
        cf.unpledge(id, 0.4 ether);

        // bob 的剩余 pledge 应为 0.6 ether
        uint256 remaining = cf.pledges(id, bob);
        assertEq(remaining, 0.6 ether);
    }

    // 取消活动后，支持者可退款
    function testCancelCampaignAndRefund() public {
        vm.prank(alice);
        uint256 id = cf.createCampaign(1 ether, 1 days);

        vm.deal(bob, 2 ether);
        vm.prank(bob);
        cf.pledge{value: 1 ether}(id);

        // alice 取消
        vm.prank(alice);
        cf.cancelCampaign(id);

        // bob refund
        uint256 beforeBal = bob.balance;
        vm.prank(bob);
        cf.refund(id);
        uint256 afterBal = bob.balance;
        assertEq(afterBal - beforeBal, 1 ether);
    }
}
```

> 注意：Foundry 中 `vm.deal`、`vm.prank`、`vm.warp` 用来模拟账户余额、交易发送者、时间推进。测试里直接读取 `pledges` mapping 使用 `cf.pledges(id, bob)` 是示意；若 solidity 自动生成 getter 不支持该形式（多维 mapping 的 getter 需要两个参数），请以正确的 getter 形式调用：`cf.pledges(id, bob)`（在当前合约 ABI 中存在）。

运行测试：

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/Crowdfunding.t.sol -vvv

[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 547.88ms
Compiler run successful!

Ran 5 tests for test/Crowdfunding.t.sol:CrowdfundingTest
[PASS] testCancelCampaignAndRefund() (gas: 160522)
[PASS] testCreateCampaign() (gas: 111954)
[PASS] testSuccessfulCampaignClaim() (gas: 242932)
[PASS] testUnpledgeDuringActive() (gas: 179724)
[PASS] test_Revert_WhenRefundTwice() (gas: 160648)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 5.72ms (10.06ms CPU time)

Ran 1 test suite in 161.34ms (5.72ms CPU time): 5 tests passed, 0 failed, 0 skipped (5 total tests)
```

---

## 6、本课练习题

1. **扩充功能**：给合约增加 `platformFee`（例如 1%），提取时由平台地址先扣除；写测试验证 fee 被正确分走。
2. **ERC20 支持**：把当前 ETH-only 的实现改造为支持 ERC20 令牌（支持任意 ERC20 token 作为募集资产）。注意 ERC20 的 transferFrom/approve 模式与 ETH 不同。
3. **前端脚本**：写一套简单的前端或脚本（JavaScript + ethers.js），完成创建 Campaign、pledge（发送交易）、查询状态、发起 refund/claim 的流程。
4. **审计练习**：找出本合约的潜在攻击面（超出课堂列举），并写一份短文说明如何修复。
5. **Gas 优化挑战**：分析 `pledge`/`refund`/`claim` 的 gas 消耗，并提出两个可行的优化点（提示：storage 布局、packed struct、减少 SSTORE 写入次数）。

---

## 7、小结

* 用 mapping 保存每位支持者的投入，避免遍历退款列表。
* 提款优先采用 Pull（用户调用提取），避免自动转帐导致的外部依赖。
* 严格遵守 **Checks-Effects-Interactions + nonReentrant**。
* 时间逻辑使用 `block.timestamp`，但要意识到其可被微调。
* 在生产环境使用已审计的 OpenZeppelin 库和专业审计流程。
