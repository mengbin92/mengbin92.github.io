# 基于`fabric-sdk-go`实现fabric浏览器

1. 使用`event.New(channelProvider context.ChannelProvider, opts ...ClientOption)`创建事件监听句柄，`ClientOption`支持三种可选项：

   1. **WithBlockEvents()**：监听接收到的出块事件，需要有足够的权限才可使用此选项
   2. **WithBlockNum(from uint64)**：从指定块高开始监听出块事件
   3. **WithSeekType(seek seek.Type)**：从最新、最旧或者指定的区块开始监听事件

2. 注册监听事件，事件不再使用后需要删除注册的监听事件。fabric支持4种事件监听：

   1. **RegisterBlockEvent(filter ...fab.BlockFilter)**：针对出块事件进行监听
   2. **RegisterFilteredBlockEvent()**：跟`RegisterBlockEvent()`功能相同，但不包含payload信息，只包含block的metadata部分
   3. **RegisterChaincodeEvent(ccID, eventFilter string)**：监听合约事件，需要合约在合约中调用**SetEvent**接口注册相应的事件
   4. **RegisterTxStatusEvent(txID string)**：监听交易ID对应交易的状态变更事件

   > 这里介绍使用RegisterBlockEvent接口的使用

3. **RegisterBlockEvent**接口返回一个注册器句柄、接收出块事件的通道、error句柄。通道数据类型为：

   ```go
   type BlockEvent struct {
   	// Block is the block that was committed
   	Block *cb.Block
   	// SourceURL specifies the URL of the peer that produced the event
   	SourceURL string
   }
   ```

   我们需要的信息就都包含在**Block**结构中，接下来需要的就是对**Block**结构进行解析，从中拿到我们需要的信息。

## 1. Block结构解析

**Block**结构定义如下：

```protobuf
// This is finalized block structure to be shared among the orderer and peer
// Note that the BlockHeader chains to the previous BlockHeader, and the BlockData hash is embedded
// in the BlockHeader.  This makes it natural and obvious that the Data is included in the hash, but
// the Metadata is not.
message Block {
    BlockHeader header = 1;
    BlockData data = 2;
    BlockMetadata metadata = 3;
}
```

### 1.1 区块头解析BlockHeader

**BlockHeader**结构定义如下：

```protobuf
// BlockHeader is the element of the block which forms the block chain
// The block header is hashed using the configured chain hashing algorithm
// over the ASN.1 encoding of the BlockHeader
message BlockHeader {
    uint64 number = 1; // The position in the blockchain
    bytes previous_hash = 2; // The hash of the previous block header
    bytes data_hash = 3; // The hash of the BlockData, by MerkleTree
}
```

## 1.2 BlockMetadata

**BlockMetadata**结构定义如下：

```protobuf
message BlockMetadata {
    repeated bytes metadata = 1;
}
   
// This enum enlists indexes of the block metadata array
enum BlockMetadataIndex {
    SIGNATURES = 0;                    // Block metadata array position for block signatures
    LAST_CONFIG = 1 [deprecated=true]; // Block metadata array position to store last configuration block sequence number
    TRANSACTIONS_FILTER = 2;           // Block metadata array position to store serialized bit array filter of invalid transactions
    ORDERER = 3 [deprecated=true];     // Block metadata array position to store operational metadata for orderers
    COMMIT_HASH = 4;                   /* Block metadata array position to store the hash of TRANSACTIONS_FILTER State Updates,and the COMMIT_HASH of the previous block */
}
```

## 1.3 BlockData解析

**BlockData**定义如下，对于Go来说，该结构体仅有一个`[][]byte`类型的`Data`字段，可以使用**Envelope**结构来解析`Data`字段。

```protobuf
message BlockData {
    repeated bytes data = 1;
}
```

### Envelope结构解析

**Envelope**结构定义如下：

```protobuf
// Envelope wraps a Payload with a signature so that the message may be authenticated
message Envelope {
    // A marshaled Payload
    bytes payload = 1;
   
    // A signature by the creator specified in the Payload header
    bytes signature = 2;
}
```

**Envelope**解析可以参看我之前的[文章](https://www.cnblogs.com/lianshuiwuyi/p/14109406.html)，这里就不再赘述了。

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。
> Author: MonsterMeng92

---
