#!/bin/bash
# =============================================================================
# 22-openwrt-dns.sh — OpenWrt dnsmasq 静态解析管理 (在部署控制机 master-01 上执行)
#
# 用法:
#   bash scripts/22-openwrt-dns.sh list                     # 列出静态解析与上游
#   bash scripts/22-openwrt-dns.sh add <域名> <IP>          # 幂等添加 (单个主机名或整个域)
#   bash scripts/22-openwrt-dns.sh del <域名>               # 删除该域名的所有条目
#   bash scripts/22-openwrt-dns.sh dedupe                   # 清理重复条目 (历史遗留)
#   bash scripts/22-openwrt-dns.sh sync                     # 去重 + 确保项目必需记录
#   bash scripts/22-openwrt-dns.sh test <域名> [DNS服务器]  # 从 OpenWrt 与集群两侧验证解析
#   bash scripts/22-openwrt-dns.sh upstream                 # 查看上游 DNS
#
# ⚠️ 为什么需要这个脚本:
#   `uci add_list` 是【追加】语义, 不是幂等写入。直接用 add_list 配 DNS,
#   每次重跑脚本都会多出一条重复记录 (本项目实测曾累积到 3 份相同条目)。
#   本脚本的 add/del 都会先重建列表, 因此重复执行结果一致。
#
# 详细教程: docs/11-OpenWrt-DNS使用教程.md
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

OPENWRT_ROOT_PWD="${VAULT_OPENWRT_ROOT_PASSWORD}"
ZONE="${LOCAL_ZONE:-yjscloud.local}"     # 本地域
HARBOR_IP_ADDR="${HARBOR_IP}"            # 172.16.222.207

command -v sshpass >/dev/null 2>&1 || {
  echo "安装 sshpass..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sshpass >/dev/null
}

ow() {
  sshpass -p "${OPENWRT_ROOT_PWD}" ssh -n \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@${OPENWRT_IP}" "$@"
}

# 远程通用函数: 以 uci 操作 dhcp.@dnsmasq[0].address
read -r -d '' REMOTE_LIB <<'REMOTE' || true
addr_list() { uci get dhcp.@dnsmasq[0].address 2>/dev/null || true; }
# 重建 address 列表: 丢弃域名等于 $1 的条目 ( $1 为空则全部保留 )
addr_rebuild() {
  drop="$1"; keep=""
  for e in $(addr_list); do
    case "$e" in
      "/${drop}/"*) ;;
      *) keep="$keep $e" ;;
    esac
  done
  uci delete dhcp.@dnsmasq[0].address 2>/dev/null || true
  for e in $keep; do uci add_list dhcp.@dnsmasq[0].address="$e"; done
}
addr_dedupe() {
  seen=""; keep=""
  for e in $(addr_list); do
    case " $seen " in
      *" $e "*) ;;
      *) seen="$seen $e"; keep="$keep $e" ;;
    esac
  done
  uci delete dhcp.@dnsmasq[0].address 2>/dev/null || true
  for e in $keep; do uci add_list dhcp.@dnsmasq[0].address="$e"; done
}
addr_count() { addr_list | tr ' ' '\n' | grep -vc '^$'; }
REMOTE

cmd="${1:-list}"

