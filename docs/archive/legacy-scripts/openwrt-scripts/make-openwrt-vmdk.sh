#!/bin/bash
# =============================================================================
# make-openwrt-vmdk.sh — 制作 OpenWrt 40G 磁盘镜像 (在任一 Ubuntu VM 上执行)
# 详见 docs/03-OpenWrt.md 第 1 节。产物 /tmp/openwrt.vmdk 需拷回部署机 files/。
# =============================================================================
set -e
echo "[1/4] 安装 qemu-utils"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-utils >/dev/null
cd /tmp
echo "[2/4] 下载 OpenWrt 24.10.2 squashfs-combined (aliyun)"
rm -f openwrt.img.gz
curl -fsSL --retry 3 -o openwrt.img.gz https://mirrors.aliyun.com/openwrt/releases/24.10.2/targets/x86/64/openwrt-24.10.2-x86-64-generic-squashfs-combined.img.gz
ls -lh openwrt.img.gz
echo "[3/4] 解压 + 扩容到 40G"
zcat openwrt.img.gz > openwrt.img 2>/dev/null || true
truncate -s 40G openwrt.img
echo "[4/4] 转 streamOptimized vmdk"
qemu-img convert -f raw -O vmdk -o subformat=streamOptimized openwrt.img openwrt.vmdk
rm -f openwrt.img openwrt.img.gz
chmod 644 /tmp/openwrt.vmdk
echo "DONE"
ls -lh /tmp/openwrt.vmdk
