---
layout: post
title: 《纸上谈兵·solidity》第 48 课：DeFi 实战(12) -- 前端 DApp 集成与用户交互（React + ethers.js 实战）
tags: solidity
mermaid: false
math: false
---

> 鸽了大半个月，终于收尾了

## 1、学习目标

* 理解前端与智能合约交互的基本架构（Provider / Signer / Contract / Events / Off-chain indexer）。
* 用 `ethers.js` 在 React 中完成常见流程：Connect Wallet、Approve、Deposit、Borrow、Repay、提案/投票。
* 用 Hooks 抽象常用逻辑（useProvider/useWallet/useContract/useAsyncTx），实现整洁可复用的 UI 接口。
* 处理生产级问题：gas 估算、链切换、交易失败回滚、乐观 UI、事件订阅。
* 本地测试、集成、部署到 Vercel/Netlify 的要点。

---

## 2、架构概览与设计要点

推荐架构（前端单页 / React）：

* **Provider 层**（ethers Provider / Signer）
  * Read-only provider（RPC）用于链上数据读取
  * Signer provider（Metamask / WalletConnect）用于签名 tx
* **Contracts 层**
  * 抽象合同实例，按 network + address + ABI 组织
* **State 层**（React Context / Zustand / Redux）
  * 存放 wallet、chain、常用合约实例、用户余额、交易队列
* **UI 层**
  * 小组件：ConnectButton、TokenInput、TxButton、Modal、Notifications
  * 页面：Pool、Borrow、Dashboard、Governance

* **可选后端**（indexer / subgraph / TheGraph / Moralis）用于复杂查询与历史数据（避免前端频繁做 RPC scans）

设计要点：

* 把所有链交互封装在 Hook 中（便于测试与替换）
* 所有交易使用统一 `sendTx` 函数，负责：gas 估算、签名、等待、回滚、通知、重试策略
* 事件监听做防抖与去重（event logs 可能重复）
* 对 ERC20：始终做 `allowance` 检查并把 `approve` 做成 UX 流程（2 步：approve -> action）
* UI 对失败场景友好提示：revert message、nonce 溢出、insufficient funds、approval needed
* 支持链切换（提示用户切换到目标 chain 并尝试 programmatic switch）

---

## 3、核心前端概念（详细解释）

### 3.1 Provider / Signer / Contract

* **Provider**：只读的链连接（JsonRpcProvider），用于 read calls（balanceOf、totalDeposits）。
* **Signer**：代表用户签名交易（window.ethereum.getSigner()）。
* **Contract**：ethers.Contract(providerOrSigner)；用 provider 调 read、用 signer 调写 tx。

### 3.2 ERC20 流程（常见误区）

* 在调用 `pool.deposit()`（合约从用户 `transferFrom` 取款）前，必须 `token.approve(pool, amount)`。
* 把 `approve` 的 gas 和等待纳入 UX（显示 pending、等待 confirmations）。
* 有时 approve 需要先将 allowance 设为 0 再设新值以支持某些 ERC20（老代币 bug），但大多数现代代币支持直接设定。

### 3.3 事件监听 vs 轮询

* 事件监听（`contract.on('Deposit', handler)`）低延迟，但在断线/刷新后可能丢失历史事件 → 后端 indexer 或 RPC `getLogs` 补偿。
* 生产环境：结合 indexer（TheGraph）与事件监听，监听做 UX 推送，indexer 做页面历史展示与分页。

### 3.4 Gas 估算与用户体验

* 使用 `contract.estimateGas.functionName(...args)` 做估算；若估算失败（revert），在前端要捕获错误并显示可读提示。
* 对于复杂交易（多合约调用、重入可能），预估 gas 加安全系数（1.2x）并用 `gasLimit` 提交，避免因网络费用波动导致失败。

### 3.5 Error/ Revert 处理

* Ethers 抛出的错误 message 常常包含 JSON RPC 数据，解析方式要 robust（有时 revert message 在 `error.error.message` 或 `error.data` 下）。
* 把 revert 显示成可理解文本，如"存款失败：余额不足"或"许可不足，请先 Approve"。

---

## 4、实战：项目文件结构（实现示例）

