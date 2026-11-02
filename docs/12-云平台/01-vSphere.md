# vSphere（主线平台）

## 概念

| 组件 | 角色 |
|---|---|
| ESXi | 裸金属 hypervisor，跑 VM |
| vCenter | 集中管理多台 ESXi（本项目经它操作；vsphere_host 定位独立主机，无集群环境） |
| Datacenter / Host / Datastore / Portgroup | Terraform data.tf 定位的四类对象 |
| Template | 克隆源（本项目: Ubuntu 24.04 Cloud Image） |

## Compute（计算）

- VM 规格：cluster.yaml 的 cpu/memory/disk → vm.tf for_each
- 置备参数（eagerlyScrub/thin）继承模板；`allow_unverified_ssl` 兼容自签证书
- 资源余量：规划时给宿主留 20% 余量；开启内存预留视宿主内存而定

## Network（网络）

- 端口组 = 二层广播域；节点固定 IP 经 guestinfo.metadata（network v2）注入，不用 DHCP
- 网段规划：节点段 + MetalLB 池 + 基础设施 IP（OpenWrt/Harbor）互不重叠
- cn 方案：OpenWrt VM 做网关/DNS（examples/openwrt，BIOS 引导 + vmdk 模板）

## Storage（存储）

- Datastore 放 VM 盘；节点附加数据盘（data_disk）→ Longhorn
- 模板制作（一次性）：

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized noble-...img noble.vmdk
# vSphere 上传 vmdk → 建 VM (BIOS, vmxnet3) → 转模板
```

- 模板内 cloud-init ≥ 21.3 是 guestinfo 数据源的前提

## Security（安全）

- 最小权限账号（VM CRUD + 模板克隆 + extra_config）；密码在 terraform.tfvars/env
- vCenter 管理网与业务网段隔离；证书问题可用 allow_unverified_ssl 但建议上 CA
- 凭据纪律见 docs/99-参考/02-凭据说明

## Kubernetes on vSphere（本项目全景）

```
terraform/vsphere (clone + guestinfo) → Cloud-Init (kubeadm-ready) → kubeadm init/join
→ Cilium → MetalLB (L2, 与节点同网段) → Longhorn (数据盘聚合)
```
