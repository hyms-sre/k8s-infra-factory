#!/bin/bash
# =============================================================================
# motd-install.sh — 在【单个节点】上安装 GZD Cloud 欢迎信息
# 由 scripts/38-motd.sh 分发到各节点后执行; 也可单独在节点上手工运行。
#
# 用法: bash motd-install.sh <集群名> [banner文件路径]
#
# ⚠️ 关键: /etc/issue.d 里的 \n \4 \6 \t 是 agetty 的转义序列, 必须是
#    【字面反斜杠 + 字母】。一旦被提前展开成真实换行/制表符, agetty 就
#    拿不到转义了。因此下面全部使用带引号的 heredoc (<<'EOF'), 禁止变量展开。
#
# 采用 issue.d 机制而非直接覆盖 /etc/issue —— 与 cloud-init 模板 (userdata-v2)
# 的写法保持一致, 且不破坏发行版自带的 /etc/issue。
# =============================================================================
set -euo pipefail

CLUSTER="${1:-gzd-cluster}"
BANNER="${2:-/tmp/gzd-banner.txt}"

if [ ! -f "$BANNER" ]; then
  echo "  [FATAL] banner 文件不存在: $BANNER" >&2
  exit 1
fi

# ---------------------------------------------------------------- /etc/issue.d
# agetty 会把 /etc/issue 与 /etc/issue.d/*.issue 合并后输出。
# 转义: \n=主机名 \4=IPv4 \6=IPv6 \t=时间 \S=系统名 \r=发行版 \l=tty
mkdir -p /etc/issue.d
cp "$BANNER" /etc/issue.d/10-gzd-banner.issue
cat > /etc/issue.d/50-gzd-cloud.issue <<'ISSUEEOF'

  GZD Cloud 定制镜像  ·  Ubuntu 24.04 LTS (noble)  ·  Kubernetes Ready
  --------------------------------------------------------------------------
  Hostname : \n
  IPv4     : \4
  IPv6     : \6
  Time     : \t
ISSUEEOF
chmod 0644 /etc/issue.d/10-gzd-banner.issue /etc/issue.d/50-gzd-cloud.issue

# ----------------------------------------------------------------- /etc/motd
# 此文件不做转义解析, 所以这里用【真实制表符】做缩进 (printf '\t')
NODE_ROLE="worker"
if command -v kubectl >/dev/null 2>&1; then
  if kubectl get node "$(hostname)" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null | grep -q .; then
    NODE_ROLE="control-plane"
  fi
fi
NODE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

{
  cat "$BANNER"
  echo
  echo "  GZD Cloud 定制镜像 · 由 GZD Cloud 提供与维护"
  echo
  printf '\t集群    : %s\n' "$CLUSTER"
  printf '\t主机名  : %s\n' "$(hostname)"
  printf '\tIPv4    : %s\n' "$NODE_IP"
  printf '\t角色    : %s\n' "$NODE_ROLE"
  echo
  printf '\t提示    : 镜像经 Harbor 代理缓存, 直接用原始镜像名拉取即可\n'
  printf '\tHarbor  : https://harbor.yjscloud.local\n'
  printf '\t文档    : /opt/iac/docs\n'
} > /etc/motd
chmod 0644 /etc/motd

# ------------------------------------------------- 动态 motd (Ubuntu 原生机制)
install -m 0644 "$BANNER" /etc/gzd-banner.txt
# 命名 00- 使其排在 Ubuntu 自带 00-header 之前 → banner 成为登录后第一眼
cat > /etc/update-motd.d/00-gzd-cloud <<'MOTDEOF'
#!/bin/sh
[ -f /etc/gzd-banner.txt ] && cat /etc/gzd-banner.txt
echo
echo "  GZD Cloud 定制镜像 · 由 GZD Cloud 提供与维护"
echo
printf '\t主机名  : %s\n' "$(hostname)"
printf '\tIPv4    : %s\n' "$(hostname -I 2>/dev/null | awk '{print $1}')"
printf '\t时间    : %s\n' "$(date '+%F %T %Z')"
echo
MOTDEOF
chmod 0755 /etc/update-motd.d/00-gzd-cloud
# 清理旧命名, 避免重复输出
rm -f /etc/update-motd.d/99-gzd-cloud
# 关闭 motd-news: 登录时会联网抓取 Canonical 新闻, 受限网络下只会徒增延迟
if [ -x /etc/update-motd.d/50-motd-news ]; then
  chmod -x /etc/update-motd.d/50-motd-news
fi

# pam_motd 读 /run/motd.dynamic, 而 /run 重启即清空, 且 pam.d 里带 noupdate
# → 必须自己保证开机重建
cat > /etc/systemd/system/gzd-motd.service <<'UNITEOF'
[Unit]
Description=GZD Cloud MOTD regeneration
After=local-fs.target
Before=sshd.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'run-parts /etc/update-motd.d > /run/motd.dynamic'

[Install]
WantedBy=multi-user.target
UNITEOF

run-parts /etc/update-motd.d > /run/motd.dynamic 2>/dev/null || true
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable gzd-motd.service >/dev/null 2>&1 || true

# ------------------------------------------------------------------- 自检
ISSUE_D=/etc/issue.d/50-gzd-cloud.issue
esc="$(grep -oE '\\[n46t]' "$ISSUE_D" | sort -u | tr '\n' ' ')"
printf '  %-20s %s\n' "issue.d 转义:" "$esc"
printf '  %-20s %s bytes\n' "issue.d/10-banner:" "$(wc -c < /etc/issue.d/10-gzd-banner.issue)"
printf '  %-20s %s bytes\n' "issue.d/50-cloud:" "$(wc -c < "$ISSUE_D")"
printf '  %-20s %s bytes\n' "/etc/issue (发行版):" "$(wc -c < /etc/issue)"
printf '  %-20s %s bytes\n' "/etc/motd:" "$(wc -c < /etc/motd)"
printf '  %-20s %s\n' "动态 motd:" "$([ -s /run/motd.dynamic ] && echo 已生成 || echo 缺失)"
