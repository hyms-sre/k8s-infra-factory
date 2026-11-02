# terraform/vsphere — vSphere Kubernetes IaC 主入口

> **这里就是 vSphere Kubernetes IaC**：Python 生成节点参数 → Terraform 批量创建 VM →
> Cloud-Init 把 Ubuntu 初始化到 **kubeadm-ready**。

```bash
cd terraform/vsphere
python generate.py      # cluster.yaml → vm.tf (K8s 节点定义)
terraform init
terraform plan
terraform apply
```

## 1. 这是干什么的

把「集群要几台什么规格的 VM」声明在 `cluster.yaml`，由 `generate.py` 生成
`vm.tf`（一个 `for_each` 资源管理全部 master/worker），Terraform 负责在 vSphere
上克隆模板、注入 Cloud-Init、管理 VM 生命周期。

## 2. 需要什么

- 本机：Python ≥ 3.9（PyYAML）、Terraform ≥ 1.5、SSH 密钥对（`~/.ssh/id_ed25519`）
- vSphere：数据中心 / ESXi 主机 / 数据存储 / 端口组 / **Ubuntu 24.04 Cloud Image 模板**
  （需内置 cloud-init ≥ 21.3，制作方法见 `docs/12-云平台/01-vSphere.md`）

## 3. 如何配置

| 文件 | 内容 | 是否入 Git |
|---|---|---|
| `cluster.yaml` | 集群名、master/worker 数量与规格、网段/IP/DNS、K8s 版本、用户/SSH、Harbor | 是（无敏感值） |
| `terraform.tfvars` | vCenter 地址与账号、模板名 | **否**（从 `examples/k8s/terraform.tfvars.example` 复制后填写） |

```bash
cp examples/k8s/terraform.tfvars.example terraform.tfvars
# 或用环境变量: export TF_VAR_vsphere_password='...'
```

cn（中国网络环境）配置变体见 `live/lab/vsphere/cn/cluster/`。

## 4. Python 怎么生成

```bash
python generate.py                # 读 ./cluster.yaml
python generate.py --config other.yaml
```

generate.py 的全部逻辑：读配置 → 按数量/规格生成节点（自动分配 IP、按命名规范
生成主机名与 vSphere 显示名、解析 K8s 版本联动值）→ 重写 `vm.tf` → 打印摘要。
它是纯参数生成器，不执行 terraform、不做部署。

## 5. 生成了什么

只生成/更新 **`vm.tf`**（禁止手工编辑，也禁止生成 master01.tf/worker01.tf 之类的
per-node 文件）：

```hcl
locals {
  cluster = { name = "...", user = "...", k8s_version = "...", harbor = ... }
  nodes   = { "lab-hq-k8s01-master-01" = { vm_name, role, ip, gateway, cpu, ... } }
}

resource "vsphere_virtual_machine" "k8s_node" {
  for_each = local.nodes    # ← 一个资源管理所有节点
  ...
}
```

## 6. Terraform 怎么执行

```bash
terraform init      # 下载 vmware/vsphere provider (版本锁定见 .terraform.lock.hcl)
terraform plan      # 预览: +N 台 VM
terraform apply     # 创建
terraform destroy   # 销毁全部节点 VM
```

vSphere 连接参数在 `variables.tf` 声明、`terraform.tfvars` / `TF_VAR_*` 注入。

## 7. VM 会生成什么

每台 VM：按节点规格的 CPU/内存/系统盘（+可选数据盘）→ 从模板克隆 →
`guestinfo.metadata` 注入**静态 IP/网关/DNS**（IP 来自 cluster.yaml，非 DHCP）。

## 8. Cloud-Init 做什么

`user-data.yaml.tpl`（经 `guestinfo.userdata` 注入）首启自动完成：
hostname / timezone / NTP / 用户 / SSH 公钥 / apt 源 / 基础包 / swap / 内核模块 /
sysctl / **containerd** / crictl / **kubelet / kubeadm / kubectl**（apt-mark hold）/
helm / nerdctl / bash 补全 / Harbor 镜像映射（启用时）/ 数据盘挂载。

终点是 **kubeadm-ready**——不做 kubeadm init/join，不装任何平台组件。
排障：节点上 `cloud-init status --long`、`/var/log/cloud-init-output.log`。

## 9. Kubernetes 下一步

1. 集群引导（kubeadm init / join / kubeconfig / CNI）：
   `docs/02-Kubernetes/07-kubeadm实践.md` 与 `docs/13-实战场景/01-vSphere-Kubernetes.md`
2. 平台扩展（MetalLB / 存储 / 观测 / GitOps）：`k8s-plugins/`
3. 环境组织与 cn 方案：`live/` 与 `docs/13-实战场景/02-CN网络环境.md`

## 文件一览

| 文件 | 职责 | 生成者 |
|---|---|---|
| `cluster.yaml` | 集群定义（用户编辑） | 用户 |
| `generate.py` | Kubernetes Node Generator | 人维护 |
| `vm.tf` | 节点数据 + for_each 资源 | **generate.py** |
| `provider.tf` / `versions.tf` | Provider 与版本约束 | 人维护 |
| `variables.tf` / `data.tf` | 输入变量 / 环境数据源 | 人维护 |
| `locals.tf` / `main.tf` | 公共参数 / cloud-init 公共变量装配 | 人维护 |
| `outputs.tf` | 节点摘要输出 | 人维护 |
| `user-data.yaml.tpl` / `meta-data.yaml.tpl` | Cloud-Init | 人维护 |
| `terraform.tfvars` | vCenter 凭据（gitignore） | 用户 |
| `terraform.tfstate*` | Terraform 状态（gitignore，勿删） | terraform |
