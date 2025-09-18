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
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LPToken.sol";

contract SimplePair is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token0;
    IERC20 public token1;
    LPToken public lpToken;

    uint112 private reserve0; // uses single slot, must be uint112
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public constant FEE_NUM = 3; // 0.3% fee numerator
    uint256 public constant FEE_DEN = 1000; // denominator

    address public constant MINIMUM_LIQUIDITY_HOLDER = address(0xdead);

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

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        // deploy LP token with pair as minter
        lpToken = new LPToken("SimpleLP", "sLP");
    }

    function getReserves() public view returns (uint112 r0, uint112 r1) {
        return (reserve0, reserve1);
    }

    // ---- ADD LIQUIDITY: mint LP tokens ----
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
            // initial liquidity
            liquidity = sqrt(amount0 * amount1) - 1000; // lock a minimum liquidity to avoid divide by zero later
            lpToken.mint(MINIMUM_LIQUIDITY_HOLDER, 1000); // burn 1000 to lock
        } else {
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
    function burn(
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = lpToken.balanceOf(address(this));
        uint256 _totalSupply = lpToken.totalSupply();

        require(liquidity > 0, "No liquidity");

        // transfer LP tokens from sender to pair and burn
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
    // caller transfers tokens in before calling swap; we accept amount0Out/amount1Out to be sent to `to`
    // This function follows CEI and checks the invariant after fee
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

        // --- Transfer output tokens first ---
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        // --- Compute input amounts ---
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

        // --- Check constant product invariant with fee ---
        require(
            (balance0 * FEE_DEN - amount0In * FEE_NUM) *
                (balance1 * FEE_DEN - amount1In * FEE_NUM) >=
                uint256(reserve0) * reserve1 * FEE_DEN * FEE_DEN,
            "K"
        );

        // --- Update reserves ---
        _update(uint112(balance0), uint112(balance1));

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);

        // --- Flash swap hook ---
        if (data.length > 0) {
            // optional callback
        }
    }

    // ---- HELPERS ----
    function _update(uint112 _reserve0, uint112 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp % 2 ** 32);
        emit Sync(_reserve0, _reserve1);
    }

    // ---- UTILITIES ----
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
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
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleFactory.sol";

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

contract SimpleRouter {
    using SafeERC20 for IERC20;
    SimpleFactory public factory;

    constructor(address _factory) {
        factory = SimpleFactory(_factory);
    }

    // UniswapV2-style getAmountOut but parameterized by fee numerator/denominator
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

    // swapExactTokensForTokens (single-hop, simplified)
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to
    ) external {
        address pairAddr = factory.getPair(tokenIn, tokenOut);
        require(pairAddr != address(0), "PAIR_NOT_EXIST");
        ISimplePair pair = ISimplePair(pairAddr);

        // transfer tokenIn from user to pair (pair will see increased balance)
        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddr, amountIn);

        // read reserves and map to in/out order
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

        // call swap on the pair with correct output side
        if (token0 == tokenIn) {
            // tokenIn is token0, so we want token1 out
            pair.swap(0, amountOut, to, "");
        } else {
            // tokenIn is token1, so token0 out
            pair.swap(amountOut, 0, to, "");
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address to
    ) external returns (uint256 liquidity) {
        // 1. 找到或创建交易对
        address pairAddr = factory.getPair(tokenA, tokenB);
        if (pairAddr == address(0)) {
            pairAddr = factory.createPair(tokenA, tokenB);
        }

        // 2. 把用户的 token 转到 pair
        IERC20(tokenA).safeTransferFrom(msg.sender, pairAddr, amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, pairAddr, amountBDesired);

        // 3. 调用 pair 的 mint，铸造 LP 给用户
        liquidity = ISimplePair(pairAddr).mint(to);
    }
}
```

> 注意：`Router` 的示例是教学版，实际 Router 要计算 `amountOut` **并传递实际 expected output**，或者调用 Pair 的 swap 并处理 amounts precisely. 在课程中我们会把 Router 做成能计算 `getAmountOut`、`quote`、`getAmountsOut` 的完整版本（与 UniswapV2Router 更相似）。

---

## 5. Foundry 测试思路（示例片段）

用 Foundry 写测试覆盖：Create pair、add liquidity、swap、remove liquidity、滑点测试。

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleFactory.sol";
import "../src/SimplePair.sol";
import "../src/SimpleRouter.sol";

contract DexTest is Test {
    TestToken tokenA;
    TestToken tokenB;
    SimpleFactory factory;
    SimpleRouter router;
    address alice = address(0x123);
    address bob = address(0x234);

    function setUp() public {
        tokenA = new TestToken("TokenA", "TKA");
        tokenB = new TestToken("TokenB", "TKB");
        factory = new SimpleFactory();
        router = new SimpleRouter(address(factory));
        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 1_000_000e18);
        tokenA.mint(bob, 1_000_000e18);
        tokenB.mint(bob, 1_000_000e18);
    }

    function testAddLiquidityAndSwap() public {
        // 地址
        address user1 = address(0x123);
        address user2 = address(0x234);

        // 准备 token

        // 发币给用户
        tokenA.mint(user1, 1e21);
        tokenB.mint(user1, 1e21);
        tokenA.mint(user2, 1e21);
        tokenB.mint(user2, 1e21);

        // 创建 router + factory + pair

        // 用户1 添加流动性
        vm.startPrank(user1);
        tokenA.approve(address(router), 1e21);
        tokenB.approve(address(router), 1e21);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1e21,
            1e21,
            user1
        );
        vm.stopPrank();

        // 获取 pair
        ISimplePair pair = ISimplePair(
            factory.getPair(address(tokenA), address(tokenB))
        );

        // 用户2 想 swap tokenA -> tokenB
        uint256 reserveA;
        uint256 reserveB;
        (reserveA, reserveB) = pair.getReserves();

        uint256 amountOut = 9e18; // 想要输出的 tokenB
        uint256 FEE_NUM = 3;
        uint256 FEE_DEN = 1000;

        // 按恒定乘积公式计算需要多少 tokenA 输入
        // amountIn = ((reserveIn * amountOut * FEE_DEN) / ((reserveOut - amountOut) * (FEE_DEN - FEE_NUM))) + 1
        uint256 amountIn = (reserveA * amountOut * FEE_DEN) /
            ((reserveB - amountOut) * (FEE_DEN - FEE_NUM)) +
            1;

        uint256 beforeA = tokenA.balanceOf(user2);
        uint256 beforeB = tokenB.balanceOf(user2);

        // 批准 + 转账 + swap
        vm.startPrank(user2);
        tokenA.approve(address(pair), amountIn);
        tokenA.transfer(address(pair), amountIn);
        pair.swap(0, amountOut, user2, "");
        vm.stopPrank();

        uint256 afterA = tokenA.balanceOf(user2);
        uint256 afterB = tokenB.balanceOf(user2);

        // B 收到正确数量
        assertEq(afterB - beforeB, amountOut);

        // A 支出至少 amountIn（也可以允许多一点，因为手续费）
        assertGe(beforeA - afterA, amountIn);
    }
}
```

> 测试需精确计算 `amountOut` 的公式（课程中会给出 `getAmountOut(amountIn, reserveIn, reserveOut)` 函数并在 Router 与测试中统一使用）。

---