本项目基于 **React + Vite + Tailwind CSS + ethers.js v5** 构建：

```bash
defi-frontend/
├── package.json
├── vite.config.js
├── tailwind.config.js
├── src/
│   ├── App.jsx                    # 主应用组件（标签页切换）
│   ├── main.jsx                   # 入口文件
│   ├── index.css                  # 全局样式
│   ├── hooks/                     # React Hooks
│   │   ├── useProvider.js         # Provider Hook（支持 window.ethereum 和 RPC）
│   │   ├── useWallet.js           # 钱包连接 Hook（账户、链、连接/断开）
│   │   ├── useContract.js         # 合约实例 Hook
│   │   └── useAsyncTx.js          # 异步交易 Hook（统一交易处理）
│   ├── components/                # React 组件
│   │   ├── ConnectButton.jsx      # 连接钱包按钮
│   │   ├── TokenInput.jsx         # 代币输入组件（带余额和最大按钮）
│   │   ├── TxButton.jsx           # 交易按钮（pending 状态）
│   │   ├── PoolPanel.jsx          # 借贷池面板（存款/借款/还款/提取）
│   │   └── GovernancePanel.jsx   # 治理面板（提案/投票/执行）
│   ├── utils/                     # 工具函数
│   │   ├── constants.js           # 合约地址和 RPC 配置
│   │   ├── format.js              # 格式化函数（代币、地址、错误）
│   │   └── governance.js          # 治理工具（calldata 生成、状态映射）
│   └── abis/                      # 合约 ABI
│       ├── ERC20Token.json
│       ├── LendingPool.json
│       ├── GovToken.json
│       ├── SimpleGovernor.json
│       └── RewardDistributor.json
└── contracts/                     # 智能合约源码（Solidity）
```

---

## 5、关键代码实现（项目实际代码）

### 5.1 `src/hooks/useProvider.js`

```javascript
import { useEffect, useState } from "react";
import { ethers } from "ethers";

/**
 * Provider Hook
 * 用于获取以太坊 Provider
 * @param {string} rpcUrl - RPC URL（可选，如果未提供则使用 window.ethereum）
 * @returns {ethers.providers.Provider|null} Provider 实例
 */
export function useProvider(rpcUrl) {
  const [provider, setProvider] = useState(null);

  useEffect(() => {
    if (typeof window !== "undefined" && window.ethereum) {
      const p = new ethers.providers.Web3Provider(window.ethereum, "any");
      setProvider(p);
      return;
    }
    if (rpcUrl) {
      setProvider(new ethers.providers.JsonRpcProvider(rpcUrl));
    }
  }, [rpcUrl]);

  return provider;
}
```

**要点**：
- 优先使用 `window.ethereum`（MetaMask 等钱包）
- 如果没有钱包，回退到 RPC URL（只读模式）
- 使用 `"any"` 网络模式以支持多链

### 5.2 `src/hooks/useWallet.js`

```javascript
import { useState, useEffect, useCallback } from "react";

/**
 * Wallet Hook
 * 用于管理钱包连接状态
 * @param {ethers.providers.Provider} provider - Provider 实例
 * @returns {Object} 钱包相关状态和方法
 */
export function useWallet(provider) {
  const [account, setAccount] = useState(null);
  const [signer, setSigner] = useState(null);
  const [chainId, setChainId] = useState(null);

  useEffect(() => {
    if (!provider) {
      setAccount(null);
      setSigner(null);
      setChainId(null);
      return;
    }

    const init = async () => {
      try {
        const accounts = await provider.listAccounts();
        if (accounts.length > 0) {
          const _signer = provider.getSigner();
          setSigner(_signer);
          const addr = await _signer.getAddress();
          setAccount(addr);
          const net = await provider.getNetwork();
          setChainId(net.chainId);
        } else {
          setAccount(null);
          setSigner(null);
        }
      } catch (e) {
        console.error("useWallet init error:", e);
        setAccount(null);
        setSigner(null);
      }
    };

    init();

    // 监听账户变化
    if (window.ethereum) {
      const handleAccountsChanged = (accounts) => {
        if (accounts.length > 0) {
          init();
        } else {
          setAccount(null);
          setSigner(null);
        }
      };

      const handleChainChanged = () => {
        init();
      };

      window.ethereum.on("accountsChanged", handleAccountsChanged);
      window.ethereum.on("chainChanged", handleChainChanged);

      return () => {
        window.ethereum.removeListener("accountsChanged", handleAccountsChanged);
        window.ethereum.removeListener("chainChanged", handleChainChanged);
      };
    }
  }, [provider]);

  const connect = useCallback(async () => {
    if (!provider) throw new Error("No provider");
    try {
      await provider.send("eth_requestAccounts", []);
      const _signer = provider.getSigner();
      setSigner(_signer);
      const addr = await _signer.getAddress();
      setAccount(addr);
      const net = await provider.getNetwork();
      setChainId(net.chainId);
    } catch (e) {
      console.error("Connect wallet error:", e);
      throw e;
    }
  }, [provider]);

  const disconnect = useCallback(() => {
    setAccount(null);
    setSigner(null);
    setChainId(null);
  }, []);

  return { account, signer, chainId, connect, disconnect };
}
```

