---
layout: post
title: 《纸上谈兵·solidity》第 35 课：去中心化交易所（DEX）实战 — 合约设计
tags: solidity
mermaid: false
math: false
--- 

## 1. 学习目标

完成本课后你将能：

1. 理解 AMM（Constant Product）核心数学与滑点、价格影响、k 常数。
2. 实现一个简化但**可用的** Uniswap V2 风格 DEX：Pair（流动性池）、Factory（创建 Pair）、Router（方便交互）。
3. 为 LP 提供者实现 mint / burn（LP Token）逻辑并处理手续费（比如 0.3%）。
4. 写测试（Foundry / Hardhat）覆盖添加流动性、兑换与移除流动性。
5. 用 React + ethers.js(v6) 写简单前端界面实现 Add Liquidity / Swap / Remove Liquidity。
6. 理解常见攻击面（闪电贷、价格操控、滑点）并能提出防护建议。

---

## 2. 课程结构

1. AMM 原理与 constant product（数学、滑点、手续费）
2. 实现 Token（测试代币）与 Safe Transfer 辅助工具
3. 实现 Pair（流动性池） — addLiquidity / removeLiquidity / swap（含手续费）
4. 实现 Factory（管理 Pair）与 Router（便捷方法）
5. Foundry 单元测试：正常流程与异常场景
6. 前端交互（React + ethers.js）与 UX 注意点（滑点、预估）
7. 安全审计清单与性能优化（gas、EVM 细节）

---

## 3. 关键设计决定（简述）

* 跟随 Uniswap V2 的核心思路：`x * y = k`，在 swap 中通过 `amountOut = reserveB - (k / newReserveA)` 或等价公式计算输出。
* 引入手续费（例如 0.3%），把手续费加入池子（即留在 reserves）以奖励 LP。实现方式与 Uniswap：对 `amountIn` 扣手续费后计算实际进池数。
* 为 LP 引入 ERC20 LP Token（OpenZeppelin ERC20）代表份额。
* 使用 `SafeERC20` 做转账以兼容不返回 bool 的 ERC20。
* CEI（Checks-Effects-Interactions）和 `nonReentrant` 保护关键调用。

---

## 4. 核心合约代码（可直接编译）

下面是一个 **精简但功能完整** 的 DEX 实现：`Token`（测试代币）、`LPToken`、`Pair`、`Factory`、`Router`。所有合约基于 `pragma ^0.8.20` 并使用 OpenZeppelin。

> 注意：为了教学代码可读性，省略了某些边界优化（例如：手续费接入到特殊收款地址的分离），但逻辑与 Uniswap V2 一致并适合做项目原型与安全练习。

### 1) TestToken.sol（测试代币）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

### 2) LPToken.sol（简单 LP 代币）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20 {
    address public pair;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        pair = msg.sender; // Only pair contract will deploy this token
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == pair, "Only pair");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == pair, "Only pair");
        _burn(from, amount);
    }
}
```

### 3) SimplePair.sol（核心流动性池）

```solidity
// SPDX-License-Identifier: MIT
// SimplePair.sol
// Description: A minimal decentralized exchange (DEX) pair contract for token swaps and liquidity provision.
// Author: Your Name
// Version: 1.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LPToken.sol";

/**
 * @title SimplePair
 * @dev A minimal decentralized exchange (DEX) pair contract for token swaps and liquidity provision.
 * This contract allows users to add/remove liquidity and swap tokens while maintaining a constant product invariant.
 */
