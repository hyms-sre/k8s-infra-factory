# =============================================================================
# stage-to-master.ps1 — 分发 IaC 工程到部署控制机 master-01:/opt/iac
# 之后所有部署脚本都在 master-01 上执行 (Makefile 的设计执行位置)
# =============================================================================
$ErrorActionPreference = "Stop"
$dest = "appuser@172.16.222.201"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no $dest "sudo mkdir -p /opt/iac && sudo chown appuser:appowner /opt/iac"
# 脚本与清单 (小文件)
scp -o BatchMode=yes -o StrictHostKeyChecking=no -r scripts inventory profiles examples Makefile "${dest}:/opt/iac/"
# 工件 (files/ 排除大文件分批传)
ssh -o BatchMode=yes -o StrictHostKeyChecking=no $dest "mkdir -p /opt/iac/files"
foreach ($f in @("openwrt.vmdk","luci-app-openclash.ipk","crictl.tar.gz","nerdctl.tar.gz","helm.tar.gz","cilium-cli.tar.gz","cilium-quick-install.yaml","metallb-native.yaml","gateway-api-crds.yaml","envoy-gateway-install.yaml","longhorn.yaml","govc.tgz")) {
  Write-Host "scp files/$f"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no "files/$f" "${dest}:/opt/iac/files/"
}
# secrets
ssh -o BatchMode=yes -o StrictHostKeyChecking=no $dest "mkdir -p /opt/iac/secrets"
scp -o BatchMode=yes -o StrictHostKeyChecking=no secrets/secrets.env "${dest}:/opt/iac/secrets/"
Write-Host "=== staged (harbor 离线包 617MB 单独后台传: make stage-harbor)"
