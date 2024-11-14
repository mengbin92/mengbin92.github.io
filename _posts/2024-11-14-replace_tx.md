---
layout: post
title: replacement transaction underpriced
tags: ethereum
mermaid: false
math: false
---  

在与以太坊区块链进行交互时，特别是在发送交易时，你可能会遇到一个错误信息：`replacement transaction underpriced`。这个错误通常出现在试图替换已经在交易池中的交易时，新的交易的 **gasPrice** 太低。下面将解释为什么会出现这个错误，介绍它的背景，以及如何避免这个问题。

---

## 为什么会出现 `replacement transaction underpriced` 错误？

**错误原因**：

`replacement transaction underpriced` 错误通常在以下情况下发生：

1. **尝试替换一个已经在交易池中的交易**，但新交易的 **gasPrice** 太低，不足以被矿工接受。
2. 以太坊节点使用了 **交易替代机制**（Replacement Transaction），如果你尝试替换一个已经提交到交易池的交易，但新的交易的 `gasPrice` 没有达到预期的标准，节点会抛出这个错误。

**交易替代机制（Replacement Transaction）**  

在以太坊中，交易池（mempool）中的交易通常会被按 **gasPrice** 排序。矿工会优先选择 **gasPrice** 较高的交易进行打包。为了保证交易能够尽快被矿工打包，你可能会选择通过一个新的交易来 **替换** 之前的交易，并提高其 `gasPrice`。

例如，如果你提交了一个交易，但它长时间未被矿工处理，你可能希望通过提交一个新的交易，并设置一个更高的 `gasPrice` 来替代这个交易，促使矿工优先处理它。

但是，替代交易的 **gasPrice** 必须比原来的交易 **高**。如果你尝试用较低的 `gasPrice` 替代原有交易，就会遇到 `replacement transaction underpriced` 错误。

**具体情景**：

- 假设你提交了一笔交易，`gasPrice` 为 20 Gwei，但该交易在交易池中停留了较长时间，未被矿工处理。于是你提交了一个新交易，想要替换原交易，设置了 19 Gwei 的 `gasPrice`。
- 由于新交易的 `gasPrice` 低于原交易的 `gasPrice`，即使是替换交易，矿工也更倾向于优先处理 `gasPrice` 更高的交易，因此你会遇到 `replacement transaction underpriced` 错误。

---

## 什么是交易替代机制（Replacement Transaction）？

以太坊的 **交易替代机制** 是指，当你已经提交了一笔交易并且该交易还在交易池中，但由于某种原因（如未被处理或 `gasPrice` 太低），你可以通过提交一个新的交易来替代旧交易。新的交易必须满足以下条件：

1. 新交易的 **nonce** 必须与原交易相同。
2. 新交易的 **gasPrice** 必须大于原交易的 `gasPrice`（否则会触发 `replacement transaction underpriced` 错误）。
3. 新交易的其他内容可以不同，比如接收地址、数据、交易值等。

这个机制是为了允许用户通过提高 `gasPrice`，让自己的交易优先被矿工处理。

**交易替代的应用场景**：

1. **交易被卡住**：当你发送的交易由于 `gasPrice` 太低而长时间未被处理时，你可以提交一个新的交易，并通过提高 `gasPrice` 来确保它被矿工优先处理。
2. **手动控制交易优先级**：有时你可能希望通过设置更高的 `gasPrice`，确保某个重要的交易能够尽早被打包，比如在进行高价值转账或智能合约交互时。

---

## EIP-1559 和 `replacement transaction underpriced` 错误

### EIP-1559 简介

随着以太坊 **EIP-1559** 升级的实施，交易费用的计算方式发生了变化。EIP-1559 引入了 **base fee** 和 **tip**（小费）的概念，代替了原先的 `gasPrice`。在 EIP-1559 模式下，交易费用由网络自动调整，矿工不再直接决定每笔交易的费用，而是根据区块内的 **base fee** 和用户支付的小费来确定。

- **Base Fee**：每个区块的基本费用，由网络自动调整，反映了当前网络的负载。
- **Tip**：用户可以设置支付给矿工的小费（即 `maxPriorityFeePerGas`）。

EIP-1559 机制改变了传统的 `gasPrice` 设置方式，并引入了 **gasFeeCap**（最大费用上限）和 **maxPriorityFeePerGas**（优先费用）来确保交易优先级。在这种机制下，交易的 `gasPrice` 和传统的 `gasPrice` 不再是固定的，而是动态变化的。

### 为什么 EIP-1559 影响 `replacement transaction underpriced` 错误？

- 在 EIP-1559 模式下，替代交易的 **maxPriorityFeePerGas** 必须比原交易的 `maxPriorityFeePerGas` 高，或者至少等于原交易的 `gasFeeCap`。如果你提交一个替代交易，未能提高费用，就会触发 `replacement transaction underpriced` 错误。
- 即使在 EIP-1559 模式下，替代交易的 **最大费用** 也需要比原交易的费用高，否则新交易仍然会被拒绝。

---

## 如何避免 `replacement transaction underpriced` 错误？

### 1. 确保新交易的 `gasPrice` 高于原交易

如果你需要替代一个未处理的交易，确保新交易的 `gasPrice` 高于原交易的 `gasPrice`，特别是在使用传统的 `gasPrice` 模式时。如果你使用的是 EIP-1559 模式，则确保替代交易的 `maxPriorityFeePerGas` 比原交易的费用高。

### 2. 使用合适的工具和库

使用如 **Web3.js** 或 **Web3j** 等库时，确保在构建替代交易时正确设置 `gasPrice` 或 `maxPriorityFeePerGas`。例如：
   
**Web3.js 示例**：
```javascript
web3.eth.sendTransaction({
    from: '0xYourAddress',
    to: '0xRecipientAddress',
    value: web3.utils.toWei('1', 'ether'),
    gas: 21000,
    gasPrice: '20000000000'  // 确保 gasPrice 高于原交易
});
```

### 3. 检查交易的 Nonce

确保新交易的 **nonce** 与原交易相同。替代交易的 `nonce` 必须与已提交的原交易相同，以便替换它。

### 4. 使用适当的网络设置

在 EIP-1559 模式下，确保为替代交易设置合适的 `gasFeeCap` 和 `maxPriorityFeePerGas`，确保替代交易的费用足够高，能够被矿工优先处理。

---

`replacement transaction underpriced` 错误通常出现在试图替代未处理的交易时，新的交易的 `gasPrice` 或 `maxPriorityFeePerGas` 太低，导致矿工不愿意处理该交易。为了避免这个错误，你需要确保替代交易的费用高于原交易，或者在 EIP-1559 模式下，设置正确的 `gasFeeCap` 和 `maxPriorityFeePerGas`。通过了解以太坊的交易替代机制和 EIP-1559 的影响，你可以更有效地管理交易并确保它们能够顺利被处理。

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  
> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  
---