contract SimplePair is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token addresses for the pair
    IERC20 public token0;
    IERC20 public token1;

    // Liquidity pool token
    LPToken public lpToken;

    // Reserves for token0 and token1
    uint112 private reserve0; // uses single slot, must be uint112
    uint112 private reserve1;
    uint32 private blockTimestampLast; // Last block timestamp for price calculations

    // Fee constants (0.3% fee)
    uint256 public constant FEE_NUM = 3; // Fee numerator
    uint256 public constant FEE_DEN = 1000; // Fee denominator

    // Address to hold minimum liquidity (burned to avoid division by zero)
    address public constant MINIMUM_LIQUIDITY_HOLDER = address(0xdead);

    // Events
    event Mint(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);

    /**
     * @dev Constructor to initialize the pair with two tokens.
     * @param _token0 Address of the first token in the pair.
     * @param _token1 Address of the second token in the pair.
     */
    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        // Deploy LP token with pair as minter
        lpToken = new LPToken("SimpleLP", "sLP");
    }

    /**
     * @dev Get the current reserves of token0 and token1.
     * @return r0 Reserve of token0.
     * @return r1 Reserve of token1.
     */
    function getReserves() public view returns (uint112 r0, uint112 r1) {
        return (reserve0, reserve1);
    }

    // ---- ADD LIQUIDITY: mint LP tokens ----
    /**
     * @dev Add liquidity to the pair and mint LP tokens.
     * @param to Address to receive the minted LP tokens.
     * @return liquidity Amount of LP tokens minted.
     */
    function mint(
        address to
    ) external nonReentrant returns (uint256 liquidity) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        require(amount0 > 0 && amount1 > 0, "Insufficient amounts");

        uint256 _totalSupply = lpToken.totalSupply();

        if (_totalSupply == 0) {
            // Initial liquidity: lock a minimum liquidity to avoid divide by zero later
            liquidity = sqrt(amount0 * amount1) - 1000;
            lpToken.mint(MINIMUM_LIQUIDITY_HOLDER, 1000); // Burn 1000 to lock
        } else {
            // Calculate liquidity based on existing reserves
            liquidity = min(
                (amount0 * _totalSupply) / reserve0,
                (amount1 * _totalSupply) / reserve1
            );
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        lpToken.mint(to, liquidity);

        _update(uint112(balance0), uint112(balance1));
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    // ---- REMOVE LIQUIDITY: burn LP tokens and send underlying ----
    /**
     * @dev Remove liquidity from the pair and burn LP tokens.
     * @param to Address to receive the underlying tokens.
     * @return amount0 Amount of token0 returned.
     * @return amount1 Amount of token1 returned.
     */
    function burn(
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = lpToken.balanceOf(address(this));
        uint256 _totalSupply = lpToken.totalSupply();

        require(liquidity > 0, "No liquidity");

        // Transfer LP tokens from sender to pair and burn
        lpToken.transferFrom(msg.sender, address(this), liquidity);
        lpToken.burn(address(this), liquidity);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");

        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        balance0 = token0.balanceOf(address(this));
        balance1 = token1.balanceOf(address(this));
        _update(uint112(balance0), uint112(balance1));

        emit Burn(msg.sender, amount0, amount1, to);
    }

    // ---- SWAP: token0 -> token1 or token1 -> token0 ----
    /**
     * @dev Swap tokens in the pair.
     * @param amount0Out Amount of token0 to send out.
     * @param amount1Out Amount of token1 to send out.
     * @param to Address to receive the output tokens.
     * @param data Optional callback data for flash swaps.
     */
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        require(
            amount0Out < reserve0 && amount1Out < reserve1,
            "Insufficient liquidity"
        );

        // Transfer output tokens first
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        // Compute input amounts
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = 0;
        if (balance0 > reserve0 - amount0Out) {
            amount0In = balance0 - (reserve0 - amount0Out);
        }
        uint256 amount1In = 0;
        if (balance1 > reserve1 - amount1Out) {
            amount1In = balance1 - (reserve1 - amount1Out);
        }
        require(amount0In > 0 || amount1In > 0, "Insufficient input amount");

        // Check constant product invariant with fee
        require(
            (balance0 * FEE_DEN - amount0In * FEE_NUM) *
                (balance1 * FEE_DEN - amount1In * FEE_NUM) >=
                uint256(reserve0) * reserve1 * FEE_DEN * FEE_DEN,
            "K"
        );

        // Update reserves
        _update(uint112(balance0), uint112(balance1));

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);

        // Flash swap hook (optional callback)
        if (data.length > 0) {
            // Optional callback logic
        }
    }

    // ---- HELPERS ----
    /**
     * @dev Internal function to update reserves and emit Sync event.
     * @param _reserve0 New reserve for token0.
     * @param _reserve1 New reserve for token1.
     */
    function _update(uint112 _reserve0, uint112 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp % 2 ** 32);
        emit Sync(_reserve0, _reserve1);
    }

    // ---- UTILITIES ----
    /**
     * @dev Returns the smaller of two numbers.
     * @param x First number.
     * @param y Second number.
     * @return The smaller number.
     */
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    /**
     * @dev Calculates the square root of a number.
     * @param y The number to calculate the square root of.
     * @return z The square root of y.
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) z = 1;
    }

    // Allow the pair to receive tokens; caller must transfer tokens in before calling mint()
    receive() external payable {}
}
```


> 说明（重要）：
>
> * `mint`：呼应 Uniswap V2 的机制：第一次 mint 会锁定少量流动性（这里写成 1000 单位仅作示例）；后续按 share 发放 LP token。为了更精确可以直接参照 UniswapV2Pair 的实现。
> * `swap`：对 `amountIn` 扣除手续费后校验 x\*y 不变（用 adjusted variables 保留 fee 的影响）。这种检查方式和 Uniswap V2 一致（用 `balance * 1000 - amountIn * 3` 的形式）。
> * `lpToken` 的 mint/burn 模式在本例中很简化：Pair 合约是 LPToken 的 minter。为测试方便，`burn` 的实现里我们把用户先 transferFrom 到 pair（实际可更复杂）。课程后续会把 LPToken 设计得更严谨（总供应管理、transferFrom 权限等）。

### 4) SimpleFactory.sol（创建 pair）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimplePair.sol";

contract SimpleFactory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");

        SimplePair newPair = new SimplePair(token0, token1);
        pair = address(newPair);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
```

### 5) Router（便捷接口：添加流动性 & 交换）

```solidity
// SPDX-License-Identifier: MIT
// SimpleRouter.sol
// Description: A minimal decentralized exchange (DEX) router contract for token swaps and liquidity provision.
// Author: Your Name
// Version: 1.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleFactory.sol";

/**
 * @title ISimplePair
 * @dev Interface for the SimplePair contract, defining functions for fee calculation, reserves, and token swaps.
 */
