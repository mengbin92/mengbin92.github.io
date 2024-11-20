---
layout: post
title: PoA Clique共识下新增验证者节点
tags: ethereum
mermaid: false
math: false
---

在前一篇文章中，我们介绍了PoA Clique共识下如何新增同步节点。本文将介绍如何在PoA Clique共识下新增验证者节点。  

**Clique 共识**是以太坊的**权威证明（Proof of Authority, PoA）**共识机制的一种实现，主要用于私链或测试链场景。在 Clique 共识中，验证者节点（Sealer Nodes）扮演了核心角色，负责区块的生成和链的维护。

## 1. 验证者节点的定义

验证者节点是 Clique 共识下的核心节点，负责以下任务：

- **提议新区块**：验证者通过轮流机制（Round Robin）提议新区块。
- **签署区块**：验证者在生成的区块中附加自己的数字签名，证明区块的合法性。
- **维持网络安全性**：验证者是唯一能够出块的节点，防止了非验证者的恶意挖矿。

## 2. 验证者节点的特点

- **固定列表**：验证者节点的身份是静态配置的，初始时由创世区块（genesis.json）定义。
- **动态调整**：运行时可以通过投票增减验证者节点。
- **身份明确**：验证者节点使用自己的账户地址作为身份标识。
- **无需高算力**：不像 PoW 共识，Clique 共识不需要复杂的计算，因此验证者节点对硬件要求较低。

## 3. 验证者节点的职责

1. **轮流出块**
   - 验证者节点按顺序轮流出块。
   - 如果轮到某个验证者，但它未及时出块（例如离线），下一个验证者将接替。
2. **遵守出块时间**
   - 出块间隔通常为固定时间（`period`，默认 15 秒），定义在创世文件中。
   - 每个验证者节点只能在自己的时间段内出块。
3. **签署区块**
   - 每个区块都必须由验证者节点签署，其签名信息保存在区块头中。
   - 验证者的签名证明区块是由合法的节点生成。
4. **防止恶意行为**
   - 验证者不能连续生成多个区块（除非其他验证者离线）。
   - Clique 共识通过强制的冷却时间防止一个验证者频繁出块。
5. **参与验证者管理**：验证者节点可以通过投票机制增加或移除其他验证者。

## 4. 验证者的管理

Clique 共识支持动态管理验证者节点：

- **增加验证者**：现有验证者可以提议增加新的验证者节点，超过 50% 的验证者投票赞成后，新的节点将成为验证者：
    ```javascript
    clique.propose("0xNewValidatorAddress", true)
    ```
- **移除验证者**：现有验证者可以提议移除某个验证者，超过 50% 的验证者投票赞成后，目标节点将被移除：
    ```javascript
    clique.propose("0xValidatorAddressToRemove", false)
    ```
- **验证者列表**：以下命令查看当前的验证者节点列表：
    ```javascript
    clique.getSigners()
    ```
- **检查当前出块状态**：通过以下命令查看当前节点的出块活动：
    ```javascript
    clique.status()
    ```

## 5. 验证者节点的出块机制

Clique 共识的出块机制如下：

1. **按顺序轮流出块**：每个验证者按预定顺序生成区块，顺序在创世文件中定义或通过验证者列表确定。
2. **冷却时间**：
   - 验证者在生成一个区块后，必须等待其他验证者出块后才能再次出块。
   - 如果强制出块，其他节点会拒绝该区块。
3. **容错机制**：如果某个验证者离线，其他验证者会接管出块，网络仍能正常运行。

## 6. 验证者节点的设置

**创世文件中定义验证者**：在创世区块配置（`genesis.json`）中，可以通过 `extraData` 字段定义初始验证者。

示例：

```json
"extraData": "0x0000000000000000000000000000000000000000000000000000000000000000<validators_addresses_in_hex>0000000000000000000000000000000000000000000000000000000000000000"
```

`<validators_addresses_in_hex>` 是验证者地址的拼接，每个地址为 20 字节。

**节点启动时开启挖矿**：验证者节点需要使用 `--mine` 参数启动 Geth：

```bash
$ geth --datadir /path/to/data --networkid 1234 --mine --miner.etherbase "0xYourValidatorAddress" --unlock "0xYourValidatorAddress" --password password.txt
```

**检查是否正在挖矿**：通过以下命令查看节点是否正在挖矿：

```javascript
eth.mining
```

返回 `true` 表示节点正在尝试生成区块。

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