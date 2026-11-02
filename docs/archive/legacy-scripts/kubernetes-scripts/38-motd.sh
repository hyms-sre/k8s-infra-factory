#!/bin/bash
# =============================================================================
# 38-motd.sh — 分发并安装 GZD Cloud 欢迎信息 (/etc/issue + MOTD)
#
# 内容源: files/motd/gzd-banner.txt  (cloud-init 模板复用同一文件, 避免漂移)
# 执行体: scripts/lib/motd-install.sh (在目标节点上运行, 见其头部注释)
#
# 覆盖范围: 全部 K8s 节点; 如需只更新部分节点, 设置 MOTD_NODES 环境变量:
#   MOTD_NODES="172.16.222.201 172.16.222.202" bash scripts/38-motd.sh
# 幂等: 覆盖写入
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

BANNER_FILE="${PROJECT_ROOT}/files/motd/gzd-banner.txt"
INSTALLER="${PROJECT_ROOT}/scripts/lib/motd-install.sh"
CLUSTER_NAME="${CLUSTER_NAME:-test-cjl-k8s01}"

for f in "$BANNER_FILE" "$INSTALLER"; do
  [ -f "$f" ] || { echo "[FATAL] 缺少文件: $f" >&2; exit 1; }
done

NODES=("${ALL_K8S_IPS[@]}")
if [ -n "${MOTD_NODES:-}" ]; then
  read -r -a NODES <<<"${MOTD_NODES}"
fi

echo "=== 安装 GZD Cloud 欢迎信息 (${#NODES[@]} 个节点, 集群 ${CLUSTER_NAME}) ==="
for ip in "${NODES[@]}"; do
  echo "== $ip"
  scp_node "$BANNER_FILE" "$ip" "/tmp/gzd-banner.txt"
  scp_node "$INSTALLER"   "$ip" "/tmp/motd-install.sh"
  ssh_node "$ip" "sudo bash /tmp/motd-install.sh '${CLUSTER_NAME}' /tmp/gzd-banner.txt"
done

echo "=== 完成。验证方式 ==="
echo "  ssh ${SSH_USER}@${MASTER_IP}            # 登录后应显示 banner"
echo "  ssh ${SSH_USER}@${MASTER_IP} 'cat -A /etc/issue'   # 应看到字面 \\n \\4 \\6 \\t"
