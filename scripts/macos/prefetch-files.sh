#!/usr/bin/env bash
# =============================================================================
# prefetch-files.sh — 预下载部署工件到 downloads/ (macOS 版, 与 Linux 同一逻辑)
# macOS 用 scripts/macos/prefetch-files.sh (同一逻辑)
# =============================================================================
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."   # 项目根
mkdir -p downloads

get() { # url, out
  local url="$1" out="downloads/$2"
  if [ -s "$out" ]; then echo "SKIP $2"; return 0; fi
  echo "GET  $2 ..."
  curl -fsSL --retry 3 --connect-timeout 20 -o "$out" "$url" \
    && echo "OK   $2 ($(du -m "$out" | cut -f1) MB)" \
    || echo "FAIL $2"
}

# --- 客户端工具 (版本与 config/default.yaml 的 tools 段一致) ---
get "https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.33.0/crictl-v1.33.0-linux-amd64.tar.gz" crictl.tar.gz
get "https://github.com/containerd/nerdctl/releases/download/v2.0.4/nerdctl-2.0.4-linux-amd64.tar.gz" nerdctl.tar.gz
get "https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz" helm.tar.gz
get "https://github.com/cilium/cilium-cli/releases/download/v0.18.4/cilium-linux-amd64.tar.gz" cilium-cli.tar.gz

# --- CNI manifests (k8s-plugins 使用) ---
get "https://raw.githubusercontent.com/cilium/cilium/v1.17.0/install/kubernetes/quick-install.yaml" cilium-quick-install.yaml

# --- Harbor 离线安装包 (examples/harbor) ---
get "https://github.com/goharbor/harbor/releases/download/v2.12.2/harbor-offline-installer-v2.12.2.tgz" harbor-offline-installer-v2.12.2.tgz

# --- OpenClash (examples/openwrt/files 使用) ---
get "https://github.com/vernesong/OpenClash/raw/master/luci-app-openclash/luci-app-openclash.ipk" luci-app-openclash.ipk

echo
echo "=== prefetch done ==="
ls -lh downloads/ 2>/dev/null
