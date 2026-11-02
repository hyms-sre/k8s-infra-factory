#!/bin/bash
# =============================================================================
# 20-openwrt-create.sh — 创建 OpenWrt VM (k8s01-openwrt01[222.210]-20260907)
# 不经 terraform: OpenWrt 无 cloud-init 模板, 使用官方 squashfs-combined 制作的 vmdk。
# 磁盘制作 (任一 Ubuntu VM, 见 docs/03-OpenWrt.md):
#   curl -O https://mirrors.aliyun.com/openwrt/releases/24.10.2/targets/x86/64/\
#        openwrt-24.10.2-x86-64-generic-squashfs-combined.img.gz
#   zcat *.img.gz > openwrt.img && truncate -s 40G openwrt.img
#   qemu-img convert -f raw -O vmdk -o subformat=streamOptimized openwrt.img openwrt.vmdk
# 幂等: VM 已存在则跳过。
# 注意: govc 对名字/路径中的 [] 需要 \[ \] 转义。
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

VM="k8s01-openwrt01[222.210]-20260907"
VM_ESC='/CJL/vm/k8s01-openwrt01\[222.210\]-20260907'
DC="CJL"; HOST="172.16.222.243"; DS="date01"; NET="VM Network"
VMDK_LOCAL="${VMDK_LOCAL:-files/openwrt.vmdk}"
DS_DIR="openwrt-img-222210"          # import.vmdk 目标目录 (顶层, 自动创建)

export GOVC_URL="172.16.222.240"
export GOVC_USERNAME="${VAULT_VCENTER_USER}"
export GOVC_PASSWORD="${VAULT_VCENTER_PASSWORD}"
export GOVC_INSECURE=true
export GOVC_DATACENTER="${DC}"
export GOVC_HOST="/${DC}/host/${HOST}"
export GOVC_RESOURCE_POOL="/${DC}/host/${HOST}/Resources"
GOVC="${GOVC_BIN:-govc}"

if "$GOVC" find "/${DC}/vm" -type m -name "${VM}" 2>/dev/null | grep -q .; then
  echo "=== OpenWrt VM 已存在, 跳过创建"
  exit 0
fi

[ -f "$VMDK_LOCAL" ] || { echo "[FATAL] 缺少 $VMDK_LOCAL, 见脚本头注释制作"; exit 1; }

echo "[1/3] 导入磁盘 (import.vmdk 自动展开 streamOptimized)"
"$GOVC" import.vmdk -ds "${DS}" "${VMDK_LOCAL}" "${DS_DIR}"

echo "[2/3] 创建 VM (2C/4G, 40G 磁盘, vmxnet3, BIOS)"
"$GOVC" vm.create \
  -dc="${DC}" -host.ipath="/${DC}/host/${HOST}/${HOST}" \
  -pool="/${DC}/host/${HOST}/Resources" \
  -ds="${DS}" -net.adapter=vmxnet3 -net="${NET}" \
  -m=4096 -c=2 -g=other26xLinux64Guest -firmware=bios -on=false \
  -disk="${DS_DIR}/openwrt.vmdk" \
  "${VM}"

echo "[3/3] 开机"
"$GOVC" vm.power -on "${VM_ESC}"
echo "=== OpenWrt VM 已创建开机 (出厂 IP 192.168.1.1, 由 21-openwrt-config.sh 配置为 .210)"
