---
layout: post
title: 《纸上谈兵·solidity》番外1 -- ERC20Permit
tags: solidity
mermaid: false
math: false
---  

在以太坊世界中，ERC-20代币标准无疑是最重要的标准之一。然而，传统ERC-20的授权机制存在一个明显的用户体验问题：需要先进行授权交易，然后才能进行实际操作，这不仅增加了Gas费用，还导致了糟糕的双重交易体验。OpenZeppelin的ERC20Permit扩展正是为了解决这一问题而生的创新方案。

## 1. 什么是ERC20Permit？

ERC20Permit是基于EIP-2612标准的ERC-20扩展，它引入了通过离线签名进行授权的功能。这意味着代币持有者无需发送链上交易即可完成授权，从而实现了无Gas费用的授权操作。

**传统授权 vs ERC20Permit授权**

| 特性对比 | 传统ERC-20 `approve` | ERC20Permit `permit` |
| :--- | :--- | :--- |
| **交互方式** | 必须发送链上交易 | **离线签名** + 由任何账户提交链上交易 |
| **Gas支付者** | 代币所有者 | 可以是**任何中继者**（甚至代付方） |
| **用户体验** | 需两次链上交易（`approve` + 实际操作），流程繁琐 | **授权与操作可合并为一次交易**，体验流畅 |
| **核心优势** | 简单直接 | **无Gas授权**、改善用户体验、支持元交易 |

## 2. ERC20Permit的工作原理与安全机制

### 2.1 核心流程

ERC20Permit的核心是`permit`函数，其工作流程如下：

1. **离线签名**：代币所有者对一条结构化的授权消息进行签名
2. **提交链上**：任何获得此签名的人将签名提交到链上的`permit`函数
3. **验证执行**：合约验证签名有效性后自动设置对应的`allowance`

### 2.2 安全基石

ERC20Permit的安全性建立在三个关键机制上：

1. **EIP-712结构化签名**：EIP-712标准允许对签名消息进行结构化编码，使得在钱包中签名时，用户可以清晰看到可读的授权请求详情，大大降低了因签名内容不明确而受骗的风险。
2. **Nonce防重放攻击**：每个地址维护一个独立的nonce计数器，每次成功使用`permit`后nonce递增，确保同一签名不能被重复使用。
3. **Deadline有效期控制**：签名中包含过期时间，合约验证时会检查当前时间是否超过deadline，防止过期授权被执行。

## 3. 使用 Foundry 测试 ERC20Permit

Foundry是以太坊开发者社区日益流行的测试框架，以其快速的执行速度和原生Solidity支持而备受青睐。

### 3.1 测试合约准备

