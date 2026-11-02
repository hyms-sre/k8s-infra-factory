#!/bin/bash
# =============================================================================
# 45-envoy-gateway.sh — Envoy Gateway v1.5 (Gateway API CRD + Controller)
# 全离线: CRD/install.yaml 均为本地文件; 镜像从 manifest 解析预拉取 (1ms.run 中转)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check envoy-gw && { echo "=== envoy-gateway 已完成, 跳过"; exit 0; }

echo "[1/4] Gateway API CRD (v1.3, 本地文件)"
ssh_node "$MASTER_IP" "kubectl apply -f /opt/iac/files/gateway-api-crds.yaml | tail -2"

echo "[2/4] 预拉取 Envoy Gateway 镜像"
for ip in "${WORKER_IPS[@]}" "$MASTER_IP"; do prepull_manifest "$ip" "/opt/iac/files/envoy-gateway-install.yaml"; done

echo "[3/4] 部署 Envoy Gateway 控制器"
ssh_node "$MASTER_IP" "kubectl apply -f /opt/iac/files/envoy-gateway-install.yaml | tail -2"

echo "[4/4] 示例 Gateway + 等待就绪"
ssh_node "$MASTER_IP" "
  kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=300s || true
  kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: lab-gw
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
    allowedRoutes:
      namespaces:
        from: All
EOF
  kubectl get gatewayclass eg 2>/dev/null || true
  kubectl -n envoy-gateway-system get pods
"
state_done envoy-gw
echo "=== envoy-gateway done"
