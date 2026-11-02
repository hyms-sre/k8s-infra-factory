#!/bin/bash
# =============================================================================
# 43-cilium.sh — 安装 Cilium CNI v1.17 (仅网络; Hubble 开启)
# 镜像: 各节点经 quay.m.daocloud.io 全引用拉取 + tag 回 quay.io 原名 (离线安装)
# CLI: master-01 使用 /opt/iac/files/cilium-cli.tar.gz
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check cilium && { echo "=== cilium 已完成, 跳过"; exit 0; }
state_check cluster-init || state_done cluster-init   # 42 中断过则补标记

CILIUM_IMAGES=(
  "quay.io/cilium/cilium:v1.17.0"
  "quay.io/cilium/cilium-envoy:v1.31.5-1737535524-fe8efeb16a7d233bffd05af9ea53599340d3f18e"
  "quay.io/cilium/operator-generic:v1.17.0"
)

echo "[1/3] 预拉取 Cilium 镜像到全部节点 (${#CILIUM_IMAGES[@]} 个 × ${#ALL_K8S_IPS[@]} 节点)"
for ip in "${ALL_K8S_IPS[@]}"; do
  for img in "${CILIUM_IMAGES[@]}"; do
    echo "  ${ip} ← ${img%%:*}..."
    if ! mirror_pull "$ip" "$img"; then
      echo "  (WARN: ${img} 经 daocloud 失败, 尝试 Harbor/直连交给 kubelet 重试)"
    fi
  done
done

echo "[2/3] master-01: 安装 cilium CLI (本地包)"
ssh_node "$MASTER_IP" "
  if ! command -v cilium >/dev/null 2>&1; then
    sudo tar -C /usr/local/bin -xzf /opt/iac/files/cilium-cli.tar.gz cilium
  fi
  cilium version --client | head -1
"

echo "[3/3] 安装 Cilium (kube-proxy 保留模式)"
ssh_node "$MASTER_IP" "
  cilium install --version 1.17.0 \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=false \
    --set hubble.enabled=true 2>&1 | tail -6
  echo '--- 等待 DaemonSet 就绪 (镜像已在本地, 应较快)...'
  kubectl -n kube-system rollout status ds/cilium --timeout=900s || true
  kubectl -n kube-system rollout status ds/cilium-envoy --timeout=300s || true
  kubectl get nodes
  kubectl -n kube-system get pods -l k8s-app=cilium -o wide | head -6
"
state_done cilium
echo "=== cilium done"
