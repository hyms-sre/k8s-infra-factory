# vm-specs — 按 Kubernetes 版本切换的虚拟机配置预设

> 参考 [suyiiyii/terraform-script](https://github.com/suyiiyii/terraform-script) 的
> `k8s_version_short` / `k8s_version_full` 思路改造：**K8s 版本收敛为一个变量**，
> 其联动组件（apt 源、sandbox 镜像、crictl）由 `locals.tf` 的版本目录自动派生。

## 版本矩阵

| 预设文件 | `k8s_version` | apt 源路径段 | sandbox 镜像 | crictl | 定位 |
|---|---|---|---|---|---|
| `k8s-v1.33.tfvars` | `v1.33` | `.../v1.33/deb/` | `pause:3.10` | `v1.33.0` | 保守线，生态最成熟 |
| `k8s-v1.36.tfvars` | `v1.36` | `.../v1.36/deb/` | `pause:3.10.1` | `v1.33.0` | **★ 当前生产** |
| `k8s-v1.37.tfvars` | `v1.37` | `.../v1.37/deb/` | `pause:3.11` | `v1.34.0` | 最新 GA，需校验生态 |

矩阵真值定义在 `locals.tf` 的 `k8s_catalog`。**新增版本只需在目录里加一行**，
不需要改 `main.tf`、cloud-init 模板或 Shell 脚本。

## 用法

```bash
cd <项目根>

# 初始化
terraform init -input=false

# 用某个版本预设
terraform plan  -var-file=examples/kubernetes/vm-specs/k8s-v1.36.tfvars
terraform apply -auto-approve -var-file=examples/kubernetes/vm-specs/k8s-v1.36.tfvars
```

凭据建议走环境变量，不要写进 tfvars：

```bash
export TF_VAR_vsphere_password='...'
```

## 与旧 `terraform.tfvars` 的关系

`examples/kubernetes/terraform.tfvars` 是重构前的配置，仍可直接使用。
两者对同一批 VM 解析出的规格**完全一致**，因此对已部署的 test-cjl-k8s01 集群零漂移：

- 旧写法：每台 VM 显式写 `cpu` / `memory` / `disk_size`
- 新写法：写 `role`，规格缺省时从 `local.role_defaults` 取

角色默认规格：

| role | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---|---|
| `control-plane` | 4 | 4 GB | 40 GB | 50 GB |
| `worker` | 4 | 8 GB | 40 GB | 50 GB |
| `registry` | 4 | 4 GB | 40 GB | 200 GB |
| `gateway` | 2 | 4 GB | 40 GB | — |

## 切换版本的完整步骤

K8s 版本不只是 apt 源，还牵动镜像与 addons，建议按序执行：

1. 改 `k8s_version`（或换预设文件）
2. `terraform apply` → 重装 kubelet/kubeadm/kubectl 并改写 sandbox 镜像
3. 校验 sandbox 镜像：`kubeadm config images list --kubernetes-version=<full>`
4. 校验 addons 兼容性：Cilium / Gateway API CRD / MetalLB / Longhorn
5. `make resume` 重跑受影响阶段，最后 `make verify`

## ⚠️ 部署前必查

```bash
# sandbox 镜像是否与目标版本匹配（务必在目标节点上跑）
kubeadm config images list --kubernetes-version=1.36.4 | grep pause

# crictl 与 K8s 版本差异不应超过 1 个 minor
crictl --version
```
