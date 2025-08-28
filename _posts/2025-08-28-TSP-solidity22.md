---
layout: post
title: 《纸上谈兵·solidity》第 22 课：代币合约（ERC20）从零实现与扩展
tags: solidity
mermaid: false
math: false
---

## 1、课程目标

在本课中，我们将从零开始实现一个 **最小可用的 ERC20 代币合约**，并逐步扩展功能，包括铸造（mint）、销毁（burn）、权限控制（owner / onlyOwner）。
通过本课，我们可以：

1. 理解 **ERC20 标准接口**。
2. 学会实现一个 **完全符合 ERC20 标准的合约**。
3. 掌握 **代币扩展功能设计**。
4. 使用 **Foundry 编写单元测试**，验证代币逻辑的正确性。

---

## 2、ERC20 标准简介

ERC20 是以太坊上 **最常用的代币标准**，定义了代币的最小接口，保证钱包、交易所、DApp 能够与代币交互。

**核心函数：**

* `totalSupply()`: 返回代币总量
* `balanceOf(address)`: 查询地址余额
* `transfer(address, uint256)`: 转账
* `approve(address, uint256)`: 授权某人花费代币
* `allowance(address, address)`: 查询授权额度
* `transferFrom(address, address, uint256)`: 代替别人转账

**核心事件：**

* `Transfer(address indexed from, address indexed to, uint256 value)`
* `Approval(address indexed owner, address indexed spender, uint256 value)`

---

## 3、最小 ERC20 合约实现

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MyERC20 {
    string public name = "MyToken";
    string public symbol = "MTK";
    uint8 public decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        _balances[msg.sender] -= amount;
        _balances[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Not approved");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Invalid address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Invalid address");
        require(_balances[account] >= amount, "Insufficient balance");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}
