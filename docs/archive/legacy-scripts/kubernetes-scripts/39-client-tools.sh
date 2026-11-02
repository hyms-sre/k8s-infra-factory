#!/bin/bash
# =============================================================================
# 39-client-tools.sh — 分发安装客户端工具到全部 K8s 节点 (从 master-01 执行)
# crictl / nerdctl / helm (files/ 已预下载) + 命令补全; kubectl 已由 apt 安装
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

read -r -d '' TOOLS_SCRIPT <<'TOOLSEOF' || true
set -euo pipefail
F=/opt/iac-files
echo "--- crictl"
sudo tar -C /usr/local/bin -xzf $F/crictl.tar.gz crictl
echo "--- nerdctl"
sudo tar -C /usr/local/bin -xzf $F/nerdctl.tar.gz
echo "--- helm"
tar -C /tmp -xzf $F/helm.tar.gz linux-amd64/helm
sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
# bash 补全 (root + appuser)
for u in /root /home/appuser; do
  mkdir -p $u/.bashrc.d
  cat > $u/.bashrc.d/k8s-completion.sh <<EOF
source /usr/share/bash-completion/bash_completion 2>/dev/null || true
source <(kubectl completion bash) 2>/dev/null || true
alias k=kubectl
complete -o default -F __start_kubectl k 2>/dev/null || true
source <(helm completion bash) 2>/dev/null || true
source <(nerdctl completion bash) 2>/dev/null || true
EOF
  chmod +x $u/.bashrc.d/k8s-completion.sh
done
grep -q "bashrc.d" /home/appuser/.bashrc || printf 'for f in ~/.bashrc.d/*.sh; do [ -f "$f" ] && source "$f"; done\n' >> /home/appuser/.bashrc
echo "TOOLS-OK $(helm version --short) $(crictl --version | awk '{print $3}')"
TOOLSEOF

echo "[1/2] 分发工具包到各节点 /opt/iac-files"
for ip in "${ALL_K8S_IPS[@]}"; do
  ssh_node "$ip" "sudo mkdir -p /opt/iac-files && sudo chown appuser /opt/iac-files"
  for f in crictl.tar.gz nerdctl.tar.gz helm.tar.gz; do
    scp_node "/opt/iac/files/$f" "$ip" "/opt/iac-files/$f"
  done
done

echo "[2/2] 安装 + 补全"
for ip in "${ALL_K8S_IPS[@]}"; do
  ssh_node "$ip" "$TOOLS_SCRIPT"
done
echo "=== client-tools done"
