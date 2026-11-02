# 场景: vSphere + Kubernetes（本项目主流程）

## 目标

从零到一套可用的 K8s 集群：VM 创建 → 系统初始化 → 集群引导 → 最小可验证。

## 步骤

```bash
# 0. 前置: vSphere 模板 (docs/12-云平台/01-vSphere.md) + 本机工具
cd terraform/vsphere
vim cluster.yaml                                   # 集群定义
cp ../examples/k8s/terraform.tfvars.example terraform.tfvars && vim terraform.tfvars

# 1. 生成 + 创建
python generate.py                                 # cluster.yaml → vm.tf
terraform init && terraform apply                  # VM + Cloud-Init (kubeadm-ready)

# 2. 验证节点
ssh <user>@<master-ip> 'cloud-init status --long; kubectl version --client'

# 3. 集群引导 (docs/02-Kubernetes/07-kubeadm实践.md)
kubeadm init --pod-network-cidr=10.244.0.0/16 ...
kubeadm token create --print-join-command          # worker join
cilium install                                     # CNI
kubectl get nodes                                  # 全 Ready

# 4. 最小验证
kubectl run net --rm -it --image=busybox -- ping -c2 kubernetes.default
```

## 关键检查点

| 检查点 | 期望 |
|---|---|
| generate.py 输出 | 节点数/IP/主机名/规格符合预期 |
| plan | 仅新增节点, 无意外 diff |
| cloud-init | status: done, 无 error |
| get nodes | NotReady→Ready (装 CNI 后) |

## 常见故障

见 docs/99-参考/05-故障排查.md（guestinfo/网段/CNI/config_path 等）。
