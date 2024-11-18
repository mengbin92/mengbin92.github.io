---
layout: post
title: UUPS 代理使用示例 
tags: ethereum
mermaid: false
math: false
---  

## UUPSUpgradeable  

`UUPSUpgradeable` 是 OpenZeppelin 提供的用于实现可升级合约的一种标准。UUPS 代表“Universal Upgradeable Proxy Standard”，是以太坊社区推动的一种可升级合约方式。与传统的代理模式相比，UUPS 提供了更为灵活和高效的合约升级机制。以下是关于 `UUPSUpgradeable` 的详细介绍：

### 1. UUPS 的基本概念

- **代理模式**: UUPS 利用代理合约来实现合约的升级。核心逻辑合约（也称为实现合约）存储业务逻辑，而代理合约负责存储状态并将调用转发到实现合约。
- **升级逻辑**: 唯一需要注意的点是，合约的升级逻辑是由实现合约中的 `_authorizeUpgrade` 函数控制的，只有授权的账户（例如合约的所有者）可以进行升级操作。

### 2. UUPSUpgradeable 合约结构

OpenZeppelin 的 `UUPSUpgradeable` 合约提供了可升级合约的核心功能，主要包含以下几个部分：

#### a. 初始化

```solidity
function __UUPSUpgradeable_init() internal onlyInitializing {
    // Initialization logic, if needed
}
```
- 这是 `UUPSUpgradeable` 的初始化函数，在合约创建时调用以初始化 UUPS 特性的所需状态。

#### b. 授权升级

```solidity
function _authorizeUpgrade(address newImplementation) internal virtual;
```
- 这是一个关键函数，任何试图升级合约的操作都会调用这个函数。子合约需要重写此函数来添加访问控制的逻辑。
- 一般情况下，只有合约的所有者或特定角色的账户能够调用这个函数，通常使用修饰符如 `onlyOwner` 控制访问。

## 通过Remix部署UUPSUpgradeable合约  

接下来我们将通过Remix来部署 `UUPSUpgradeable` 合约。

### 1. 编写合约

以下面的合约为例，我们使用 OpenZeppelin 提供的 `UUPSUpgradeable` 实现了一个可升级的计数器合约：  

```solidity
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Counter is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    uint256 public count;

    // initialize: required
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    // _authorizeUpgrade: required
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function store(uint256 _count) external {
        count = _count;
    }

}
```  

在上面的合约中，它具备：

- 可升级的特性（使用 UUPS 策略）。
- 权限管理（只有合约的所有者可以进行升级）。
- 一个简单的存储函数，可以任意设置计数值。

### 2. 编译部署合约  

编译合约的过程与其它合约的编译过程相同，但需要注意的是，在合约部署时我们需要选择 `Deploy with Proxy`选项：  

<div align="center">
  <img src="../img/2024-11-18/deploy01.png" alt="deploy01">
</div>  

点击 `Deploy` 按钮，会弹窗提示：  

<div align="center">
  <img src="../img/2024-11-18/deploy02.png" alt="deploy02">
</div>   

告知我们选择 `Deploy with Proxy` 会启动**两个**交易：

1. 部署实现合约
2. 部署 ERC1967 代理合约

之后我们选择 `Proceed` 按钮，会弹窗提示我们将部署一个代理合约：  

<div align="center">
  <img src="../img/2024-11-18/deploy03.png" alt="deploy03">
</div>  

之后成功部署之后，在左侧会出现两笔交易：第一个是合约部署交易，第二个是合约的代理地址：  

<div align="center">
  <img src="../img/2024-11-18/deploy04.png" alt="deploy04">
</div>  

现在我们通过代理合约地址来调用上面的合约：

<div align="center">
  <img src="../img/2024-11-18/deploy05.png" alt="deploy05">
</div>

### 3. 升级合约  

在上面的过程中，我们部署了基本的合约，现在我们可以升级它了：

- 增加一个累加的接口
- 再进行升级操作

合约升级时，我们需要选择 `Upgrade with Proxy`，参数传入我们上一节得到的代理合约地址：

<div align="center">
  <img src="../img/2024-11-18/deploy06.png" alt="deploy06">
</div>

合约部署成功之后，跟初始部署一样，我们得到两个地址：

- 实现合约地址
- 代理合约地址

<div align="center">
  <img src="../img/2024-11-18/deploy07.png" alt="deploy07">
</div>

点开后会发现，我们新增的 `increase` 函数已经存在了。在上一节中，我们在合约中存进了数字 `1`，现在调用 `increase` 函数可以将其增加到 `2`：

<div align="center">
  <img src="../img/2024-11-18/deploy08.png" alt="deploy08">
</div>  

至此，我们完成了合约的升级。  

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