# examples/k8s — 如何使用 terraform/vsphere 部署 K8s

本目录不是第二份 K8s 实现，只演示核心入口 `terraform/vsphere/` 的完整使用流程。

## 1. 准备

- vSphere：数据中心 / ESXi / 数据存储 / 端口组 / Ubuntu 24.04 Cloud Image 模板
  （制作见 `docs/12-云平台/01-vSphere.md`）
- 本机：Python 3.9+（`pip install pyyaml`）、Terraform ≥ 1.5、SSH 密钥对

## 2. 配置

```bash
# 集群定义 (集群名/节点数量/规格/网段): terraform/vsphere/cluster.yaml
# 参考样例: 本目录 config.example.yaml (含逐字段注释)

# vCenter 凭据 (不入 Git):
cp examples/k8s/terraform.tfvars.example terraform/vsphere/terraform.tfvars
# 填入真实 vCenter 地址与账号
```

## 3. 生成节点定义

```bash
cd terraform/vsphere
python generate.py
# 输出: Cluster / Masters / Workers / 节点清单 (IP/主机名/规格) + Generated: vm.tf
```

## 4. 创建 VM

```bash
terraform init
terraform plan
terraform apply
```

Cloud-Init 首启自动把每台 VM 初始化到 kubeadm-ready
（containerd / kubelet / kubeadm / kubectl / helm / nerdctl）。

## 5. 引导集群

```bash
ssh <user>@<master-ip>     # kubeadm init ...  (完整命令见 docs/02-Kubernetes/07-kubeadm实践.md)
ssh <user>@<worker-ip>     # kubeadm join ...
```

## 6. 扩展平台

按 `k8s-plugins/README.md` 安装 MetalLB / 存储 / 观测 / GitOps 等插件。

## 本目录文件

| 文件 | 作用 |
|---|---|
| `config.example.yaml` | cluster.yaml 逐字段注释样例 |
| `terraform.tfvars.example` | vCenter 凭据模板 |
