---
layout: post
title: PoA 验证者也能获取出块奖励吗？
tags: [blockchain, ethereum]
mermaid: false
math: false
---  

## 1. 出块奖励

出块奖励是指在区块链网络中，节点（如矿工或验证者）成功创建和添加一个新的区块到区块链上时所获得的奖励。这种奖励通常以加密货币的形式发放，目的是激励节点参与网络的维护和安全。

出块奖励的主要功能包括：

1. **激励参与**：通过提供经济奖励，鼓励更多节点参与网络的维护，增强网络的安全性和去中心化程度。
2. **补偿成本**：出块过程需要计算资源和电力，奖励可以帮助节点补偿这些成本。
3. **新币发行**：在一些区块链中，出块奖励也是新币生成的机制之一，随着时间推移逐渐增加流通中的货币供应量。

在不同的区块链网络中，出块奖励的数额和发放方式可能有所不同，有的会随着时间递减（如比特币），有的则可能是固定的（如某些私链）。

## 2. PoA 验证者

在以太坊私链中，使用PoA（Proof of Authority）机制的验证者扮演着关键角色：

1. **身份验证**：PoA机制依赖于少数可信的节点（验证者）来创建和验证区块。这些节点的身份通常是已知的，确保他们在网络中具有一定的信誉。
2. **出块和验证**：验证者负责创建新块并验证其他节点提交的块。他们根据网络的共识协议轮流出块。
3. **经济激励**：验证者通过交易费用获得经济激励，鼓励他们诚实地参与网络运作。
4. **治理角色**：验证者通常在网络治理中也扮演重要角色，可能参与决策和协议更新，确保网络的安全性和稳定性。
5. **高效性和低延迟**：由于节点数量较少，PoA网络通常具有更高的交易处理速度和低延迟，适合需要快速确认的应用场景。
6. **安全性考量**：虽然PoA提高了效率，但其安全性依赖于验证者的信誉和治理机制，一旦验证者失信，网络可能面临风险。

这种机制适合特定的私链应用，如企业内部链或联盟链，强调效率与安全性的平衡。  

## 3. 验证者是否可以获得出块奖励？  

在以太坊私链的PoA（Proof of Authority）机制中，常见的共识算法包括 **Clique** 和 **EHash**。这里以 **Clique** 为例，来看看验证者是否可以获得出块奖励。

