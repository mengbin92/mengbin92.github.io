---
layout: post
title: 《纸上谈兵·solidity》第 31 课：多签钱包在跨链桥中的应用 —— Nomad 事件复盘
tags: solidity
mermaid: false
math: false
---  

## 1. 什么是多签（Multi-Signature Wallet）

**多签钱包（Multisig）** 就是需要多个签名（多个私钥持有者）共同批准，交易才能执行的钱包。

* **普通钱包（EOA）**：只要有 1 个私钥，就能随意转账。
* **多签钱包**：需要满足某个门槛（例如 3/5，表示 5 个签名人中至少 3 个签名），交易才会被执行。

实现上常用的模式：

* **Gnosis Safe** 是以太坊生态里最常见的多签合约。
* 在合约层面，通常设计为：提交交易 → 收集签名 → 达到门槛后 `execute()`。

好处：

* 单个私钥丢失不会直接导致资金丢失。
* 大额交易需要多方确认，能降低误操作或被攻击的风险。

---

## 2. Nomad Bridge 漏洞复现里发生了什么

在[上节课程](./2025-09-08-TSP-solidity30.md)中我们复现了 Nomad Bridge 的漏洞，其中问题在于：

* 它的 **消息验证逻辑被错误初始化**（所有消息都被认为是有效的）。
* 攻击者只要构造一个假消息，就能调用 `process()`，指定任意接收人地址（即使是自己）。
* 桥合约没有额外的安全检查，所以资金直接被转出。

换句话说：**单点验证失效 → 没有额外的防线 → 一次错误就全网可盗**。

---

## 3. 如何用多签避免这种情况

多签可以在桥合约中作为 **“最后一道关卡”**：

* 不让桥合约在收到任意消息后 **直接付款**，而是把提案（转账请求）放进一个 **多签合约队列**。
* 只有当 **多个独立签名人**（比如不同组织/节点）确认这个转账时，资金才会真正转出。

流程可以这样设计：

1. `Bridge.process()` 收到消息后，不是直接 `call{value: amount}(recipient)`。
2. 而是调用 **多签钱包的 `submitTransaction()`**，生成一个待确认交易（比如“给 Alice 转 100 ETH”）。
3. 多签成员（至少 M-of-N）检查消息是否真实（链下或链上验证），然后逐个签名确认。
4. 当签名数达到阈值，才能 `execute()`，最终把钱打出去。

这样，即使验证逻辑里有 bug（像 Nomad 那样，所有消息都被当作合法），攻击者伪造的消息也不会自动放款，必须经过多签审批，风险被大幅降低。

---

## 4. 多签版 Nomad Bridge

