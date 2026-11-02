#!/bin/bash
# =============================================================================
# 21-openwrt-config.sh — 配置 OpenWrt (在部署控制机 master-01 上执行)
# 流程: master-01 加临时二级 IP 192.168.1.254 → ssh 出厂 OpenWrt(192.168.1.1, 无密码)
#       → 设静态 .210/网关 .254/DNS → root 密码 → 关 LAN DHCP → opkg 阿里云源
#       → dnsmasq 本地域(harbor.yjscloud.local) → OpenClash (ipk+订阅)
# 幂等: .210 可达则跳过网络初始化, 只补软件配置。
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

OPENWRT_ROOT_PWD="${VAULT_OPENWRT_ROOT_PASSWORD}"
OPENWRT_VER="24.10.2"
OPKG_MIRROR="https://mirrors.aliyun.com/openwrt/releases/${OPENWRT_VER}"
GW="172.16.222.254"

command -v sshpass >/dev/null || { echo "[0/6] 安装 sshpass"; sudo apt-get install -y -qq sshpass >/dev/null; }
command -v govc >/dev/null || sudo cp ~/bin/govc /usr/local/bin/ 2>/dev/null || true

ow_boot() { sshpass -p "" ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 "$@"; }
ow()      { sshpass -p "${OPENWRT_ROOT_PWD}" ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"${OPENWRT_IP}" "$@"; }

if ! ping -c1 -W1 "${OPENWRT_IP}" >/dev/null 2>&1; then
  echo "[1/6] master-01 加临时二级 IP 192.168.1.254 访问出厂 OpenWrt"
  DEV=$(ip -o -4 route show default | awk '{print $5}' | head -1)
  sudo ip addr add 192.168.1.254/24 dev "$DEV" 2>/dev/null || true
  sleep 5   # 等 OpenWrt 启动完成
  ping -c1 -W2 192.168.1.1 >/dev/null || { echo "等待 OpenWrt 首次启动..."; sleep 30; }

  echo "[2/6] 设置静态 ${OPENWRT_IP}/24, 网关 ${GW}, 关 LAN DHCP (避免污染生产网段)"
  ow_boot "
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='${OPENWRT_IP}'
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway='${GW}'
    uci -q delete network.lan.dns
    uci add_list network.lan.dns='223.5.5.5'
    uci add_list network.lan.dns='119.29.29.29'
    uci set network.lan.dhcp='0' 2>/dev/null || true
    uci -q delete dhcp.lan.ignore
    uci set dhcp.lan.ignore='1'
    uci commit network; uci commit dhcp
    echo 'root:${OPENWRT_ROOT_PWD}' | chpasswd
    /etc/init.d/network restart >/dev/null 2>&1 &
  "
  sudo ip addr del 192.168.1.254/24 dev "$DEV" 2>/dev/null || true
  echo "等待网络切换生效..."; sleep 20
fi

ping -c1 -W2 "${OPENWRT_IP}" >/dev/null || mar "无法访问 ${OPENWRT_IP} — 请通过 vSphere 控制台检查 OpenWrt 网络配置后 make resume"

echo "[3/6] opkg 换阿里云源 (${OPENWRT_VER})"
ow "
  sed -i.bak 's|https://downloads.openwrt.org/releases/${OPENWRT_VER}|${OPKG_MIRROR}|g; s|http://downloads.openwrt.org/releases/${OPENWRT_VER}|${OPKG_MIRROR}|g' /etc/opkg/distfeeds.conf
  opkg update >/dev/null && echo 'opkg update OK'
"

echo "[4/6] 基础包: bash/curl/kmod-tun 等 (OpenClash 依赖)"
ow "opkg install ca-bash curl unzip ipset ip-full kmod-tun kmod-inet-diag luci-compat >/dev/null 2>&1; echo deps-done"

echo "[5/6] dnsmasq: 本地域 yjscloud.local (harbor→.207)"
# ⚠️ uci add_list 是【追加】语义, 不是幂等写入。脚本被 make resume 重复执行时
#    会不断累积重复条目 (本项目实测曾累积到 3 份相同记录)。
#    因此这里先 del_list 再 add_list, 保证重复执行结果一致。
# 详细用法与常见场景见 docs/11-OpenWrt-DNS使用教程.md
ow "
  add_addr() {  # \$1 = /域名/IP
    uci del_list dhcp.@dnsmasq[0].address=\"\$1\" 2>/dev/null || true
    uci add_list dhcp.@dnsmasq[0].address=\"\$1\"
  }
  add_addr '/harbor.yjscloud.local/172.16.222.207'
  add_addr '/yjscloud.local/172.16.222.207'
  uci commit dhcp; /etc/init.d/dnsmasq restart
  echo -n '  address 条目数: '
  uci get dhcp.@dnsmasq[0].address | tr ' ' '\n' | grep -vc '^\$'
  nslookup harbor.yjscloud.local 127.0.0.1 | tail -3
"
# 说明: 上游 DNS (dhcp.@dnsmasq[0].server) 不再在此写死 ——
#   OpenClash 启动后会把它接管为 127.0.0.1#7874 (fake-ip 模式),
#   此处设置会被覆盖。需要自定义上游请改 OpenClash 配置或在其停用后设置。

echo "[6/6] 安装 OpenClash"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${PROJECT_ROOT}/files/luci-app-openclash.ipk" "root@${OPENWRT_IP}:/tmp/" 2>/dev/null || \
  sshpass -p "${OPENWRT_ROOT_PWD}" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${PROJECT_ROOT}/files/luci-app-openclash.ipk" "root@${OPENWRT_IP}:/tmp/"
ow "opkg install /tmp/luci-app-openclash.ipk >/dev/null && echo 'openclash installed'"
if [ -n "${VAULT_OPENCLASH_SUBSCRIPTION:-}" ]; then
  ow "uci set openclash.config.subscribe_url='${VAULT_OPENCLASH_SUBSCRIPTION}' 2>/dev/null; uci commit openclash 2>/dev/null || true"
else
  cat >> "${STATE_DIR}/BLOCKED.log" 2>/dev/null <<EOF || true
[OpenWrt] OpenClash 订阅 URL 未配置 — 登录 http://${OPENWRT_IP}/cgi-bin/luci/admin/services/openclash 填写订阅/节点后启动
EOF
  echo "  [NOTE] 订阅为空: 请在 LuCI OpenClash 页面手工填订阅/节点 (已记入 BLOCKED 提示)"
fi

echo "=== OpenWrt 配置完成: LuCI http://${OPENWRT_IP} (root / VAULT_OPENWRT_ROOT_PASSWORD)"
