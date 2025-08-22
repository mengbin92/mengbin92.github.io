---
layout: post
title: 《纸上谈兵·solidity》第 18 课：合约设计模式实战（三）—— 代理 + 插件化架构（Diamond Standard / EIP-2535）
tags: solidity
mermaid: false
math: false
--- 

## 引言

在区块链上，**合约一旦部署便不可修改**，这是去中心化的根本保障。但对于复杂应用来说，这却成了一把双刃剑：

* **问题 1**：如果逻辑写错了，无法直接修复
* **问题 2**：如果功能需要迭代，必须重新部署并迁移用户资产与数据

于是，出现了 **代理合约升级模式**（第 14 课介绍过）：

* **数据存储在 Proxy**
* **逻辑在 Logic**
* 通过升级 Proxy 指向的 Logic，实现逻辑的替换

但是：

* 当合约功能越来越多时，单一 Logic 变得过于臃肿
* 每次升级都要替换整个 Logic
* 模块化程度不够

于是，社区提出了 **Diamond Standard（EIP-2535）** —— 允许一个代理合约挂载多个逻辑模块（Facet），形成插件化架构。

---

## 1. Diamond Standard 的设计目标

EIP-2535 的核心思想是：

**合约应该像一个操作系统，可以随时增加或删除功能，而不是“一次性写死”。**

设计目标：

1. **模块化** —— 每个功能是一个 Facet（切片），可以独立开发/替换
2. **可升级** —— 可以动态增加、替换、删除 Facet
3. **存储安全** —— 所有 Facet 共享 Diamond 的存储，避免数据迁移
4. **治理灵活** —— 项目方可通过治理控制哪些 Facet 可被替换

---

## 2. Diamond 的核心结构

一个 Diamond 系统一般包含：

* **Diamond（主合约）**
  * 保存所有存储变量
  * 管理 Facet 的映射关系（函数选择器 → Facet 地址）
  * 负责将用户调用分发到正确的 Facet
* **Facet（功能切片）**
  * 实现具体功能（ERC20 模块、治理模块、DEX 模块……）
  * 没有独立存储，依赖 Diamond 的存储
* **DiamondCut（升级控制器）**
  * 提供 `addFacet` / `replaceFacet` / `removeFacet` 方法
  * 定义 Facet 的增删改逻辑

---

## 3. 调用流程对比

传统 Proxy 调用：

用户 → Proxy → delegatecall → Logic

Diamond 调用：

用户 → Diamond → 查找 Facet 地址 → delegatecall → Facet

区别：

* Proxy 只能有 **一个 Logic**
* Diamond 可以挂载 **多个 Facet**

---

## 4. 存储布局问题

在 **delegatecall** 中，执行代码用的是 Facet 的逻辑，但读写的是 Diamond 的存储。
所以：

* 所有 Facet 必须遵循 **统一的存储布局**
* 一般采用 **Storage Slot 固定写法**（如 keccak256 常量 Slot）来避免冲突

常见写法（StorageLib.sol）：

```solidity
library LibAppStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

    struct AppStorage {
        uint256 value;
        mapping(address => uint256) balances;
    }

    function diamondStorage() internal pure returns (AppStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
```

每个 Facet 使用 `LibAppStorage` 获取同一份存储，避免覆盖。

---

## 5. 简化版实现

我们写一个最小可运行的 Diamond 合约系统。

### Diamond.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Diamond {
    mapping(bytes4 => address) public facets;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addFacet(bytes4 selector, address facet) external onlyOwner {
        facets[selector] = facet;
    }

    fallback() external payable {
        address facet = facets[msg.sig];
        require(facet != address(0), "Function not found");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
```

### FacetA.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FacetA {
    uint256 public value;

    function setValue(uint256 _v) external {
        value = _v;
    }
}
```

### FacetB.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FacetB {
    uint256 public number;

    function add(uint256 a, uint256 b) external returns (uint256) {
        number = a + b;
        return number;
    }
}
```

---

## 6. Foundry 测试

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Diamond.sol";
import "../src/FacetA.sol";
import "../src/FacetB.sol";

contract DiamondTest is Test {
    Diamond diamond;
    FacetA facetA;
    FacetB facetB;

    function setUp() public {
        diamond = new Diamond();
        facetA = new FacetA();
        facetB = new FacetB();

        diamond.addFacet(FacetA.setValue.selector, address(facetA));
        diamond.addFacet(FacetB.add.selector, address(facetB));
    }

    function testFacetACall() public {
        (bool ok, ) = address(diamond).call(
            abi.encodeWithSelector(FacetA.setValue.selector, 42)
        );
        assertTrue(ok, "FacetA call failed");
    }

    function testFacetBCall() public {
        (bool ok, bytes memory data) = address(diamond).call(
            abi.encodeWithSelector(FacetB.add.selector, 1, 2)
        );
        assertTrue(ok, "FacetB call failed");
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 3);
    }
}
```

运行：

```bash
➜  tutorial git:(main) ✗ forge test --match-path test/Diamond.t.sol -vvv      

[⠊] Compiling...
[⠒] Compiling 4 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 522.72ms
Compiler run successful!

Ran 2 tests for test/Diamond.t.sol:DiamondTest
[PASS] testFacetACall() (gas: 33464)
[PASS] testFacetBCall() (gas: 34743)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 4.38ms (1.35ms CPU time)

Ran 1 test suite in 162.88ms (4.38ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 7. Diamond 的优势与挑战

### 优势

1. **模块化**：功能可拆分到不同 Facet
2. **动态扩展**：可随时添加新模块
3. **节省 Gas**：用户只调用需要的功能，不必加载整个大合约
4. **大型项目可维护性强**

### 挑战

1. **复杂度高**：管理 selector → facet 映射逻辑繁琐
2. **存储一致性问题**：开发者需要小心避免 slot 冲突
3. **调试困难**：调试 delegatecall 内部逻辑不如普通合约直观
4. **治理风险**：如果 DiamondCut 被攻击者控制，整个系统都可能被劫持

---

## 8. 适用场景

* **大型 DeFi 协议**（如 Uniswap、Aave）：需要频繁扩展功能
* **DAO 系统**：随着治理需要扩展新的投票机制
* **NFT 市场**：快速迭代拍卖、版税、租赁功能

---

## 9. 总结与思考

* Diamond 是代理模式的进化版，支持多模块挂载
* 通过 **selector → facet** 的动态映射实现可扩展性
* 避免了单一逻辑合约臃肿和升级风险
* 但需要额外的存储设计和治理机制

**思考题：**

1. 如果某个 Facet 被攻击，如何仅替换它而不影响整个系统？
2. 在 Diamond 架构中，是否能引入多签/时间锁机制来增强升级安全性？
3. Diamond 是否适合小型合约项目？为什么？

---

这一课我们系统学习了 **Diamond Standard（EIP-2535）** 的设计思想、简化实现与应用场景。

下一课（第 18 课）我们将转向 **安全专题**，研究常见攻击手法（Reentrancy、Front-running、DoS）与防御手段，从进攻视角理解安全设计。

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