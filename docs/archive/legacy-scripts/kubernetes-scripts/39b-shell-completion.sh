#!/bin/bash
# =============================================================================
# 39b-shell-completion.sh — bash-completion + kubectl/nerdctl/crictl/helm 补全
# 在全部 K8s 节点执行 (从 master-01 通过 00-env.sh 的 all_k8s 分发)
# 幂等: 重复执行不会重复追加 .bashrc 内容
# 注意: 依赖 kubectl/nerdctl 已安装 → 必须排在 41-k8s-install.sh 之后
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

read -r -d '' COMPLETION_SCRIPT <<'COMPEOF' || true
set -uo pipefail

echo "--- [1/5] bash-completion 包"
if [ ! -f /usr/share/bash-completion/bash_completion ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash-completion >/dev/null 2>&1 || true
fi
if [ -f /usr/share/bash-completion/bash_completion ]; then
  echo "    bash-completion OK"
else
  echo "    !! bash-completion MISSING"
fi

echo "--- [2/5] /etc/bash_completion.d/ 下的各命令补全脚本"
sudo mkdir -p /etc/bash_completion.d

if command -v kubectl >/dev/null 2>&1; then
  kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null
  sudo chmod a+r /etc/bash_completion.d/kubectl
  echo "    kubectl completion -> /etc/bash_completion.d/kubectl"
fi
if command -v nerdctl >/dev/null 2>&1; then
  nerdctl completion bash | sudo tee /etc/bash_completion.d/nerdctl >/dev/null
  sudo chmod a+r /etc/bash_completion.d/nerdctl
  echo "    nerdctl completion -> /etc/bash_completion.d/nerdctl"
fi
if command -v helm >/dev/null 2>&1; then
  helm completion bash | sudo tee /etc/bash_completion.d/helm >/dev/null
  sudo chmod a+r /etc/bash_completion.d/helm
  echo "    helm completion -> /etc/bash_completion.d/helm"
fi
if command -v crictl >/dev/null 2>&1; then
  if crictl completion bash >/tmp/crictl.comp 2>/dev/null && [ -s /tmp/crictl.comp ]; then
    sudo mv /tmp/crictl.comp /etc/bash_completion.d/crictl
    sudo chmod a+r /etc/bash_completion.d/crictl
    echo "    crictl completion -> /etc/bash_completion.d/crictl"
  fi
fi

echo "--- [3/5] ~/.bashrc 追加 (幂等)"
for rc in /root/.bashrc /home/appuser/.bashrc; do
  if [ ! -f "$rc" ]; then
    sudo touch "$rc"
    echo "    创建 $rc (原不存在)"
  fi
  if sudo grep -q "bash-completion (managed)" "$rc" 2>/dev/null; then
    echo "    $rc 已存在, 跳过"
  else
    sudo tee -a "$rc" >/dev/null <<'RCEOF'

# --- bash-completion (managed) ---
source /usr/share/bash-completion/bash_completion
alias k=kubectl
complete -o default -F __start_kubectl k 2>/dev/null
# --- end bash-completion ---
RCEOF
    echo "    $rc 已追加"
  fi
done
sudo chown appuser:appowner /home/appuser/.bashrc 2>/dev/null || true

echo "--- [4/5] 清理旧的非托管补全片段 (避免重复注册)"
for u in /root /home/appuser; do
  if [ -f "$u/.bashrc.d/k8s-completion.sh" ]; then
    sudo rm -f "$u/.bashrc.d/k8s-completion.sh"
    echo "    移除 $u/.bashrc.d/k8s-completion.sh (已由托管块接管)"
  fi
done

echo "--- [5/5] 验证"
sudo bash -ic 'type _init_completion >/dev/null 2>&1 && echo "    root  _init_completion: OK" || echo "    root  _init_completion: MISSING"' 2>/dev/null
sudo bash -ic 'complete -p k >/dev/null 2>&1 && echo "    root  k 补全: OK" || echo "    root  k 补全: MISSING"' 2>/dev/null
sudo -u appuser bash -ic 'type _init_completion >/dev/null 2>&1 && echo "    appuser _init_completion: OK" || echo "    appuser _init_completion: MISSING"' 2>/dev/null
sudo -u appuser bash -ic 'complete -p k >/dev/null 2>&1 && echo "    appuser k 补全: OK" || echo "    appuser k 补全: MISSING"' 2>/dev/null
COMPEOF

echo "=== 分发 bash 补全配置到全部 K8s 节点 ==="
for ip in "${ALL_K8S_IPS[@]}"; do
  echo "== $ip"
  ssh_node "$ip" "$COMPLETION_SCRIPT"
done
echo "=== shell completion done"
