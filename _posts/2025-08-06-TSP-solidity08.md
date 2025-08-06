---
layout: post
title: 《纸上谈兵·solidity》第 8 课：Solidity 中的继承与接口 —— 模块化不是“复制粘贴”的借口
tags: solidity
mermaid: false
math: false
---  

模块化开发是大型合约系统不可或缺的组成部分。本课简单剖析 Solidity 中的继承（Inheritance）、接口（Interface）、抽象合约（Abstract Contract）等关键机制，帮你在合约系统中**正确地拆分职责、重用逻辑、规范合约交互**，而不是简单复制粘贴。

---

## 一、继承（Inheritance）

继承是 Solidity 的核心语言特性之一。它允许你将多个合约组织在一起形成层级结构，子合约可以继承父合约的**状态变量、函数、事件和修饰器（modifier）**。

### 继承语法：

```solidity
contract Parent {
    string public name = "parent";
}

contract Child is Parent {
    function getName() public view returns (string memory) {
        return name;
    }
}
```

这里 `Child` 自动继承了 `Parent` 中的 `name` 状态变量。

---

## 二、构造函数的继承与初始化顺序

Solidity 支持显式传参给父合约的构造函数：

```solidity
contract A {
    uint public x;
    constructor(uint _x) {
        x = _x;
    }
}

contract B is A {
    constructor() A(42) {}
}
```

### 多重继承时的初始化顺序：

```solidity
contract A {
    constructor() { /* A init */ }
}
contract B is A {
    constructor() A() { /* B init */ }
}
contract C is A, B {
    constructor() A() B() {}
}
```

初始化顺序遵循**继承声明顺序**，不是构造函数中的调用顺序。

---

## 三、函数重写：`virtual` 和 `override`

如果你希望某个函数可以被子合约覆盖（重写），你必须在父合约中标记为 `virtual`。子合约中实现该函数时必须使用 `override`。

```solidity
contract Base {
    function foo() public pure virtual returns (string memory) {
        return "Base";
    }
}

contract Derived is Base {
    function foo() public pure override returns (string memory) {
        return "Derived";
    }
}
```

多重继承时需指定 override 的所有来源：

```solidity
contract A {
    function bar() public pure virtual returns (string memory) {
        return "A";
    }
}

contract B {
    function bar() public pure virtual returns (string memory) {
        return "B";
    }
}

contract C is A, B {
    function bar() public pure override(A, B) returns (string memory) {
        return "C";
    }
}
```

---

## 四、抽象合约（Abstract Contract）

当合约包含至少一个未实现的函数（即不提供函数体），它就变成了抽象合约。

```solidity
abstract contract Animal {
    function speak() public view virtual returns (string memory);
}
```

抽象合约不能被部署，必须由继承它的合约来**实现所有未实现函数**：

```solidity
contract Dog is Animal {
    function speak() public pure override returns (string memory) {
        return "Woof!";
    }
}
```

抽象合约非常适合做**模板、接口的默认实现**等用途。

---

## 五、接口（Interface）

接口定义了一组标准的函数签名，用于合约之间通信时的**约定**。与抽象合约不同的是：

* 所有函数必须是 `external`
* 不允许有状态变量和实现逻辑
* 不允许构造函数
* 可用于调用链上已部署合约的 ABI

```solidity
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}
```

使用示例：

```solidity
IERC20 token = IERC20(tokenAddress);
token.transfer(msg.sender, 1000);
```

---

## 六、组合 vs 继承 vs 接口：模块化选择建议

| 场景              | 使用模式 | 理由与优势                  |
|:--------------- |:---- |:---------------------- |
| 重用通用逻辑或变量       | 继承   | 降低代码重复率，可共用函数、状态等      |
| 动态组合、插拔式模块（如插件） | 组合   | 解耦更彻底，适合通过部署地址传入外部依赖   |
| 合约之间通信或依赖       | 接口   | 减少依赖方对实现方的了解程度，便于升级和替换 |
| 多模块逻辑共用一份代码     | 抽象合约 | 提供默认行为或统一接口逻辑的模板式架构    |

---

## 七、Foundry 实战测试：继承逻辑

**src/Base.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Base {
    function value() public pure virtual returns (uint256) {
        return 1;
    }
}
```

**src/Child.sol**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Base.sol";

contract Child is Base {
    function value() public pure override returns (uint256) {
        return 2;
    }
}
```

**test/Inherit.t.sol:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Child.sol";

