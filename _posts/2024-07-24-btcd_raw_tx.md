---
layout: post
title: 使用btcd发送交易
tags: [blockchain, go]
mermaid: false
math: false
---  

`btcd` 是一个用Go语言（golang）编写的比特币全节点替代实现。`btcsuite` 是一个Go语言的 `btc` 库集合，我们可以使用它来构建比特币交易。

## 1. 环境准备  

要发送 `btc` 交易，首先我们需要能访问到 `btc` 网络。这里以测试链为例，使用 docker 来启动一个 `btcd` 全节点。`docker-compose.yml` 文件如下：  

```yaml
networks:
  btcd:

services:
  btcd:
    image: mengbin92/btcd:0.24.2
    container_name: btcd_full_node
    volumes:
      - ./btcd:/root/.btcd
    ports:
      - 8334:8334
    networks:
      - btcd
```  

`btcd` 的配置文件在 `btcd` 目录下，`btcd.conf` 如下：  

```ini
; 构建并维护一个完整的基于哈希的交易索引，使所有交易都可以通过 getrawtransaction RPC 获得。
txindex=1
; 构建和维护基于地址的完整交易索引，使 searchrawtransactions RPC 可用。
addrindex=1

# for rpcserver
rpcuser=rpcuser
rpcpass=rpcpassword
rpclisten=0.0.0.0:8334

# 连接测试链
testnet=1
```  

之后通过 `docker-compose up -d` 启动 `btcd` 全节点。

## 2. 初始化 RPC 客户端  

```go
func loadRPCClient() *rpcclient.Client {
	viper.SetConfigFile("./config/config.yaml")
	err := viper.ReadInConfig()
	if err != nil {
		panic(err)
	}

	rpcuser = viper.GetString("btc.rpcuser")
	rpcpass = viper.GetString("btc.rpcpass")
	endpoint = viper.GetString("btc.endpoint")
	rpccert = viper.GetString("btc.rpccert")

    // 使用tls链接，所以需要导入btcd生成的rpc证书
	cert, err := os.ReadFile(rpccert)
	if err != nil {
		panic(err)
	}

	connCfg := &rpcclient.ConnConfig{
		Host:         endpoint,
		User:         rpcuser,
		Pass:         rpcpass,
		HTTPPostMode: true,
		Certificates: cert,
	}

	client, err = rpcclient.New(connCfg, nil)
	if err != nil {
		panic(err)
	}
	return client
}
```  

配置文件内容如下：  

```yaml
version: "3.8"

btc:
  rpcuser: rpcuser
  rpcpass: rpcpass
  rpccert: ./btcd/rpc.cert
  endpoint: 127.0.0.1:8334
```  

## 3. 构建交易输出  

这里以向地址 `tb1qndsh2mllf8g2hf29svazpxksa3ns4zga3n55mc` 转账 `100000 sat` 为例，现在我们需要构建交易输出：  

```go
// BuildTxOut 构建一个比特币交易输出（TxOut）
func BuildTxOut(addr string, amount int64, params chaincfg.Params) (*wire.TxOut, []byte, error) {
    // 解析比特币地址
    destinationAddress, err := btcutil.DecodeAddress(addr, &params)
    if err != nil {
        return nil, nil, err
    }

    // 生成支付到地址的脚本
    pkScript, err := txscript.PayToAddrScript(destinationAddress)
    if err != nil {
        return nil, nil, err
    }

    // 创建一个新的交易输出，金额单位为 satoshis
    return wire.NewTxOut(amount, pkScript), pkScript, nil
}
``` 

## 4. 获取发送者的余额  

这里通过 `SearchRawTransactionsVerbose` 获取指定地址相关的交易，然后再通过 `GetTxOut` 获取发送者的余额。

```go
// GetUTXOs 获取指定比特币地址的所有未花费交易输出（UTXOs）
func GetUTXOs(addr string) ([]*btcjson.ListUnspentResult, error) {
	// 解析比特币地址
	address, err := btcutil.DecodeAddress(addr, &chaincfg.TestNet3Params)
	if err != nil {
		return nil, err
	}

	// 使用SearchRawTransactionsVerbose获取与地址相关的所有交易
	transactions, err := client.SearchRawTransactionsVerbose(address, 0, 100, true, false, nil)
	if err != nil {
		return nil, err
	}

	// 用于存储UTXO的切片
	utxos := []*btcjson.ListUnspentResult{}

	// 遍历所有交易
	for _, tx := range transactions {
		// 将交易ID字符串转换为链哈希对象
		txid, err := chainhash.NewHashFromStr(tx.Txid)
		if err != nil {
			log.Fatalf("Invalid txid: %v", err)
		}

		// 遍历交易的输出
		for _, vout := range tx.Vout {
			// 检查输出地址是否是我们关心的地址
			if vout.ScriptPubKey.Address != addr {
				continue
			}

			// 使用GetTxOut方法获取交易输出，确认该输出是否未花费
			utxo, err := client.GetTxOut(txid, vout.N, true)
			if err != nil {
				panic(err)
			}

			// 如果交易输出未花费，则将其添加到UTXO切片中
			if utxo != nil {
				utxo := &btcjson.ListUnspentResult{
					TxID:          tx.Txid,
					Vout:          uint32(vout.N),
					Address:       addr,
					ScriptPubKey:  vout.ScriptPubKey.Hex,
					Amount:        vout.Value,				// 单位为BTC
					Confirmations: int64(tx.Confirmations),
					Spendable:     true,
				}
				utxos = append(utxos, utxo)
			}
		}
	}

	// 返回UTXO集合
	return utxos, nil
}
```  