```

---

## 4、扩展功能设计

### 1. Mint 与 Burn

* `mint(address to, uint256 amount)`：铸造新代币，增加供应量。
* `burn(uint256 amount)`：销毁持有者的代币，减少供应量。

### 2. 权限控制

* 只有合约 `owner` 可以调用 `mint`。
* 使用 `modifier onlyOwner` 来限制。

扩展后的合约：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 一个最小但可扩展的 ERC20 实现（带 Mint 与 Burn 功能）
/// @notice 本合约演示了代币标准 ERC20 的完整逻辑，并在此基础上增加了扩展功能。
contract MyERC20WithMintBurn {
    // ======== 基本元信息 ========

    /// @notice 代币名称（例如：Ethereum）
    string public name = "MyToken";

    /// @notice 代币符号（例如：ETH）
    string public symbol = "MTK";

    /// @notice 代币小数位数，通常是 18（与以太币一致）
    uint8 public decimals = 18;

    /// @notice 代币总供应量
    uint256 private _totalSupply;

    /// @notice 合约拥有者地址（只有它能调用 mint）
    address public owner;

    // ======== 账户与授权映射 ========

    /// @notice 每个账户的余额映射
    mapping(address => uint256) private _balances;

    /// @notice 授权额度映射：owner => (spender => 金额)
    ///         例如 Alice 授权 Bob 使用 100 个代币：_allowances[Alice][Bob] = 100
    mapping(address => mapping(address => uint256)) private _allowances;

    // ======== 事件（区块链日志） ========

    /// @notice 代币转账事件
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice 授权额度变更事件
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ======== 修饰器（权限控制） ========

    /// @notice 限制函数只能由合约拥有者调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ======== 构造函数 ========

    /// @notice 部署合约时会铸造初始代币给部署者
    /// @param initialSupply 初始供应量
    constructor(uint256 initialSupply) {
        owner = msg.sender; // 部署者成为合约拥有者
        _mint(msg.sender, initialSupply); // 铸造初始代币
    }

    // ======== ERC20 标准函数 ========

    /// @notice 返回代币总供应量
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice 查询某个账户的余额
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice 转账函数
    /// @param to 接收者地址
    /// @param amount 转账金额
    /// @dev 会触发 Transfer 事件
    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address"); // 禁止转账到 0 地址
        require(_balances[msg.sender] >= amount, "Insufficient balance"); // 确保余额足够

        // 扣减发送者余额
        _balances[msg.sender] -= amount;

        // 增加接收者余额
        _balances[to] += amount;

        // 记录日志
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice 授权某人（spender）可以花费调用者的代币
    /// @param spender 被授权的账户
    /// @param amount 授权金额
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;

        // 触发 Approval 事件，方便链上追踪
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice 查询 owner 给 spender 的授权额度
    function allowance(address _owner, address spender) external view returns (uint256) {
        return _allowances[_owner][spender];
    }

    /// @notice 转账（使用授权额度），常用于交易所托管、自动化支付等场景
    /// @param from 代币来源地址（必须已授权）
    /// @param to 代币接收地址
    /// @param amount 转账金额
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Not approved");

        // 扣减 from 的余额
        _balances[from] -= amount;

        // 增加接收者余额
        _balances[to] += amount;

        // 扣减调用者可用的授权额度
        _allowances[from][msg.sender] -= amount;

        // 触发转账事件
        emit Transfer(from, to, amount);
        return true;
    }

    // ======== 扩展功能：Mint 与 Burn ========

    /// @notice 铸造代币（只能由 owner 调用）
    /// @param to 接收者
    /// @param amount 铸造数量
    /// @dev 注意：滥用 mint 会导致代币贬值
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice 销毁调用者的代币
    /// @param amount 销毁数量
    /// @dev 用户只能销毁自己的代币，无法销毁别人账户的
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ======== 内部函数（供 mint/burn 使用） ========

    /// @notice 内部铸造逻辑
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Invalid address");

        // 增加总供应量
        _totalSupply += amount;

        // 增加账户余额
        _balances[account] += amount;

        // 触发 Transfer 事件，from = address(0) 代表铸造
        emit Transfer(address(0), account, amount);
    }

    /// @notice 内部销毁逻辑
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Invalid address");
        require(_balances[account] >= amount, "Insufficient balance");

        // 扣减账户余额
        _balances[account] -= amount;

        // 扣减总供应量
        _totalSupply -= amount;

        // 触发 Transfer 事件，to = address(0) 代表销毁
        emit Transfer(account, address(0), amount);
    }
}
```

---

## 5、Foundry 测试

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol"; // Foundry 的测试基类
import "../src/MyERC20WithMintBurn.sol"; // 引入待测试的合约

