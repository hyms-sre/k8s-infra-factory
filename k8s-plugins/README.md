# k8s-plugins — Kubernetes 平台扩展

K8s Base（`terraform/vsphere` + Cloud-Init → kubeadm 引导）只负责让集群**正常运行**；
本目录负责让集群变成**完整的平台**。插件与 Base 严格分离：

```
Kubernetes (kubeadm 引导完成)
   ↓
k8s-plugins/networking/metallb       ← LoadBalancer IP 池
k8s-plugins/storage/longhorn         ← 持久化存储 (默认 StorageClass)
k8s-plugins/gitops/argocd            ← 持续部署
k8s-plugins/observability/prometheus ← 监控告警
...
```

**绝对不要为了安装一个插件去修改 Cloud-Init**（user-data 不装 Prometheus/ArgoCD/MetalLB）。

## 分类

| 目录 | 插件 |
|---|---|
| `networking/` | MetalLB、Gateway API |
| `storage/` | NFS、Longhorn |
| `observability/` | Metrics Server、Prometheus、Grafana、Loki、ECK |
| `cicd/` | Jenkins、GitLab Runner、Tekton |
| `gitops/` | ArgoCD、Flux |
| `security/` | cert-manager、Kyverno、Trivy |
| `platform/` | Headlamp |

## 当前状态

**目录 + README 先行，实现按需逐个补**——不要为了目录好看一次性塞几十个插件。
每个插件实现时补齐：安装脚本或命令、Helm values、Kubernetes manifests、配置。

各环境实际安装了什么、用了什么 values，记录在 `live/<环境>/.../platform/`。

## 原则

- **不进 Cloud-Init**：OS 初始化只到 kubeadm-ready（CNI 例外，属集群启动的一部分）
- **不进 Terraform**：插件是集群内资源，用 kubectl/helm 管理
- **国内环境**：镜像优先走 Harbor proxy cache（`cluster.yaml` 的 `harbor.upstreams`），
  排错见 `docs/99-参考/05-故障排查.md`
- **幂等**：helm upgrade / kubectl apply 天然幂等，安装命令必须可重复执行

## 推荐安装顺序

1. MetalLB（Web 类插件的 LoadBalancer 前提）
2. 存储（Longhorn / NFS，有状态服务的前提）
3. Metrics Server → cert-manager → Gateway API → 观测栈 → GitOps → CI/CD

各插件已知的踩坑清单见 `docs/99-参考/05-故障排查.md`。
