---
layout: post
title: 
tags: 
mermaid: false
math: false
---  

比特币（Bitcoin，简称BTC）作为一种去中心化的数字货币，使用了一种叫做比特币脚本（Bitcoin Script）的编程语言来实现其交易功能。比特币脚本是一种基于堆栈的脚本语言，允许在交易验证过程中执行复杂的条件检查。比特币脚本中的操作码（opcodes）是脚本的基本组成部分，用于执行各种操作。以下是一些在比特币交易中常用的操作码及其功能介绍：

### 1. OP_DUP

**操作**：复制堆栈顶元素。

**用途**：在多重签名交易中常用，复制公钥以便多次使用。

### 2. OP_HASH160

**操作**：对堆栈顶的元素进行SHA-256哈希后，再进行RIPEMD-160哈希。

**用途**：常用于生成比特币地址。

### 3. OP_EQUAL

**操作**：检查堆栈顶的两个元素是否相等。

**用途**：验证数据一致性。

### 4. OP_EQUALVERIFY

**操作**：检查堆栈顶的两个元素是否相等，如果相等则继续执行，否则中止并失败。

**用途**：通常用于验证交易签名。

### 5. OP_CHECKSIG

**操作**：验证堆栈顶的签名和公钥是否匹配。

**用途**：验证交易签名的有效性。

### 6. OP_CHECKMULTISIG

**操作**：验证多重签名的有效性。

**用途**：在多重签名地址中使用，需要多个签名来授权交易。

### 7. OP_RETURN

**操作**：终止脚本执行并标记交易输出为无效。

**用途**：用于嵌入数据或标记交易为不可花费。

### 示例脚本解析

一个典型的P2PKH（Pay-to-PubKey-Hash）脚本如下：

```plaintext
OP_DUP OP_HASH160 <PubKeyHash> OP_EQUALVERIFY OP_CHECKSIG
```

**解析**：

1. `OP_DUP`：复制堆栈顶的公钥。
2. `OP_HASH160`：对公钥进行哈希，得到公钥哈希。
3. `<PubKeyHash>`：堆栈中放入预期的公钥哈希。
4. `OP_EQUALVERIFY`：比较堆栈顶的两个元素是否相等，若不相等则脚本失败。
5. `OP_CHECKSIG`：验证公钥和签名是否匹配。

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
