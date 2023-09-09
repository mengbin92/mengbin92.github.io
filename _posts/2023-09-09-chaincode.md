---
layout: post
title: Fabric 2.x 智能合约开发记录
tags: [fabric, go] 
mermaid: false
math: false
---  

## 表象：Return schema invalid. required items must be unique [recovered]

虽然 Fabric v2.2 已经发布了很久了，但之前因为项目历史问题，一直使用的都是 Fabric v1.4.8，所以智能合约也一直使用的都是 `github.com/hyperledger/fabric/core/chaincode/shim` 包。  

在合约开发过程中，我一般都是使用下面的接口格式来定义合约的业务逻辑：  

```go
func create(stub shim.ChaincodeStubInterface, payload string) ([]byte, error)
```

在开发 Fabric v2.2 的智能合约时， 使用 `github.com/hyperledger/fabric-contract-api-go/contractapi` 替换 `github.com/hyperledger/fabric/core/chaincode/shim`，接口格式如下：  

```go
func create(ctx contractapi.TransactionContextInterface, payload string) ([]byte, error)
```

然而这样的接口在合约示例化的时候翻车了：  

```shell
Error compiling schema for SmartContract [create]. Return schema invalid. required items must be unique [recovered]
```

翻阅 `github.com/hyperledger/fabric-contract-api-go` 时，在其[使用教程](https://github.com/hyperledger/fabric-contract-api-go/blob/main/tutorials/getting-started.md)发现一些限制：  

- 合同的函数只能接受以下类型的参数：
  - string
  - bool
  - int（包括 int8、int16、int32 和 int64）
  - uint（包括 uint8、uint16、uint32 和 uint64）
  - float32
  - float64
  - time.Time
  - 任何允许类型的数组/切片
  - 结构体（其公共字段全部属于允许类型或另一个结构体）
  - 指向结构体的指针
  - 具有键类型为 string 和值为任何允许类型的映射
  - interface{}（仅当直接传入时才允许，在通过事务调用时将接收一个 string 类型）
- 合同的函数还可以接受事务上下文，前提是：
  - 它作为第一个参数传入
  - 二选一：
    - 它要么是类型为 *contractapi.TransactionContext 的对象，要么是在链码中定义的自定义事务上下文，用于合同的使用
    - 它是一个接口，用于合同的事务上下文类型符合该接口，例如 [contractapi.TransactionContextInterface](https://godoc.org/github.com/hyperledger/fabric-contract-api-go/contractapi#TransactionContextInterface)。
- 合同的函数只能返回零、一个或两个值：
  - 如果函数被定义为返回零值，那么对该合同函数的所有调用将返回成功响应
  - 如果函数被定义为返回一个值，那么该值可以是参数列表中列出的任何允许类型之一（除了 interface{}），或者是错误。
  - 如果函数被定义为返回两个值，那么第一个值可以是参数列表中列出的任何允许类型之一（除了 interface{}），第二个值必须是错误。

仔细阅读会发现 `func create(ctx contractapi.TransactionContextInterface, payload string) ([]byte, error)` 并没有违法上面的规则，但示例化的时候就是无法通过。  

上面的报错信息也明确说了是返回值不对，那就改下接口的返回值：  

```go  
func create(ctx contractapi.TransactionContextInterface, payload string) (string, error)
func create(ctx contractapi.TransactionContextInterface, payload string) (*Company, error)
func create(ctx contractapi.TransactionContextInterface, payload string) (int, error)
```

修改后在进行实例化，这次不再报错了。  

但是明明之前的也没有违反规则，为什么会报错呢？想不通为什么，所以准备给官方提个Issue，万一真是个bug呢？  

结果就在[issues](https://github.com/hyperledger/fabric-contract-api-go/issues)里发现了这个[Possible issues with byte[] as return type](https://github.com/hyperledger/fabric-contract-api-go/issues/53)，一看日期**Oct 20, 2021**，快两年了也没官方的回应......

## 结论

最后搜了一圈也没找到原因，查看源码，感觉问题可能是出在 `contractFunctionReturns`，具体还得等研究完源码之后才能有答案

```go
type contractChaincodeContract struct {
	info                      metadata.InfoMetadata
	functions                 map[string]*internal.ContractFunction
	unknownTransaction        *internal.TransactionHandler
	beforeTransaction         *internal.TransactionHandler
	afterTransaction          *internal.TransactionHandler
	transactionContextHandler reflect.Type
}

// ContractChaincode a struct to meet the chaincode interface and provide routing of calls to contracts
type ContractChaincode struct {
	DefaultContract       string
	contracts             map[string]contractChaincodeContract
	metadata              metadata.ContractChaincodeMetadata
	Info                  metadata.InfoMetadata
	TransactionSerializer serializer.TransactionSerializer
}

// ContractFunction contains a description of a function so that it can be called by a chaincode
type ContractFunction struct {
	function reflect.Value
	callType CallType
	params   contractFunctionParams
	returns  contractFunctionReturns
}

type contractFunctionReturns struct {
	success reflect.Type
	error   bool
}
```

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---

