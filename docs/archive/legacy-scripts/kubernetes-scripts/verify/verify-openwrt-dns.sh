#!/bin/bash
# verify-openwrt-dns.sh — 检查 OpenWrt DNS 静态条目是否健康 (在 master-01 执行)
#
# 背景: `uci add_list` 是追加语义, 非幂等。脚本重复执行会累积重复条目
#       (本项目实测曾累积到 3 份), 故加此回归检查。
# 详见 docs/11-OpenWrt-DNS使用教程.md §6.1
set -u
source /opt/iac/secrets/secrets.env
OW="172.16.222.210"

ow() {
  sshpass -p "${VAULT_OPENWRT_ROOT_PASSWORD}" ssh -n \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${OW}" "$1" 2>/dev/null
}

# 1) 无重复条目
dup=$(ow 'uci get dhcp.@dnsmasq[0].address 2>/dev/null | tr " " "\n" | sort | uniq -d | grep -c .')
[ "${dup:-1}" = "0" ] || exit 1

# 2) 必备记录存在 (Harbor 本地域)
addr=$(ow 'uci get dhcp.@dnsmasq[0].address 2>/dev/null')
echo "$addr" | grep -q '/yjscloud.local/' || exit 1

# 3) 实际能解析
ow 'nslookup harbor.yjscloud.local 127.0.0.1 2>/dev/null' | grep -q '172.16.222.207' || exit 1

exit 0