创建待测试的ERC20Permit代币合约：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title MyToken - A custom ERC20 token with minting functionality
/// @notice This contract extends ERC20 and ERC20Permit to support permit functionality
contract MyToken is ERC20, ERC20Permit {
    /// @notice Initializes the token with a name and symbol
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {}

    /// @notice Mints new tokens to a specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

### 3.2 核心测试用例详解

**test/ERC20PermitTest.t.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

/// @title MyTokenTest - Test suite for MyToken contract
/// @notice This contract tests the functionality of the MyToken ERC20 token
contract MyTokenTest is Test {
    MyToken public token;

    uint256 public ownerPrivateKey = 0xA11CE;
    address public owner = vm.addr(ownerPrivateKey);
    address public sender = makeAddr("sender");

    /// @notice Sets up the test environment
    function setUp() public {
        vm.deal(owner, 1000 ether);
        vm.deal(sender, 1000 ether);

        token = new MyToken("MyToken", "MTK");
        token.mint(owner, 1000 ether);
    }

    /// @notice Tests a valid permit signature
    function testPermitValidSignature() public {
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        // 构建EIP-712签名
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            ownerPrivateKey,
            owner,
            sender,
            value,
            deadline,
            domainSeparator,
            nonce
        );

        // 由spender提交permit交易
        vm.prank(sender);
        token.permit(owner, sender, value, deadline, v, r, s);

        // 验证结果
        assertEq(token.allowance(owner, sender), value);
        assertEq(token.nonces(owner), nonce + 1);
    }

    /// @notice Tests setting a normal allowance
    function testPermitAllowanceSetCorrectly() public {
        // 正常授权额度
        _testPermitAllowance(10 ether, sender, unicode"正常授权额度");
    }

    /// @notice Tests setting a zero allowance
    function testPermitZeroAllowance() public {
        // 0额度
        _testPermitAllowance(0 ether, sender, unicode"0额度");
    }

    /// @notice Tests setting the maximum allowance
    function testPermitMaxAllowance() public {
        // 最大额度授权
        _testPermitAllowance(type(uint256).max, sender, unicode"最大额度授权");
    }

    /// @notice Tests setting multiple allowances for different spenders
    function testPermitMultipleAllowances() public {
        address spender1 = makeAddr("spender1");
        address spender2 = makeAddr("spender2");
        address spender3 = makeAddr("spender3");

        _testPermitAllowance(100 ether, spender1, unicode"spender1");
        _testPermitAllowance(200 ether, spender2, unicode"spender2");
        _testPermitAllowance(300 ether, spender3, unicode"spender3");

        assertEq(token.allowance(owner, spender1), 100 ether);
        assertEq(token.allowance(owner, spender2), 200 ether);
        assertEq(token.allowance(owner, spender3), 300 ether);
    }

    /// @notice Internal helper function to test permit allowances
    function _testPermitAllowance(
        uint256 value,
        address spender,
        string memory caseName
    ) internal {
        console.log("caseName:", caseName);
        console.log("value:", value);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        uint256 initialAllowance = token.allowance(owner, spender);
        assertEq(initialAllowance, 0);

        // 创建有效的EIP-712签名
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            ownerPrivateKey,
            owner,
            spender,
            value,
            deadline,
            token.DOMAIN_SEPARATOR(),
            nonce
        );

        vm.prank(spender);
        token.permit(owner, spender, value, deadline, v, r, s);

        uint256 finalAllowance = token.allowance(owner, spender);
        assertEq(finalAllowance, value);
        assertEq(token.nonces(owner), nonce + 1);
    }

    /// @notice Tests reverting when an invalid signature is provided
    function test_RevertWhen_Permit_InvalidSignature() public {
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            ownerPrivateKey,
            owner,
            sender,
            value,
            deadline,
            token.DOMAIN_SEPARATOR(),
            nonce
        );

        vm.prank(address(0x123));
        vm.expectRevert();
        token.permit(owner, address(0x123), value, deadline, v, r, s);

        assertEq(token.allowance(owner, sender), 0);
        assertEq(token.nonces(owner), nonce);
    }

    /// @notice Tests reverting when the permit deadline has expired
    function test_RevertWhen_Permit_ExiredDeadline() public {
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            ownerPrivateKey,
            owner,
            sender,
            value,
            deadline,
            token.DOMAIN_SEPARATOR(),
            nonce
        );

        // 将时间warp到deadline之后
        vm.warp(block.timestamp + 2 hours);

        vm.prank(sender);
        vm.expectRevert();
        token.permit(owner, sender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, sender), 0);
        assertEq(token.nonces(owner), nonce);
    }

    /// @notice Tests reverting when attempting a replay attack
    function test_revertWhen_Permit_ReplayAttack() public {
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            ownerPrivateKey,
            owner,
            sender,
            value,
            deadline,
            token.DOMAIN_SEPARATOR(),
            nonce
        );

        vm.startPrank(sender);
        token.permit(owner, sender, value, deadline, v, r, s);

        vm.expectRevert();
        token.permit(owner, sender, value, deadline, v, r, s);
        
        vm.stopPrank();
    }

    /// @notice Internal helper function to create a valid EIP-712 signature
    function _createPermitSignature(
        uint256 privateKey,
        address ownerAddr,
        address spenderAddr,
        uint256 value,
        uint256 deadline,
        bytes32 domainSeparator,
        uint256 nonce
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // EIP-712类型哈希
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        // 计算结构哈希
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                ownerAddr,
                spenderAddr,
                value,
                nonce,
                deadline
            )
        );

        // 计算最终摘要
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // 使用私钥签名
        (v, r, s) = vm.sign(privateKey, digest);
    }   
}
```

### 3.3 运行测试与最佳实践

**运行测试**：

```bash
➜  tutorial git:(master) forge test -vvv
[⠊] Compiling...
[⠔] Compiling 40 files with Solc 0.8.29
[⠒] Solc 0.8.29 finished in 1.42s
Compiler run successful!

Ran 8 tests for test/MyToken.t.sol:MyTokenTest
[PASS] testPermitAllowanceSetCorrectly() (gas: 86933)
Logs:
  caseName: 正常授权额度
  value: 10000000000000000000

[PASS] testPermitMaxAllowance() (gas: 87020)
Logs:
  caseName: 最大额度授权
  value: 11579208923731619542357098500868790785326998466564056403947584007913129639935

[PASS] testPermitMultipleAllowances() (gas: 197035)
Logs:
  caseName: spender1
  value: 100000000000000000000
  caseName: spender2
  value: 200000000000000000000
  caseName: spender3
  value: 300000000000000000000

[PASS] testPermitValidSignature() (gas: 80322)
[PASS] testPermitZeroAllowance() (gas: 67031)
Logs:
  caseName: 0额度
  value: 0

[PASS] test_RevertWhen_Permit_ExiredDeadline() (gas: 33318)
[PASS] test_RevertWhen_Permit_InvalidSignature() (gas: 58149)
[PASS] test_revertWhen_Permit_ReplayAttack() (gas: 85527)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 5.31ms (17.05ms CPU time)

Ran 1 test suite in 393.50ms (5.31ms CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)
```

> 更详细的测试日志可以通过 `forge test -vvvv` 查看。

**测试最佳实践**：

1. **全面覆盖**：确保测试所有正常路径和异常路径
2. **边界测试**：测试极值情况（如0值、最大值）
3. **安全测试**：重点关注可能的安全漏洞场景
4. **集成测试**：测试与其他功能的交互
5. **Gas优化**：关注关键操作的Gas消耗

## 4. 安全注意事项

尽管ERC20Permit大大改善了用户体验，但也引入了新的安全考量：

- **用户端风险**
  - **签名钓鱼**：攻击者可能诱导用户签署恶意permit请求
  - **解决方案**：教育用户仔细检查签名请求的详细信息
- **开发端注意事项**
  - **签名验证**：确保完整实现EIP-712标准
  - **Deadline处理**：合理设置默认过期时间
  - **错误处理**：提供清晰的错误信息

## 5. 实际应用场景

ERC20Permit在现代DeFi应用中有着广泛的应用：

1. **去中心化交易所**：将授权和交易合并为单次操作
2. **无Gas交易**：通过中继器实现用户无需支付Gas
3. **智能合约钱包**：支持批量交易和复杂操作
4. **跨链应用**：优化跨链操作的授权流程

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