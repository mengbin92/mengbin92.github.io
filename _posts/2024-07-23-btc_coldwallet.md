---
layout: post
title: Bitcoin-core 冷钱包 
tags: blockchain
mermaid: false
math: false
---  

Bitcoin Core 是比特币的官方客户端，由比特币核心开发团队维护。它不仅可以作为全节点运行，验证区块链的每个交易，还可以作为一个钱包来存储和管理比特币。使用 Bitcoin Core 创建冷钱包是一种高度安全的方式，因为冷钱包是离线存储私钥的，可以有效防止黑客攻击。下面详细介绍如何使用 Bitcoin Core 创建和管理冷钱包。

## 什么是冷钱包？

冷钱包（Cold Wallet）是指不连接到互联网的比特币钱包，主要用于长期安全存储比特币。与之相对的是热钱包（Hot Wallet），热钱包是连接到互联网的，适合频繁交易。

## 为什么选择 Bitcoin Core 作为冷钱包？

1. **安全性高**：Bitcoin Core 作为全节点钱包，可以直接与比特币网络交互，而不依赖第三方服务，安全性更高。
2. **完全控制**：用户可以完全掌握自己的私钥和比特币，无需依赖第三方。
3. **功能丰富**：Bitcoin Core 支持高级功能，如多重签名、交易脚本等。

## 使用 Bitcoin Core 创建冷钱包的步骤

1. **准备工作**：
   - 一台安全的、未连接互联网的电脑（用于创建和存储冷钱包）
   - 一台联网的电脑（用于日常交易）。
2. **在离线电脑上安装 Bitcoin Core**：
   1. **下载 Bitcoin Core 安装包**
   2. **安装 Bitcoin Core**
   3. **初始化钱包**
3. **创建离线地址**：
   1. **创建新钱包**
   2. **生成比特币地址**
4. **在联网电脑上创建热钱包**：
   1. **安装 Bitcoin Core**：在联网电脑上重复离线电脑的安装步骤。
   2. **初始化钱包**： 让 Bitcoin Core 完全同步区块链数据。
   3. **创建热钱包**：同样在联网电脑上创建一个新的钱包，用于日常交易。
5. **从热钱包向冷钱包转账**：
   1. **获取冷钱包地址**
   2. **发送比特币**
6. **签名交易（离线）**：
   1. **创建交易**
   2. **转移到离线电脑**
   3. **签名交易**
   4. **将签名交易转回联网电脑**
7. **广播交易（在线）**

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
