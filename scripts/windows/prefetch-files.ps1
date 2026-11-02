# =============================================================================
# prefetch-files.ps1 — 在 Windows 侧预下载部署工件 (VM/内网网络不可靠时使用)
#
# 下载到 downloads/ (不入 Git):
#   - 工具类 (crictl/nerdctl/helm/cilium-cli): cloud-init 可直接配置镜像 URL,
#     离线包作为备用, 也可自建 HTTP 服务供节点拉取
#   - manifest / 离线安装包: 对应 k8s-plugins/ 与 examples/harbor 使用
# Linux/macOS 等价脚本: scripts/linux/prefetch-files.sh
# =============================================================================
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path downloads | Out-Null
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-File($url, $out) {
  if (Test-Path "downloads\$out") { Write-Host "SKIP $out"; return }
  Write-Host "GET  $out ..."
  & curl.exe -sL --retry 3 --connect-timeout 20 -o "downloads\$out" $url
  if (Test-Path "downloads\$out") { $len = (Get-Item "downloads\$out").Length; Write-Host ("OK   {0} ({1:N1} MB)" -f $out, ($len/1MB)) }
  else { Write-Host "FAIL $out" }
}

# --- 客户端工具 (版本与 config/default.yaml 的 tools 段一致) ---
Get-File "https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.33.0/crictl-v1.33.0-linux-amd64.tar.gz" "crictl.tar.gz"
Get-File "https://github.com/containerd/nerdctl/releases/download/v2.0.4/nerdctl-2.0.4-linux-amd64.tar.gz" "nerdctl.tar.gz"
Get-File "https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz" "helm.tar.gz"
Get-File "https://github.com/cilium/cilium-cli/releases/download/v0.18.4/cilium-linux-amd64.tar.gz" "cilium-cli.tar.gz"

# --- CNI 与插件 manifests (k8s-plugins 使用) ---
Get-File "https://raw.githubusercontent.com/cilium/cilium/v1.17.0/install/kubernetes/quick-install.yaml" "cilium-quick-install.yaml"

# --- Harbor 离线安装包 (examples/harbor, 大文件约 900MB) ---
Get-File "https://github.com/goharbor/harbor/releases/download/v2.12.2/harbor-offline-installer-v2.12.2.tgz" "harbor-offline-installer-v2.12.2.tgz"

# --- OpenClash (examples/openwrt/files 使用) ---
Get-File "https://github.com/vernesong/OpenClash/raw/master/luci-app-openclash/luci-app-openclash.ipk" "luci-app-openclash.ipk"

Write-Host "`n=== prefetch done ==="
Get-ChildItem downloads | Format-Table Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} -AutoSize
