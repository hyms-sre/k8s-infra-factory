#!/bin/bash
# =============================================================================
# 32-node-registry-mirrors.sh — 节点 containerd 镜像映射 (在 master-01 执行)
#
# 把 Harbor 的全部 Proxy Cache 项目映射到各节点 containerd certs.d,
# 使 crictl / nerdctl 拉取 docker.io 等上游镜像时自动经 Harbor 代理并缓存。
#
# ⚠️⚠️ 关键坑 (本项目实测, 改动前务必读完) ⚠️⚠️
#   containerd 2.2.1 的 CRI 插件 **无法解析 config_path 的多路径写法**。
#   `containerd config default` 生成的默认值是:
#       config_path = '/etc/containerd/certs.d:/etc/docker/certs.d'
#   带冒号时 CRI 会【静默忽略】整个 certs.d 目录 —— 表现为:
#       crictl pull 直连 registry-1.docker.io → i/o timeout
#       (而 nerdctl 走 transfer 插件却能正常走 Harbor, 极易误判为"映射没问题")
#   必须改成单一路径:
#       config_path = '/etc/containerd/certs.d'
#   CRI(images) 与 transfer 两处都要改, 缺一不可。
#
# 幂等: 每次全量重写 hosts.toml 与 config_path
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

# 由 00-env.sh 的 HARBOR_PROXY_MAP 生成 "registry|project" 两列
PAIRS=""
for entry in "${HARBOR_PROXY_MAP[@]}"; do
  IFS='|' read -r reg proj _rtype _url <<<"$entry"
  PAIRS="${PAIRS}${reg}|${proj}"$'\n'
done

read -r -d '' MIRROR_SCRIPT <<MIRROREOF || true
set -euo pipefail
CERT_D='/etc/containerd/certs.d'
CONF='/etc/containerd/config.toml'

echo "  --- 安装 Harbor CA 到系统信任链"
if [ -f /tmp/harbor-ca.crt ]; then
  sudo cp /tmp/harbor-ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
  sudo update-ca-certificates >/dev/null 2>&1 || true
fi

echo "  --- 写 certs.d (HTTPS 指向 Harbor Proxy)"
while IFS='|' read -r reg proj; do
  [ -z "\$reg" ] && continue
  sudo mkdir -p "\$CERT_D/\$reg"
  sudo tee "\$CERT_D/\$reg/hosts.toml" >/dev/null <<HOSTSEOF
server = "https://\$reg"

[host."${REGISTRY_HTTPS}/v2/\$proj"]
  capabilities = ["pull", "resolve"]
  override_path = true
HOSTSEOF
done <<'PAIRSEOF'
${PAIRS}
PAIRSEOF

echo "  --- 修正 config_path 为单一路径 (CRI 与 transfer 都要改)"
sudo sed -i "s|config_path = '[^']*:[^']*'|config_path = '\$CERT_D'|g" "\$CONF"
sudo sed -i "s|config_path = ''|config_path = '\$CERT_D'|g" "\$CONF"
grep -n "config_path" "\$CONF" | sed 's/^/    /'

echo "  --- 重启 containerd"
sudo systemctl restart containerd
sleep 6
echo "    containerd: \$(systemctl is-active containerd)"

echo "  --- 本机 TLS 信任校验 (不带 -k)"
curl -s -o /dev/null -w "    https %{http_code} (401=正常)\n" --connect-timeout 8 ${REGISTRY_HTTPS}/v2/ || true

echo "    MIRRORS-OK \$(hostname): \$(ls \$CERT_D | tr '\n' ' ')"
MIRROREOF

echo "=== 分发镜像映射到全部 K8s 节点 ==="
for ip in "${ALL_K8S_IPS[@]}"; do
  echo "== $ip"
  if [ -f "${PROJECT_ROOT}/${HARBOR_CA_LOCAL}" ]; then
    scp_node "${PROJECT_ROOT}/${HARBOR_CA_LOCAL}" "$ip" "/tmp/harbor-ca.crt"
  fi
  ssh_node "$ip" "$MIRROR_SCRIPT"
done
echo "=== 节点镜像映射完成 (拉取优先 Harbor Proxy, 未命中回源上游) ==="
