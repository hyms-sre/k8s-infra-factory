# AWS（预留设计，未实现）

> 当前状态：只有本 README。正式实现前请以 terraform/vsphere 的结构为蓝本。

## 未来范围

| 层 | AWS 对应物 | 说明 |
|---|---|---|
| 网络 | VPC / Subnet / Security Group / IGW-NAT | 对应 vSphere 端口组/路由 |
| 计算 | EC2 (或 EKS NodeGroup) | 对应 vSphere VM；user-data 注入同一份 cloud-config |
| 集群 | EKS 或 自建 kubeadm | 自建可复用本项目 generate.py + cloud-init 全链路 |
| 存储 | EBS / EFS / S3 | 对应数据盘/共享存储/对象备份 |
| IAM | 实例角色/IRSA | 替代静态凭据 |

## 设计约定（实现时遵守）

- 目录结构对齐 terraform/vsphere：README + generate.py + provider/versions/variables/
  data/locals/main/vm.tf + outputs + cloud-init 模板
- cluster.yaml schema 尽量复用（network 段语义换成 VPC/subnet）
- 凭据走 IAM（不落 tfvars），AGENTS 约束见根 AGENT.md 与 docs/99-参考/02