在[go-ethereum tags v1.13.15](https://github.com/ethereum/go-ethereum/tree/v1.13.15)中，

```go
// consensus/clique/clique.go
// Finalize implements consensus.Engine. There is no post-transaction
// consensus rules in clique, do nothing here.
func (c *Clique) Finalize(chain consensus.ChainHeaderReader, header *types.Header, state *state.StateDB, txs []*types.Transaction, uncles []*types.Header, withdrawals []*types.Withdrawal) {
	// No block rewards in PoA, so the state remains as is
}
```  

从上面的代码可以看出，在 **Clique** 共识算法中，验证者节点不产生出块奖励，因此，验证者节点在创建新块时，除了交易费用以外，并不会获得任何出块奖励。  

所以，在 **Clique** 共识下，PoA私链的ETH总量是固定的，即网络启动时通过 **alloc** 参数预分配的ETH数量。这就需要我们在网络建立之初对整个网络中可能需要的ETH数量有个大致的估算，但随着网络的运行时间越来越长，ETH的需求量可能会发生变化，预设的ETH可能不再满足网络运行的需要。此时，我们就需要增加ETH的供应量。  

要增加ETH总量，除了引入新的验证者节点外，还需要引入出块奖励。但引入新的验证者节点就需要在网络初始化时创建好足够多的验证者节点，否则就需要重启网络，这意味着之前的历史数据就要被丢弃，这肯定不是我们所希望看到的。因此，就需要引入出块奖励。  

### 3.1 引入出块奖励

引入出块奖励，就需要对 **Geth**（Go Ethereum）源码进行修改，使其支持自定义的出块奖励机制。  

修改 **Clique** 配置，增加 **reward** 字段，用于配置验证者的出块奖励。  

```go
// params/config.go
// CliqueConfig is the consensus engine configs for proof-of-authority based sealing.
type CliqueConfig struct {
	Period uint64 `json:"period"` // Number of seconds between blocks to enforce
	Epoch  uint64 `json:"epoch"`  // Epoch length to reset votes and checkpoint
	Reward uint64 `json:"reward"` // Block rewards paid to validators
}
```  

此外，还需要修改 **Finalize**，在创建新块时，给予验证者相应的出块奖励：  

```go
// consensus/clique/clique.go
// Finalize implements consensus.Engine. There is no post-transaction
// consensus rules in clique, do nothing here.
func (c *Clique) Finalize(chain consensus.ChainHeaderReader, header *types.Header, state *state.StateDB, txs []*types.Transaction, uncles []*types.Header, withdrawals []*types.Withdrawal) {
	// No block rewards in PoA, so the state remains as is

	if len(txs) != 0 {
		miner, err := ecrecover(chain.CurrentHeader(), c.signatures)
		if err != nil {
			log.Error("Failed to recover miner address", "err", err)
			return
		}
		// 奖励
		state.AddBalance(miner, uint256.NewInt(chain.Config().Clique.Reward*1e18))
	}

}
```  

**ecrecover** 可以从以太坊区块头的签名中提取账户地址。  

### 3.2 验证  

使用如下 `genesis.json` 启动修改后的 **Geth**，启动节点。

```json
{
    "config": {
        ".....":"....",
        "clique": {
            "period": 10,
            "epoch": 30000,
            "reward": 1
        }
    },
    ".....":"....",
}
```

如上配置，设置出块奖励为 1 ETH，启动节点，观察验证者节点的出块奖励。  

```bash
#
$ geth attach
Welcome to the Geth JavaScript console!

instance: Geth/v1.13.15-stable-a10b60d7/linux-amd64/go1.21.13
coinbase: 0x618c92d30e4a7b21a0d00dc7f5038024752adfd5
at block: 665 (Wed Oct 16 2024 08:56:46 GMT+0000 (UTC))
 datadir: /root/.ethereum
 modules: admin:1.0 clique:1.0 debug:1.0 engine:1.0 eth:1.0 miner:1.0 net:1.0 rpc:1.0 txpool:1.0 web3:1.0

To exit, press ctrl-d or type exit
# 查看0x618c92d30e4a7b21a0d00dc7f5038024752adfd5余额
> eth.getBalance("0x618c92d30e4a7b21a0d00dc7f5038024752adfd5")
1.0000293000000057596308703e+25
# 从0x618c92d30e4a7b21a0d00dc7f5038024752adfd5 转账 1 ETH
> eth.sendTransaction({"to":"086afb25e849aabeb24e8340e7807d5cc944b501","from":"0x618c92d30e4a7b21a0d00dc7f5038024752adfd5", value: 1e18})
"0x292ee16330319f8ea182851d6cca5ef59ef606abb0459ffa57841d221e9b2464"
# 0x618c92d30e4a7b21a0d00dc7f5038024752adfd5余额
> eth.getBalance("0x618c92d30e4a7b21a0d00dc7f5038024752adfd5")
1.0000293000000057596308703e+25
```

## 4. 扩展：PoA 共识算法

在以太坊私链的PoA（Proof of Authority）机制中，常见的共识算法包括 **Clique** 和 **EHash**。它们各自有不同的设计思路和应用场景。下面是两者的详细对比：

### 4.1. Clique

Clique 是以太坊官方提供的 PoA 共识算法之一，在 **Geth**（Go Ethereum）客户端中支持。它的主要特点和机制如下：

- **验证者节点**：Clique 使用一组已知且信任的验证者节点来生产区块。每个区块由一个验证者轮流创建，确保网络的去中心化程度。
- **轮流出块**：验证者按照一定顺序轮流创建区块。每个验证者有一个轮流的时间窗口，在这个时间窗口内它有优先出块的权利。
- **链上治理**：Clique 支持验证者集的动态调整。新增或移除验证者节点需要通过链上投票实现。其他验证者节点需要达成共识后，才能添加新的验证者或移除现有的验证者。
- **出块速度**：Clique 通常配置的出块时间在 5 到 15 秒之间，具体的时间可以根据私链的需求进行调整。
- **容错性**：Clique 可以容忍一定比例的恶意或离线验证者，前提是大多数验证者仍然在线并且遵循协议。
- **适用场景**：由于其简单且高效的特点，Clique 常用于测试网络（如以太坊 Ropsten 测试网）以及小规模的私链和企业链中。

### 4.2 EHash (Ethash in PoA context)

Ethash 是以太坊原本使用的 PoW（Proof of Work）共识算法。然而，有时候 Ethash 的概念也被延伸用于 PoA 机制的上下文中，特别是在一些私链中。这里，EHash 作为 PoA 实现会有一些不同的特点：

- **共识机制的变种**：在某些自定义的 PoA 实现中，可以基于 Ethash 进行修改，使其更像 PoA 的特性，但这些实现通常不是以太坊官方支持的。在这种变种中，验证者不再进行复杂的哈希计算（挖矿），而是通过权限来直接创建区块。
- **更高的灵活性**：EHash 可能适用于某些希望在 PoA 和 PoW 之间找到一个折中的场景，可以利用原本的 Ethash 硬件设施来进行共识运作，但这在严格意义上并不属于标准的 PoA。
- **应用场景**：EHash 在 PoA 环境中的使用较少，一般出现在需要兼容 PoW 特性的特定场景中。这类共识机制在某些实验性的私链中使用，但在主流应用中，Clique 更为常见。

### 4.3 对比总结

| 特性         | Clique                         | EHash（在PoA上下文中）               |
| ------------ | ------------------------------ | ------------------------------------ |
| **出块方式** | 轮流出块，基于验证者身份       | 类似PoA机制的变种，可能基于PoW兼容性 |
| **治理机制** | 链上投票，动态调整验证者       | 自定义，实现上不统一                 |
| **性能**     | 快速（5-15秒），适合低延迟场景 | 可能会更慢，因需要部分计算           |
| **适用场景** | 测试网络、小型私链、企业链     | 特定实验性链，需兼容PoW特性          |
| **容错性**   | 容忍一定比例的恶意或离线验证者 | 根据实现不同而异                     |
| **复杂度**   | 简单，容易配置                 | 可能需要更多的定制和配置             |

### 总结
- **Clique** 是更常见的 PoA 共识选择，适合绝大多数以太坊私链应用，尤其是那些希望提高出块速度和交易处理效率的网络。它以简单、易于配置和治理为主要优势。
- **EHash** 的 PoA 变种可能会用在需要特殊 PoW 兼容性的情况下，但应用范围较窄，且大多数场景下不如 Clique 那样标准化和便捷。

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