## 5. 构建交易输入  

现在我们已经拿到了发送者的余额，接下来需要构建交易输入。  

```go
func BuildTxIn(wif *btcutil.WIF, amount int64, txOut *wire.TxOut, params *chaincfg.Params) (*wire.MsgTx, error) {
	// 解析比特币地址
	fromAddr, err := btcutil.NewAddressWitnessPubKeyHash(btcutil.Hash160(wif.SerializePubKey()), params)
	if err != nil {
		return nil, errors.Wrap(err, "解析比特币地址失败")
	}

	// 获取UTXOs
	utxos, err := GetUTXOs(fromAddr.EncodeAddress())
	if err != nil {
		return nil, errors.Wrap(err, "获取UTXOs失败")
	}

	msgTx := wire.NewMsgTx(wire.TxVersion)
	// 创建一个新的交易输入，金额单位为 satoshis
	totalInput := int64(0)
	for _, utxo := range utxos {
		// totalInput 大于 amount，用于计算交易费
		if totalInput > amount {
			break
		}
		txHash, err := chainhash.NewHashFromStr(utxo.TxID)
		if err != nil {
			return nil, errors.Wrap(err, "解析交易哈希失败")
		}

		txIn := wire.NewTxIn(&wire.OutPoint{Hash: *txHash, Index: uint32(utxo.Vout)}, nil, nil)
		msgTx.AddTxIn(txIn)
		totalInput += int64(utxo.Amount * 1e8)
	}
	msgTx.AddTxOut(txOut)

	// 交易费
	// 假定交易费率为每字节 1sat
	fee := int64(msgTx.SerializeSize())
	// 找零	
	change := totalInput - amount
	// 这里假定找零一定大于交易费，交易费太少的话可能导致交易一直无法确认
	// 如果change <= fee的话，零钱会转给出块的矿工
	if change > fee {
		changePkScript, err := txscript.PayToAddrScript(fromAddr)
		if err != nil {
			return nil, errors.Wrap(err, "生成找零地址的脚本失败")
		}
		txOut := wire.NewTxOut(change-fee, changePkScript)
		msgTx.AddTxOut(txOut)
	}

	// 签署交易
	// 发送方地址为SegWit的P2WPKH 地址，所以要消费该地址的UTXO，只能通过见证输入进行消费
	for i, txIn := range msgTx.TxIn {
		prevOutputScript, err := hex.DecodeString(utxos[i].ScriptPubKey)
		if err != nil {
			panic(err)
		}
		txHash, err := chainhash.NewHashFromStr(utxos[i].TxID)
		if err != nil {
			return nil, errors.Wrap(err, "解析交易哈希失败")
		}
		outPoint := wire.OutPoint{Hash: *txHash, Index: uint32(utxos[i].Vout)}
		prevOutputFetcher := txscript.NewMultiPrevOutFetcher(map[wire.OutPoint]*wire.TxOut{
			outPoint: {Value: int64(utxos[i].Amount * 1e8), PkScript: prevOutputScript}, 
		})
		sigHashes := txscript.NewTxSigHashes(msgTx, prevOutputFetcher)
		sigScript, err := txscript.WitnessSignature(msgTx, sigHashes, int(utxos[i].Vout), int64(utxos[i].Amount*1e8), prevOutputScript, txscript.SigHashAll, wif.PrivKey, true)
		if err != nil {
			return nil, errors.Wrap(err, "签名交易失败")
		}
		txIn.Witness = sigScript
	}
	return msgTx, nil
}
```  

至此，我们就已经完成了交易的构建过程，接下来就是将交易广播到区块链网络，等待确认。  

## 6. 广播交易

广播交易可以使用 `SendRawTransaction`，函数会将交易提交到服务器，然后服务器将其转发到网络。该函数会返回交易哈希，如果交易成功广播，那么哈希值会是一个有效的哈希值。

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


