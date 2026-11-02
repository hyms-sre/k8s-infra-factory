#!/bin/bash
# =============================================================================
# 46-longhorn.sh — Longhorn v1.9 (CSI + 默认 StorageClass)
# 全离线: 本地 longhorn.yaml; 镜像从 manifest 解析经 1ms.run 中转预拉取
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check longhorn && { echo "=== longhorn 已完成, 跳过"; exit 0; }

echo "[1/3] 预拉取 Longhorn 全部镜像 (manifest 解析, ${LONGHORN_VER})"
for ip in "${ALL_K8S_IPS[@]}"; do prepull_manifest "$ip" "/opt/iac/files/longhorn.yaml"; done

echo "[2/3] 部署 Longhorn (本地 manifest)"
ssh_node "$MASTER_IP" "
  kubectl apply -f /opt/iac/files/longhorn.yaml >/dev/null
  echo '等待 longhorn-manager...'
  kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=900s || true
  kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=900s || true
"

echo "[3/3] 设为默认 StorageClass"
ssh_node "$MASTER_IP" "
  kubectl patch storageclass longhorn -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}' || true
  kubectl get sc
"
state_done longhorn
echo "=== longhorn done"
