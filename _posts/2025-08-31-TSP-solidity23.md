---
layout: post
title: 《纸上谈兵·solidity》第 23 课：NFT 合约（ERC721 / ERC1155）实战
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

* 理解 **ERC721 与 ERC1155** 的标准接口
* 从零实现一个 **最小化 ERC721（NFT）合约**
* 扩展功能：元数据管理（BaseURI）、批量铸造 / 批量转账
* 对比 OpenZeppelin 实现
* 使用 Foundry 测试

---

## 2、知识点梳理

1. **ERC721 核心接口**
   * `balanceOf(address)`
   * `ownerOf(uint256)`
   * `safeTransferFrom(address,address,uint256)`
   * `transferFrom(address,address,uint256)`
   * `approve(address,uint256)` / `setApprovalForAll(address,bool)`
   * 事件：`Transfer`, `Approval`, `ApprovalForAll`
2. **ERC1155 核心接口**
   * 支持 **多代币标准**（FT / NFT / SFT）
   * `balanceOf(address,uint256)`
   * `safeTransferFrom(address,address,uint256,uint256,bytes)`
   * `safeBatchTransferFrom(...)`
   * 事件：`TransferSingle`, `TransferBatch`, `ApprovalForAll`
3. **应用场景差异**
   * **ERC721** → 独一无二的资产（头像、土地、艺术品）
   * **ERC1155** → 大规模批量资产（游戏道具、门票、盲盒）

---

## 3、最小 ERC721 实现

**MyERC721.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MyERC721 {
    // NFT 名称和符号
    string public name = "MyNFT";
    string public symbol = "MNFT";

    // 记录每个 tokenId 的所有者
    mapping(uint256 => address) private _owners;
    // 记录每个地址拥有多少 NFT
    mapping(address => uint256) private _balances;
    // 每个 tokenId 的单独授权（一个地址可被允许转移这个 tokenId）
    mapping(uint256 => address) private _tokenApprovals;
    // 授权某个地址操作所有 token（批量授权）
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // 事件：转账、授权、批量授权
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // 查询某个地址持有多少 NFT
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "zero address");
        return _balances[owner];
    }

    // 查询某个 tokenId 的所有者
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "not minted");
        return owner;
    }

    // 授权某个地址可以转移指定的 tokenId
    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner, "not owner");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    // 查询某个 tokenId 被授权给了谁
    function getApproved(uint256 tokenId) public view returns (address) {
        return _tokenApprovals[tokenId];
    }

    // 批量授权：允许某个 operator 管理 msg.sender 所有的 token
    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // 转移 NFT
    function transferFrom(address from, address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);

        // 检查调用者是否有权限（是所有者 / 被单独授权 / 被批量授权）
        require(
            msg.sender == owner ||
            msg.sender == _tokenApprovals[tokenId] ||
            _operatorApprovals[owner][msg.sender],
            "not authorized"
        );
        require(from == owner, "wrong from");
        require(to != address(0), "zero address");

        // 更新余额
        _balances[from] -= 1;
        _balances[to] += 1;
        // 更新所有者
        _owners[tokenId] = to;

        // 清除旧授权
        delete _tokenApprovals[tokenId];
        emit Transfer(from, to, tokenId);
    }

    // 内部函数：铸造 NFT
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "zero address");
        require(_owners[tokenId] == address(0), "already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }
}
```

---

## 4、简化 ERC1155 实现

**MyERC1155.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MyERC1155 {
    // balances[tokenId][owner] = 持有数量
    mapping(uint256 => mapping(address => uint256)) private balances;
    // 操作授权
    mapping(address => mapping(address => bool)) private operatorApprovals;

    // ERC1155 事件（单次转账 & 批量转账）
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    // 查询余额
    function balanceOf(address account, uint256 id) public view returns (uint256) {
        return balances[id][account];
    }

    // 批量查询余额
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids) public view returns (uint256[] memory) {
        require(accounts.length == ids.length, "length mismatch");
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint i = 0; i < accounts.length; i++) {
            batchBalances[i] = balances[ids[i]][accounts[i]];
        }
        return batchBalances;
    }

    // 设置批量操作授权
    function setApprovalForAll(address operator, bool approved) public {
        operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // 铸造代币
    function mint(address to, uint256 id, uint256 amount) public {
        balances[id][to] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    // 批量铸造代币
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) public {
        require(ids.length == amounts.length, "length mismatch");
        for (uint i = 0; i < ids.length; i++) {
            balances[ids[i]][to] += amounts[i];
        }
        emit TransferBatch(msg.sender, address(0), to, ids, amounts);
    }
}
```

---

## 5、ERC721 与 ERC1155 对比表格

