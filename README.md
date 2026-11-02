# 基于 Terraform 的 vSphere Kubernetes 集群自动化交付平台

**版本：v1.0.1**

`iac-k8s-esxi` 是一个面向 VMware vSphere 的 Kubernetes 基础设施即代码（IaC）
项目。项目使用 **Terraform + Python + Cloud-Init + kubeadm**，将 Kubernetes
节点的虚拟机资源创建、操作系统初始化和集群交付流程标准化。

> 当前正式支持的平台为 VMware vSphere。AWS 和 Aliyun 目录目前仅作为后续扩展
> 的设计预留，并不代表已经实现多云统一部署。

## 项目架构

```text
cluster.yaml
    │
    ▼
generate.py                 # 生成 Kubernetes 节点定义
    │
    ▼
vm.tf (for_each)            # Terraform 管理全部节点
    │
    ▼
Terraform + vSphere Provider
    │
    ▼
vSphere VM × N
    │
    ▼
Cloud-Init                   # 初始化 Ubuntu 节点至 kubeadm-ready
    │
    ▼
kubeadm init / join          # 引导 Kubernetes 集群
    │
    ▼
k8s-plugins                  # 网络、存储、观测、GitOps 等平台扩展
```

## 核心能力

- **vSphere 基础设施自动化**：通过 Terraform 批量创建、更新和销毁 Kubernetes
  集群虚拟机。
- **配置驱动的节点生成**：以 `cluster.yaml` 作为集群拓扑、节点规格、网络地址
  和 Kubernetes 版本的统一配置入口，由 Python 生成 `vm.tf`。
- **自动化主机初始化**：Cloud-Init 自动完成主机名、静态网络、SSH、时间同步、
  系统参数、containerd、kubelet、kubeadm 和 kubectl 配置。
- **Kubernetes 集群交付**：将 vSphere 虚拟机资源准备至 `kubeadm-ready`，再通过
  kubeadm 完成控制平面和工作节点引导。
- **平台能力扩展**：通过 `k8s-plugins/` 管理 Cilium、MetalLB、Gateway API、
  Longhorn、NFS、Prometheus、Grafana、Loki、ArgoCD、Flux、Kyverno 等组件。
- **多环境组织**：通过 `live/` 管理实验环境、生产环境以及国内网络环境配置，
  实现环境参数隔离和配置复用。
- **受限网络适配**：国内网络场景可结合 OpenWrt/OpenClash 和 Harbor Proxy
  Cache 提供 DNS、代理出口及镜像缓存。
- **可重复构建**：基础设施和节点初始化均采用声明式配置，支持集群的销毁与重建。

## 技术栈

| 层次 | 技术 |
|---|---|
| 虚拟化平台 | VMware vSphere、ESXi、vCenter |
| 基础设施即代码 | Terraform、VMware vSphere Provider |
| 配置生成 | Python、PyYAML |
| 操作系统初始化 | Ubuntu Cloud Image、Cloud-Init |
| 容器运行时 | containerd |
| Kubernetes | kubeadm、kubelet、kubectl |
| 网络 | Cilium、MetalLB、Gateway API、Envoy Gateway |
| 存储 | Longhorn、NFS |
| 可观测性 | Prometheus、Grafana、Loki、Metrics Server、ECK |
| 平台工程 | Helm、ArgoCD、Flux、Headlamp |
| 安全与供应链 | cert-manager、Kyverno、Trivy |
| 工程工具 | Makefile、Docusaurus |

## 快速开始

### 前置条件

- Python 3.9 或更高版本，并安装 PyYAML
- Terraform 1.5 或更高版本
- 可访问的 vCenter 或独立 ESXi 环境
- 已准备 Ubuntu 24.04 Cloud Image 模板，并内置 Cloud-Init
- SSH 密钥对

### 配置并生成节点定义

```bash
cd terraform/vsphere

# 编辑集群名称、节点数量、规格、IP、网段和 Kubernetes 版本
vim cluster.yaml

# 从示例复制 vSphere 连接参数，凭据不要提交到 Git
cp ../../examples/k8s/terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 生成 vm.tf
python generate.py
```

### 初始化和部署基础设施

```bash
terraform init
terraform plan
terraform apply
```

也可以在仓库根目录使用 Makefile：

```bash
make generate
make init
make validate
make plan
make apply
```

Terraform 完成后，虚拟机将被创建并初始化为 `kubeadm-ready`。集群引导和平台
组件安装请参考 `docs/02-Kubernetes/`、`live/` 和 `k8s-plugins/` 中的说明。

## 目录结构

```text
iac-k8s-esxi/
├── terraform/
│   ├── vsphere/             # 正式支持的 vSphere 实现
│   ├── aws/                # 后续扩展预留
│   └── aliyun/             # 后续扩展预留
├── live/                   # lab、prod 及网络环境组织
├── k8s-plugins/            # Kubernetes 平台能力扩展
├── examples/               # Kubernetes、Harbor、OpenWrt 示例
├── scripts/                # Windows、Linux、macOS 辅助脚本
├── docs/                   # 技术知识库和部署文档
├── website/                # Docusaurus 文档站点
├── Makefile                # 常用操作封装
└── README.md
```

## 凭据与状态文件

以下内容不得提交到 Git：

- `terraform.tfvars`
- vSphere 密码及其他敏感变量
- Terraform State 文件
- kubeconfig、SSH 私钥和运行时生成的凭据

推荐使用环境变量注入敏感值，例如：

```bash
export TF_VAR_vsphere_password='your-password'
```

## 设计边界

- Terraform 负责 vSphere 虚拟机等基础设施资源。
- Python 只负责读取 `cluster.yaml` 并生成节点定义，不执行 Terraform。
- Cloud-Init 负责操作系统和 Kubernetes 基础组件初始化，不安装全部平台插件。
- kubeadm 负责 Kubernetes 集群引导。
- `k8s-plugins/` 负责集群创建后的网络、存储、观测、GitOps 和安全能力。

## 文档

- `docs/00-引言/`：项目介绍、架构、技术栈和快速开始
- `docs/02-Kubernetes/`：Kubernetes 集群引导实践
- `docs/12-云平台/`：vSphere 及云平台设计
- `docs/13-实战场景/`：vSphere Kubernetes 和国内网络环境实践
- `docs/99-参考/`：配置、版本、排障和命令参考

启动 Docusaurus 知识库：

```bash
cd website
npm install
npm run start
```

