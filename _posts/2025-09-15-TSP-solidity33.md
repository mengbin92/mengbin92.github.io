---
layout: post
title: 《纸上谈兵·solidity》第 33 课：多签钱包（Multisig Wallet）-- 合约设计与实现
tags: solidity
mermaid: false
math: false
---  

## 课程目标

学完本课你将能：

* 设计符合生产需求的多签钱包（支持 ETH / ERC20 支出、提案/确认/撤销/执行流程）；
* 用 Solidity 编写安全、可审计的多签合约（包含事件、权限与防重入）；
* 写基本的测试（Foundry示例），并用前端与合约交互（React + ethers.js）；
* 理解多签在治理/部署/运维中的最佳实践与安全注意事项。

---

## 1. 设计要点（需求与安全约束）

在着手编码前，先确认需求与基本安全约束：

必须支持：

* 多个管理员（owners），阈值 `required`（例如 2/3）；
* 提交交易（目标地址、value、data）成为提案；
* 多个 owner 对提案进行确认（同意）；
* 达到阈值后任何人可执行；执行前要再次检查阈值与未执行状态；
* 能接收 ETH（receive / fallback）；
* 支持 ERC20 支付（通过执行任意 call 实现）；
* 事件完善，便于链上/离线审计日志；
* 防重入、Checks-Effects-Interactions（CEI）模式、以及对 ERC20 不返回 bool 的兼容性处理（wrapper 或低层调用）。

可选（建议）：

* 提案超时 / 自动失效；
* 可由多签自身变更 owner 或阈值（通过被多签执行的特殊交易）；
* 日限额（daily limit）或 timelock（延时执行）；
* 多签与 Gnosis Safe 等集成或支持代理升级（慎重）。

---

## 2. 合约实现（简洁版）

