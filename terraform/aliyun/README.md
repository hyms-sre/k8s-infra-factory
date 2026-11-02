# terraform/aliyun — Alibaba Cloud 平台层（预留）

当前**未实现**。未来将支持通过阿里云构建 Kubernetes 环境，预计包含：

- VPC / 交换机 / 安全组（网络）
- ECS（计算节点，替代 vSphere VM）
- ACK 或自建 kubeadm 集群
- NAS / OSS / 云盘（存储）

现阶段 Kubernetes IaC 请使用 `terraform/vsphere/`。
设计约定（职责边界/命名/幂等）与 vsphere 平台层保持一致。
