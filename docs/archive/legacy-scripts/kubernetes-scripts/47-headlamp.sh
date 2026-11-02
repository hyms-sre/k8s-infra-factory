#!/bin/bash

# =============================================================================
# 47-headlamp.sh
#
# Headlamp v0.45.0
#
# 功能：
#   1. Worker 节点预加载 Headlamp 镜像
#   2. 部署 Headlamp
#   3. 使用 Kubernetes in-cluster 模式
#   4. 使用 headlamp/headlamp-admin ServiceAccount
#   5. ClusterRoleBinding -> cluster-admin
#   6. MetalLB 固定 LoadBalancer IP
#   7. 自动生成 1 年登录 Token
#
# 访问：
#   http://${HEADLAMP_LB_IP}
#
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/00-env.sh"

load_secrets

state_check headlamp && {
    echo "=== headlamp 已完成, 跳过"
    exit 0
}

HEADLAMP_IMAGE="ghcr.io/headlamp-k8s/headlamp:v0.45.0"
HEADLAMP_NS="headlamp"
HEADLAMP_LB_IP="${HEADLAMP_LB_IP:-172.16.222.211}"

echo
echo "=============================================="
echo " Headlamp v0.45.0"
echo "=============================================="
echo

# =============================================================================
# 1. 预加载镜像
# =============================================================================

echo "[1/5] 预加载 Headlamp 镜像"

for ip in "${WORKER_IPS[@]}"; do
    echo "  -> ${ip}"

    mirror_pull \
        "$ip" \
        "$HEADLAMP_IMAGE" \
        || true
done


# =============================================================================
# 2. Namespace + ServiceAccount + RBAC
# =============================================================================

echo "[2/5] 创建 Namespace / ServiceAccount / RBAC"

ssh_node "$MASTER_IP" "kubectl apply -f -" <<'EOF'

apiVersion: v1
kind: Namespace
metadata:
  name: headlamp

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp

---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: headlamp-admin
  namespace: headlamp

EOF


# =============================================================================
# 3. Deployment
# =============================================================================

echo "[3/5] 部署 Headlamp"

ssh_node "$MASTER_IP" "kubectl apply -f -" <<EOF

apiVersion: apps/v1
kind: Deployment
metadata:
  name: headlamp
  namespace: ${HEADLAMP_NS}
  labels:
    app: headlamp
spec:
  replicas: 1

  selector:
    matchLabels:
      app: headlamp

  template:
    metadata:
      labels:
        app: headlamp

    spec:

      serviceAccountName: headlamp-admin

      automountServiceAccountToken: true

      containers:
      - name: headlamp

        image: ${HEADLAMP_IMAGE}

        imagePullPolicy: IfNotPresent

        args:
        - "-in-cluster"
        - "-plugins-dir=/headlamp/plugins"

        ports:
        - name: http
          containerPort: 4466
          protocol: TCP

        readinessProbe:
          httpGet:
            path: /
            port: 4466
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6

        livenessProbe:
          httpGet:
            path: /
            port: 4466
          initialDelaySeconds: 30
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 6

        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi

---

apiVersion: v1
kind: Service
metadata:
  name: headlamp
  namespace: ${HEADLAMP_NS}
  annotations:
    metallb.io/address-pool: headlamp-pool
    metallb.io/allow-shared-ip: "lab"

spec:
  type: LoadBalancer

  selector:
    app: headlamp

  ports:
  - name: http
    port: 80
    targetPort: 4466
    protocol: TCP

EOF


echo "[3/5] 等待 Headlamp Pod"

ssh_node "$MASTER_IP" \
    "kubectl -n ${HEADLAMP_NS} rollout status deploy/headlamp --timeout=300s"


# =============================================================================
# 4. MetalLB 固定 IP
# =============================================================================

echo "[4/5] 配置 MetalLB 固定 IP: ${HEADLAMP_LB_IP}"

ssh_node "$MASTER_IP" "kubectl -n metallb-system apply -f -" <<EOF

apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: headlamp-pool
  namespace: metallb-system
spec:
  addresses:
  - ${HEADLAMP_LB_IP}/32

---

apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: headlamp-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - headlamp-pool

EOF


ssh_node "$MASTER_IP" \
    "kubectl -n ${HEADLAMP_NS} annotate svc headlamp \
    metallb.io/address-pool=headlamp-pool \
    --overwrite"


echo
echo "等待 LoadBalancer IP..."

for i in $(seq 1 30); do

    LB_IP="$(
        ssh_node "$MASTER_IP" \
        "kubectl -n ${HEADLAMP_NS} get svc headlamp \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" \
        2>/dev/null || true
    )"

    if [[ "$LB_IP" == "$HEADLAMP_LB_IP" ]]; then
        break
    fi

    sleep 2
done


# =============================================================================
# 5. Token
# =============================================================================

echo "[5/5] 创建 Headlamp 登录 Token"

TOKEN="$(
    ssh_node "$MASTER_IP" \
    "kubectl -n ${HEADLAMP_NS} create token headlamp-admin --duration=8760h"
)"

mkdir -p "${PROJECT_ROOT}/files"

printf '%s\n' "$TOKEN" \
    > "${PROJECT_ROOT}/files/headlamp-token.txt"

ssh_node "$MASTER_IP" \
    "mkdir -p /opt/iac/files && \
     printf '%s\n' '$TOKEN' > /opt/iac/files/headlamp-token.txt"


# =============================================================================
# 验证
# =============================================================================

echo
echo "=============================================="
echo " Headlamp 部署完成"
echo "=============================================="

echo
echo "Pod:"
ssh_node "$MASTER_IP" \
    "kubectl -n ${HEADLAMP_NS} get pods -o wide"

echo
echo "Service:"
ssh_node "$MASTER_IP" \
    "kubectl -n ${HEADLAMP_NS} get svc headlamp -o wide"

echo
echo "RBAC:"
ssh_node "$MASTER_IP" \
    "kubectl auth can-i \
    --as=system:serviceaccount:${HEADLAMP_NS}:headlamp-admin \
    '*' '*'"

echo
echo "HTTP:"
curl -I \
    --max-time 10 \
    "http://${HEADLAMP_LB_IP}" \
    || true

echo
echo "=============================================="
echo " URL:"
echo " http://${HEADLAMP_LB_IP}"
echo
echo " Token:"
echo " ${TOKEN:0:20}..."
echo
echo " 完整 Token:"
echo " ${PROJECT_ROOT}/files/headlamp-token.txt"
echo " /opt/iac/files/headlamp-token.txt"
echo "=============================================="

state_done headlamp

echo
echo "=== headlamp done ==="