/// @title MyERC20WithMintBurn 的单元测试
/// @notice 使用 Foundry 测试框架验证代币逻辑
contract MyERC20WithMintBurnTest is Test {
    MyERC20WithMintBurn token; // 测试用代币实例
    address alice = address(0x1); // 测试账户 Alice
    address bob   = address(0x2); // 测试账户 Bob

    /// @notice 在每个测试前执行，初始化合约实例
    function setUp() public {
        // 部署一个初始供应量为 1000 的代币
        token = new MyERC20WithMintBurn(1000 * 1e18);
    }

    /// @notice 测试：初始供应量是否正确分配给部署者
    function testInitialSupply() public view {
        uint256 supply = token.totalSupply();
        assertEq(supply, 1000 * 1e18);

        uint256 balanceOwner = token.balanceOf(address(this));
        assertEq(balanceOwner, 1000 * 1e18);
    }

    /// @notice 测试：普通转账逻辑
    function testTransfer() public {
        // 给 Alice 转 100 代币
        token.transfer(alice, 100 * 1e18);

        // 验证 Alice 的余额
        uint256 balanceAlice = token.balanceOf(alice);
        assertEq(balanceAlice, 100 * 1e18);

        // 验证部署者余额减少
        uint256 balanceOwner = token.balanceOf(address(this));
        assertEq(balanceOwner, 900 * 1e18);
    }

    /// @notice 测试：转账余额不足时报错
    function testTransferRevertIfInsufficientBalance() public {
        vm.expectRevert("Insufficient balance"); // 预期报错
        vm.prank(alice); // 让 Alice 作为 msg.sender 执行
        token.transfer(bob, 1); // Alice 没钱，还要转账 -> 报错
    }

    /// @notice 测试：授权与 transferFrom
    function testApproveAndTransferFrom() public {
        // 部署者授权 Alice 使用 200 代币
        token.approve(alice, 200 * 1e18);

        // 验证授权额度
        uint256 allowance = token.allowance(address(this), alice);
        assertEq(allowance, 200 * 1e18);

        // 让 Alice 调用 transferFrom
        vm.prank(alice);
        token.transferFrom(address(this), bob, 150 * 1e18);

        // 验证 Bob 的余额
        uint256 balanceBob = token.balanceOf(bob);
        assertEq(balanceBob, 150 * 1e18);

        // 验证剩余授权额度
        uint256 remaining = token.allowance(address(this), alice);
        assertEq(remaining, 50 * 1e18);
    }

    /// @notice 测试：mint 功能（只有 owner 能调用）
    function testMintByOwner() public {
        uint256 beforeSupply = token.totalSupply();

        // 给 Alice 铸造 500 代币
        token.mint(alice, 500 * 1e18);

        // 验证总供应量增加
        assertEq(token.totalSupply(), beforeSupply + 500 * 1e18);

        // 验证 Alice 的余额增加
        assertEq(token.balanceOf(alice), 500 * 1e18);
    }

    /// @notice 测试：非 owner 调用 mint 会失败
    function testMintRevertIfNotOwner() public {
        vm.expectRevert("Not owner");
        vm.prank(alice); // 伪造 Alice 调用
        token.mint(alice, 1000 * 1e18);
    }

    /// @notice 测试：burn 功能
    function testBurn() public {
        uint256 beforeSupply = token.totalSupply();
        uint256 beforeBalance = token.balanceOf(address(this));

        // 销毁 100 代币
        token.burn(100 * 1e18);

        // 验证总供应量减少
        assertEq(token.totalSupply(), beforeSupply - 100 * 1e18);

        // 验证调用者余额减少
        assertEq(token.balanceOf(address(this)), beforeBalance - 100 * 1e18);
    }

    /// @notice 测试：余额不足时 burn 会失败
    function testBurnRevertIfInsufficientBalance() public {
        vm.expectRevert("Insufficient balance");
        vm.prank(alice); // Alice 没钱
        token.burn(1);
    }
}
```

执行测试：  

```bash
➜  counter git:(main) ✗ forge test --match-path test/MyERC20WithMintBurn.t.sol -vvv
[⠊] Compiling...
[⠢] Compiling 1 files with Solc 0.8.29
[⠆] Solc 0.8.29 finished in 1.12s
Compiler run successful!

Ran 8 tests for test/MyERC20WithMintBurn.t.sol:MyERC20WithMintBurnTest
[PASS] testApproveAndTransferFrom() (gas: 80002)
[PASS] testBurn() (gas: 28538)
[PASS] testBurnRevertIfInsufficientBalance() (gas: 14157)
[PASS] testInitialSupply() (gas: 15398)
[PASS] testMintByOwner() (gas: 48465)
[PASS] testMintRevertIfNotOwner() (gas: 14689)
[PASS] testTransfer() (gas: 46148)
[PASS] testTransferRevertIfInsufficientBalance() (gas: 16894)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 7.09ms (11.64ms CPU time)

Ran 1 test suite in 359.69ms (7.09ms CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)
```

---

## 6、小结

1. ERC20 是以太坊代币的基础标准，掌握它等于打下了坚实基础。
2. 本课我们实现了一个完整的 ERC20，并扩展了 **Mint / Burn / 权限控制**。
3. 下一步，我们会在 **第 22 课：NFT 合约（ERC721 / ERC1155）实战** 中学习非同质化代币的实现。

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