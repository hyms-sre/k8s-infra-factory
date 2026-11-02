#!/bin/bash
# =============================================================================
# 44-metallb.sh — MetalLB v0.14 (L2 模式), 池 172.16.222.211-220 (10 个 LB IP)
# 全离线: manifest 用本地 /opt/iac/files/metallb-native.yaml
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check metallb && { echo "=== metallb 已完成, 跳过"; exit 0; }

echo "[1/3] 预拉取 MetalLB 镜像 (从 manifest 解析)"
for ip in "${ALL_K8S_IPS[@]}"; do prepull_manifest "$ip" "/opt/iac/files/metallb-native.yaml"; done

echo "[2/3] 部署 MetalLB (本地 manifest)"
ssh_node "$MASTER_IP" "kubectl apply -f /opt/iac/files/metallb-native.yaml && kubectl -n metallb-system rollout status deploy/controller --timeout=300s || true"

echo "[3/3] IPAddressPool + L2Advertisement"
ssh_node "$MASTER_IP" "kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_POOL}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
EOF
kubectl -n metallb-system get pods"
state_done metallb
echo "=== metallb done"
