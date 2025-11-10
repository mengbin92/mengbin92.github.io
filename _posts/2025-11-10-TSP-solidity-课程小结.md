---
layout: post
title: 《纸上谈兵·solidity》课程小结
tags: solidity
mermaid: false
math: false
---

## 课程结构

### 第一部分：基础入门（第 0-2 课）
- **第 0 课**：搭建开发环境（Remix / Foundry / Hardhat）
- **第 1 课**：部署第一个合约
- **第 2 课**：合约交互（view/pure vs 状态修改）

### 第二部分：语言核心（第 3-12 课）
- **第 3-4 课**：事件与错误处理
- **第 5 课**：外部调用与重入防护
- **第 6 课**：存储布局（storage/memory/calldata）
- **第 7-8 课**：函数可见性、继承与接口
- **第 9-12 课**：事件日志、fallback、错误处理、ABI 编码

### 第三部分：高级特性（第 13-22 课）
- **第 13-14 课**：低级调用（call/delegatecall）、代理模式
- **第 15-18 课**：库、支付模式、权限管理、Diamond 标准
- **第 19-20 课**：安全专题（常见攻击与防御）
- **第 21-22 课**：Gas 优化、ERC20 实现

### 第四部分：实战项目（第 23-35 课）
- **第 23 课**：NFT（ERC721/ERC1155）
- **第 24 课**：众筹合约
- **第 25-26 课**：DEX、借贷合约
- **第 27 课**：DAO 治理
- **第 28-31 课**：安全审计案例（The DAO、Parity、Nomad）
- **第 32-36 课**：DeFi 基础、多签钱包、DEX 实战

### 第五部分：DeFi 进阶（第 37-48 课）
- **第 37-39 课**：资金池、利率模型、清算机制、aToken
- **第 40-42 课**：风险控制、协议费、多市场支持
- **第 43-45 课**：清算进阶、利率曲线、复利机制
- **第 46-48 课**：跨链借贷、治理代币、前端 DApp 集成

---

## 核心知识点

### Solidity 基础
- 数据类型、存储位置、函数类型、可见性、继承、错误处理

### 安全编程
- 重入防护、权限控制、CEI 模式、Pull 支付、Gas 优化

### 设计模式
- 代理模式（透明代理、UUPS、Diamond）、访问控制、可升级合约

### 标准协议
- ERC20、ERC721、ERC1155、ERC165、EIP-2535

### DeFi 核心
- 资金池、利率模型、清算机制、价格预言机、DAO 治理

---

## 实战项目

1. HelloWorld / Counter 合约
2. ERC20 / ERC721 / ERC1155 代币
3. 众筹合约 / DEX / 借贷池
4. 多签钱包 / DAO 治理
5. 完整 DeFi 协议（借贷、清算、治理）

---

## 工具链

- **开发**：Remix IDE、Foundry、Hardhat、VSCode
- **测试**：Foundry Test、Hardhat Test
- **部署**：forge script、hardhat deploy、Anvil
- **前端**：ethers.js、React、MetaMask

---

## 学习路径

- **初学者**：第 0-2 课 → 第 3-12 课 → 第 13-16 课 → 第 22-24 课
- **进阶**：第 17-21 课 → 第 25-27 课 → 第 28-31 课 → 第 32-36 课
- **专业**：第 37-48 课（完整 DeFi 协议开发）

---

## 安全原则

1. 最小权限原则
2. CEI 模式（Check-Effects-Interactions）
3. Pull 支付模式
4. 输入验证
5. 重入防护（ReentrancyGuard）
6. 避免时间依赖
7. 外部调用谨慎处理
8. 重要操作记录事件
9. 上线前代码审计

---

## 常见陷阱

- **开发**：存储槽冲突、函数选择器碰撞、delegatecall 陷阱、Gas 限制
- **安全**：重入攻击、整数溢出、权限绕过、时间依赖
- **部署**：代理合约构造函数、初始化函数、升级兼容性、事件索引限制

---

## 推荐资源

- [Solidity 官方文档](https://docs.soliditylang.org/)
- [Foundry 文档](https://book.getfoundry.sh/)
- [OpenZeppelin 文档](https://docs.openzeppelin.com/)

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  