`MultiSigNomadBridge.sol` 是一个模拟 Nomad 桥接合约的多签版本，在执行 `process()` 时，会提交一个签名集合，只有满足签名条件才会执行放款操作：  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SecureBridgeMulti - 多签 (M-of-N) 验证的跨链桥示例
/// @notice 教学用：通过多个验证者签名来验证跨链消息合法性
contract SecureBridgeMulti {
    mapping(bytes32 => bool) public processed;
    mapping(address => bool) public isValidator;
    address[] public validators;
    uint public threshold;
    address public owner;

    event Deposit(address indexed from, uint amount);
    event Processed(bytes32 indexed txHash, address indexed to, uint amount, uint signers);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(address[] memory _validators, uint _threshold) {
        require(_validators.length >= _threshold && _threshold > 0, "invalid threshold");
        owner = msg.sender;
        validators = _validators;
        threshold = _threshold;
        for (uint i = 0; i < _validators.length; i++) {
            isValidator[_validators[i]] = true;
        }
    }

    // 管理功能：更新验证者集（仅用于教学演示）
    function setValidators(address[] calldata _validators, uint _threshold) external onlyOwner {
        require(_validators.length >= _threshold && _threshold > 0, "invalid threshold");
        // 清理旧的映射
        for (uint i = 0; i < validators.length; i++) {
            isValidator[validators[i]] = false;
        }
        validators = _validators;
        threshold = _threshold;
        for (uint i = 0; i < _validators.length; i++) {
            isValidator[_validators[i]] = true;
        }
    }

    // 存款函数
    function deposit() external payable {
        require(msg.value > 0, "zero");
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice 处理跨链消息，需至少 threshold 个验证者签名
    /// @param txHash 跨链原文哈希（由链下系统生成）
    /// @param to 接收地址
    /// @param amount 转账金额（wei）
    /// @param signatures 签名数组（每个签名为 r||s||v 的 bytes，v 放最后一个字节）
    function process(bytes32 txHash, address to, uint256 amount, bytes[] calldata signatures) external {
        require(!processed[txHash], "already processed");
        require(signatures.length >= threshold, "not enough signatures");

        bytes32 hash = keccak256(abi.encodePacked(txHash, to, amount));
        bytes32 message = prefixed(hash);

        // 记录已见的签名者，防止重复计数
        uint validCount = 0;
        uint len = signatures.length;
        // 使用临时内存数组保存已用签名者（按地址）
        address[] memory seen = new address[](len);

        for (uint i = 0; i < len; i++) {
            address signer = recoverSigner(message, signatures[i]);
            if (signer == address(0)) continue;
            if (!isValidator[signer]) continue;

            // 检查 signer 是否已被计数过
            bool already = false;
            for (uint j = 0; j < validCount; j++) {
                if (seen[j] == signer) {
                    already = true;
                    break;
                }
            }
            if (already) continue;

            // 记录并计数
            seen[validCount] = signer;
            validCount++;

            if (validCount >= threshold) break; // 已满足阈值，提前退出
        }

        require(validCount >= threshold, "insufficient valid signatures");

        processed[txHash] = true;
        payable(to).transfer(amount);

        emit Processed(txHash, to, amount, validCount);
    }

    // 恢复签名者地址（签名格式： r (32) | s (32) | v (1) ）
    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        // v 默认修正：某些工具返回 0/1
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);

        return ecrecover(message, v, r, s);
    }

    // 以太坊签名前缀
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    // 获取全部验证者
    function getValidators() external view returns (address[] memory) {
        return validators;
    }

    // 合约余额（便于测试）
    function getBalance() external view returns (uint) {
        return address(this).balance;
    }

    // 紧急提取（仅 owner 用于教学演示）
    function emergencyWithdraw(address payable to, uint amount) external onlyOwner {
        to.transfer(amount);
    }
}
```  

`NomadMultiSig.t.sol` 是测试脚本，模拟了 3 个验证者（v1、v2、v3）和 1 个攻击者（hacker）：  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VulnerableBridge.sol";
import "../src/SecureBridgeMulti.sol";
import "../src/BridgeAttacker.sol";

contract NomadMultiSigTest is Test {
    VulnerableBridge vulnBridge;
    SecureBridgeMulti secureBridge;
    BridgeAttacker attacker;

    address deployer = address(0xABCD);
    address hacker = address(0xBEEF);

    // 三个验证者的私钥（用于 vm.sign）
    uint256 vk1 = 0x1;
    uint256 vk2 = 0x2;
    uint256 vk3 = 0x3;

    address v1;
    address v2;
    address v3;

    function setUp() public {
        v1 = vm.addr(vk1);
        v2 = vm.addr(vk2);
        v3 = vm.addr(vk3);
        vm.deal(deployer, 20 ether);

        // 部署漏洞桥并注资
        vm.startPrank(deployer);
        vulnBridge = new VulnerableBridge();
        vulnBridge.deposit{value: 10 ether}();
        vm.stopPrank();

        // 部署多签修复版：validators = [v1, v2, v3], threshold = 2
        address[] memory vals = new address[](3);
        vals[0] = v1;
        vals[1] = v2;
        vals[2] = v3;
        secureBridge = new SecureBridgeMulti(vals, 2);

        // 存入修复版桥资金
        vm.startPrank(deployer);
        secureBridge.deposit{value: 10 ether}();
        vm.stopPrank();
    }

    /// @notice 漏洞桥被直接伪造消息抢劫
    function testExploitVulnBridge() public {
        attacker = new BridgeAttacker(address(vulnBridge));
        emit log_named_uint("VulnBridge Balance Before", address(vulnBridge).balance);

        vm.prank(hacker);
        attacker.fakeMessage(keccak256("fake_tx"), 10 ether);

        emit log_named_uint("VulnBridge Balance After", address(vulnBridge).balance);
        emit log_named_uint("Attacker Balance After", address(hacker).balance);

        assertEq(address(vulnBridge).balance, 0, "vuln drained");
    }

    /// @notice 修复版：没有签名 -> 调用失败
    function test_RevertWhen_NoSignatures() public {
        bytes32 txHash = keccak256("some_tx");
        // 构建空签名数组
        bytes[] memory sigs;

        vm.prank(hacker);
        vm.expectRevert("not enough signatures");
        secureBridge.process(txHash, hacker, 1 ether, sigs);
    }

    /// @notice 修复版：只有一个验证者签名 -> 失败（阈值为2）
    function test_RevertWhen_WithOneSignature() public {
        bytes32 txHash = keccak256("tx_one_sig");
        address to = hacker;
        uint amount = 1 ether;
        bytes32 hash = keccak256(abi.encodePacked(txHash, to, amount));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vk1, message);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes[] memory sigs = new bytes[](1);
        sigs[0] = sig;

        vm.prank(hacker);
        vm.expectRevert("not enough signatures");
        secureBridge.process(txHash, to, amount, sigs);
    }

    /// @notice 修复版：两个不同验证者签名 -> 成功
    function testProcessWithTwoSignatures() public {
        bytes32 txHash = keccak256("tx_two_sig");
        address to = hacker;
        uint amount = 3 ether;
        bytes32 hash = keccak256(abi.encodePacked(txHash, to, amount));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // v1 签名
        (uint8 v1v, bytes32 r1, bytes32 s1) = vm.sign(vk1, message);
        bytes memory sig1 = abi.encodePacked(r1, s1, v1v);

        // v2 签名
        (uint8 v2v, bytes32 r2, bytes32 s2) = vm.sign(vk2, message);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2v);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sig1;
        sigs[1] = sig2;

        emit log_named_uint("SecureBridge Balance Before", address(secureBridge).balance);

        // 调用 process，满足阈值，应成功
        secureBridge.process(txHash, to, amount, sigs);

        emit log_named_uint("SecureBridge Balance After", address(secureBridge).balance);
        assertEq(address(secureBridge).balance, 10 ether - amount);
    }

    /// @notice 重放测试：同一 txHash 再次执行应被拒绝
    function testReplayPrevention() public {
        bytes32 txHash = keccak256("tx_replay");
        address to = hacker;
        uint amount = 2 ether;
        bytes32 hash = keccak256(abi.encodePacked(txHash, to, amount));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v1v, bytes32 r1, bytes32 s1) = vm.sign(vk1, message);
        bytes memory sig1 = abi.encodePacked(r1, s1, v1v);
        (uint8 v2v, bytes32 r2, bytes32 s2) = vm.sign(vk2, message);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2v);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sig1;
        sigs[1] = sig2;

        // 第一次成功
        secureBridge.process(txHash, to, amount, sigs);
        assertEq(address(secureBridge).balance, 10 ether - amount);

        // 第二次调用应 revert("already processed")
        vm.expectRevert("already processed");
        secureBridge.process(txHash, to, amount, sigs);
    }
    receive() external payable {}
}
```

**执行测试**：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/NomadMultiSig.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠘] Solc 0.8.30 finished in 608.98ms
Compiler run successful!

Ran 5 tests for test/NomadMultiSig.t.sol:NomadMultiSigTest
[PASS] testExploitVulnBridge() (gas: 332407)
Logs:
  VulnBridge Balance Before: 10000000000000000000
  VulnBridge Balance After: 0
  Attacker Balance After: 0

[PASS] testProcessWithTwoSignatures() (gas: 104458)
Logs:
  SecureBridge Balance Before: 10000000000000000000
  SecureBridge Balance After: 7000000000000000000

[PASS] testReplayPrevention() (gas: 104139)
[PASS] test_RevertWhen_NoSignatures() (gas: 17646)
[PASS] test_RevertWhen_WithOneSignature() (gas: 23377)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 11.55ms (14.20ms CPU time)

Ran 1 test suite in 167.14ms (11.55ms CPU time): 5 tests passed, 0 failed, 0 skipped (5 total tests)
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