# fabric网络升级   

原文地址在[这里](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade.html)。  

在fabric网络中，升级nodes和通道至最新版本需要四步：  

1. 备份账本和MSPs。
2. 以滚动的方式将orderer升级到最新版。
3. 以滚动的方式将peers升级到最新版。
4. 将orderer系统通道和所有可用的应用程序通道升级至最新版。  

更多通道 capabilities信息，可以从[这里](https://hyperledger-fabric.readthedocs.io/en/release-2.2/capabilities_concept.html)了解。  

要了解以上的升级过程，可以查阅这些教程：  

1. [Considerations for getting to v2.x](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html) 介绍如何从之前的版本或其他长期支持版本升级至最新版。
2. [Upgrading your components](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrading_your_components.html) capabilities更新之前应该先升级组件。
3. [Updating the capability level of a channel](https://hyperledger-fabric.readthedocs.io/en/release-2.2/updating_capabilities.html) 完成所有节点的升级。
4. [Enabling the new chaincode lifecycle](https://hyperledger-fabric.readthedocs.io/en/release-2.2/enable_cc_lifecycle.html) 针对fabric v2.x，需要为新的chaincode lifecycle添加特定的背书策略。  

现在升级节点和增加通道的能力被认作是一个标准的Fabric过程，所以我们不再显示升级到最新版的命令。同样地，fabric-samples repo中也不会再提供脚本将示例网络升级到最新版。  

> fabric网络升级到最新版之后，最好也将SDK升级至最新版。  

---  

## Considerations for getting to v2.x  

本章节主要介绍如何从之前的版本或其他长期支持版本升级至最新版。  

### 从2.1升级到2.2  

Fabric v2.1和v2.2都是稳定版，以bug修复和其它形式的代码加固位置。因此，升级不需要特别考虑，也不需要更新特定的镜像版本或通道配置更新。  

### 从v1.4.x长期支持版本升级到v2.2  

从v1.4.x升级到v2.2，你需要考虑一下内容：  

#### chaincode lifecycle    

在chaincode被应用到通道前，允许多个组织表决该合约应该如何使用，这是v2.0新增的功能。要了解更多关于chaincode lifecycle的信息，可以参阅[这里](https://hyperledger-fabric.readthedocs.io/en/release-2.2/chaincode_lifecycle.html)。  

最佳操作是在启用使用了新的chaincode lifecycle的通道和应用程序之前，先升级通道中的所有peers节点（尽管通道 capabilities不是必须的，但此时更新它更有意义）。未更新至v2.x的peers节点都将会在启用任一capability后崩溃，未更新至v2的orderer节点会在启用通道 capability后崩溃。这种崩溃行为是有意义的，因为如果peers节点或orderer节点不支持必要的capabilities，那它将不能安全地参与到通道中。  

在通道更新应用程序的capabilities到v2.0之后，你必须使用v2.x lifecycle程序来打包、安装、审核和提交新的chaincode。因此，在更新功能之前，请确保为新的 lifecycle做好准备。  

新的lifecycle默认使用的背书策略是在配置在通道中的（例如 org中的`MAJORITY`），因此通道启用capabilities时应将背书策略添加到通道的配置中。  

有关如何编辑相关通道配置以通过为每个组织添加背书策略的方式来启用行的lifecycle的信息，请查阅[Enabling the new chaincode lifecycle](https://hyperledger-fabric.readthedocs.io/en/release-2.2/enable_cc_lifecycle.html)。

#### chaincode shim包（仅Golang版）  

在升级peers和通道之前，推荐使用**vendor**来管理v1.4版本的Go chaincode使用的shim包。这样的话，你就无需更改的你的chaincode。  

Fabric网络升级后，如果你不使用vendor来管理你的shim包，尽管之前的chaincode镜像仍能正常工作，但这是有风险的。如果你的chaincode镜像从你的环境中删除了，那么v2.x的peer的invoke会重建chaincode镜像，但此时会报错，因为找不到shim包。  

此时，你有两个选择：  

1. 如果整个通道都已经准备好升级chaincode，那你可以在所有的peers和通道上升级chaincode（至于使用旧的还是新的lifecycle，这取决于你启用的capability版本）。此时最好的方式是使用go mod来管理新的chaincode使用的shim包。
2. 如果整个通道都没有准备好升级chaincode，那你可以使用环境变量来指定的重建chaincode镜像时使用v1.4的`ccenv`。v1.4的`ccenv`仍可以在v2.x的peers上使用。  

#### chaincode日志（仅Golang版） 

chaincode shim包中的日志服务shim.ChaincodeLogger已被删除，所以需要用户自己选择日志服务。详见[Logging control](https://hyperledger-fabric.readthedocs.io/en/release-2.2/logging-control.html#chaincode)。

#### Peer数据库升级  

关于如何升级peers节点的详细信息，可以参考[upgrading components](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrading_your_components.html)。在升级的你的peers节点之前，你还需要额外进行一步操作，那就是升级peer数据库。所有peers节点的数据库（不仅包括状态数据库，还包括历史数据库和peer节点的其它内部数据库）都必须使用v2.x的数据格式进行重建，这是升级到v2.x版本的一部分。要出发重建操作，在peers节点启动前需要删除数据库。接下来介绍如何使用`peer node upgrade-dbs`命令来删除本地数据库并为升级做好准备，这样在启动v2.xpeers节点的第一时间，所有的数据库都会被重建。如果你使用CouchDB作为状态数据库，v2.2的peers已经支持自动删除CouchDB了。要启用该支持，需要你配置peer使用CouchDB，且在执行`upgrade-dbs`命令前启动CouchDB。在v2.0和v2.1中，peer并不支持自动删除CouchDB数据库，你需要自己手动删除。  

在使用`docker run`命令启动新的peer容器之后，再使用下面的命令来升级peer节点（你可以跳过设置`IMAGE_TAG`的步骤，因为`upgrade-dbs`只对v2.x Fabric有效。如果跳过的话，你需要设置`PEER_CONTAINER`和`LEDGERS_BACKUP` 环境变量）。使用下面的命令来代替`docker run`命令启动peer的话，peer节点会删除本地的数据库，并为管理本地数据库做好准备（如果你是从v1.4.x版本升级的话，请使用v2.1代替v2.0）：  

```bash
docker run --rm -v /opt/backup/$PEER_CONTAINER/:/var/hyperledger/production/ \
            -v /opt/msp/:/etc/hyperledger/fabric/msp/ \
            --env-file ./env<name of node>.list \
            --name $PEER_CONTAINER \
            hyperledger/fabric-peer:2.0 peer node upgrade-dbs
```  

在v2.0和v2.1中，如果你使用的是CouchDB作为状态数据库，那么也需要删除CouchDB数据库。删除CouchDB的`/data`目录即可。  

然后使用下面的命令来启动`2.0`标签的peer：  

```bash  
docker run -d -v /opt/backup/$PEER_CONTAINER/:/var/hyperledger/production/ \
            -v /opt/msp/:/etc/hyperledger/fabric/msp/ \
            --env-file ./env<name of node>.list \
            --name $PEER_CONTAINER \
            hyperledger/fabric-peer:2.0 peer node start
```  

peer节点会在启动之后立即使用v2.x数据格式重建数据库。由于重建数据库可能是一个漫长的过程（这取决于你的数据库大小，可能长达数小时），所以需要实时检查peer节点的日志来确认重建的进度。每隔1000个区块，你会看到如下信息：  

> <font color="red">[lockbasedtxmgr] CommitLostBlock -> INFO 041 Recommitting block [1000] to state database</font>  

表示数据库还在重建中。  

如果升级过程中没有删除数据库，在peer节点启动时会返回错误信息：**peer节点使用的是老旧的数据格式，必须使用`peer node upgrade-dbs`命令删除上述数据库（如果使用CouchDB作为状态数据库，则需要手动删除）**。处理完成后重启节点即可。  

#### Capability  

v2.0新增了下面三个Capabilities：  

1. **Application `V2_0`**: 如[Fabric chaincode lifecycle](https://hyperledger-fabric.readthedocs.io/en/release-2.2/chaincode_lifecycle.html)章节所述，启用了新的chaincode lifecycle。  
2. **通道 `V2_0`**：无更新，但与application和orderer版本保持一致。
3. **Orderer `V2_0`**：控制`Use通道CreationPolicyAsAdmins`，可修改通道创建交易的验证方式。当configtxgen与`-bashProfile`选项联用时，可重置从orderer系统通道继承的值。

与Capability版本更新一样，更新`Application`和`通道`之前，确保已经升级的了你的peer可执行文件，更新`Orderer`和`通道`之前，确保已经升级的了你的orderer可执行文件。  

关于如何设置新的Capabilities，详见[Updating the capability level of a 通道](https://hyperledger-fabric.readthedocs.io/en/release-2.2/updating_capabilities.html)。  

#### 为每个组织配置orderer终端（推荐配置）

从v1.4.2开始，推荐在组织版本为所有的系统通道和应用程序通道定义orderer终端，可以在组织的通道配置中新增`OrdererEndpoints`来替代全局的`OrdererAddresses`。如果有一个组织设置了组织版本的的orderer服务终端，那么在连接orderer节点时，所有的orderers和peers都会忽略通道版本的终端。  

当服务发现与多个组织提供的orderer节点一起使用时，那就必须使用组织版本的orderer终端。这需要客户端配置正确的TLS证书。  

如果你的通道配置中每个组织都未包含`OrdererEndpoints`，那你需要升级你的通道配置来给它们添加这一配置。首先需要创建一个包含新配置章节的JSON文件。  

在这个例子中，我们将为名为`OrdererOrg`的组织添加配置。如果你有多个提供orderer服务的组织，那么每个组织都需要添加配置。JSON文件`orglevelEndpoints.json`内容如下：  

```json
{
  "OrdererOrgEndpoint": {
      "Endpoints": {
          "mod_policy": "Admins",
          "value": {
              "addresses": [
                 "127.0.0.1:30000"
              ]
          }
      }
   }
}
```  

之后，导入如下配置：  

- <font color="red">CH_NAME</font>：待更新的通道名称。所有的系统通道和应用程序通道都应该包含排序节点的组织终端。
- <font color="red">CORE_PEER_LOCALMSPID</font>：提出通道更新的组织的MSPID。排序组织的MSP之一。
- <font color="red">CORE_PEER_MSPCONFIGPATH</font>：标识你的组织的MSP的绝对路径。
- <font color="red">TLS_ROOT_CA</font>：提出系统通道更新的组织根证书的绝对路径。
- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。访问排序服务时，你可以访问提供排序服务的任何排序节点。你的请求会自动提交给leader节点。
- <font color="red">ORGNAME</font>：当前你要更新的组织名称，例如`OrdererOrg`。

当你设置好环境变量后，就可以按照[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。  

之后使用下面的命令将组织的lifecycle策略（`orglevelEndpoints.json`文件中配置的）添加到名为`modified_config`的文件中：  

```bash
jq -s ".[0] * {\"通道_group\":{\"groups\":{\"Orderer\": {\"groups\": {\"$ORGNAME\": {\"values\": .[1].${ORGNAME}Endpoint}}}}}}" config.json ./orglevelEndpoints.json > modified_config.json
```  

之后的操作，详见[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

如果排序服务组织执行它们自己的通道编辑操作，那么它们可以在没有进一步签名（默认情况下，编辑组织内部参数只需要该组织管理员的签名）的情况下编辑配置。如果不同组织执行更新，那就需要被编辑的组织对更新请求进行签名。  

---  

## 更新你的组件  

如果想了解最新版Fabric的特殊事项，详见[Upgrading to the latest release of Fabric](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html)。  

本章只介绍更新Fabric组件的操作。关于如何通过编辑通道来改变你通道的capability版本，详见[Updating a 通道 capability](https://hyperledger-fabric.readthedocs.io/en/release-2.2/updating_capabilities.html)。  

> 注意：在Hyperledger Fabric中使用术语**升级**时，指的是升级组件的版本（例如，将可执行文件升级到最新版）。使用**更新**时，指的是配置的更新，例如更新通道的配置或部署脚本。在Fabric中，如果没有数据**迁移**的话，我们不会使用术语**迁移**。  

### 总览  

整体来看，在可执行程序层面升级你的节点，分两步：  

1. 备份账本和MSPs
2. 更新所有的可执行程序到最新版  

如果你拥有排序节点和peers，最好的做法是先升级排序节点。peer节点版本滞后或暂时无法处理某些交易，之后它总是可以赶上的。但如果相当数量的排序节点宕机，那Fabric网络将无法提供服务。  

本文所有的操作都是通过Docker CLI命令执行。如果你使用其它的部署方法（Rancher，Kubernetes，OpenShift，等等），请查阅它的文档了解其CLI如何使用。  

对于本机部署的，你还需要更新节点的YAML配置文件，例如`orderer.yaml`。  

备份`orderer.yaml`或`core.yaml`（peer节点），然后使用最新发布版中的`orderer.yaml`或`core.yaml`来替换它们。之后将备份的`orderer.yaml`或`core.yaml`文件中修改的地方更新到新的文件中。可以使用`diff`来协助。注意，更新YAML文件时，推荐使用最新发布的来替换原有的，这样可以减少很多错误。  

本文是假设你是使用Docker来部署Fabric网络的，YAML文件都已经内嵌到docker镜像中，配置文件中的默认值可以通过环境变量覆盖。  

### 环境变量配置  

在部署peer或order节点时，你需要设置大量跟配置相关的环境变量。最好的做法是将这些环境记录在与要部署相关节点相关的文件中，并保存到本地。这样，在更新节点时可以保证你使用的是更节点创建是一样的环境变量。  

下面是**peer**相关的一系列环境变量（这些环境变量是本地部署使用的）可以放在文件中，你可能并不需要用到下面所有的环境变量：  

```
CORE_PEER_TLS_ENABLED=true
CORE_PEER_GOSSIP_USELEADERELECTION=true
CORE_PEER_GOSSIP_ORGLEADER=false
CORE_PEER_PROFILE_ENABLED=true
CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
CORE_PEER_ID=peer0.org1.example.com
CORE_PEER_ADDRESS=peer0.org1.example.com:7051
CORE_PEER_LISTENADDRESS=0.0.0.0:7051
CORE_PEER_CHAINCODEADDRESS=peer0.org1.example.com:7052
CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
CORE_PEER_GOSSIP_BOOTSTRAP=peer0.org1.example.com:7051
CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.org1.example.com:7051
CORE_PEER_LOCALMSPID=Org1MSP
```  

下面是**orderer**相关的一系列环境变量（这些环境变量是本地部署使用的）可以放在文件中，你可能并不需要用到下面所有的环境变量： 

```
ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
ORDERER_GENERAL_GENESISMETHOD=file
ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block
ORDERER_GENERAL_LOCALMSPID=OrdererMSP
ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
ORDERER_GENERAL_TLS_ENABLED=true
ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
```  

你需要为每个你想升级的节点设置环境变量。  

### 账本备份与还原  

虽然我们将在本教程中演示备份账本数据的过程，但并不严格要求备份peer或排序节点（提供排序服务的一组排序节点之一）的账本数据。因为即使是最坏的情况下（例如硬盘故障），peer节点也能在没有账本的情况下启动。之后你再将peer节点重新加入到期望的通道中，peer节点会自动为每个通道创建账本，并周期性的从排序符合或其它peer节点中接受区块数据。在处理区块的过程中，peer节点会构建它自己的状态数据库。  

但是，备份账本数据可以直接还原peer节点，不需要考虑从创世块构建数据和重新处理所有交易所花费的时间和计算成本，这一通过通常会花费数小时（取决于账本的大小）。此外，账本数据的备份还可能有助于新增peer节点，它可以从现有的peer节点获取账本数据来启动自己。  

本文假定账本数据存放的文件路径并没有改变，还放在默认的路径：`/var/hyperledger/production/`(peer节点)或`/var/hyperledger/production/orderer`（排序节点）。如果你的路径改变了，那么在执行下面的命令时就需要输入你存放账本数据的路径。  

需要注意的是账本和chaincodes数据都保存在该路径下。最好的做法是将两者都进行备份，这样做的话会忽略`/var/hyperledger/production/ledgersData`下的`stateLeveldb`、`historyLeveldb`和`chains/index`目录。尽管这样可以减少备份所需的存储空间，但peer从备份的数据中恢复时可能会花费更多的时间，因为这些账本会在peer启动时重新构建。  

如果使用CouchDB作为状态数据库，那么默认路径下是没有`stateLeveldb`的，因为状态数据库的数据会存如CouchDB中。同样的，如果peer启动时找不到CouchDB数据库或块高较小（基于早先的CouchDB备份），状态数据库会自动地重构数据直至当前块高。所以，如果你分别备份peer的账本数据和CouchDB数据，那么你需要确保CouchDB备份总早于peer的备份。  

### 升级排序节点  

排序节点应该以滚动的方式进行升级（在一次升级过程中）。总体来讲，排序节点的更新步骤如下：  

1. 关闭排序节点。
2. 备份排序节点的账本和MSP。
3. 移除排序节点容器。
4. 使用相应的镜像启动新的排序节点。

在排序服务的所有节点上重复执行上面的过程，直至整个排序服务都完成升级。  

#### 设置环境变量  

在更新排序节点前导入以下环境变量：  

- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。注意，每个节点更新时你都样设置一遍。
- <font color="red">LEDGERS_BACKUP</font>：存放备份数据的路径。就如下面的示例中，每个节点都有它自己的子目录来存放它的账本。目录如果不存在的话，你需要手动创建。
- <font color="red">IMAGE_TAG</font>：你期望升级到的Fabric版本，例如v2.0。

注意，**镜像标签**是必须设置，这样才能确保你使用正确的镜像来启动节点。设置标签的过程取决你的部署方式。  

#### 升级容器  

开始更新之前，我们需要先**下线排序节点**：  

```bash
docker stop $ORDERER_CONTAINER
```  

服务下线后，你就可以**备份账本和MSP**：  

```bash
docker cp $ORDERER_CONTAINER:/var/hyperledger/production/orderer/ ./$LEDGERS_BACKUP/$ORDERER_CONTAINER
```  

然后删除排序服务容器（因为我们需要新容器与现有的容器同名）：  

```bash
docker rm -f $ORDERER_CONTAINER
```  

最后，启用新的排序节点容器：  

```bash
docker run -d -v /opt/backup/$ORDERER_CONTAINER/:/var/hyperledger/production/orderer/ \
            -v /opt/msp/:/etc/hyperledger/fabric/msp/ \
            --env-file ./env<name of node>.list \
            --name $ORDERER_CONTAINER \
            hyperledger/fabric-orderer:$IMAGE_TAG orderer
```  

当所有的排序节点都完成升级，你就可以开始升级peer节点。  

### 升级peer节点  

与排序节点升级一样，peer节点也应该以滚动的方式进行升级（在一次升级过程中）。正如排序节点升级时提到的，排序节点的升级和peer节点的升级是可以并行的，但在本教程中我们是串行执行这两个过程。总体来看，peer节点的升级需要以下几步：  

1. 下线peer节点。
2. 备份peer账本和MSP。
3. 移除chaincode容器和镜像。
4. 移除peer容器。
5. 使用相应的镜像启动新的peer容器。  

#### 设置环境变量  

在更新peer节点前导入以下环境变量：  

- <font color="red">PEER_CONTAINER</font>：peer节点的容器名称。注意，每个节点更新时你都样设置一遍。
- <font color="red">LEDGERS_BACKUP</font>：存放备份数据的路径。就如下面的示例中，每个节点都有它自己的子目录来存放它的账本。目录如果不存在的话，你需要手动创建。
- <font color="red">IMAGE_TAG</font>：你期望升级到的Fabric版本，例如v2.0。

注意，**镜像标签**是必须设置，这样才能确保你使用正确的镜像来启动节点。设置标签的过程取决你的部署方式。  

在所有peer节点上重复执行上面的过程，以便完成所有peer节点的升级。  

#### 升级容器  

首先，使用下面的命令来**下线peer节点**：  

```bash
docker stop $PEER_CONTAINER
```  

然后**备份peer账本和MSP**：  

```bash
docker cp $PEER_CONTAINER:/var/hyperledger/production ./$LEDGERS_BACKUP/$PEER_CONTAINER
```  

在完成peer节点下线和账本备份后，**移除peerchaincode容器和镜像**：  

```bash
CC_CONTAINERS=$(docker ps | grep dev-$PEER_CONTAINER | awk '{print $1}')
if [ -n "$CC_CONTAINERS" ] ; then docker rm -f $CC_CONTAINERS ; fi

CC_IMAGES=$(docker images | grep dev-$PEER | awk '{print $1}')
if [ -n "$CC_IMAGES" ] ; then docker rmi -f $CC_IMAGES ; fi
```  

然后删除peer容器（因为我们需要新容器与现有的容器同名）：  

```bash
docker rm -f $PEER_CONTAINER
```  



最后，启动新的peer容器：  

```bash
docker run -d -v /opt/backup/$PEER_CONTAINER/:/var/hyperledger/production/ \
            -v /opt/msp/:/etc/hyperledger/fabric/msp/ \
            --env-file ./env<name of node>.list \
            --name $PEER_CONTAINER \
            hyperledger/fabric-peer:$IMAGE_TAG peer node start
```  

chaincode容器并不需要手动启动。在收到chaincode请求时（invoke或query），peer首先会检查chaincode是否在运行。如果是，直接使用；如果没有的话，peer节点会启动chaincode（必要时会重建chaincode镜像）。  

#### 验证peer升级完成  

确认peer是否完成升级最好的方法是一次chaincode调用请求。注意，查询操作只能确定账本所在的单个peer节点成功升级。如果你想确认多个peer节点是否升级完成，同时更新chaincode也是升级操作的一部分的话，那你应该等到符合背书策略、且来自足够多组织的peer节点完成升级之后在进行验证。  

在你计划验证之前，你需要升级来自足够多的组织的peer节点，以满足你的背书策略。但只有将更新chaincode作为升级peer操作的一部分时，才需要这样做。如果你的升级操作中不包括更新chaincode，那验证peer升级是否完成的操作可能会得到运行不同Fabric版本的peer节点的背书。  

### 升级CA  

要了解如何升级你的Fabric CA服务，详见[CA documentation](http://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html#upgrading-the-server)。  

### 升级 Node.js SDK  

升级Node.js SDK前需要先升级Fabric和Fabric CA。Fabric和Fabric CA兼容旧版的SDK。在旧版的Fabric和Fabric CA上使用较新的SDK，通常会提示旧版的Fabric和Fabric CA部分功能不可用，且兼容性并未经过测试。  

在你应用程序的根目录下执行下面的命令可以升级所有的`Node.js`客户端：  

```bash
npm install fabric-client@latest

npm install fabric-ca-client@latest
```  

上面的命令安装最新版的Fabric和Fabric CA客户端，并将版本信息写入`package.json`中。  

### 升级CouchDB  

如果使用CouchDB作为状态数据库，那么在你升级peer节点也要同步升级CouchDB。  

升级CouchDB：  

1. 下线CouchDB。
2. 备份CouchDB数据目录。
3. 安装最新版的CouchDB或更新部署脚本启用新的Docker镜像。
4. 重启CouchDB。  

### 升级Node chaincode  

要升级到新版的Node chaincode shim包，开发人员需要：  

1. 更新chaincode`package.json`中的`fabric-shim`至新版。
2. 重新打包新的chaincode包，并在通道的所有背书节点上进行安装。
3. 升级新到新的chaincode，详见[Peer chaincode commands](https://hyperledger-fabric.readthedocs.io/en/release-2.2/commands/peerchaincode.html)。  

### 升级Go chaincode  

关于升级Go chaincode到v2.0版，详见[Chaincode shim changes](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html#chaincode-shim-changes)。  

有大量的第三方工具来帮你管理你的chaincode shim包。选择你熟悉的方式来管理你的chaincode shim包，并重新打包你的chaincode。  

如果你更新了chaincode shim包，那你必须在所有已安装改chaincode的peer节点上重新安装它。安装时使用相同的名称，不同的版本号。之后你还要在部署了该chaincode的所有通道上执行chaincode升级操作来升级chaincode。  

## 更新通道的capability版本  

如果不熟悉capability，那么操作前可以查阅[Capabilities](https://hyperledger-fabric.readthedocs.io/en/release-2.2/capabilities_concept.html)。需要注意的是**在启用capabilities前，需要升级归属该通道的peer节点和排序节点**。  

更多关于最新版Fabric中capabilities版本的信息，详见[Upgrading your components](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html#Capabilities)。  

> 注意：在Hyperledger Fabric中使用术语**升级**时，指的是升级组件的版本（例如，将可执行文件升级到最新版）。使用**更新**时，指的是配置的更新，例如更新通道的配置或部署脚本。在Fabric中，如果没有数据**迁移**的话，我们不会使用术语**迁移**。    

### 先决条件和注意事项  

更新前，请先确保你的机器上有[Prerequisites](https://hyperledger-fabric.readthedocs.io/en/release-2.2/prereqs.html)中所提及的所有依赖。这将保证你拥有更新通道配置所需的最新版工具。  

由于Fabric可以并且应该滚动更新，所以**启用capabilities前需要完成Fabric的升级**。任何没有升级到至少capabilities相关的可执行程序都将引起崩溃，并指出错误的配置，否则会导致账本分叉。  

一旦启用capabilities，它成为该通道的永久记录。这意味着即使之后禁用了capabilities，旧的可执行程序也无法参与到该通道中，因为它无法处理启用capabilities到禁用capabilities期间的所有区块。结果就是一旦启用了capabilities，就不建议或不支持禁用它。  

有鉴于此，可将启用capabilities视为不可逆的。所以在测试设置新capabilities，并在生成环境下启用之前，请三思。  

### 概览  

在接下来的教程中，我们将展示如何在所有的系统通道和应用程序通道中配置capabilities更新。  

是否需要为所有的通道更新配置的每个部分，这取决于最新版的内容以及你的使用场景。详情参见[Upgrading to the latest version of Fabric](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html)。需要注意的是在使用最新版功能前，可能需要更新到最新的capability版本，最好的做法是始终使用最新版的可执行程序和最新的capability版本。  

因为更新capability版本涉及到配置更新事务流程，相关命令详见[Updating a 通道 configuration](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html)。  

与通道其它配置更新一样，capability版本更新也分三步（每个通道）：  

1. 获取最新的通道配置
2. 创建修改后的通道配置
3. 创建配置更新事务

我们将按照下面的顺序来启用capabilities：  

1. [Orderer system 通道](https://hyperledger-fabric.readthedocs.io/en/release-2.2/updating_capabilities.html#orderer-system-通道-capabilities)
   1. Orderer group
   2. 通道 group
2. [Application 通道](https://hyperledger-fabric.readthedocs.io/en/release-2.2/updating_capabilities.html#enable-capabilities-on-existing-通道)
   1. Orderer group
   2. 通道 group
   3. Application group

尽管可以同时编辑通道配置的多个部分，但在本教程中我们将展示如何逐步处理这些过程。也就是说我们不会在一次配置修改中同时修改系统通道的`Orderer`组和`通道`组。这是因为并不是每次发布都有新的`Orderer`组capability和`通道`组capability。  

在生成网络中，单个用户可以独立完成所有通道（和其它配置）更新时不可能的，也是不明智的。例如，orderer system 通道更新，只能由组织的管理员来执行（尽管可以将peer组织添加到排序服务组织中）。同样地，更新其它的`Orderer`或`通道`组的通道配置除了需要排序服务组织的签名外还需要peer组织的签名。分布式系统需要协同管理。  

#### 新建capabilities配置文件  

本教程假设名为`capabilities.json`的文件已创建，它包含所有你想更新的capabilities。使用`jq`将编辑的配置应用到修改后的文件中。  

你也不是非要创建类似`capabilities.json`的文件或使用`jq`工具。修改后的配置也可手动编辑，详见[sample 通道 configuration](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#sample-通道-configuration)。  

然而，这里所描述的过程（使用JSON文件和`jq`工具）在脚本化方面确实有优势，这使得它适合想大量的通道进行配置更新。这也是这种方式为什么会成为**更新通道的推荐方式**。  

示例中，`capabilities.json`文件内容如下（如果将更新通道作为你[Fabric升级到最新版](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html)的一部分，则需要将capabilities设置为适合该版本的版本）：  

```json
{
     "通道": {
         "mod_policy": "Admins",
             "value": {
                 "capabilities": {
                     "V2_0": {}
                 }
             },
         "version": "0"
     },
     "orderer": {
         "mod_policy": "Admins",
             "value": {
                 "capabilities": {
                     "V2_0": {}
                 }
             },
         "version": "0"
     },
     "application": {
         "mod_policy": "Admins",
             "value": {
                 "capabilities": {
                     "V2_0": {}
                 }
             },
         "version": "0"
     }
   }
```  

默认情况下，peer节点并不是orderer system 通道的管理员，所以peer节点不能发起orderer system 通道配置更新。排序组织的管理员必须创建类似的文件（没`application`组capability，因为系统通道中不存在`application`组）来执行系统通道配置更新操作。默认情况下应用程序通道配置是复制系统通道的，所以除非为了特定的capability版本而创建了不同的通道配置，否则应用程序通道的`Orderer`组和`通道`组与网络中其它的系统通道是一样的。  

### orderer system 通道 capabilities  

默认情况下应用程序通道复制系统通道的配置，所以最好的操作是在跟应用程序通道前先更新系统通道的capabilities。就像[Upgrading your components](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrading_your_components.html)中所述，更新peer之前先将排序节点更新至最新版。  

orderer system 通道归排序服务组织管理。默认情况下，只有一个组织（在排序服务初始化节点时创建的组织），但也可以扩展多个组织（例如，有多个组织为排序服务提供节点）。  

在更新`Orderer`和`通道` capability之前，请确保在你的排序服务中的所有节点都已经升级到所需版本。如果排序节点没有升级到所需版本，它将无法处理具有该capability的配置块，并且将崩溃。类似的，如果排序服务中新增一条通道，那所有将被加入到该通道的peer节点必须至少处于`通道`和`Application` capabilities相近的节点版本，否则在处理配置块时这些peer节点将会崩溃。要了解更多信息，详见[Capabilities](https://hyperledger-fabric.readthedocs.io/en/release-2.2/capabilities_concept.html)。  

#### 设置环境变量  

你需要导入以下环境变量：  

- <font color="red">CH_NAME</font>：待更新的系统通道名称。
- <font color="red">CORE_PEER_LOCALMSPID</font>：执行通道更新操作的MSP ID，排序服务组织中的MSP。
- <font color="red">TLS_ROOT_CA</font>：排序节点TLS证书的绝对路径。
- <font color="red">CORE_PEER_MSPCONFIGPATH</font>：标识你的组织的MSP存放的绝对路径。
- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。访问排序服务时，你可以访问排序服务中的任意节点。你的请求会自动提交给leader节点。  

#### `Orderer`组  

关于如何拉取、传递和确定通道配置范围的命令，详见[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。如果你有了`modified_config.json`文件，那你可以使用下面的命令来新增`Orderer`组capabilities：  

```bash
jq -s '.[0] * {"通道_group":{"groups":{"Orderer": {"values": {"Capabilities": .[1].orderer}}}}}' config.json ./capabilities.json > modified_config.json
```  

然后执行步骤[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

因为你现在更新的是系统通道，系统通道修改策略只需要排序服务组织的管理员签名。

#### `通道`组  

关于如何拉取、传递和确定通道配置范围的命令，详见[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。如果你有了`modified_config.json`文件，那你可以使用下面的命令来新增`通道`组capabilities：  

```bash
jq -s '.[0] * {"通道_group":{"values": {"Capabilities": .[1].通道}}}' config.json ./capabilities.json > modified_config.json
```  

然后执行步骤[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

因为你现在更新的是系统通道，系统通道的修改策略只需要排序服务组织的管理员签名。在应用程序通道中，假如你没有修改默认值，通常需要同时满足`Application`组（由peer组织的MSPs组成）和`Orderer`组（由排序服务组织组成）的**大多数管理员**策略。  

### 在已有通道上启用capabilities  

现在我们来更新orderer system 通道的capabilities，我们将会更新已有通道（你想更新的）的配置。   

应用程序通道的配置与系统通道的非常相似。这样，我们就能复用`capabilities.json`文件，并使用相同的命令来进行更新（只需要重新设置环境变量即可）。  

**在更新capabilities前，请确保排序服务中的所有排序节点和通道中的所有peer节点都已升级至要求的版本，否则未升级的节点将无法处理启用了capability的配置块并引起崩溃**。更多信息详见[Capabilities](https://hyperledger-fabric.readthedocs.io/en/release-2.2/capabilities_concept.html)。  

#### 设置环境变量  

- <font color="red">CH_NAME</font>：待更新的应用程序通道名称。
- <font color="red">CORE_PEER_LOCALMSPID</font>：执行通道更新操作的MSP ID，peer组织中的MSP。
- <font color="red">TLS_ROOT_CA</font>：peer组织TLS证书的绝对路径。
- <font color="red">CORE_PEER_MSPCONFIGPATH</font>：标识你的组织的MSP存放的绝对路径。
- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。访问排序服务时，你可以访问排序服务中的任意节点。你的请求会自动提交给leader节点。  

#### `Orderer`组  

[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。如果你有了`modified_config.json`文件，那你可以使用下面的命令来新增`Orderer`组capabilities：  

```bash
jq -s '.[0] * {"通道_group":{"groups":{"Orderer": {"values": {"Capabilities": .[1].orderer}}}}}' config.json ./capabilities.json > modified_config.json
```  

然后执行步骤[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

该capability默认的修改策略是需要`Orderer`组中**大多数管理员**同意（即，大多数排序服务的管理员）。peer组织可以更新该capability，但这种情况下，peer组织的签名并不满足该策略。  

#### `通道`组  

[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。如果你有了`modified_config.json`文件，那你可以使用下面的命令来新增`通道`组capabilities：  

```bash
jq -s '.[0] * {"通道_group":{"values": {"Capabilities": .[1].通道}}}' config.json ./capabilities.json > modified_config.json
```  

然后执行步骤[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

该capability默认的修改策略是需要`Application`和`Orderer`组**大多数管理员**审核通过。也就是说，需要peer组织和排序服务组织中大多数管理员对该请求进行签名认证。  

#### `Application`组  

[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。如果你有了`modified_config.json`文件，那你可以使用下面的命令来新增`通道`组capabilities：  

```bash
jq -s '.[0] * {"通道_group":{"groups":{"Application": {"values": {"Capabilities": .[1].application}}}}}' config.json ./capabilities.json > modified_config.json
```  

然后执行步骤[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。   

该capability默认的修改策略是需要`Application`组**大多数管理员**审核通过。也就是说，需要peer组织中的大多数管理员进行投票。排序服务的管理员不需要参与。  

**这样的结果就是不要将此capability设置为不存在的版本**。因为排序节点既不会解析应用程序capabilities，也不会验证它，排序节点会审核通过所有的应用程序capabilities版本并将新的配置块分发给peer节点以便peer节点将其保存到账本中。这样的话，peer节点将无法处理该capability并引起崩溃。即使之后再将一个合法的capability版本配置到peer节点上，但之前的配置块仍存在于账本中，当尝试处理之前的配置块时还是会引发崩溃。  

这也是为什么需要`capabilities.json`这样的文件。它可以有效防止简单的用户错误，例如，当将应用程序的apability设置为`V20`，而不是`V2_0`时，这会导致通道不可用且无法恢复。  

### 启用capabilities后进行验证  

验证capabilities是否成功启用的最好方式是在所有的通道上执行一次chaincode调用。未升级到相应版本的节点都无法解析新的capabilities，这些节点都会崩溃。在这些节点成功重启之前你需要将它们升级至相应的版本。  

---

## 启用新的chaincode lifecycle  

用户从v1.4.x升级到v2.x后，必须编辑通道配置来启用新的lifecycle功能。这个过程涉及到相关用户必须执行的一系列[通道配置更新](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html)。  

要启用新的chaincode lifecycle，应用程序通道的`Channel`和`Application`capabilities必须更新到**V2_0**，详见[Considerations for getting to 2.0](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html#chaincode-lifecycle)。  

总体来看，通道配置更新分三步（每个通道）：  

1. 获取最新的通道配置
2. 创建修改后的通道配置
3. 创建配置更新交易  

接下来我们使用`enable_lifecycle.json`文件（包含我们所需要的所有通道配置更新）来更新通道配置。需要留意的是，在生成环境中，可能有多个用户发起通道更新请求。为了方便起见，我们将所有的更新都放在单个文件中呈现。  

### 创建`enable_lifecycle.json`文件  

除了使用`enable_lifecycle.json`文件外，本教程还将使用`jq`将编辑后的内容应用到文件中。修改的文件也可以手动编辑，详见[sample channel configuration](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#sample-channel-configuration)。  

本文展示的操作（使用JSON文件和`jq`工具）在脚本化方面更具优势，更适合大量的通道配置更新。也是编辑通道配置的推荐操作。  

`enable_lifecycle.json`使用的示例，例如`org1Policies`和`Org1ExampleCom`，在部署时需要替换成实际值：  

```json
{
    "org1Policies": {
        "Endorsement": {
            "mod_policy": "Admins",
            "policy": {
                "type": 1,
                "value": {
                    "identities": [
                        {
                            "principal": {
                                "msp_identifier": "Org1ExampleCom",
                                "role": "PEER"
                            },
                            "principal_classification": "ROLE"
                        }
                    ],
                    "rule": {
                        "n_out_of": {
                            "n": 1,
                            "rules": [
                                {
                                    "signed_by": 0
                                }
                            ]
                        }
                    },
                    "version": 0
                }
            },
            "version": "0"
        }
    },
    "org2Policies": {
        "Endorsement": {
            "mod_policy": "Admins",
            "policy": {
                "type": 1,
                "value": {
                    "identities": [
                        {
                            "principal": {
                                "msp_identifier": "Org2ExampleCom",
                                "role": "PEER"
                            },
                            "principal_classification": "ROLE"
                        }
                    ],
                    "rule": {
                        "n_out_of": {
                            "n": 1,
                            "rules": [
                                {
                                    "signed_by": 0
                                }
                            ]
                        }
                    },
                    "version": 0
                }
            },
            "version": "0"
        }
    },
    "appPolicies": {
        "Endorsement": {
            "mod_policy": "Admins",
            "policy": {
                "type": 3,
                "value": {
                    "rule": "MAJORITY",
                    "sub_policy": "Endorsement"
                }
            },
            "version": "0"
        },
        "LifecycleEndorsement": {
            "mod_policy": "Admins",
            "policy": {
                "type": 3,
                "value": {
                    "rule": "MAJORITY",
                    "sub_policy": "Endorsement"
                }
            },
            "version": "0"
        }
    },
    "acls": {
        "_lifecycle/CheckCommitReadiness": {
            "policy_ref": "/Channel/Application/Writers"
        },
        "_lifecycle/CommitChaincodeDefinition": {
            "policy_ref": "/Channel/Application/Writers"
        },
        "_lifecycle/QueryChaincodeDefinition": {
            "policy_ref": "/Channel/Application/Readers"
        },
        "_lifecycle/QueryChaincodeDefinitions": {
            "policy_ref": "/Channel/Application/Readers"
        }
    }
}
```  

**在新的策略中，如果`NodeOUs`启用了，"role"字段应该设置为`PEER`，否则设置为`MEMBER`**。  

### 编辑通道配置  

#### 系统通道更新  

因为修改系统通道配置以启用新的lifecycle只涉及到peer组织配置中的通道配置参数，所以被编辑的peer组织都必须掉相关的通道配置更新进行签名。  

默认情况下，系统通道只能被系统通道的管理员编辑（排序服务组织的管理员，而非peer组织的），这意味着对联盟中peer组织的配置更新必须有系统通道管理提出，并发送给相应的peer组织进行签名。  

需要导入以下环境变量：  

- <font color="red">CH_NAME</font>：待更新的系统通道名称。
- <font color="red">CORE_PEER_LOCALMSPID</font>：执行通道更新操作的MSP ID，排序服务组织中的MSP。
- <font color="red">TLS_ROOT_CA</font>：发起系统通道更新组织的TLS证书的绝对路径。
- <font color="red">CORE_PEER_MSPCONFIGPATH</font>：标识你的组织的MSP存放的绝对路径。
- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。访问排序服务时，你可以访问排序服务中的任意节点。你的请求会自动提交给leader节点。 
- <font color="red">ORGNAME</font>：正在更新的组织名称。
- <font color="red">CONSORTIUM_NAME</font>：正在更新的联盟名称。  

设置好环境变量之后，[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。  

之后，使用下面的命令将lifecycle组织策略（`enable_lifecycle.json`中列出的）添加到名为`modified_config.json`文件中：  

```bash
jq -s ".[0] * {\"channel_group\":{\"groups\":{\"Consortiums\":{\"groups\": {\"$CONSORTIUM_NAME\": {\"groups\": {\"$ORGNAME\": {\"policies\": .[1].${ORGNAME}Policies}}}}}}}}" config.json ./enable_lifecycle.json > modified_config.json
```  

最后，[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

如上所述，这些更新都必须由系统通道管理员提出，并发送给相应的peer组织进行签名。  

#### 应用程序通道更新  

##### 编辑peer组织  

我们需要对所有应用程序通道上的组织执行一组类似的编辑。  

跟系统通道不同，peer组织可以发起对应用程序通道的配置更新请求。如果你只是对自己的组织进行配置更新，那你不需要其它组织的签名；但如果你要更新另一个组织的配置，那你就需要这个组织的签名。  

需要导入以下环境变量：  

- <font color="red">CH_NAME</font>：待更新的应用程序通道名称。
- <font color="red">CORE_PEER_LOCALMSPID</font>：执行通道更新操作的MSP ID，peer组织中的MSP。
- <font color="red">TLS_ROOT_CA</font>：排序节点的TLS证书的绝对路径。
- <font color="red">CORE_PEER_MSPCONFIGPATH</font>：标识你的组织的MSP存放的绝对路径。
- <font color="red">ORDERER_CONTAINER</font>：排序节点的容器名称。访问排序服务时，你可以访问排序服务中的任意节点。你的请求会自动提交给leader节点。 
- <font color="red">ORGNAME</font>：正在更新的组织名称。

设置好环境变量之后，[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。  

之后，使用下面的命令将lifecycle组织策略（`enable_lifecycle.json`中列出的）添加到名为`modified_config.json`文件中：  

```bash
jq -s ".[0] * {\"channel_group\":{\"groups\":{\"Application\": {\"groups\": {\"$ORGNAME\": {\"policies\": .[1].${ORGNAME}Policies}}}}}}" config.json ./enable_lifecycle.json > modified_config.json
```  

最后，[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

##### 编辑应用程序通道  

在所有的应用程序通道都已经[更新到包含V2_0capabilities](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrade_to_newest_version.html#capabilities)后，新的chaincode lifecycle背书策略必须添加到所有的通道中。  

所需的环境变量与更新peer组织时一样。不同之处在于不需要更新配置文件中的组织配置，所以不需要设置`ORGNAME`。  

设置好环境变量之后，[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。  

之后，使用下面的命令将lifecycle组织策略（`enable_lifecycle.json`中列出的）添加到名为`modified_config.json`文件中：  

```bash
jq -s '.[0] * {"channel_group":{"groups":{"Application": {"policies": .[1].appPolicies}}}}' config.json ./enable_lifecycle.json > modified_config.json
```  

最后，[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

要通过通过更新请求，则必须满足配置文件中`Channel/Application`章节配置的修改策略。默认情况下，需要该通道中的**大多数**peer组织同意。  

##### 编辑通道ACLs（可选）  

下面的[访问控制列表（ACL）](https://hyperledger-fabric.readthedocs.io/en/release-2.2/access_control.html)是`enable_lifecycle.json`文件中的默认值，可根据你的使用场景进行选择：  

```json
"acls": {
 "_lifecycle/CheckCommitReadiness": {
   "policy_ref": "/Channel/Application/Writers"
 },
 "_lifecycle/CommitChaincodeDefinition": {
   "policy_ref": "/Channel/Application/Writers"
 },
 "_lifecycle/QueryChaincodeDefinition": {
   "policy_ref": "/Channel/Application/Readers"
 },
 "_lifecycle/QueryChaincodeDefinitions": {
   "policy_ref": "/Channel/Application/Readers"
```  

可以使用前面编辑应用程序通道时使用的环境变量。  

设置好环境变量之后，[Step 1: Pull and translate the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-1-pull-and-translate-the-config)。  

之后，使用下面的命令将lifecycle组织策略（`enable_lifecycle.json`中列出的）添加到名为`modified_config.json`文件中：  

```bash
jq -s '.[0] * {"channel_group":{"groups":{"Application": {"values": {"ACLs": {"value": {"acls": .[1].acls}}}}}}}' config.json ./enable_lifecycle.json > modified_config.json
```  

最后，[Step 3: Re-encode and submit the config](https://hyperledger-fabric.readthedocs.io/en/release-2.2/config_update.html#step-3-re-encode-and-submit-the-config)。  

要通过通过更新请求，则必须满足配置文件中`Channel/Application`章节配置的修改策略。默认情况下，需要该通道中的**大多数**peer组织同意。  

### 在`core.yaml`中启用新的lifecycle  

如果你是按照[推荐操作](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrading_your_components.html#overview)，使用`diff`之类的工具比较新旧`core.yaml`，那你就不必添加`_lifecycle: enable`来启用系统chaincode，因为它在新版`core.yaml`的`chaincode/system`下。   

如果你是直接更新原有的YAML文件，那就必须添加`_lifecycle: enable`来启用系统chaincode。  

关于节点升级的信息，详见[Upgrading your components](https://hyperledger-fabric.readthedocs.io/en/release-2.2/upgrading_your_components.html)。  



---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。 
> Author: MonsterMeng92

---