**要点**：
- 自动检测已连接的账户（`listAccounts()`）
- 监听账户切换和链切换事件
- 提供 `connect()` 和 `disconnect()` 方法
- 自动更新 signer 和 chainId

### 5.3 `src/hooks/useContract.js`

```javascript
import { useMemo } from "react";
import { ethers } from "ethers";

/**
 * Contract Hook
 * 用于创建合约实例
 * @param {string} address - 合约地址
 * @param {Array} abi - 合约 ABI
 * @param {ethers.providers.Provider|ethers.Signer} providerOrSigner - Provider 或 Signer
 * @returns {ethers.Contract|null} 合约实例
 */
export function useContract(address, abi, providerOrSigner) {
  return useMemo(() => {
    if (!address || !abi || !providerOrSigner) return null;
    try {
      return new ethers.Contract(address, abi, providerOrSigner);
    } catch (e) {
      console.error("useContract error", e);
      return null;
    }
  }, [address, abi, providerOrSigner]);
}
```

**要点**：
- 使用 `useMemo` 避免重复创建合约实例
- 支持 provider（只读）和 signer（可写）
- 自动处理错误情况

### 5.4 `src/hooks/useAsyncTx.js`

统一发送 tx 的 hook：估 gas、发送、等待、通知。

```javascript
import { useState } from "react";

/**
 * Async Transaction Hook
 * 用于处理异步交易，包括 gas 估算、发送、等待、错误处理
 * @returns {Object} 交易相关状态和方法
 */
export function useAsyncTx() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(null);

  const sendTx = async (txPromise, onReceipt) => {
    setError(null);
    setPending(true);
    try {
      const tx = await txPromise;
      // 如果 tx 是 TransactionResponse
      if (tx && tx.wait) {
        const receipt = await tx.wait();
        if (onReceipt) onReceipt(receipt);
        setPending(false);
        return receipt;
      } else {
        // 已经是 receipt 或结果
        setPending(false);
        if (onReceipt) onReceipt(tx);
        return tx;
      }
    } catch (e) {
      // 解析 revert 字符串
      let msg = e?.error?.message || e?.message || String(e);
      setError(msg);
      setPending(false);
      throw e;
    }
  };

  const clearError = () => {
    setError(null);
  };

  return { sendTx, pending, error, clearError };
}
```

**要点**：
- 统一处理交易状态（pending、error）
- 自动等待交易确认（`tx.wait()`）
- 支持回调函数（`onReceipt`）
- 错误解析和状态管理

### 5.5 `src/components/PoolPanel.jsx`（核心功能）

借贷池面板：展示 pool stats 并提供 deposit/borrow/repay/withdraw flow。

**关键实现**：

