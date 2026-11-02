# Terraform 与 Kubernetes、云平台的关系

## 常见困惑："Terraform 能部署 K8s 吗？"

能，但本项目**刻意不用** Terraform 部署 Kubernetes 应用，分工如下：

| 层 | 工具 | 理由 |
|---|---|---|
| 基础设施（VM/网络/存储卷） | Terraform | 生命周期长、声明式合适 |
| 机器初始化 | Cloud-Init | 属于镜像/实例语义 |
| 集群引导（init/join） | kubeadm（文档驱动） | 一次性有状态操作，声明式反而别扭 |
| 集群内应用/插件 | kubectl / Helm | 变更频率高，K8s 自己的 API 就是声明式的 |

在 K8s 世界里，"Kubernetes 之于容器" ≈ "Terraform 之于云资源"——都是声明式调和
（reconcile），只是层次不同。两层各自声明式，中间不需要再套一层 Terraform。

## 云平台维度

```
terraform/vsphere   ← 当前唯一正式实现
terraform/aws       ← 预留 (VPC/EKS/EC2/NodeGroup)
terraform/aliyun    ← 预留 (VPC/ECS/ACK)
```

平台层差异被隔离在 terraform/<平台>/ 内：cluster.yaml 的 schema、generate.py、
Cloud-Init 模板在平台间尽量复用（AWS/Aliyun 上以 user-data 注入同一份 cloud-config）。

## 延伸阅读

- 官方教程 developer.hashicorp.com/terraform/tutorials
- Provider 文档 registry.terraform.io/providers/hashicorp/kubernetes
- docs/12-云平台/（vSphere 主线 + AWS/Aliyun 预留设计）
