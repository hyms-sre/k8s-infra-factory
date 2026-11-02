# terraform/aws — AWS 平台层（预留）

当前**未实现**。未来将支持通过 AWS 构建 Kubernetes 环境，预计包含：

- VPC / Subnet / Security Group（网络）
- EC2（计算节点，替代 vSphere VM）
- EKS 或自建 kubeadm 集群 / Node Group
- EBS / EFS / S3（存储）

现阶段 Kubernetes IaC 请使用 `terraform/vsphere/`。
设计约定（职责边界/命名/幂等）与 vsphere 平台层保持一致。
