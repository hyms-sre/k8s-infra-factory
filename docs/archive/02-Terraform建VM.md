# 02 — Terraform 创建虚拟机

> 执行位置：任意能 SSH 到 vCenter 的机器（本项目在 Windows 侧执行 Terraform，控制机 master-01 负责后续编排）。
> 实际执行时 terraform.exe 位于 `C:\Users\windows10\bin\terraform.exe` (v1.9.8)。

## 1. 初始化（首次）

```bash
terraform init -input=false
```

- provider 用 **`vmware/vsphere`**（注意：老的 `hashicorp/vsphere` 已迁移，继续用老源会安装失败）
- 版本约束在 `versions.tf`：`vmware/vsphere ~> 2.0`，实际安装 2.17.0

## 2. 环境变量定义

- `variables.tf`：`virtual_machines` 列表对象（vm_name/fqdn/cpu/memory/disk_size/ip/gateway/nameservers/addl_disks）
- **关键改造**（相对原教程）：环境是**独立 ESXi 无集群**，因此把教程里的 `data.vsphere_compute_cluster` 换成：

```hcl
data "vsphere_host" "this" {
  name          = "172.16.222.243"
  datacenter_id = data.vsphere_datacenter.this.id
}
# main.tf 中
resource_pool_id = data.vsphere_host.this.resource_pool_id
```

## 3. VM 定义（examples/kubernetes/terraform.tfvars）

```hcl
vsphere_server     = "172.16.222.240"
vsphere_datacenter = "CJL"
vsphere_host       = "172.16.222.243"
vsphere_datastore  = "date01"
vsphere_network    = "VM Network"
vm_template_name   = "ubuntu-noble-24.04-cloudimg-20260826"
```

每台 VM 的命名（tfvars 中 `vm_name` 与 `fqdn`）：

| vm_name (vSphere 显示名) | fqdn (Linux 主机名) |
|---|---|
| k8s01-master01[222.201]-20260907 | test-cjl-k8s01-master-01 |
| k8s01-worker01[222.202]-20260907 | test-cjl-k8s01-worker-01 |
| k8s01-worker02[222.203]-20260907 | test-cjl-k8s01-worker-02 |
| k8s01-worker03[222.204]-20260907 | test-cjl-k8s01-worker-03 |
| k8s01-harbor01[222.207]-20260907 | test-cjl-harbor-registry-01 |

OpenWrt VM 不走 Terraform（见 03-OpenWrt.md）。

## 4. Cloud-init 注入（guestinfo）

`main.tf` 的 `extra_config` 注入两份模板（base64）：

- `examples/metadata.tftpl` — 静态网络（netplan, ens192）：

```yaml
network:
  version: 2
  ethernets:
    ens192:
      addresses: [ ${ip} ]          # 如 172.16.222.201/24
      gateway4: ${gateway}          # 172.16.222.254
      nameservers:
        addresses: [172.16.222.210, 223.5.5.5, 119.29.29.29]  # DNS 首选 OpenWrt
```

- `examples/kubernetes/userdata.tftpl` — 创建 `appuser`（sudo 免密、注入 SSH 公钥）、hostname、时区 Asia/Shanghai、`/dev/sdb` 格式化挂载到 `/var/lib/longhorn`、`ssh_pwauth: no`（仅密钥登录）

## 5. 执行命令与预期输出

```bash
terraform plan  -var-file=examples/kubernetes/terraform.tfvars   # Plan: 5 to add
terraform apply -auto-approve -var-file=examples/kubernetes/terraform.tfvars
# 预期输出 (实际执行 2026-09-07 03:2x, 每台约 2m45s):
#   vsphere_virtual_machine.vm[0]: Creation complete after 2m45s [id=4236ec11-...]
#   Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

## 6. 验证

```bash
ping 172.16.222.201                     # 等 cloud-init 首次配置 (3-5 分钟)
ssh appuser@172.16.222.201 hostname     # → test-cjl-k8s01-master-01
ssh appuser@172.16.222.201 cloud-init status   # → status: done
ssh appuser@172.16.222.202 lsblk        # sda 40G + sdb 50G
```

## 7. 销毁

```bash
make destroy    # = terraform destroy -auto-approve -var-file=... (OpenWrt VM 需另外用 govc 删)
```

## 8. 本环境踩过的坑（复现时注意）

| 坑 | 处理 |
|---|---|
| govc 对 VM 名里 `[ ]` 解析为 datastore 路径 | 全路径用 `\[` `\]` 转义，如 `/CJL/vm/k8s01-openwrt01\[222.210\]-20260907` |
| registry.k8s.io/docker.io 被墙 | 见 docs/01 镜像源结论；kubeadm 用 `--image-repository=registry.aliyuncs.com/google_containers`，containerd 的 `sandbox_image` 必须改到阿里云（Ubuntu 24.04 新配置字段是 `sandbox = '...'` 不是 `sandbox_image`） |
| ssh -n | 脚本里嵌套 ssh 必须加 `-n`，否则内层 ssh 吃掉 `bash -s` 的 stdin 导致脚本静默截断 |
