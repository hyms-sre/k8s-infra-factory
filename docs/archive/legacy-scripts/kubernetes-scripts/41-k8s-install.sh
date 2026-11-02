#!/bin/bash
# =============================================================================
# 41-k8s-install.sh — containerd + kubeadm/kubelet/kubectl v1.36 (全部节点)
# 阿里云源; sandbox_image 指向阿里云; systemd cgroup; 节点 registry 映射 Harbor
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check k8s-install && { echo "=== k8s-install 已完成, 跳过"; exit 0; }

read -r -d '' INSTALL_SCRIPT <<'INSTALLEOF' || true
set -euo pipefail
echo "--- [1/3] containerd"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq containerd apt-transport-https >/dev/null
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# SystemdCgroup + 阿里云 sandbox (兼容新旧配置字段)
sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause[^"]*"|sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.10.1"|' /etc/containerd/config.toml
sudo sed -i "s|sandbox = .registry.k8s.io/pause.*|sandbox = 'registry.aliyuncs.com/google_containers/pause:3.10.1'|" /etc/containerd/config.toml
grep -q "registry.aliyuncs.com/google_containers/pause" /etc/containerd/config.toml || { echo "sandbox sed FAILED"; exit 1; }
# 节点镜像映射: 6 个上游 → Harbor Proxy Cache (未命中回源上游)
# ⚠️ config_path 必须是【单一路径】。containerd 2.2.1 的 CRI 插件无法解析
#    "a:b" 形式的多路径值, 会静默忽略整个 certs.d → crictl 直连上游超时。
while IFS='|' read -r reg proj; do
  [ -z "$reg" ] && continue
  sudo mkdir -p /etc/containerd/certs.d/$reg
  sudo tee /etc/containerd/certs.d/$reg/hosts.toml >/dev/null <<HOSTSEOF
server = "https://$reg"

[host."https://harbor.yjscloud.local/v2/$proj"]
  capabilities = ["pull", "resolve"]
  override_path = true
HOSTSEOF
done <<'MAPEOF'
docker.io|dockerhub
quay.io|quay
ghcr.io|ghcr
registry.k8s.io|k8s
gcr.io|gcr
mcr.microsoft.com|mcr
MAPEOF
sudo sed -i "s|config_path = '[^']*:[^']*'|config_path = '/etc/containerd/certs.d'|g" /etc/containerd/config.toml
sudo sed -i "s|config_path = ''|config_path = '/etc/containerd/certs.d'|g" /etc/containerd/config.toml
grep -n "config_path" /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- [2/3] kubeadm/kubelet/kubectl (阿里云 kubernetes-new)"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.36/deb/Release.key" | \
  sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.36/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq kubelet kubeadm kubectl >/dev/null
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null

echo "--- [3/3] crictl endpoint 配置"
sudo mkdir -p /etc/crictl.d
echo "runtime-endpoint: unix:///run/containerd/containerd.sock" | sudo tee /etc/crictl.yaml >/dev/null
echo "K8S-INSTALL-OK $(hostname) kubectl=$(kubectl version --client -o json 2>/dev/null | head -c 200 | grep -o '"gitVersion": *"v[0-9.]*"' | head -1)"
INSTALLEOF

echo "=== 分发执行 k8s 组件安装 (4 节点并行)"
all_k8s "$INSTALL_SCRIPT"
echo "=== k8s-install done"
state_done k8s-install
