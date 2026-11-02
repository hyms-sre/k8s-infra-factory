#!/usr/bin/env bash
# =============================================================================
# make-vmdk.sh — OpenWrt 官方 squashfs-combined img → vSphere vmdk (一次性)
# 用法: bash files/make-vmdk.sh <OpenWrt 版本, 如 24.10.2>
# 依赖: qemu-utils (apt install qemu-utils)
# =============================================================================
set -euo pipefail

VER="${1:?用法: make-vmdk.sh <版本, 如 24.10.2>}"
OUT_DIR="$(pwd)"
IMG="openwrt-${VER}-x86-64-generic-squashfs-combined"

command -v qemu-img >/dev/null || { echo "[ERROR] 缺少 qemu-utils: sudo apt install qemu-utils"; exit 1; }

cd "$OUT_DIR"
echo "[1/4] 下载官方镜像 (阿里云镜像源)"
curl -fLO "https://mirrors.aliyun.com/openwrt/releases/${VER}/targets/x86/64/${IMG}.img.gz"

echo "[2/4] 解压并扩容到 40G (squashfs 首启自动把剩余空间做成 rootfs_data)"
zcat "${IMG}.img.gz" > openwrt.img
truncate -s 40G openwrt.img

echo "[3/4] 转换为 vmdk (streamOptimized)"
qemu-img convert -f raw -O vmdk -o subformat=streamOptimized openwrt.img openwrt.vmdk

echo "[4/4] 完成: $(pwd)/openwrt.vmdk"
echo "下一步: 上传到 vSphere 制作模板 (BIOS 引导), 见 examples/openwrt/README.md 第 1 节"
rm -f openwrt.img "${IMG}.img.gz"