下面给出一个简洁而安全的多签钱包实现（受 Gnosis /经典MultiSig启发），适合作为课程代码基础。注意：生产前仍需审计与更多边界测试。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimpleMultisig - 多签钱包合约
 * @notice 支持多签交易管理，允许所有者提交、确认和执行交易
 * @dev 该合约实现了多签钱包的核心功能，包括交易生命周期管理和所有者管理
 */

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SimpleMultisig is ReentrancyGuard {
    /* ========== EVENTS ========== */
    /// @notice ETH 存款事件
    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    /// @notice 交易提交事件
    event SubmitTransaction(uint256 indexed txId, address indexed destination, uint256 value, bytes data, address indexed proposer);

    /// @notice 交易确认事件
    event ConfirmTransaction(address indexed owner, uint256 indexed txId);

    /// @notice 交易撤销确认事件
    event RevokeConfirmation(address indexed owner, uint256 indexed txId);

    /// @notice 交易执行事件
    event ExecuteTransaction(address indexed owner, uint256 indexed txId, bool success, bytes returnData);

    /// @notice 所有者添加事件
    event OwnerAdded(address indexed owner);

    /// @notice 所有者移除事件
    event OwnerRemoved(address indexed owner);

    /// @notice 确认需求变更事件
    event RequirementChanged(uint256 required);

    /* ========== STATE ========== */
    /// @notice 所有者地址映射
    mapping(address => bool) public isOwner;

    /// @notice 所有者地址列表
    address[] public owners;

    /// @notice 交易执行所需的最小确认数
    uint256 public required;

    /// @notice 交易结构体
    struct Transaction {
        address destination; // 目标地址
        uint256 value;       // 转账金额
        bytes data;         // 调用数据
        bool executed;      // 是否已执行
        uint256 numConfirmations; // 确认数
    }

    /// @notice 交易列表
    Transaction[] public transactions;

    /// @notice 交易确认状态映射
    mapping(uint256 => mapping(address => bool)) public confirmations;

    /* ========== MODIFIERS ========== */
    /// @notice 仅所有者修饰符
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    /// @notice 交易存在修饰符
    modifier txExists(uint256 _txId) {
        require(_txId < transactions.length, "Tx does not exist");
        _;
    }

    /// @notice 交易未执行修饰符
    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "Tx already executed");
        _;
    }

    /// @notice 交易未确认修饰符
    modifier notConfirmed(uint256 _txId) {
        require(!confirmations[_txId][msg.sender], "Tx already confirmed by caller");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    /**
     * @notice 构造函数
     * @param _owners 初始所有者列表
     * @param _required 交易执行所需的最小确认数
     */
    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required number");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
            emit OwnerAdded(owner);
        }
        required = _required;
        emit RequirementChanged(required);
    }

    /* ========== FALLBACKS ========== */
    /// @notice 接收 ETH 的回调函数
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /// @notice 默认回调函数
    fallback() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /* ========== OWNER MANAGEMENT ========== */
    /**
     * @notice 添加所有者
     * @dev 仅限当前所有者调用
     * @param _owner 新所有者地址
     */
    function addOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "Invalid owner");
        require(!isOwner[_owner], "Already owner");
        isOwner[_owner] = true;
        owners.push(_owner);
        emit OwnerAdded(_owner);
    }

    /**
     * @notice 移除所有者
     * @dev 仅限当前所有者调用
     * @param _owner 要移除的所有者地址
     */
    function removeOwner(address _owner) external onlyOwner {
        require(isOwner[_owner], "Not owner");
        isOwner[_owner] = false;
        // 从所有者列表中移除
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        // 如果所需确认数大于当前所有者数量，则调整
        if (required > owners.length) {
            required = owners.length;
            emit RequirementChanged(required);
        }
        emit OwnerRemoved(_owner);
    }

    /**
     * @notice 修改所需确认数
     * @dev 仅限当前所有者调用
     * @param _required 新的所需确认数
     */
    function changeRequirement(uint256 _required) external onlyOwner {
        require(_required > 0 && _required <= owners.length, "Invalid required");
        required = _required;
        emit RequirementChanged(_required);
    }

    /* ========== TRANSACTION LIFECYCLE ========== */
    /**
     * @notice 提交交易
     * @dev 仅限所有者调用
     * @param _destination 目标地址
     * @param _value 转账金额
     * @param _data 调用数据
     * @return txId 交易 ID
     */
    function submitTransaction(address _destination, uint256 _value, bytes calldata _data) external onlyOwner returns (uint256) {
        uint256 txId = transactions.length;
        transactions.push(Transaction({
            destination: _destination,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        }));
        emit SubmitTransaction(txId, _destination, _value, _data, msg.sender);
        return txId;
    }

    /**
     * @notice 确认交易
     * @dev 仅限所有者调用
     * @param _txId 交易 ID
     */
    function confirmTransaction(uint256 _txId) external onlyOwner txExists(_txId) notExecuted(_txId) notConfirmed(_txId) {
        confirmations[_txId][msg.sender] = true;
        transactions[_txId].numConfirmations += 1;
        emit ConfirmTransaction(msg.sender, _txId);
    }

    /**
     * @notice 撤销交易确认
     * @dev 仅限所有者调用
     * @param _txId 交易 ID
     */
    function revokeConfirmation(uint256 _txId) external onlyOwner txExists(_txId) notExecuted(_txId) {
        require(confirmations[_txId][msg.sender], "Tx not confirmed");
        confirmations[_txId][msg.sender] = false;
        transactions[_txId].numConfirmations -= 1;
        emit RevokeConfirmation(msg.sender, _txId);
    }

    /**
     * @notice 执行交易
     * @dev 仅限所有者调用
     * @param _txId 交易 ID
     */
    function executeTransaction(uint256 _txId) external nonReentrant onlyOwner txExists(_txId) notExecuted(_txId) {
        Transaction storage txn = transactions[_txId];
        require(txn.numConfirmations >= required, "Not enough confirmations");

        txn.executed = true; // CEI: 执行前设置状态

        (bool success, bytes memory returnData) = txn.destination.call{value: txn.value}(txn.data);
        emit ExecuteTransaction(msg.sender, _txId, success, returnData);
        require(success, "Tx execution failed");
    }

    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @notice 获取所有者列表
     * @return 所有者地址数组
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice 获取交易数量
     * @return 交易数量
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @notice 获取交易详情
     * @param _txId 交易 ID
     * @return destination 目标地址
     * @return value 转账金额
     * @return data 调用数据
     * @return executed 是否已执行
     * @return numConfirmations 确认数
     */
    function getTransaction(uint256 _txId) external view returns (
        address destination,
        uint256 value,
        bytes memory data,
        bool executed,
        uint256 numConfirmations
    ) {
        Transaction storage t = transactions[_txId];
        return (t.destination, t.value, t.data, t.executed, t.numConfirmations);
    }

    /**
     * @notice 检查交易是否被某所有者确认
     * @param _txId 交易 ID
     * @param _owner 所有者地址
     * @return 是否已确认
     */
    function isConfirmed(uint256 _txId, address _owner) external view returns (bool) {
        return confirmations[_txId][_owner];
    }
}
```

**实现说明（关键点）**

* `executeTransaction` 在做外部 call 前先把 `executed = true`，符合 CEI，结合 `nonReentrant` 进一步防止重入。
* 通过 `destination.call{value:...}(data)` 支持任意合约调用（ERC20 转账、approve、合约交互等）。
* `addOwner` / `removeOwner` / `changeRequirement` 是 `onlyOwner` 的；生产中建议**只能通过 multisig 自身执行**（即由所有者提交但不能被单个 owner 直接调用）。本示例放开权限以便教学；实际应把这些方法做为 `internal` 或 require msg.sender == address(this)（通过 multisig 自己提交的 tx）来强制 governance。
* 对于 ERC20 的不返回 bool 情形，调用方应使用低级 call；在本多签，外部调用目标合约会自己处理（前端/脚本在构造 data 时应使用 token 的 ABI 或直接发送 tx）。

---

## 3. 测试（Foundry 示例片段）

下面是部分接口的测试，测试要点：提案提交、确认、执行、ETH收发、ERC20 调用。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleMultisig.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DummyToken - 模拟 ERC20 代币合约
 * @notice 用于测试 SimpleMultisig 合约的模拟代币
 */
contract DummyToken is ERC20 {
    /**
     * @notice 构造函数
     * @dev 初始化代币名称、符号和铸造初始供应量
     */
    constructor() ERC20("Dummy", "DUM") {
        _mint(msg.sender, 1000e18);
    }
}

/**
 * @title MultisigTest - SimpleMultisig 合约的测试
 * @notice 测试 SimpleMultisig 合约的功能
 */
contract MultisigTest is Test {
    /// @notice SimpleMultisig 合约实例
    SimpleMultisig multisig;

    /// @notice 模拟 ERC20 代币合约
    DummyToken token;

    /// @notice 所有者地址
    address owner1 = address(0x123);
    address owner2 = address(0x234);
    address owner3 = address(0x345);

    /// @notice 普通用户地址
    address user = address(0x456);

    /**
     * @notice 初始化测试环境
     * @dev 设置初始 ETH 余额、所有者和多签合约
     */
    function setUp() public {
        // 分配 ETH 余额
        vm.deal(address(this), 10 ether);
        vm.deal(owner1, 1 ether);
        vm.deal(owner2, 1 ether);
        vm.deal(owner3, 1 ether);

        // 初始化多签合约
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        multisig = new SimpleMultisig(owners, 2);

        // 初始化模拟代币并转移部分到多签合约
        token = new DummyToken();
        token.transfer(address(multisig), 1000e18);
    }

    /**
     * @notice 测试 ETH 交易的提交、确认和执行
     * @dev 验证 ETH 转账功能是否正常
     */
    function testSubmitConfirmExecuteETH() public {
        // owner1 提交并确认交易
        vm.startPrank(owner1);
        uint256 txId = multisig.submitTransaction(user, 1 ether, "");
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // owner2 确认交易
        vm.startPrank(owner2);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // 执行交易
        vm.startPrank(owner1);
        payable(address(multisig)).transfer(1 ether); // 提供 ETH 资金
        multisig.executeTransaction(txId);
        vm.stopPrank();

        // 验证用户 ETH 余额
        assertEq(address(user).balance, 1 ether);
    }

    /**
     * @notice 测试 ETH 交易确认不足时的回滚
     * @dev 验证确认不足时交易执行失败
     */
    function test_RevertIf_NotEnoughConfirmations_ExecuteETH() public {
        // owner1 提交交易
        vm.startPrank(owner1);
        uint256 txId = multisig.submitTransaction(user, 1 ether, "");
        vm.stopPrank();

        // owner2 确认交易
        vm.startPrank(owner2);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // 执行交易（预期失败）
        vm.startPrank(owner1);
        payable(address(multisig)).transfer(1 ether); // 提供 ETH 资金
        vm.expectRevert("Not enough confirmations");
        multisig.executeTransaction(txId);
        vm.stopPrank();

        // 验证用户 ETH 余额未变化
        assertEq(address(user).balance, 0 ether);
    }

    /**
     * @notice 测试 ERC20 代币转账
     * @dev 验证多签合约可以执行 ERC20 转账
     */
    function testExecuteERC20Transfer() public {
        // 构造 ERC20 转账数据
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            user,
            10e18
        );

        // owner1 提交交易
        vm.startPrank(owner1);
        uint256 txId = multisig.submitTransaction(address(token), 0, data);
        vm.stopPrank();

        // owner2 确认交易
        vm.startPrank(owner2);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // owner3 确认交易
        vm.startPrank(owner3);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // 执行交易
        vm.startPrank(owner1);
        multisig.executeTransaction(txId);
        vm.stopPrank();

        // 验证用户代币余额
        assertEq(token.balanceOf(user), 10e18);
    }

    /**
     * @notice 测试 ERC20 交易确认不足时的回滚
     * @dev 验证确认不足时 ERC20 转账失败
     */
    function test_RevertIf_NotEnoughConfirmations_ExecuteERC20Transfer()
        public
    {
        // 构造 ERC20 转账数据
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            user,
            10e18
        );

        // owner1 提交交易
        vm.startPrank(owner1);
        uint256 txId = multisig.submitTransaction(address(token), 0, data);
        vm.stopPrank();

        // owner2 确认交易
        vm.startPrank(owner2);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // 执行交易（预期失败）
        vm.startPrank(owner1);
        vm.expectRevert("Not enough confirmations");
        multisig.executeTransaction(txId);
        vm.stopPrank();

        // 验证用户代币余额未变化
        assertEq(token.balanceOf(user), 0);
    }

    /**
     * @notice 测试撤销交易确认
     * @dev 验证撤销交易确认是否正常
     */
    function testRevokeConfirmExecuteETH() public {
        // owner1 提交并确认交易
        vm.startPrank(owner1);
        uint256 txId = multisig.submitTransaction(user, 1 ether, "");
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        // owner2 确认交易
        vm.startPrank(owner2);
        multisig.confirmTransaction(txId);
        vm.stopPrank();

        payable(address(multisig)).transfer(1 ether); // 提供 ETH 资金

        // 执行交易
        vm.startPrank(owner1);
        multisig.revokeConfirmation(txId);
        vm.expectRevert("Not enough confirmations");
        multisig.executeTransaction(txId);
        vm.stopPrank();

        // 验证用户 ETH 余额
        assertEq(address(user).balance, 0 ether);
    }
}
```

**测试要点**

* 用 `vm.deal` / `vm.startPrank` 模拟多签 owner。
* 测试 ETH 提案需先确保合约里有足够余额（测试里直接向合约转 ETH）。
* 测试 ERC20 通过构造 ABI data 调用 token contract 的 `transfer` 方法。

**执行测试**：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/MultisigTest.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 573.34ms
Compiler run successful!

Ran 4 tests for test/MultisigTest.t.sol:MultisigTest
[PASS] testExecuteERC20Transfer() (gas: 315292)
[PASS] testSubmitConfirmExecuteETH() (gas: 247698)
[PASS] test_RevertIf_NotEnoughConfirmations_ExecuteERC20Transfer() (gas: 233708)
[PASS] test_RevertIf_NotEnoughConfirmations_ExecuteETH() (gas: 168993)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 1.51ms (843.67µs CPU time)

Ran 1 test suite in 151.18ms (1.51ms CPU time): 4 tests passed, 0 failed, 0 skipped (4 total tests)
```

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