#!/bin/bash
# =============================================================================
# 30-harbor-init.sh — Harbor 私有镜像仓库首次安装 (在 master-01 执行)
#
# 步骤: 数据盘检查 → docker → 离线安装 Harbor → (HTTPS 由 33-harbor-tls.sh 负责)
#
# ⚠️ 重要 (本项目实测踩坑):
#   harbor.yml 必须由【官方 harbor.yml.tmpl 打补丁】生成。
#   手写精简版 (只写 hostname/http/data_volume/trivy) 会在 `./prepare` 时报
#       KeyError: 'max_job_workers'
#   导致配置根本没生效 —— 容器继续用上一次生成的配置运行, 极难排查。
#   本脚本改为从 tmpl 生成, 从根上消除这个坑。
#
# 本脚本只装 HTTP; HTTPS 由 33-harbor-tls.sh 追加 (两者合起来才是完整状态)。
# 幂等: harbor 已安装 (state/harbor.done) 则跳过
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

HARBOR_PWD="${VAULT_HARBOR_ADMIN_PASSWORD}"
# DB 口令: 优先取 secrets, 未配置则回退默认 (避免像旧版那样写死在脚本里)
HARBOR_DB_PWD="${VAULT_HARBOR_DB_PASSWORD:-HarborDb-Yjs-2026}"
TGZ="/tmp/harbor-offline-installer-${HARBOR_VER}.tgz"

state_check harbor && { echo "=== harbor 已完成, 跳过"; exit 0; }

echo "[1/6] 数据盘检查 (cloud-init 已把 /dev/sdb 挂到 /var/lib/longhorn)"
ssh_node "$HARBOR_IP" "mountpoint -q /var/lib/longhorn && df -h /var/lib/longhorn | tail -1 || echo 'WARN: 数据盘未挂载'"

echo "[2/6] docker + hosts"
ssh_node "$HARBOR_IP" "
  grep -q 'harbor.yjscloud.local' /etc/hosts || echo '127.0.0.1 harbor.yjscloud.local' | sudo tee -a /etc/hosts >/dev/null
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io >/dev/null
  sudo systemctl enable --now docker >/dev/null 2>&1
  # Harbor install.sh 依赖 docker-compose 命令, Ubuntu 只有 compose 插件, 做 shim
  printf '#!/bin/sh\nexec docker compose \"\$@\"\n' | sudo tee /usr/local/bin/docker-compose >/dev/null
  sudo chmod +x /usr/local/bin/docker-compose
  sudo docker version --format 'docker {{.Server.Version}}'
"

echo "[3/6] 解压 harbor 离线包"
ssh_node "$HARBOR_IP" "[ -d /opt/harbor ] || (sudo tar -xzf ${TGZ} -C /opt/ && echo extracted)"

echo "[4/6] 从 harbor.yml.tmpl 生成完整 harbor.yml (http 阶段)"
ssh_node "$HARBOR_IP" "
set -e
cd /opt/harbor
[ -f harbor.yml ] && sudo cp -a harbor.yml harbor.yml.bak-\$(date +%Y%m%d-%H%M%S) || true
sudo tee /tmp/mk-harbor-yml.py >/dev/null <<'PYEOF'
import os
s = open('/opt/harbor/harbor.yml.tmpl').read()
reps = [
 ('hostname: reg.mydomain.com', 'hostname: harbor.yjscloud.local'),
 ('harbor_admin_password: Harbor12345', 'harbor_admin_password: ' + os.environ['HPW']),
 ('  password: root123', '  password: ' + os.environ['DPW']),
 ('data_volume: /data', 'data_volume: /var/lib/longhorn'),
 ('  skip_update: false', '  skip_update: true'),
 ('  offline_scan: false', '  offline_scan: true'),
 ('  security_check: vuln', '  security_check: false'),
]
for a, b in reps:
    if a not in s:
        print('  WARN pattern not found: ' + a)
    s = s.replace(a, b, 1)
open('/opt/harbor/harbor.yml', 'w').write(s)
print('  harbor.yml 已生成')
PYEOF
sudo env HPW='${HARBOR_PWD}' DPW='${HARBOR_DB_PWD}' python3 /tmp/mk-harbor-yml.py
sudo python3 -c \"import yaml; yaml.safe_load(open('/opt/harbor/harbor.yml')); print('  YAML OK')\"
grep -nE '^hostname|^http:|^  port:|^data_volume|max_job_workers' harbor.yml | sed 's/^/  /'
"

echo "[5/6] install.sh --with-trivy (需数分钟)"
ssh_node "$HARBOR_IP" "cd /opt/harbor && sudo bash ./install.sh --with-trivy 2>&1 | tail -4"
ssh_node "$HARBOR_IP" "sleep 5; sudo docker ps --format '{{.Names}}: {{.Status}}' | head -12"

echo "[6/6] 验证 HTTP 可达"
ssh_node "$HARBOR_IP" "
for i in \$(seq 1 20); do
  code=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://harbor.yjscloud.local/v2/ 2>/dev/null || echo 000)
  [ \"\$code\" = '401' ] && break
  sleep 5
done
echo \"  http /v2/ -> \$code (401 = 正常)\"
"

state_done harbor
echo "=== Harbor 安装完成 (HTTP)。下一步: make harbor-tls 启用 HTTPS ==="
