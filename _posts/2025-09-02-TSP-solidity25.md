---
layout: post
title: 《纸上谈兵·solidity》第 25 课：简化版的去中心化交易所（DEX）简化版
tags: solidity
mermaid: false
math: false
---

## 1、学习目标

1. 理解 **恒定乘积公式 x \* y = k** 的原理
2. 实现一个最小化的 DEX，支持 **流动性提供 / 兑换 / 提取**
3. 引入 **LP Token**，模拟流动性凭证
4. 探讨 AMM 的优缺点 & Gas 优化点

---

## 2、恒定乘积公式 (AMM)

* **资金池**：假设有 `TokenA` 和 `TokenB`，储备量分别为 `x` 和 `y`
* **公式**：`x * y = k`
* **含义**：只要有人兑换，必须保持乘积 `k` 不变
* **结果**：兑换时会自动形成滑点，越大的单笔兑换，价格偏移越大

---

## 3、简化版 DEX 合约

我们实现一个简化的 **ETH ↔ ERC20 Token 交易对**：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// IERC20: ERC20 代币标准接口
interface IERC20 {
    // 转账代币
    function transfer(address to, uint amount) external returns (bool);
    // 从授权地址转账代币
    function transferFrom(address from, address to, uint amount) external returns (bool);
    // 查询代币余额
    function balanceOf(address account) external view returns (uint);
}