```javascript
// 确保 allowance 足够
const ensureAllowance = async (amount) => {
  if (!token || !pool || !signer || !account) return;

  const allowance = await token.allowance(account, CONTRACT_ADDRESSES.LendingPool);
  if (allowance.lt(amount)) {
    await sendTx(token.connect(signer).approve(CONTRACT_ADDRESSES.LendingPool, amount));
  }
};

// 存款（自动处理 approve）
const handleDeposit = async () => {
  if (!token || !pool || !signer) {
    alert("请先连接钱包");
    return;
  }

  try {
    clearError();
    const amt = parseToken(depositVal);
    if (amt.lte(0)) {
      alert("请输入有效的金额");
      return;
    }

    await ensureAllowance(amt);
    await sendTx(pool.connect(signer).deposit(amt), () => {
      setDepositVal("");
      setTimeout(() => window.location.reload(), 2000);
    });
  } catch (e) {
    console.error("Deposit error:", e);
    alert(formatError(e));
  }
};
```

**要点**：
- 自动检查并处理 `approve`（`ensureAllowance`）
- 使用 `formatToken`/`parseToken` 处理代币数量
- 交易成功后刷新数据
- 友好的错误提示

### 5.6 `src/components/GovernancePanel.jsx`（治理功能）

治理面板：创建提案、投票、执行提案。

**关键实现**：

```javascript
// 创建提案
const handleCreateProposal = async () => {
  if (!governor || !signer) {
    alert("请先连接钱包");
    return;
  }

  try {
    clearError();

    if (!proposalTarget || !proposalCalldata || !proposalDescription) {
      alert("请填写完整的提案信息");
      return;
    }

    const targets = [proposalTarget];
    const values = [0];
    const calldatas = [proposalCalldata];

    await sendTx(
      governor.connect(signer).propose(targets, values, calldatas, proposalDescription),
      () => {
        setProposalDescription("");
        setProposalTarget("");
        setProposalCalldata("");
        alert("提案创建成功！");
        loadProposals();
      }
    );
  } catch (e) {
    console.error("Create proposal error:", e);
    alert(formatError(e));
  }
};

// 投票
const handleVote = async (proposalId, support) => {
  if (!governor || !signer) {
    alert("请先连接钱包");
    return;
  }

  try {
    clearError();
    await sendTx(governor.connect(signer).castVote(proposalId, support), () => {
      alert("投票成功！");
      loadProposals();
    });
  } catch (e) {
    console.error("Vote error:", e);
    alert(formatError(e));
  }
};
```

**要点**：
- 支持手动输入 calldata 或使用工具生成
- 从事件加载提案列表（`getLogs`）
- 过滤无效提案（Canceled、Expired、测试提案）
- 显示提案状态和投票统计

### 5.7 `src/utils/format.js`（格式化工具）

```javascript
import { formatUnits, parseUnits } from "ethers/lib/utils";

/**
 * 格式化代币数量（从 wei 转换为可读格式）
 */
export function formatToken(value, decimals = 18, precision = 4) {
  if (!value || value.toString() === "0") return "0";
  try {
    const formatted = formatUnits(value, decimals);
    const num = parseFloat(formatted);
    if (num === 0) return "0";
    return num.toFixed(precision).replace(/\.?0+$/, "");
  } catch (e) {
    return "0";
  }
}

/**
 * 解析代币数量（从可读格式转换为 wei）
 */
export function parseToken(value, decimals = 18) {
  if (!value || value === "") return parseUnits("0", decimals);
  try {
    return parseUnits(value, decimals);
  } catch (e) {
    return parseUnits("0", decimals);
  }
}

/**
 * 格式化地址（显示前6位和后4位）
 */
export function formatAddress(address) {
  if (!address) return "";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/**
 * 格式化错误消息（用户友好）
 */
export function formatError(error) {
  if (!error) return "未知错误";
  
  const message = error.message || error.toString();
  
  // 常见错误消息映射
  if (message.includes("user rejected")) {
    return "用户拒绝了交易";
  }
  if (message.includes("insufficient funds")) {
    return "余额不足";
  }
  if (message.includes("allowance")) {
    return "许可不足，请先 Approve";
  }
  // ... 更多错误映射
  
  return message;
}
```

**要点**：
- 统一的代币格式化（避免精度问题）
- 用户友好的错误提示
- 地址格式化（缩短显示）

### 5.8 `src/utils/governance.js`（治理工具）

