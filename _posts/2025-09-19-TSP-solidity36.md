---
layout: post
title: 《纸上谈兵·solidity》第 35 课：去中心化交易所（DEX）实战 — 上线
tags: solidity
mermaid: false
math: false
--- 

## 6. 前端（React + ethers.js v6）示例（Swap + Add Liquidity）

前端要点：

* 用 ethers v6 的 `BrowserProvider` 与 `Signer`（之前在教程使用过）
* 在发起 swap 之前**先估算 amountOut**（用 on-chain `getReserves()` 和 `getAmountOut` 公式）并展示滑点风险（比如设置 minAmountOut = amountOut \* (1 - slippage))
* 对用户友好显示价格、预估滑点、手续费和池子深度

下面是一个简化的 Swap UI 组件（注意：需替换合约地址 & ABI 文件）：

```jsx
// SwapWidget.jsx
import React, { useEffect, useState } from "react";
import { ethers } from "ethers";
import SimpleFactoryABI from "./abi/SimpleFactory.json";
import SimplePairABI from "./abi/SimplePair.json";
import IERC20ABI from "./abi/IERC20.json";

const FACTORY_ADDR = "0x..."; // 部署好的 factory

function getAmountOut(amountIn, reserveIn, reserveOut) {
  // UniswapV2 formula with fee 0.3% (numerator 997, denominator 1000)
  const amountInWithFee = amountIn * 997n;
  const numerator = amountInWithFee * BigInt(reserveOut);
  const denominator = (BigInt(reserveIn) * 1000n) + amountInWithFee;
  return numerator / denominator;
}

export default function SwapWidget({ tokenInAddr, tokenOutAddr }) {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [factory, setFactory] = useState(null);
  const [pairAddr, setPairAddr] = useState(null);
  const [reserveIn, setReserveIn] = useState(0n);
  const [reserveOut, setReserveOut] = useState(0n);
  const [amountIn, setAmountIn] = useState("0.0");
  const [amountOutEst, setAmountOutEst] = useState("0.0");
  const [slippage, setSlippage] = useState(0.005); // 0.5%

  useEffect(() => {
    if (!window.ethereum) return;
    const p = new ethers.BrowserProvider(window.ethereum);
    setProvider(p);
    p.getSigner().then(s => setSigner(s));
    const f = new ethers.Contract(FACTORY_ADDR, SimpleFactoryABI, p);
    setFactory(f);
  }, []);

  useEffect(() => {
    if (!factory || !tokenInAddr || !tokenOutAddr) return;
    async function loadPair() {
      const addr = await factory.getPair(tokenInAddr, tokenOutAddr);
      setPairAddr(addr);
      if (addr !== ethers.ZeroAddress) {
        const pair = new ethers.Contract(addr, SimplePairABI, provider);
        const r = await pair.getReserves();
        // need to map reserves to tokenIn/tokenOut order
        const token0 = tokenInAddr.toLowerCase() < tokenOutAddr.toLowerCase() ? tokenInAddr : tokenOutAddr;
        const reserve0 = BigInt(r[0].toString());
        const reserve1 = BigInt(r[1].toString());
        if (token0 === tokenInAddr.toLowerCase()) {
          setReserveIn(reserve0);
          setReserveOut(reserve1);
        } else {
          setReserveIn(reserve1);
          setReserveOut(reserve0);
        }
      }
    }
    loadPair();
  }, [factory, tokenInAddr, tokenOutAddr, provider]);

  useEffect(() => {
    if (!reserveIn || !reserveOut) return;
    try {
      const ai = BigInt(ethers.parseUnits(amountIn || "0", 18).toString());
      const out = getAmountOut(ai, reserveIn, reserveOut);
      setAmountOutEst(ethers.formatUnits(out.toString(), 18));
    } catch (e) {
      setAmountOutEst("0.0");
    }
  }, [amountIn, reserveIn, reserveOut]);

  async function swap() {
    if (!signer || !pairAddr) return alert("Connect wallet or no pair");
    const pair = new ethers.Contract(pairAddr, SimplePairABI, signer);
    const tokenIn = new ethers.Contract(tokenInAddr, IERC20ABI, signer);
    const tokenOut = new ethers.Contract(tokenOutAddr, IERC20ABI, signer);

    const decimals = 18; // adapt per token
    const amountInParsed = ethers.parseUnits(amountIn, decimals);

    // Estimate amountOut
    const amountOut = BigInt(ethers.parseUnits(amountOutEst, decimals).toString());
    const minOut = amountOut - (amountOut * BigInt(Math.floor(slippage * 10000))) / 10000n; // convert slippage to fraction

    // Approve pair to spend tokenIn
    const allowance = await tokenIn.allowance(await signer.getAddress(), pairAddr);
    if (BigInt(allowance.toString()) < BigInt(amountInParsed.toString())) {
      const tx = await tokenIn.approve(pairAddr, amountInParsed);
      await tx.wait();
    }

    // Determine which side to call: we must call swap(amount0Out, amount1Out, to, "")
    // Map tokenIn/tokenOut to token0/token1
    const token0Addr = await pair.token0();
    let tx;
    if (token0Addr.toLowerCase() === tokenInAddr.toLowerCase()) {
      // tokenIn is token0 -> output is token1
      const amount1Out = BigInt(minOut.toString());
      tx = await pair.swap(0n, amount1Out, await signer.getAddress(), "0x");
    } else {
      const amount0Out = BigInt(minOut.toString());
      tx = await pair.swap(amount0Out, 0n, await signer.getAddress(), "0x");
    }
    await tx.wait();
    alert("Swap executed");
  }

  return (
    <div>
      <h3>Swap</h3>
      <input value={amountIn} onChange={(e) => setAmountIn(e.target.value)} />
      <p>Estimated Out: {amountOutEst}</p>
      <p>Slippage: {(slippage*100).toFixed(2)}%</p>
      <button onClick={swap}>Swap</button>
    </div>
  );
}
```