// SimpleDEX: 简单的去中心化交易所合约
contract SimpleDEX {
    IERC20 public token;          // 交易对中的 ERC20 代币合约
    uint public totalLiquidity;   // 总流动性（LP 总量）
    mapping(address => uint) public liquidity; // 用户地址到其 LP 份额的映射

    // 事件定义
    event Init(address indexed provider, uint ethAmount, uint tokenAmount);    // 池子初始化事件
    event Deposit(address indexed provider, uint ethAmount, uint tokenAmount, uint liquidityMinted); // 流动性添加事件
    event Withdraw(address indexed provider, uint ethAmount, uint tokenAmount, uint liquidityBurned); // 流动性提取事件
    event Swap(address indexed trader, string direction, uint inputAmount, uint outputAmount); // 交易事件

    // 构造函数
    // @param tokenAddr: ERC20 代币合约地址
    constructor(address tokenAddr) {
        token = IERC20(tokenAddr);
    }

    // 初始化流动性池
    // @param tokenAmount: 初始代币数量
    // @return uint: 初始流动性数量
    function init(uint tokenAmount) public payable returns (uint) {
        require(totalLiquidity == 0, "already initialized"); // 确保池子未初始化

        totalLiquidity = address(this).balance; // 初始流动性为合约中的 ETH 余额
        liquidity[msg.sender] = totalLiquidity;  // 记录用户的 LP 份额

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "token transfer failed"); // 转入代币

        emit Init(msg.sender, msg.value, tokenAmount); // 触发初始化事件
        return totalLiquidity;
    }

    // 提供流动性（添加 ETH 和代币到池子）
    // @return uint: 新铸造的 LP 份额数量
    function deposit() public payable returns (uint) {
        uint ethReserve = address(this).balance - msg.value; // 计算 ETH 储备（扣除当前转账）
        uint tokenReserve = token.balanceOf(address(this));  // 获取代币储备

        // 计算需要转入的代币数量（按比例）
        uint tokenAmount = (msg.value * tokenReserve) / ethReserve;
        // 计算新铸造的 LP 份额
        uint liquidityMinted = (msg.value * totalLiquidity) / ethReserve;

        liquidity[msg.sender] += liquidityMinted; // 更新用户 LP 份额
        totalLiquidity += liquidityMinted;        // 更新总流动性

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "token transfer failed"); // 转入代币

        emit Deposit(msg.sender, msg.value, tokenAmount, liquidityMinted); // 触发流动性添加事件
        return liquidityMinted;
    }

    // 提取流动性（赎回 LP 份额）
    // @param amount: 要提取的 LP 份额数量
    // @return (uint, uint): 返回提取的 ETH 数量和代币数量
    function withdraw(uint amount) public returns (uint, uint) {
        require(liquidity[msg.sender] >= amount, "not enough liquidity"); // 检查用户 LP 余额

        // 按比例计算可提取的 ETH 和代币数量
        uint ethAmount = (amount * address(this).balance) / totalLiquidity;
        uint tokenAmount = (amount * token.balanceOf(address(this))) / totalLiquidity;

        liquidity[msg.sender] -= amount; // 扣除用户 LP 份额
        totalLiquidity -= amount;        // 减少总流动性

        payable(msg.sender).transfer(ethAmount); // 转出 ETH
        require(token.transfer(msg.sender, tokenAmount), "token transfer failed"); // 转出代币

        emit Withdraw(msg.sender, ethAmount, tokenAmount, amount); // 触发流动性提取事件
        return (ethAmount, tokenAmount);
    }

    // 用 ETH 兑换代币
    // @return uint: 兑换获得的代币数量
    function ethToToken() public payable returns (uint) {
        uint ethReserve = address(this).balance - msg.value; // 计算 ETH 储备（扣除当前转账）
        uint tokenReserve = token.balanceOf(address(this));  // 获取代币储备

        // 计算兑换的代币数量（含手续费）
        uint tokenAmount = getOutputAmount(msg.value, ethReserve, tokenReserve);

        require(token.transfer(msg.sender, tokenAmount), "token transfer failed"); // 转出代币

        emit Swap(msg.sender, "ETH_TO_TOKEN", msg.value, tokenAmount); // 触发交易事件
        return tokenAmount;
    }

    // 用代币兑换 ETH
    // @param tokenAmount: 要兑换的代币数量
    // @return uint: 兑换获得的 ETH 数量
    function tokenToEth(uint tokenAmount) public returns (uint) {
        uint tokenReserve = token.balanceOf(address(this)); // 获取代币储备
        uint ethReserve = address(this).balance;             // 获取 ETH 储备

        // 计算兑换的 ETH 数量（含手续费）
        uint ethAmount = getOutputAmount(tokenAmount, tokenReserve, ethReserve);

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "token transfer failed"); // 转入代币
        payable(msg.sender).transfer(ethAmount); // 转出 ETH

        emit Swap(msg.sender, "TOKEN_TO_ETH", tokenAmount, ethAmount); // 触发交易事件
        return ethAmount;
    }

    // AMM 定价公式（含 0.3% 手续费）
    // @param inputAmount: 输入数量
    // @param inputReserve: 输入资产储备
    // @param outputReserve: 输出资产储备
    // @return uint: 输出数量
    function getOutputAmount(uint inputAmount, uint inputReserve, uint outputReserve) internal pure returns (uint) {
        uint inputAmountWithFee = inputAmount * 997; // 扣除 0.3% 手续费
        uint numerator = inputAmountWithFee * outputReserve; // 分子
        uint denominator = (inputReserve * 1000) + inputAmountWithFee; // 分母
        return numerator / denominator; // 计算结果
    }

    // 查询当前价格（1 代币 = ? ETH, 1 ETH = ? 代币）
    // @return (uint, uint): ETH 价格和代币价格（乘以 1e18 避免浮点数）
    function getPrice() external view returns (uint ethPerToken, uint tokenPerEth) {
        uint ethReserve = address(this).balance; // ETH 储备
        uint tokenReserve = token.balanceOf(address(this)); // 代币储备
        return (
            ethReserve * 1e18 / tokenReserve, // 1 代币 = ? ETH
            tokenReserve * 1e18 / ethReserve  // 1 ETH = ? 代币
        );
    }
}
```

---

## 4、流程示例

1. **初始化池子**
   * Alice 调用 `init(1000 tokens)` 并附带 1 ETH
   * 池子中：`x=1 ETH, y=1000 tokens`
2. **添加流动性**
   * Bob 存入 0.5 ETH，则需按比例存入 500 tokens
   * 获得对应的 LP 份额
3. **兑换 ETH → Token**
   * 用户支付 0.1 ETH
   * 合约计算输出 Token 数量，并更新储备
4. **提取流动性**
   * 用户赎回 LP，按比例取回 ETH 和 Token

---

## 5、合约测试

我们还是使用 **Foundry** 来测试合约：  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleDEX.sol";

// MockERC20: 模拟 ERC20 代币合约，用于测试 DEX 功能
contract MockERC20 {
    string public name = "MockToken"; // 代币名称
    string public symbol = "MTK";     // 代币符号
    uint8 public decimals = 18;       // 代币精度

    mapping(address => uint) public balanceOf;                     // 地址到余额的映射
    mapping(address => mapping(address => uint)) public allowance; // 授权额度映射

    event Transfer(address indexed from, address indexed to, uint value); // 转账事件
    event Approval(address indexed owner, address indexed spender, uint value); // 授权事件

    // 铸造代币
    // @param to: 接收地址
    // @param amount: 铸造数量
    function mint(address to, uint amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // 转账代币
    // @param to: 接收地址
    // @param amount: 转账数量
    // @return bool: 是否成功
    function transfer(address to, uint amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance too low");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // 授权额度
    // @param spender: 被授权地址
    // @param amount: 授权数量
    // @return bool: 是否成功
    function approve(address spender, uint amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // 从授权地址转账
    // @param from: 转出地址
    // @param to: 接收地址
    // @param amount: 转账数量
    // @return bool: 是否成功
    function transferFrom(
        address from,
        address to,
        uint amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "balance too low");
        require(allowance[from][msg.sender] >= amount, "allowance too low");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// SimpleDEXTest: 测试 SimpleDEX 合约的功能
contract SimpleDEXTest is Test {
    MockERC20 token; // 模拟 ERC20 代币
    SimpleDEX dex;   // 待测试的 DEX 合约

    address alice = address(0x123); // 测试账户 Alice
    address bob = address(0x234);   // 测试账户 Bob

    // 初始化测试环境
    function setUp() public {
        token = new MockERC20();
        dex = new SimpleDEX(address(token));

        // 给 Alice 和 Bob 分配初始 ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // 给 Alice 铸造代币并授权 DEX
        token.mint(alice, 10000 ether);
        vm.startPrank(alice);
        token.approve(address(dex), type(uint).max);
        vm.stopPrank();
    }

    // 测试初始化和流动性提供功能
    function testInitAndDeposit() public {
        vm.startPrank(alice);
        dex.init{value: 1 ether}(1000 ether); // 初始化 DEX
        vm.stopPrank();

        // 验证价格计算是否正确
        (uint ethPrice, uint tokenPrice) = dex.getPrice();
        assertGt(ethPrice, 0);
        assertGt(tokenPrice, 0);

        // Bob 提供流动性
        vm.startPrank(bob);
        token.mint(bob, 5000 ether);
        token.approve(address(dex), type(uint).max);
        dex.deposit{value: 0.5 ether}();
        vm.stopPrank();
    }

    // 测试 ETH 兑换代币功能
    function testSwapEthToToken() public {
        vm.startPrank(alice);
        dex.init{value: 1 ether}(1000 ether);

        uint tokenOut = dex.ethToToken{value: 0.1 ether}(); // 兑换代币
        assertGt(tokenOut, 0); // 验证兑换数量大于零
        vm.stopPrank();
    }

    // 测试代币兑换 ETH 功能
    function testSwapTokenToEth() public {
        vm.startPrank(alice);
        dex.init{value: 1 ether}(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.mint(bob, 100 ether);
        token.approve(address(dex), type(uint).max);

        uint ethOut = dex.tokenToEth(50 ether); // 兑换 ETH
        assertGt(ethOut, 0); // 验证兑换数量大于零
        vm.stopPrank();
    }

    // 测试提取流动性功能
    function testWithdrawLiquidity() public {
        vm.startPrank(alice);
        dex.init{value: 1 ether}(1000 ether);

        (uint ethOut, uint tokenOut) = dex.withdraw(0.5 ether); // 提取流动性
        assertGt(ethOut, 0); // 验证提取的 ETH 数量大于零
        assertGt(tokenOut, 0); // 验证提取的代币数量大于零
        vm.stopPrank();
    }
}
```  