interface ISimplePair {
    function FEE_NUM() external pure returns (uint256);
    function FEE_DEN() external pure returns (uint256);
    function getReserves() external view returns (uint112, uint112);
    function token0() external view returns (address);
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
    function mint(address to) external returns (uint256 liquidity);
}

/**
 * @title SimpleRouter
 * @dev A minimal decentralized exchange (DEX) router contract for token swaps and liquidity provision.
 * This contract interacts with SimplePair contracts to facilitate token swaps and liquidity management.
 */
contract SimpleRouter {
    using SafeERC20 for IERC20;
    SimpleFactory public factory;

    /**
     * @dev Constructor to initialize the router with a factory address.
     * @param _factory Address of the SimpleFactory contract.
     */
    constructor(address _factory) {
        factory = SimpleFactory(_factory);
    }

    /**
     * @dev Calculate the output amount for a token swap, considering fees.
     * @param amountIn Amount of input tokens.
     * @param reserveIn Reserve of the input token.
     * @param reserveOut Reserve of the output token.
     * @param feeNum Fee numerator (e.g., 3 for 0.3% fee).
     * @param feeDen Fee denominator (e.g., 1000 for 0.3% fee).
     * @return Amount of output tokens after fees.
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeNum,
        uint256 feeDen
    ) public pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (feeDen - feeNum);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * feeDen) + amountInWithFee;
        return numerator / denominator;
    }

    /**
     * @dev Swap exact input tokens for output tokens (single-hop).
     * @param amountIn Amount of input tokens.
     * @param amountOutMin Minimum amount of output tokens expected.
     * @param tokenIn Address of the input token.
     * @param tokenOut Address of the output token.
     * @param to Address to receive the output tokens.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to
    ) external {
        // Get the pair address for the input and output tokens
        address pairAddr = factory.getPair(tokenIn, tokenOut);
        require(pairAddr != address(0), "PAIR_NOT_EXIST");
        ISimplePair pair = ISimplePair(pairAddr);

        // Transfer input tokens from the user to the pair
        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddr, amountIn);

        // Read reserves and determine the order of tokens in the pair
        (uint112 r0, uint112 r1) = pair.getReserves();
        address token0 = pair.token0();
        uint256 reserveIn;
        uint256 reserveOut;
        if (token0 == tokenIn) {
            reserveIn = uint256(r0);
            reserveOut = uint256(r1);
        } else {
            reserveIn = uint256(r1);
            reserveOut = uint256(r0);
        }

        // Calculate the output amount and ensure it meets the minimum requirement
        uint256 feeNum = pair.FEE_NUM();
        uint256 feeDen = pair.FEE_DEN();
        uint256 amountOut = getAmountOut(
            amountIn,
            reserveIn,
            reserveOut,
            feeNum,
            feeDen
        );
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Execute the swap based on the token order
        if (token0 == tokenIn) {
            // Swap token0 for token1
            pair.swap(0, amountOut, to, "");
        } else {
            // Swap token1 for token0
            pair.swap(amountOut, 0, to, "");
        }
    }

    /**
     * @dev Add liquidity to a token pair and mint LP tokens.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @param amountADesired Desired amount of tokenA to add.
     * @param amountBDesired Desired amount of tokenB to add.
     * @param to Address to receive the LP tokens.
     * @return liquidity Amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address to
    ) external returns (uint256 liquidity) {
        // 1. Find or create the token pair
        address pairAddr = factory.getPair(tokenA, tokenB);
        if (pairAddr == address(0)) {
            pairAddr = factory.createPair(tokenA, tokenB);
        }

        // 2. Transfer tokens from the user to the pair
        IERC20(tokenA).safeTransferFrom(msg.sender, pairAddr, amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, pairAddr, amountBDesired);

        // 3. Mint LP tokens to the user
        liquidity = ISimplePair(pairAddr).mint(to);
    }
}
```

> 注意：`Router` 的示例是教学版，实际 Router 要计算 `amountOut` **并传递实际 expected output**，或者调用 Pair 的 swap 并处理 amounts precisely. 在课程中我们会把 Router 做成能计算 `getAmountOut`、`quote`、`getAmountsOut` 的完整版本（与 UniswapV2Router 更相似）。

---

## 5. Foundry 测试思路（示例片段）

用 Foundry 写测试覆盖：Create pair、add liquidity、swap、remove liquidity、滑点测试。

```solidity
// SPDX-License-Identifier: UNLICENSED
// DexTest.t.sol
// Description: Test contract for the decentralized exchange (DEX) functionality.
// Author: Your Name
// Version: 1.0.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleFactory.sol";
import "../src/SimpleRouter.sol";
import "../src/SimplePair.sol";

/**
 * @title DexTest
 * @dev Test contract for the decentralized exchange (DEX) functionality.
 * This contract tests the token swap and liquidity provision features of the DEX.
 */
contract DexTest is Test {
    // Token contracts for testing
    TestToken tokenA;
    TestToken tokenB;

    // DEX components
    SimpleFactory factory;
    SimpleRouter router;
    address pair;

    // Test user addresses
    address user1 = address(0x123);
    address user2 = address(0x234);

    /**
     * @dev Setup function to initialize the test environment.
     * - Deploys token contracts (TokenA and TokenB).
     * - Deploys the DEX factory and router.
     * - Creates a token pair (TokenA/TokenB).
     * - Mints tokens to test users (user1 and user2).
     * - Adds initial liquidity to the pair via user1.
     */
    function setUp() public {
        // Deploy token contracts
        tokenA = new TestToken("TokenA", "TKA");
        tokenB = new TestToken("TokenB", "TKB");

        // Deploy DEX factory and router
        factory = new SimpleFactory();
        router = new SimpleRouter(address(factory));

        // Create a token pair (TokenA/TokenB)
        pair = factory.createPair(address(tokenA), address(tokenB));

        // Mint tokens to test users (user1 and user2)
        tokenA.mint(user1, 1000 ether);
        tokenB.mint(user1, 1000 ether);
        tokenA.mint(user2, 1000 ether);
        tokenB.mint(user2, 1000 ether);

        // Add initial liquidity to the pair via user1
        vm.startPrank(user1);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether, // Amount of TokenA to add
            100 ether, // Amount of TokenB to add
            user1      // Recipient of LP tokens
        );
        vm.stopPrank();
    }

    /**
     * @dev Test function to verify token swap functionality via the router.
     * - Simulates a token swap (TokenA -> TokenB) by user2.
     * - Checks the token balances before and after the swap.
     * - Asserts that the swap results in the expected token balance changes.
     */
    function testSwapWithRouter() public {
        // Start acting as user2
        vm.startPrank(user2);

        // Record token balances before the swap
        uint256 beforeA = tokenA.balanceOf(user2);
        uint256 beforeB = tokenB.balanceOf(user2);

        // Approve the router to spend user2's TokenA
        tokenA.approve(address(router), type(uint256).max);

        // Execute the swap: 10 TokenA -> TokenB
        router.swapExactTokensForTokens(
            10 ether, // Amount of TokenA to swap
            0,        // Minimum amount of TokenB expected (0 to avoid revert)
            address(tokenA), // Input token (TokenA)
            address(tokenB), // Output token (TokenB)
            user2     // Recipient of TokenB
        );

        // Record token balances after the swap
        uint256 afterA = tokenA.balanceOf(user2);
        uint256 afterB = tokenB.balanceOf(user2);

        // Stop acting as user2
        vm.stopPrank();

        // Assertions:
        // 1. TokenA balance should decrease by exactly 10 ether
        assertEq(beforeA - afterA, 10 ether, "tokenA spent not match");
        // 2. TokenB balance should increase by some amount (>0)
        assertGt(afterB - beforeB, 0, "tokenB not received");
    }
}
```

> 测试需精确计算 `amountOut` 的公式（课程中会给出 `getAmountOut(amountIn, reserveIn, reserveOut)` 函数并在 Router 与测试中统一使用）。

**验证流程**：  

```bash
➜  dex git:(main) ✗ forge test --match-path test/DexTest.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 37 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 560.13ms
Compiler run successful!

Ran 1 test for test/DexTest.t.sol:DexTest
[PASS] testSwapWithRouter() (gas: 130588)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.59ms (180.63µs CPU time)

Ran 1 test suite in 149.39ms (1.59ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```  

> 使用 `-vvvv` 可以看到更详细的日志信息

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