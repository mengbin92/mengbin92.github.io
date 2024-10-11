---
layout: post
title: Solidity、Geth、EVM 三者之间的关系
tags: [blockchain, ethereum]
mermaid: false
math: false
---  

在以太坊开发生态系统中，**Solidity 版本**、**Geth 版本** 和 **EVM（Ethereum Virtual Machine）版本** 之间有密切的关系。理解它们的关系对于智能合约开发、部署和执行至关重要。以下是对这些版本关系的详细介绍：

## 1. Solidity 版本

Solidity 是以太坊平台上的主要智能合约编程语言。它被用于编写以太坊上的智能合约，并最终编译为 EVM 字节码。Solidity 版本的演变直接影响到合约开发者可使用的语言特性、语法以及安全性改进。

- **编译与生成 EVM 字节码**：Solidity 编译器（solc）会将 Solidity 源代码编译为 EVM 字节码，以便智能合约在以太坊虚拟机（EVM）上执行。每个 Solidity 版本都会生成特定的字节码格式，因此编译后的字节码与 EVM 版本的兼容性至关重要。
- **版本更新与特性变更**：Solidity 版本的更新会带来新的语言特性、性能优化和 bug 修复。例如，新的语法改进、智能合约优化和安全漏洞修复都会随着 Solidity 版本变化而更新。
- **与 EVM 兼容性**：不同 Solidity 版本生成的字节码可能需要特定的 EVM 功能支持，因此在开发智能合约时，确保 Solidity 编译后的字节码能够在目标 EVM 版本中正确执行非常重要。

## 2. Geth 版本

Geth（Go Ethereum）是以太坊网络最广泛使用的客户端之一，它负责处理以太坊节点的操作，包括与其他节点的通信、区块链同步、交易处理等。

- **与 EVM 的集成**：Geth 本质上是运行 EVM 的容器，因此 Geth 版本会决定它所支持的 EVM 版本。EVM 是 Geth 执行智能合约的核心模块，而不同的 EVM 版本会引入不同的操作码（opcodes）和执行逻辑。
- **网络升级的支持**：Geth 的版本更新通常与以太坊的网络升级（例如分叉或协议改进）相关。每次以太坊网络进行大规模升级（如 **Byzantium**、**Constantinople** 或 **London** 硬分叉）时，都会引入新的 EVM 功能或行为。这意味着要想支持这些升级后的 EVM 功能，Geth 必须升级。
- **开发与部署**：当开发者在使用 Solidity 编译合约时，Geth 客户端会执行这些合约的字节码。因此，在部署合约之前，确保 Geth 版本与目标网络的 EVM 版本匹配很重要。

## 3. EVM 版本

EVM（以太坊虚拟机）是一个状态机，负责执行智能合约的字节码。EVM 的每次升级或变更都会影响其支持的操作码（opcodes）、执行行为以及与智能合约的兼容性。

- **EVM 操作码更新**：以太坊的不同升级会引入新的操作码或修改现有的操作码。例如，以太坊的某些硬分叉（如 **London 硬分叉**）引入了新的 EVM 操作码和 gas 费用调整。这会影响智能合约的执行成本和行为。
- **与 Solidity 的关系**：Solidity 编译的合约字节码是基于 EVM 操作码集的，因此 EVM 版本更新时，新的操作码可能会在未来的 Solidity 版本中支持。这意味着，较新的 Solidity 版本编译的合约字节码可能依赖于最新的 EVM 功能。
- **EVM 的向后兼容性**：EVM 的设计尽量保持向后兼容性，使得旧版本的合约仍能在新的 EVM 上运行。然而，如果 EVM 的某些行为或操作码发生变化，可能会影响特定智能合约的执行方式，尤其是在使用新版本 Solidity 编译的合约时。

## 4. 三者之间的关系总结

- **Solidity 负责编写和编译智能合约**，它生成的字节码是 EVM 可以理解并执行的内容。因此，Solidity 的版本必须与 EVM 版本兼容，否则生成的字节码可能无法正确执行。
- **Geth 是以太坊的核心客户端之一**，它集成了 EVM 以执行智能合约。Geth 版本与 EVM 版本紧密关联，每次以太坊的协议更新（如硬分叉）会带来新的 EVM 特性，而这些特性会体现在 Geth 的更新中。
- **EVM 是智能合约执行的核心**，不同的以太坊协议升级（如 Byzantium、Constantinople、London 等）会带来新的 EVM 版本。这些版本改进了操作码、gas 费用计算等，直接影响智能合约的执行。

## 5.实际应用中的注意事项