运行测试：  

```bash
➜  counter git:(main) ✗ forge test --match-path test/SimpleDEX.t.sol -vvv
[⠊] Compiling...
[⠢] Compiling 1 files with Solc 0.8.29
[⠆] Solc 0.8.29 finished in 1.13s
Compiler run successful!

Ran 4 tests for test/SimpleDEX.t.sol:SimpleDEXTest
[PASS] testInitAndDeposit() (gas: 211169)
[PASS] testSwapEthToToken() (gas: 126392)
[PASS] testSwapTokenToEth() (gas: 187912)
[PASS] testWithdrawLiquidity() (gas: 128136)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 8.74ms (5.84ms CPU time)

Ran 1 test suite in 346.43ms (8.74ms CPU time): 4 tests passed, 0 failed, 0 skipped (4 total tests)
```

---

## 6、本课总结

* **恒定乘积公式 x \* y = k** 是 DEX 的数学基础
* 通过 **LP Token** 表示用户在池子中的份额
* 兑换时会自动形成滑点，保证池子不会被掏空
* 实际 Uniswap V2 还包含：事件、Router、Pair 工厂、闪电贷等逻辑

---

## 7、作业

1. 在 `SimpleDEX` 中补充 `getPrice()` 方法，返回当前 **ETH/Token 价格**。
2. 修改代码，支持 **多池子**（不同的 ERC20 Token）。
3. 思考：如果没有手续费，AMM 会遇到什么问题？

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