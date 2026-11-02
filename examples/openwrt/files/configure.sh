#!/usr/bin/env bash
# =============================================================================
# configure.sh — OpenWrt 首启配置 (LAN IP / 关 DHCP / DNS / 转发)
# 用法: bash files/configure.sh <目标 LAN IP, 如 172.16.222.210>
# 前置: 控制机已能 SSH 到 OpenWrt (出厂 192.168.1.1, root 无密码)
# =============================================================================
set -euo pipefail

IP="${1:?用法: configure.sh <LAN IP>}"
GATEWAY="${GATEWAY:-172.16.222.254}"
DNS="${DNS:-223.5.5.5}"
TARGET="${OPENWRT_ADDR:-root@192.168.1.1}"

echo "[INFO] 目标: ${TARGET} → LAN ${IP} (网关 ${GATEWAY}, DNS ${DNS})"
ssh -o StrictHostKeyChecking=no "${TARGET}" "
  uci set network.lan.proto='static'
  uci set network.lan.ipaddr='${IP}'
  uci set network.lan.netmask='255.255.255.0'
  uci set network.lan.gateway='${GATEWAY}'
  uci del_list network.lan.dns='${DNS}' 2>/dev/null || true
  uci add_list network.lan.dns='${DNS}'
  uci set dhcp.lan.ignore='1'
  uci commit network
  uci commit dhcp
  /etc/init.d/network restart
"
echo "[OK] 网络已切换, 请改用 ssh root@${IP} 继续"
echo "后续: opkg 换源 / dnsmasq-full / 本地域 DNS / OpenClash — 见 examples/openwrt/README.md 第 4 节"