case "$cmd" in
  list)
    echo "=== OpenWrt (${OPENWRT_IP}) DNS 静态解析 ==="
    ow "${REMOTE_LIB}
      n=0
      for e in \$(addr_list); do n=\$((n+1)); printf '  %2d. %s\n' \"\$n\" \"\$e\"; done
      [ \"\$n\" = 0 ] && echo '  (无静态解析条目)'
      echo \"  条目总数: \$(addr_count)\"
      echo
      echo '=== 上游 DNS ==='
      for s in \$(uci get dhcp.@dnsmasq[0].server 2>/dev/null); do echo \"  \$s\"; done
      echo
      echo '=== dnsmasq 状态 ==='
      echo \"  dnsmasq-full: \$(opkg list-installed 2>/dev/null | awk '/^dnsmasq-full/{print \$3}')\"
      echo \"  监听: \$(netstat -lnup 2>/dev/null | awk '/:53 /{print \$4}' | tr '\n' ' ')\"
    "
    ;;

  add)
    domain="${2:?用法: $0 add <域名> <IP>}"
    ip="${3:?用法: $0 add <域名> <IP>}"
    echo "=== 添加: ${domain} -> ${ip} ==="
    ow "${REMOTE_LIB}
      addr_rebuild '${domain}'
      uci add_list dhcp.@dnsmasq[0].address='/${domain}/${ip}'
      uci commit dhcp
      /etc/init.d/dnsmasq restart >/dev/null 2>&1
      sleep 2
      echo -n '  当前条目数: '; addr_count
      echo -n '  本次记录出现次数 (应为 1): '
      addr_list | tr ' ' '\n' | grep -c '^/${domain}/${ip}\$'
    "
    echo "  验证:"
    ow "nslookup ${domain} 127.0.0.1 2>/dev/null | awk '/^Address: /{print \"    \"\$2}' | tail -1"
    ;;

  del)
    domain="${2:?用法: $0 del <域名>}"
    echo "=== 删除域名 ${domain} 的所有静态条目 ==="
    ow "${REMOTE_LIB}
      before=\$(addr_count)
      addr_rebuild '${domain}'
      uci commit dhcp
      /etc/init.d/dnsmasq restart >/dev/null 2>&1
      sleep 2
      echo \"  条目数: \${before} -> \$(addr_count)\"
    "
    ;;

  dedupe)
    echo "=== 清理重复条目 ==="
    ow "${REMOTE_LIB}
      before=\$(addr_count)
      addr_dedupe
      uci commit dhcp
      /etc/init.d/dnsmasq restart >/dev/null 2>&1
      sleep 2
      echo \"  条目数: \${before} -> \$(addr_count)\"
    "
    ;;

  sync)
    echo "=== 同步项目必需记录并去重 ==="
    ow "${REMOTE_LIB}
      before=\$(addr_count)
      # 先整体去重
      addr_dedupe
      # 确保必需记录存在 (幂等)
      for want in '/${ZONE}/${HARBOR_IP_ADDR}' '/${REGISTRY_URL}/${HARBOR_IP_ADDR}'; do
        have=0
        for e in \$(addr_list); do [ \"\$e\" = \"\$want\" ] && have=1; done
        [ \"\$have\" = 0 ] && uci add_list dhcp.@dnsmasq[0].address=\"\$want\"
      done
      uci commit dhcp
      /etc/init.d/dnsmasq restart >/dev/null 2>&1
      sleep 2
      echo \"  条目数: \${before} -> \$(addr_count)\"
      for e in \$(addr_list); do echo \"    \$e\"; done
    "
    ;;

  test)
    domain="${2:?用法: $0 test <域名> [DNS服务器]}"
    server="${3:-127.0.0.1}"
    echo "=== 解析验证: ${domain} (DNS=${server}) ==="
    echo "--- 从 OpenWrt 自身查询 ---"
    ow "nslookup ${domain} ${server} 2>&1 | grep -A1 '^Name:' | sed 's/^/  /'"
    echo "  (注: busybox nslookup 会同时查 A 与 AAAA; 无 IPv6 记录时会额外打印一行"
    echo "       NXDOMAIN, 属正常现象 —— 只看上面的 Name/Address 即可)"
    echo "--- 从集群 master-01 查询 (经 ${OPENWRT_IP}) ---"
    nslookup "${domain}" "${OPENWRT_IP}" 2>&1 | grep -A1 '^Name:' | sed 's/^/  /' || true
    echo "--- 从全部 K8s 节点查询 ---"
    for ip in "${ALL_K8S_IPS[@]}"; do
      printf '  %-16s -> ' "$ip"
      ssh_node "$ip" "nslookup ${domain} ${OPENWRT_IP} 2>/dev/null | awk '/^Address: /{print \$2}' | tail -1" || echo "(查询失败)"
    done
    ;;

  upstream)
    echo "=== 上游 DNS ==="
    ow "
      for s in \$(uci get dhcp.@dnsmasq[0].server 2>/dev/null); do echo \"  \$s\"; done
      echo
      echo '  说明: 若值为 127.0.0.1#7874 则表示已被 OpenClash 接管 (fake-ip 模式),'
      echo '        此时 uci 里设置的公共 DNS 不会生效, 需在 OpenClash 内调整。'
    "
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