contract InheritTest is Test {
    function testOverrideValue() public {
        Child child = new Child();
        assertEq(child.value(), 2);
    }
}
```

**执行测试：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/Inherit.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 506.50ms
Compiler run successful!

Ran 1 test for test/Inherit.t.sol:InheritTest
[PASS] testOverrideValue() (gas: 71422)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.70ms (458.38µs CPU time)

Ran 1 test suite in 215.73ms (1.70ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 八、多重继承冲突与线性化（C3 Linearization）

Solidity 使用 C3 线性化规则解决多重继承路径冲突，**声明顺序决定调用顺序**。

**src/Inheritance.sol:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract A {
    event Log(string msg);

    constructor() {
        emit Log("A initialized");
    }
}

contract B is A {
    constructor() {
        emit Log("B initialized");
    }
}

contract C is A {
    constructor() {
        emit Log("C initialized");
    }
}

contract D is B, C {
    constructor() {
        emit Log("D initialized");
    }
}
```

**`test/InheritanceTest.t.sol`:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Inheritance.sol";

contract InheritanceTest is Test {
    function testInitOrder() public {
        vm.recordLogs();
        D d = new D();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint i = 0; i < entries.length; i++) {
            emit log(string(entries[i].data));
        }
    }
}
```

**执行结果：**

```bash
➜  counter git:(main) ✗ forge test --match-path test/InheritanceTest.t.sol -vvv
[⠊] Compiling...
[⠒] Compiling 5 files with Solc 0.8.30
[⠑] Solc 0.8.30 finished in 520.22ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/InheritanceTest.t.sol:10:9:
   |
10 |         D d = new D();
   |         ^^^


Ran 1 test for test/InheritanceTest.t.sol:InheritanceTest
[PASS] testInitOrder() (gas: 75328)
Logs:
A initialized
B initialized
C initialized
D initialized

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 4.21ms (760.88µs CPU time)

Ran 1 test suite in 200.50ms (4.21ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## 九、总结

* 继承是一种结构化组织代码的方式，适用于复用状态和逻辑
* 抽象合约与接口有助于构建灵活可扩展的架构
* 接口是与外部世界交互的标准桥梁
* 多重继承需小心管理重写顺序和构造顺序

---

## 十、扩展：什么是 C3 Linearization？

C3 Linearization 是一种算法，用于解决**多重继承中的方法解析顺序（MRO，Method Resolution Order）**，即当一个合约继承了多个父合约时，**编译器如何确定哪个父合约的函数/构造函数先执行或使用。**

它的目标是生成一个**线性、有序、无重复**的父类列表，用于：

* 决定构造函数的执行顺序；
* 决定函数调用的搜索顺序（比如 `super.foo()` 调用哪一个版本）；
* 解决菱形继承（diamond inheritance）冲突。

### C3 Linearization 规则

给定一个继承链，比如：

```solidity
contract A {}
contract B is A {}
contract C is A {}
contract D is B, C {}
```

计算 `D` 的线性化顺序 `L(D)` 的规则如下：

```txt
L(D) = [D] + merge(L(B), L(C), [B, C])
```

其中 `+` 表示连接，`merge` 是核心算法，它按如下方式合并多个列表（线性化链 + 当前继承顺序）：

1. 每次从各个列表的头部选出第一个类；
2. 选择那个**不在任何其他列表的尾部**（即后续）中出现的类；
3. 将它添加到结果中并从所有列表中移除；
4. 重复，直到所有列表为空。

如果不能找到这样的类，说明继承存在冲突（比如循环继承），编译报错。


### 例子：解释上面的 D is B, C

```solidity
contract A {}
contract B is A {}
contract C is A {}
contract D is B, C {}
```

计算线性化顺序如下：

#### Step 1: 单独计算每个类的线性化结果

```txt
L(A) = [A]
L(B) = [B] + merge(L(A), [A]) = [B, A]
L(C) = [C] + merge(L(A), [A]) = [C, A]
```

#### Step 2: 计算 D

```txt
L(D) = [D] + merge(L(B), L(C), [B, C])
     = [D] + merge([B, A], [C, A], [B, C])
```

使用 merge：

* B 是第一个候选项，**不出现在任何其他列表的尾部**（C 和 A），所以 B 合法。
* 移除 B：→ \[A], \[C, A], \[C]
* C 是合法的头（不出现在其他尾部）→ 添加 C
* 移除 C：→ \[A], \[A], \[]
* A 是合法的头 → 添加 A
* 所有列表为空

最终：`L(D) = [D, B, C, A]`

---

## 下一课预告

**第 9 课：Solidity 事件与日志机制 —— 合约世界的 printf 与事件监听基础**

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