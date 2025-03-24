---
layout: post
title: 使用 ethereum-package 部署以太坊POS节点
tags: ethereum
mermaid: false
math: false
---  

### 一、环境准备

1. **安装Docker**  
   Kurtosis依赖Docker作为底层容器运行时。需根据操作系统安装Docker并启动服务：  
   ```bash
   $ systemctl start docker  # 启动Docker
   $ systemctl enable docker # 设置开机自启
   ```
2. **安装Kurtosis CLI**  
   根据操作系统选择安装命令：  
   - **MacOS**：  
     ```bash
     $ brew install kurtosis-tech/tap/kurtosis-cli
     ```
   - **Ubuntu/Debian**：  
     ```bash
     $ echo "deb [trusted=yes] https://apt.fury.io/kurtosis-tech/ /" | sudo tee /etc/apt/sources.list.d/kurtosis.list
     $ sudo apt update && sudo apt install kurtosis-cli
     ```
   - **验证安装**：  
     ```bash
     $ kurtosis version
     ```

### 二、部署默认配置的以太坊网络

1. **启动单节点测试链**  
   使用默认配置快速启动一个本地以太坊网络（包含执行层和共识层客户端）：  
   ```bash
   $ kurtosis run --enclave my-testnet github.com/ethpandaops/ethereum-package
   ```
   - `enclave`参数指定隔离环境名称（如`my-testnet`）。
   - 默认使用Geth（执行层）和Lighthouse（共识层）客户端。
2. **验证启动成功**  
   成功后会输出各服务状态，例如：  
   ```
   Successfully added 1 EL participants
   Service 'el-1-geth-lighthouse' added with service UUID...
   ```

### 三、自定义配置部署

1. **创建配置文件**  
   编写`network_params.yaml`文件，定义网络参数。例如：  
   ```yaml
   participants:
     - el_type: geth
       cl_type: lighthouse
   network_params:
     network: "holesky-shadowfork"  # 支持Shadowfork模式
   persistent: true                 # 启用持久化存储（Shadowfork必需）
   additional_services:
     - apache                       # 启用文件共享服务
   ```
   - **关键参数**：  
     - `el_type`/`cl_type`：指定执行层（Geth、Nethermind等）和共识层客户端（Lighthouse、Teku等）。
     - `network`：支持公共测试网（如`holesky`）或Shadowfork（如`holesky-shadowfork`）。
     - `persistent`：启用持久化存储，防止数据丢失。
2. **运行自定义配置**  
   ```bash
   $ kurtosis run --enclave my-testnet github.com/ethpandaops/ethereum-package --args-file network_params.yaml
   ```

### 四、Kubernetes部署（可选）

1. **Kubernetes集群要求**  
   - 推荐使用云服务（如AWS EKS、GCP GKE）或自建集群。
   - 确保存储卷性能（通过`el_volume_size`和`cl_volume_size`调整存储大小）。
2. **调整容器调度策略**  
   在`network_params.yaml`中定义Kubernetes容忍（Tolerations）：  
   ```yaml
   participants:
     - el_type: reth
       cl_type: teku
       el_tolerations:  # 覆盖全局配置
         - key: "gpu-node"
           operator: "Exists"
   global_tolerations:
     - key: "node-role.kubernetes.io/master"
       effect: "NoSchedule"
   ```
   

### 五、管理与调试

1. **访问服务日志**  
   ```bash
   $ kurtosis service logs my-testnet el-1-geth-lighthouse
   ```
2. **下载创世文件**  
   ```bash
   $ kurtosis files download my-testnet el-genesis-data ~/Downloads
   ```
3. **进入容器Shell**  
   ```bash
   $ kurtosis service shell my-testnet el-1-geth-lighthouse
   ```
   
### 六、高级功能

1. **Shadowforking**  
   通过配置文件模拟主网分叉环境：  
   ```yaml
   network_params:
     network: "mainnet-shadowfork-verkle"  # Verkle树测试
     electra_fork_epoch: 1                 # 指定分叉区块
   persistent: true
   ```
2. **MEV-Boost集成**  
   启用Flashbot的MEV基础设施：  
   ```yaml
   mev_params:
     mode: "full"  # 或 "mock" 模拟模式
   ```
3. **监控与工具**  
   默认集成Prometheus、Grafana和Blobscan（用于分析EIP-4844 Blob交易）。

### 七、清理资源

```bash
$ kurtosis enclave rm -f my-testnet  # 删除整个环境
$ kurtosis clean -a                  # 清理所有资源
```

### 注意事项

- **云环境部署**：建议使用高性能存储（如SSD），避免因磁盘速度导致同步问题。
- **客户端兼容性**：不同客户端（如Prysm）可能需要特定镜像或参数。

通过以上步骤，可以灵活部署一个多客户端、可观测性强的以太坊开发网络。更多配置细节可参考[官方文档](https://github.com/ethpandaops/ethereum-package)。

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