| 特性                  | ERC721                                      | ERC1155                                                |
| ------------------- | ------------------------------------------- | ------------------------------------------------------ |
| **资产类型**            | 单一、独特（每个 tokenId 仅对应一个资产）                   | 多代币标准（可同质化 / 非同质化 / 半同质化）                              |
| **典型场景**            | 艺术品、头像、土地、收藏品                               | 游戏道具、票券、盲盒、大规模 NFT                                     |
| **转账方式**            | `transferFrom` / `safeTransferFrom`（单个 NFT） | `safeTransferFrom`（单个），`safeBatchTransferFrom`（批量）     |
| **存储方式**            | `mapping(uint256 => address)` 记录所有权         | `mapping(uint256 => mapping(address => uint256))` 记录余额 |
| **批量支持**            | ❌ 不支持批量转账                                   | ✅ 原生支持批量转账                                             |
| **Gas 成本**          | 单个 NFT 操作时更低                                | 批量操作时更节省 Gas                                           |
| **应用生态**            | PFP、艺术类 NFT 占主流                             | 游戏、资产类项目采用更多                                           |
| **OpenZeppelin 实现** | `ERC721.sol`, `ERC721URIStorage`            | `ERC1155.sol`                                          |

---

## 6、Foundry 测试

**MyNFTTest.sol**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyERC721.sol";
import "../src/MyERC1155.sol";

// 继承 MyERC721，暴露一个外部 mint 供测试使用
contract MyERC721Mock is MyERC721 {
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MyNFTTest is Test {
    MyERC721Mock nft721;
    MyERC1155 nft1155;

    address alice = address(0x1);
    address bob   = address(0x2);

    function setUp() public {
        // 部署合约
        nft721 = new MyERC721Mock();
        nft1155 = new MyERC1155();

        // 预铸造 ERC721 tokenId = 1 给 Alice
        nft721.mint(alice, 1);
        // 预铸造 ERC1155 tokenId = 100 给 Alice（数量 10）
        nft1155.mint(alice, 100, 10);
    }

    // ---------------- ERC721 测试 ----------------
    function testERC721OwnerOf() public view {
        assertEq(nft721.ownerOf(1), alice);
    }

    function testERC721BalanceOf() public view {
        assertEq(nft721.balanceOf(alice), 1);
    }

    function testERC721Transfer() public {
        vm.prank(alice); // 伪装成 Alice
        nft721.transferFrom(alice, bob, 1);

        assertEq(nft721.ownerOf(1), bob);
        assertEq(nft721.balanceOf(alice), 0);
        assertEq(nft721.balanceOf(bob), 1);
    }

    function testERC721ApproveAndTransfer() public {
        // Alice 授权 Bob 操作 tokenId=1
        vm.prank(alice);
        nft721.approve(bob, 1);

        // Bob 代替 Alice 转移
        vm.prank(bob);
        nft721.transferFrom(alice, bob, 1);

        assertEq(nft721.ownerOf(1), bob);
    }

    function test_RevertWhen_ERC721TransferNotAuthorized() public {
        // 未授权的地址尝试转移，应失败
        vm.prank(bob);
        vm.expectRevert(bytes("not authorized"));
        nft721.transferFrom(alice, bob, 1);
    }

    // ---------------- ERC1155 测试 ----------------

    function testERC1155BalanceOf() public view {
        assertEq(nft1155.balanceOf(alice, 100), 10);
    }

    function testERC1155MintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 200;
        ids[1] = 201;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 10;

        nft1155.mintBatch(alice, ids, amounts);

        assertEq(nft1155.balanceOf(alice, 200), 5);
        assertEq(nft1155.balanceOf(alice, 201), 10);
    }

    function testERC1155BalanceOfBatch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = alice;

        uint256[] memory ids = new uint256[](2);
        ids[0] = 100;
        ids[1] = 200;

        // 先给 Alice 铸造 id=200 数量 7
        nft1155.mint(alice, 200, 7);

        uint256[] memory balances = nft1155.balanceOfBatch(accounts, ids);

        assertEq(balances[0], 10); // id=100 的数量
        assertEq(balances[1], 7);  // id=200 的数量
    }
}
```


执行测试：  

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/MyNFTTest.t.sol -vvv

[⠊] Compiling...
[⠒] Compiling 2 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 577.98ms
Compiler run successful!

Ran 8 tests for test/MyNFTTest.t.sol:MyNFTTest
[PASS] testERC1155BalanceOf() (gas: 11033)
[PASS] testERC1155BalanceOfBatch() (gas: 45135)
[PASS] testERC1155MintBatch() (gas: 68116)
[PASS] testERC721ApproveAndTransfer() (gas: 58954)
[PASS] testERC721BalanceOf() (gas: 10689)
[PASS] testERC721OwnerOf() (gas: 10794)
[PASS] testERC721Transfer() (gas: 52908)
[PASS] test_RevertWhen_ERC721TransferNotAuthorized() (gas: 22145)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 4.75ms (7.22ms CPU time)

Ran 1 test suite in 160.73ms (4.75ms CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)
```

## 7、本课总结

* **ERC721**：最经典的 NFT 标准 → 单一、独特、适合收藏品
* **ERC1155**：面向游戏和批量资产 → 更节省 Gas、灵活度高
* 元数据管理（BaseURI + tokenId）是 NFT 的灵魂
* 学习从零实现，能深入理解标准；实战推荐使用 **OpenZeppelin**

---

## 8、作业

1. 在 **ERC721** 中实现 `safeTransferFrom`，并写一个合约模拟 `onERC721Received`。
2. 在 **ERC1155** 中补充 `safeBatchTransferFrom` 的实现，并写测试。
3. 思考：如果要为 ERC721 添加 **版税（Royalty）** 功能，应该放在哪些函数中处理？