> 前端注意点（非常重要）：
>
> * 前端必须计算 `minAmountOut`（根据滑点设置），并提交给链上 swap。上面示例里我们直接 used `minOut` naive 版本演示思路，实际请确保精确的整数 math 与 token decimals。
> * 显示 `price impact`、`pool depth`（reserves）和 `expected fee`，并在用户确认对话框里再次提醒。
> * 对 ERC20 的 `decimals` 要按 token 实际值处理（用 `token.decimals()` RPC 调用）。
> * 使用 `estimateGas` 与 `gasLimit` 预估，防止交易失败。

---

## 7. 安全与审计要点（必看）

1. **滑点与前端保护**：强制用户设置 slippage tolerance 与显示 price impact，避免被链上前端 MEV 抽走。
2. **闪电贷 & 价格操控**：任何基于 on-chain 单一价格的协议都易受闪电贷操控；在更复杂场景用 TWAP 或外部预言机。
3. **重入**：在 Pair 的 `swap`、`mint`、`burn` 函数使用 CEI 与 `nonReentrant`（示例中有）。
4. **整数精度**：谨慎使用 `uint112`/`uint256`，并在 math 中避免精度误差。
5. **ERC20 不返 bool 问题**：使用 `SafeERC20`。
6. **初始流动性**：锁定初始流动性（prevent front-running initial add）并用合理机制避免被人“擦除”初始 k。
7. **检查 overflow/underflow**：Solidity ^0.8 自带检查，但仍要注意乘法可能溢出，尽量用 `uint256`。
8. **权限与升级**：生产环境中 router/factory/feeTo 等应当由治理（多签）管理；升级合约必须受多签或 timelock 控制。
9. **广泛测试**：包含大量 fuzz 测试（Foundry fuzz）、Slither 静态检查、Echidna 模糊测试。

---

## 8. 练习题（分层）

**基础练习**

1. 实现 `getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)` 并在 Router 中使用，写测试确认输出一致性。
2. 将 `SimplePair` 中的 `mint` / `burn` 做得更严谨：LPToken 的 `transferFrom`/`mint`/`burn` 按 UniswapV2 的逻辑实现（包括 `MINIMUM_LIQUIDITY`）。

**进阶练习**

1. 在 Pair 中加入 `kLast` 用于 fee-on-transfer 模式（Uniswap 的 `feeTo`），并实现 `collectFees`。
2. 实现 Router 的 `swapExactTokensForTokensSupportingFeeOnTransferTokens` 来支持有转账手续费(token tax) 的代币。

**高级练习**

1. 实现多跳 Router（`getAmountsOut`、`swapExactTokensForTokens` 支持 path\[]）。
2. 把 Pair 改为可升级代理（注意升级也要受到多签控制），并写出升级流程测试。
3. 给 Pair 添加 TWAP oracle（用累加器技术记录 price0CumulativeLast/price1CumulativeLast），并写出计算 TWAP 的方法与测试。

---

## 9. 交付清单（课程产出）

* 可编译的 Solidity 合约文件（Token, LPToken, Pair, Factory, Router）。
* Foundry 测试示例（覆盖 addLiquidity / swap / removeLiquidity）。
* React 前端示例（Swap + AddLiquidity UI，ethers v6），含代码片段与注意事项。
* 安全审计清单与练习题。

