---
layout: post
title: BTC地址类型
tags: blockchain
mermaid: false
math: false
---  

比特币（BTC）有几种不同的地址类型，每种类型的地址在格式、特性和使用场景上有所不同。以下是主要的几种比特币地址类型的对比：

### 1. P2PKH 地址（Pay to Public Key Hash）

- **格式**: 以 `1` 开头。
- **示例**: `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`
- **特性**:
  - 这是比特币最早的地址类型，也是最常用的一种，称为“传统地址”。
  - 地址长度较短。
  - 在交易中通常需要支付较高的手续费，因为它们不支持比特币的新的扩展特性。
  - 公钥哈希（Public Key Hash）形式，即从公钥生成的160位哈希。

### 2. P2SH 地址（Pay to Script Hash）

- **格式**: 以 `3` 开头。
- **示例**: `3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy`
- **特性**:
  - 允许更复杂的交易脚本，如多重签名地址、时间锁定地址等。
  - 通过哈希脚本（Script Hash）生成地址，提高了灵活性和安全性。
  - 比较常用的地址类型，尤其是在多重签名和其他高级功能中。

### 3. Bech32 地址（也称为 SegWit 地址）

- **格式**: 以 `bc1` 开头。
- **示例**: `bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf6x5`
- **特性**:
  - 这是比特币改进提案BIP 173定义的地址类型，专为SegWit（隔离见证）设计。
  - 通过优化数据存储和减少数据使用，使得交易费用较低。
  - 更安全，因其避免了部分比特币网络上的老式攻击（如交易延展性攻击）。
  - 字符集使用较特殊（Bech32编码），较难与其他地址类型混淆。
  - 兼容性可能会有一些问题，因为部分旧的钱包或交易所不支持Bech32地址。

### 4. Bech32m 地址

- **格式**: 以 `bc1p` 开头。
- **示例**: `bc1pqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqdtrp7l`
- **特性**:
  - 是一种基于Bech32编码的改进版地址格式，专为Taproot（比特币的软分叉）设计。
  - 增加了对比特币新功能Taproot的支持，可以提高隐私性和可扩展性。
  - 与Bech32地址相似，但有一定的技术区别，特别是校验码算法不同。
  
### 总结

- **地址前缀**: `1` (P2PKH), `3` (P2SH), `bc1` (Bech32), `bc1p` (Bech32m)
- **兼容性**: P2PKH 和 P2SH 地址的兼容性最强，Bech32 和 Bech32m 地址可能会在部分旧系统中遇到兼容性问题。
- **交易费**: Bech32 和 Bech32m 地址由于优化的数据结构，交易费用通常较低。
- **安全性**: Bech32 和 Bech32m 地址在安全性和抗攻击性上有优势，尤其是在抵御交易延展性攻击方面。

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
