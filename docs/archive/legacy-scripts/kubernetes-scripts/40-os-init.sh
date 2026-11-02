#!/bin/bash
# =============================================================================
# 40-os-init.sh — 所有 K8s 节点 OS 初始化 (cn profile)
# 1) apt 换阿里云  2) 基础包  3) 内核参数/模块  4) hosts (harbor.yjscloud.local)
# 5) 客户端工具: kubectl(+k 别名+补全)/crictl/nerdctl/helm  6) Longhorn 数据盘挂载
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

state_check os-init && { echo "=== os-init 已完成, 跳过"; exit 0; }

OS_INIT_SCRIPT='
set -euo pipefail
echo "--- [1/6] apt 换阿里云源"
sudo sed -i.bak "s|http://archive.ubuntu.com|https://mirrors.aliyun.com|g; s|http://security.ubuntu.com|https://mirrors.aliyun.com|g" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || \
  sudo sed -i.bak "s|http://archive.ubuntu.com|https://mirrors.aliyun.com|g; s|http://security.ubuntu.com|https://mirrors.aliyun.com|g" /etc/apt/sources.list
sudo apt-get update -qq

echo "--- [2/6] 基础包"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl wget ca-certificates gnupg lsb-release bash-completion \
  open-iscsi nfs-common socat conntrack jq python3 >/dev/null
sudo systemctl enable --now iscsid >/dev/null 2>&1 || sudo systemctl enable --now iscsi >/dev/null 2>&1 || true

echo "--- [3/6] 内核模块与 sysctl (K8s + Longhorn)"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
sudo modprobe overlay || true
sudo modprobe br_netfilter || true
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_instances       = 1024
fs.inotify.max_user_watches         = 1048576
vm.max_map_count                    = 262144
EOF
sudo sysctl --system >/dev/null
sudo swapoff -a || true

echo "--- [4/6] /etc/hosts: 集群节点 + harbor.yjscloud.local"
sudo tee -a /etc/hosts >/dev/null <<EOF

# --- iac test-cjl-k8s01 ---
172.16.222.201 test-cjl-k8s01-master-01 master-01
172.16.222.202 test-cjl-k8s01-worker-01 worker-01
172.16.222.203 test-cjl-k8s01-worker-02 worker-02
172.16.222.204 test-cjl-k8s01-worker-03 worker-03
172.16.222.207 harbor.yjscloud.local harbor
172.16.222.210 openwrt.yjscloud.local openwrt
EOF

echo "--- [5/6] Longhorn 数据盘 (第二块盘 → /var/lib/longhorn)"
if lsblk -dpno NAME | grep -q "/dev/sdb" && ! mountpoint -q /var/lib/longhorn; then
  sudo mkdir -p /var/lib/longhorn
  sudo mkfs.ext4 -F /dev/sdb
  echo "/dev/sdb /var/lib/longhorn ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
  sudo mount /var/lib/longhorn
fi
df -h /var/lib/longhorn 2>/dev/null || echo "(无数据盘)"

echo "--- [6/6] bashrc: k 别名 (appuser)"
grep -q "alias k=" ~/.bashrc || cat <<EOF >> ~/.bashrc

# kubernetes aliases & completion (iac)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF
echo "OS-INIT-OK $(hostname)"
'

echo "=== 分发执行 OS 初始化 (${#ALL_K8S_IPS[@]} 节点并行)"
all_k8s "$OS_INIT_SCRIPT"
echo "=== os-init done"
state_done os-init