```javascript
import { ethers } from "ethers";

/**
 * 生成治理操作的 calldata
 */
export function generateCalldata(functionName, params, abi) {
  try {
    const iface = new ethers.utils.Interface(abi);
    return iface.encodeFunctionData(functionName, params);
  } catch (e) {
    console.error("Generate calldata error:", e);
    throw e;
  }
}

/**
 * 常用治理操作的 calldata 生成器
 */
export const GovernanceActions = {
  setCollateralRatio: (ratio) => {
    const abi = ["function setCollateralRatio(uint256 _ratio) external"];
    return generateCalldata("setCollateralRatio", [ratio], abi);
  },
  
  setMaxBorrowRatio: (ratio) => {
    const abi = ["function setMaxBorrowRatio(uint256 _ratio) external"];
    return generateCalldata("setMaxBorrowRatio", [ratio], abi);
  },
  
  setGovernance: (newGovernance) => {
    const abi = ["function setGovernance(address _governance) external"];
    return generateCalldata("setGovernance", [newGovernance], abi);
  },
};

/**
 * 提案状态映射
 */
export const ProposalState = {
  0: "Pending",
  1: "Active",
  2: "Canceled",
  3: "Defeated",
  4: "Succeeded",
  5: "Queued",
  6: "Expired",
  7: "Executed",
};

/**
 * 投票选项
 */
export const VoteOption = {
  Against: 0,
  For: 1,
  Abstain: 2,
};
```

**要点**：
- 简化 calldata 生成（避免手动编码）
- 预定义常用治理操作
- 状态和选项映射

---

## 6、项目启动与配置

### 6.1 安装依赖

```bash
npm install
```

**主要依赖**：

- `react` ^18.2.0
- `react-dom` ^18.2.0
- `ethers` ^5.7.2
- `tailwindcss` ^3.4.0
- `vite` ^5.0.8

### 6.2 配置合约地址

在 `src/utils/constants.js` 中配置：

```javascript
export const CONTRACT_ADDRESSES = {
  ERC20Token: "0x8c1094d088E2E2B62263326e2D88Ce512327CB3c",
  LendingPool: "0x3CB5b6E26e0f37F2514D45641F15Bd6fEC2E0c4c",
  GovToken: "0xBAdc777C579B497EdE07fa6FF93bdF4E31793F24",
  SimpleGovernor: "0x90Ea96DBA5bbbb4D2F798C47FE23453054c0FAB4",
  RewardDistributor: "0xF0b1b2A91AF3B0a0a5389eA80bFfDC42CF86B7e3",
};

// RPC URL
export const RPC_URL = "http://localhost:8545"; // 本地开发
// export const RPC_URL = "https://sepolia.infura.io/v3/YOUR_KEY"; // 测试网
```

### 6.3 启动开发服务器

```bash
npm run dev
```

应用将在 `http://localhost:5173` 启动。

### 6.4 本地测试流程

1. **启动本地节点**（Anvil / Hardhat）：
   ```bash
   # 使用 Anvil (Foundry)
   anvil
   
   # 或使用 Hardhat
   npx hardhat node
   ```

2. **部署合约**到本地节点

3. **更新合约地址**（`src/utils/constants.js`）

4. **配置 MetaMask**：
   - 添加本地网络（http://localhost:8545）
   - 导入测试账户私钥

5. **连接钱包**并开始交互

---

## 7、核心功能说明

### 7.1 借贷池功能

1. **存款（Deposit）**
   - 自动检查并处理 `approve`
   - 显示用户代币余额和存款余额
   - 交易成功后自动刷新数据
2. **借款（Borrow）**
   - 检查可用借款额度
   - 显示用户借款余额
   - 实时更新池子流动性
3. **还款（Repay）**
   - 自动处理 `approve`
   - 支持部分还款
   - 更新借款余额
4. **提取（Withdraw）**
   - 检查抵押率要求
   - 显示用户存款余额
   - 更新池子统计

### 7.2 治理功能

1. **创建提案**
   - 填写提案描述
   - 输入目标合约地址
   - 生成或手动输入 calldata
   - 检查提案阈值
2. **投票**
   - 支持、反对、弃权三种选项
   - 显示投票统计
   - 检查投票权（需要先委托）