1. **匹配性检查**：开发者在编写 Solidity 合约时，需注意当前网络中 EVM 的版本和功能是否支持自己编写的合约。否则，合约可能在部署后出现无法执行或异常行为。
2. **Geth 更新**：Geth 作为常用客户端，其版本更新必须与以太坊主网的升级保持同步，以确保支持最新的 EVM 操作码和行为。如果开发者或节点运营者不及时升级 Geth，可能导致网络不兼容问题。
3. **版本锁定**：在实际的智能合约开发和部署过程中，建议开发者明确指定使用的 Solidity 版本（通过 `pragma` 语句）来防止合约的字节码在未来版本的 Solidity 编译器中生成不兼容的字节码。

## 6. 扩展一：evm版本更迭

EVM（Ethereum Virtual Machine）的版本主要与以太坊协议的升级（如硬分叉）相对应。每次以太坊进行网络升级时，EVM 的功能、操作码集以及 gas 费用计算等也会发生变化。这些升级通常以硬分叉的名称来命名，而 EVM 版本是根据这些硬分叉标记的。

以下是以太坊网络几个主要的硬分叉和相应的 EVM 版本：

1. **Frontier** (2015)：以太坊的创世区块，从这时起开始有了最初的 EVM 版本。
2. **Homestead** (2016):EVM 增加了新的功能，改进了合约创建流程，修复了一些最早期的漏洞。
3. **Tangerine Whistle** (2016):对 EVM 的 gas 费用结构进行了调整，以应对 DoS 攻击。
4. **Spurious Dragon** (2016):改进了 EVM 中的状态清理，继续对操作码和 gas 费用进行优化。
5. **Byzantium** (2017):引入了新的操作码（如 `REVERT`、`STATICCALL` 等），增强了智能合约执行时的安全性和灵活性。
6. **Constantinople** (2019):加入了新的 EVM 操作码，降低了某些合约操作的 gas 消耗。
7. **Petersburg** (2019):回滚了 Constantinople 的部分功能，修复了安全性问题。
8. **Istanbul** (2019):对某些操作码的 gas 费用再次调整，引入了新的加密原语支持。
9. **Berlin** (2021):对 gas 费用进行了更多调整，引入了一些新的 EVM 特性。
10. **London** (2021):实现了重要的 `EIP-1559` 升级，调整了 gas 费用结构，同时引入了新的 EVM 操作码（如 `BASEFEE`）。
11. **Shanghai/Capella (2023)**  :上海升级（主要是围绕以太坊权益证明机制的改进）也带来了 EVM 的一些细微改动。

不同的 EVM 版本会引入新的操作码、调整 gas 费用结构或修复安全漏洞，因此开发者需要确保其智能合约与所部署网络的 EVM 版本兼容。

## 7. 扩展二：Geth 启动区块链网络时如何指定 EVM 版本？

在 Geth 中，**默认情况下会使用当前支持的最新 EVM 版本**，这与所连接的网络一致。例如，如果 Geth 节点连接的是主网，Geth 会自动适应主网当前的 EVM 版本。Geth 本身并不会直接允许开发者在启动时通过命令行手动指定特定的 EVM 版本，**因为 Geth 是根据区块高度来确定使用哪个 EVM 版本的**。

**EVM 版本的选择是由区块链的升级机制（硬分叉）自动决定的**。当区块链达到某个特定的区块高度时，会自动切换到特定的 EVM 版本，这就是以太坊硬分叉的方式。例如，`Byzantium` 升级后，Geth 会在该升级区块（硬分叉区块）之前使用旧的 EVM 版本，而在硬分叉区块之后自动切换到 `Byzantium` EVM 版本。

### 7.1 在私链或开发网络中，开发者如何使用特定的 EVM 版本？

如果你想在开发网络或私链中手动指定特定的 EVM 版本，通常可以通过创建自定义的 **创世区块配置文件** 来指定。例如，可以在创世配置中设置网络在特定区块高度应用哪些协议升级（硬分叉），从而间接指定某个版本的 EVM。

以下是 Geth 启动一个私有链时如何指定硬分叉（对应的 EVM 版本）的例子：

```json
{
  "config": {
    "chainId": 1234,
    "homesteadBlock": 0,
    "daoForkBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0
  },
  "alloc": {},
  "difficulty": "0x20000",
  "gasLimit": "0x2fefd8",
  "genesis": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

在这个创世文件中，区块链从 `0` 号区块开始就应用所有的 EVM 升级（从 `Homestead` 到 `London`）。你可以通过修改这些 `*_Block` 参数来指定某个特定区块启用某个 EVM 版本。

### 7.2 测试环境下使用 `evm` 命令

如果你只是想在本地运行 EVM 的特定版本进行一些测试，Geth 提供了一个名为 `evm` 的工具，可以手动运行不同版本的 EVM 来测试智能合约的执行。你可以使用以下命令：

```bash
evm --code "<bytecode>" run --vm <vm-version>
```

其中 `<vm-version>` 可以是 `byzantium`、`constantinople`、`istanbul` 等指定的 EVM 版本。

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