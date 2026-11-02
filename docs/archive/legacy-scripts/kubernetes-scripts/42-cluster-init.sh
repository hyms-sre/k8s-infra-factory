#!/bin/bash
# =============================================================================
# 42-cluster-init.sh — kubeadm init (master-01) + worker join
# 1 master 拓扑, apiserver 直接监听 .201; kubeadm 镜像走阿里云
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check cluster-init && { echo "=== cluster-init 已完成, 跳过"; exit 0; }

echo "[1/4] master-01: kubeadm init (pod-cidr=${POD_CIDR})"
ssh_node "$MASTER_IP" "
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    sudo kubeadm init \
      --image-repository=registry.aliyuncs.com/google_containers \
      --apiserver-advertise-address=${MASTER_IP} \
      --pod-network-cidr=${POD_CIDR} \
      --service-cidr=${SERVICE_CIDR} \
      --node-name=test-cjl-k8s01-master-01 2>&1 | tail -8
  else
    echo 'admin.conf 已存在, 跳过 init'
  fi
  sudo kubeadm token create --print-join-command 2>/dev/null | sudo tee /root/join-command.sh >/dev/null
  sudo chmod 644 /root/join-command.sh
"

echo "[2/4] master-01: kubeconfig 给 appuser (kubectl 可直接用)"
ssh_node "$MASTER_IP" "
  mkdir -p ~/.kube
  sudo cp /etc/kubernetes/admin.conf ~/.kube/config
  sudo chown appuser:appowner ~/.kube/config
  kubectl get nodes 2>&1 | head -3
"

echo "[3/4] 预热 join 所需镜像到 workers (免得 join 时拉取超时)"
for ip in "${WORKER_IPS[@]}"; do
  mirror_pull "$ip" "registry.k8s.io/pause:3.10.1" || true
done

echo "[4/4] workers: kubeadm join"
JOIN_CMD=$(ssh_node "$MASTER_IP" "cat /root/join-command.sh")
for ip in "${WORKER_IPS[@]}"; do
  echo "  join ${ip}..."
  ssh_node "$ip" "sudo ${JOIN_CMD} --node-name=\$(hostname) 2>&1 | tail -2"
done

ssh_node "$MASTER_IP" "kubectl get nodes -o wide"
state_done cluster-init
echo "=== cluster-init done (节点 NotReady 属正常, CNI 下一阶段安装)"