3. **执行提案**
   - 提案通过后可执行
   - 显示提案状态
4. **委托代币**
   - ERC20Votes 代币需要先委托才能投票
   - 支持委托给自己

---

## 8、测试与调试

### 8.1 常见调试技巧

1. **打印交易 receipt**：
   ```javascript
   const receipt = await tx.wait();
   console.log("Tx hash:", receipt.transactionHash);
   console.log("Status:", receipt.status);
   console.log("Logs:", receipt.logs);
   ```

2. **模拟执行**（检查是否会 revert）：
   ```javascript
   try {
     await contract.callStatic.deposit(amount);
     console.log("模拟成功，可以执行");
   } catch (e) {
     console.error("模拟失败:", e);
   }
   ```

3. **检查 allowance**：
   ```javascript
   const allowance = await token.allowance(account, poolAddress);
   console.log("Allowance:", formatToken(allowance));
   ```

### 8.2 常见问题

1. **"用户拒绝了交易"**：用户在 MetaMask 中取消了交易
2. **"余额不足"**：账户 ETH 余额不足以支付 gas
3. **"许可不足"**：需要先调用 `approve`
4. **"Nonce 错误"**：交易 nonce 冲突，刷新重试

---

## 9、生产部署与运维要点

1. **RPC / Rate limits**：
   - 生产不要只依赖公共节点（Infura/Alchemy）
   - 使用自建节点或多 provider fallback
   - 实现 rate limit/backoff
2. **Indexing**：
   - 事件历史与复杂查询依赖 TheGraph 或自建 indexer
   - 避免前端做大量 `getLogs`
3. **Monitoring**：
   - 交易失败率、gas spikes、bridge latency
   - 需要监控并告警
4. **Feature flags / A/B**：
   - 通过后端/feature-flag 管理新功能 rollout
   - 避免前端直接暴露危险操作
5. **Rate-limited actions**：
   - 对高频操作做 debounce/rate-limit
   - 提示用户（避免重复发 tx 导致 nonce 混乱）

---

## 10、安全与 UX 最佳实践

* **钱包交互明确化**：在每次发送 tx 前弹出确认，显示 gas estimate、nonce、预期链上变化。
* **乐观 UI**：在 tx pending 时展示乐观变化（例如 "预计存款 +100"），但后台需在 tx confirmed 后矫正。
* **失败回滚提示**：把 revert message 解析成用户友好文本并提供解决建议。
* **避免隐式批准**：对 `approve` 做逐步确认（用户知道为什么需要 approve）。
* **安全显示**：不要在前端保存私钥、不要把敏感 ABI/action 嵌入公共 CDN。
* **硬件钱包支持**：测试 Ledger / Trezor 的签名流程。
* **Accessibility**：按钮要大、颜色对比要足、键盘可访问。

---

## 11、进阶

* **Meta-transactions / Gasless UX**：通过 relayer/biconomy 支持 gasless tx，降低入门门槛。
* **Batching**：将 approve + action 合并成一个 meta-tx（后端或合约支持）减少钱包弹窗次数。
* **Optimistic Updates + Queues**：为同一用户维护本地 pending tx 队列与 nonce 管理，避免并发冲突。
* **Front-run / MEV防护**：对关键操作（提案、清算）考虑 private mempool 或执行延时。

---

## 12、作业与扩展建议

1. 把 `useAsyncTx` 增强为支持：gasEstimate fallback、nonce queue、pending toast、retry。写单元测试覆盖失败场景。
2. 集成 TheGraph（或自建 indexer）来显示所有用户的历史 deposit/borrow/liquidation，用分页加载。
3. 做一个完整的 Governance UI：提案创建表单（可选择 target function）、投票历史、统计图表（投票率、支持率）。
4. 实现 mobile-friendly UX 并做 Lighthouse 性能优化（首屏渲染、RPC calls 节流）。
5. 在前端实现一个 Keeper 控制台（离线签名 + relayer）来触发 `accrueInterest` 与 `liquidate`，并记录回报。

项目完整代码可以从[这里](https://github.com/mengbin92/defi-example)获取。

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