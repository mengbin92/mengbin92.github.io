---
layout: post
title: 《纸上谈兵·solidity》第 34 课：多签钱包（Multisig Wallet）-- 上线
tags: solidity
mermaid: false
math: false
---  

## 4. 前端交互（React + ethers.js）——精确且可直接运行的示例

前端要能完成以下流程：

* 连接钱包（MetaMask / WalletConnect）；
* 列出 owners、required、提案列表与每个提案的确认状态；
* 提交新提案（目标地址、ETH 数量、ABI data 可通过简单 UI 或“使用代币转账”模版生成）；
* 点击“确认” / “撤销” / “执行”；
* 展示 events 日志（可从链上监听或轮询 fetch）。

**前端注意事项**

* 当生成 `data`（ABI-encoded）时，推荐前端提供「模板」，例如代币转账模板（选择 token 合约、输入接收方与数量，然后自动生成 `transfer` 的 data），以减少用户填错 raw hex 的概率。
* 对于关键操作（提交高额转账、owner 变更、阈值变更），在前端显示清晰提示、所需确认人数以及预计 gas 以供审查。
* 推荐在 UI 上显示每个 tx 的确认者名单（可通过遍历 owners 检查每个 owner 的 `confirmations[txId][owner]`）。

---

## 5. 部署建议与运维流程

* 在测试网（Sepolia / Goerli）或者本地测试网络做完整流程测试：创建 3 个私钥作为 owners，完成从提交→确认→执行的 end-to-end 测试；
* 部署合约后，**不要把 addOwner/removeOwner/changeRequirement 等函数设为外部任何人都能调用**；生产建议把这些函数限制为只能由合约本身调用（`require(msg.sender == address(this))`），并通过多签交易去变更 owner；也可把这些函数删除，只保留能通过执行交易来调用 `upgrade`/`gov` 合约的能力；
* 上线前请用 Etherscan/Block explorers 验证合约源码；
* 使用多签管理敏感操作（部署新合约、提取资金、升级代理合约等）；
* 多签的 RPC 节点/前端应做监控与报警（异常提案、连环撤销／确认行为、预定执行时间到达等）。

---

## 6. 安全检查清单（上线前必须走完）

* [ ] `executeTransaction` 是否在 CEI 模式并且有 `nonReentrant`？（本例有）
* [ ] 有没有允许单个 owner 单独改变关键参数？（避免）
* [ ] 是否记录事件，便于链上审计？（有）
* [ ] 是否对 owners 数据结构 /去重 / zero address 做校验？（构造函数有）
* [ ] 是否考虑到 ERC20 token 不返回 bool 的情况？（前端/脚本需谨慎）
* [ ] 是否限制合约能执行自身的敏感调用（如 self-destruct 等）？（审核）
* [ ] 是否有 timelock / delay 可选？（建议对大额或 owner 变动加入 timelock）
* [ ] 是否有合理的报警/通知机制（邮件/Slack/ops）当有高额提案时？
* [ ] 代码是否经过静态分析（Slither）与模糊测试（Echidna / Foundry fuzz）？
* [ ] 是否对 gas 进行压力测试（大量者、并发 confirmations）？

---

## 7. 课后练习（分级）

为加深理解，我们可以逐级练习：

### 练习 A（入门，必做）

* 把本合约改造为：**禁止单个 owner 直接调用 `addOwner` / `removeOwner` / `changeRequirement`**；要求这些方法只能由合约自身调用（即 `require(msg.sender == address(this))`）。然后通过 multisig 提案变更 owner。

### 练习 B（进阶）

* 为合约增加 **timelock**：当提交某类敏感交易（例如 `addOwner`、`removeOwner`、`changeRequirement`）并达到 confirmations，加入一个延迟（比如 48 小时）后才能执行；让普通转账仍可即时执行。实现思路：在 `submitTransaction` 标记它是否为敏感 tx（或检查目标是否为合约自身），并存储 `readyTimestamp`，`executeTransaction` 时检查时间是否到。

### 练习 C（更进阶）

* 实现**提案签名离线流程**：支持 owner 在离线时对一个 tx 的 hash 做 ECDSA 签名，然后由任意人提交这些签名到合约进行聚合验证以确认 tx（减少 on-chain confirm 的 txs）。

> 这涉及 EIP-712 签名标准与防重放。实现后可显著减少 confirmations 所需的链上操作次数。

### 练习 D（生产化）

* 将多签包装成一个升级安全的代理（Upgradeable pattern），并用 OpenZeppelin 的 Proxy 实现升级，但要确保升级本身也受多签控制。
* 集成前端通知：在有新 tx 提交或 confirmations 时，发送 webhook 到运维通道（后端监听事件并触发）。

---

## 8. 常见问题与陷阱

Q: 多签能否直接调用 ERC20 的 `transfer`？
A: 可以，通过构造 `data = abi.encodeWithSignature("transfer(address,uint256)", to, amount)` 并把 `destination` 指为 token 合约地址，value 为 0。多签合约会 `call` token 合约执行这一方法。

Q: 为何要 `txn.executed = true` 在 call 之前？
A: 防止在外部 call 中被重入导致重复执行（CEI 模式）。我们也加了 `nonReentrant` 做双重保险。

Q: 多签是否应支持智能合约 owners？
A: 可以，但如果 owner 是合约，要确保它能以受控方式签署/确认（例如通过 Gnosis Safe 的合约模块）。测试时加入合约 owners 会更复杂。

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