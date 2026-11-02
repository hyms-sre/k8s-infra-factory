#!/bin/bash
# =============================================================================
# 33-harbor-tls.sh — Harbor 启用 HTTPS + 生成内网 CA + 分发信任链
#
# 背景 (本项目实测踩坑, 必读):
#   1. harbor.yml 必须是【官方 harbor.yml.tmpl 的补丁版】。
#      手写精简版会在 `./prepare` 阶段报 KeyError: 'max_job_workers' 而无法生效,
#      容器会继续用旧的生成配置运行 —— 表现为"改了配置但行为没变"。
#   2. harbor.yml 里的 database.password 必须与 Postgres 实际口令一致。
#      若历史上被覆盖过, 需要同步 ALTER USER (本脚本第 4 步自动处理)。
#   3. containerd 2.2.1 的 CRI 插件无法解析 config_path 的多路径写法
#      ("a:b") —— 必须单一路径, 否则 certs.d 被静默忽略、拉取直连上游超时。
#      本脚本只负责证书; certs.d 的写法见 32-node-registry-mirrors.sh。
#
# 用法: 在 master-01 上 `make harbor-tls` 或 `bash scripts/33-harbor-tls.sh`
# 幂等: 证书已存在则复用; CA 重复分发会覆盖同名文件
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

HARBOR_PWD="${VAULT_HARBOR_ADMIN_PASSWORD}"
STATE_KEY="harbor-tls"

echo "=== [1/6] 在 Harbor 节点生成内网 CA + 服务器证书 (SAN) ==="
ssh_node "$HARBOR_IP" "
set -e
CERT_DIR='${HARBOR_CERT_DIR}'
sudo mkdir -p \"\$CERT_DIR\"
cd \"\$CERT_DIR\"
if [ -f ca.crt ] && [ -f harbor.yjscloud.local.crt ]; then
  echo '  证书已存在, 复用'
else
  sudo openssl genrsa -out ca.key 4096 >/dev/null 2>&1
  sudo openssl req -x509 -new -nodes -sha256 -days 3650 -key ca.key \
    -subj '/C=CN/ST=Shanghai/L=Shanghai/O=YJS Lab/CN=YJS-Lab-Internal-CA' \
    -out ca.crt >/dev/null 2>&1
  sudo openssl genrsa -out harbor.yjscloud.local.key 4096 >/dev/null 2>&1
  sudo openssl req -new -key harbor.yjscloud.local.key \
    -subj '/C=CN/ST=Shanghai/L=Shanghai/O=YJS Lab/CN=harbor.yjscloud.local' \
    -out harbor.csr >/dev/null 2>&1
  printf 'subjectAltName = DNS:harbor.yjscloud.local, DNS:harbor, DNS:localhost, IP:${HARBOR_IP}, IP:127.0.0.1%sextendedKeyUsage = serverAuth%skeyUsage = digitalSignature, keyEncipherment%s' '\n' '\n' '\n' | sudo tee san.cnf >/dev/null
  sudo openssl x509 -req -in harbor.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out harbor.yjscloud.local.crt -days 3650 -sha256 -extfile san.cnf >/dev/null 2>&1
  sudo rm -f harbor.csr
fi
sudo chmod 644 ca.crt harbor.yjscloud.local.crt
sudo chmod 600 ca.key harbor.yjscloud.local.key
echo '  SAN:'
sudo openssl x509 -in harbor.yjscloud.local.crt -noout -ext subjectAltName | tail -1
"

echo "=== [2/6] 从官方 harbor.yml.tmpl 生成完整配置并启用 https ==="
ssh_node "$HARBOR_IP" "
set -e
cd /opt/harbor
[ -f harbor.yml ] && sudo cp -a harbor.yml harbor.yml.bak-\$(date +%Y%m%d-%H%M%S) || true
HPW=\$(sudo grep '^harbor_admin_password:' harbor.yml 2>/dev/null | sed 's/^harbor_admin_password:[[:space:]]*//' | tr -d '\r')
[ -z \"\$HPW\" ] && HPW='${HARBOR_PWD}'
DPW=\$(sudo awk '/^database:/{f=1;next} f&&/^[^ ]/{f=0} f&&/password:/{sub(/^[[:space:]]*password:[[:space:]]*/,\"\");print;exit}' harbor.yml 2>/dev/null | tr -d '\r')
[ -z \"\$DPW\" ] && DPW='HarborDb-Yjs-2026'
sudo tee /tmp/mk-harbor-yml.py >/dev/null <<'PYEOF'
import os
s = open('/opt/harbor/harbor.yml.tmpl').read()
reps = [
 ('hostname: reg.mydomain.com', 'hostname: harbor.yjscloud.local'),
 ('  certificate: /your/certificate/path', '  certificate: ' + os.environ['CD'] + '/harbor.yjscloud.local.crt'),
 ('  private_key: /your/private/key/path', '  private_key: ' + os.environ['CD'] + '/harbor.yjscloud.local.key'),
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
print('  harbor.yml 已从 tmpl 生成')
PYEOF
sudo env HPW=\"\$HPW\" DPW=\"\$DPW\" CD='${HARBOR_CERT_DIR}' python3 /tmp/mk-harbor-yml.py
sudo python3 -c \"import yaml; yaml.safe_load(open('/opt/harbor/harbor.yml')); print('  YAML OK')\"
grep -nE '^https:|^  port: 443|^  certificate|^  private_key' /opt/harbor/harbor.yml | sed 's/^/  /'
"

echo "=== [3/6] prepare (重新生成 compose/nginx 配置, 保留 trivy) ==="
ssh_node "$HARBOR_IP" "cd /opt/harbor && sudo ./prepare --with-trivy 2>&1 | tail -4"

echo "=== [4/6] 对齐 Postgres 口令 (避免 core 因 SASL 认证失败 crash-loop) ==="
ssh_node "$HARBOR_IP" "
DPW=\$(sudo awk '/^database:/{f=1;next} f&&/^[^ ]/{f=0} f&&/password:/{sub(/^[[:space:]]*password:[[:space:]]*/,\"\");print;exit}' /opt/harbor/harbor.yml | tr -d '\r')
if sudo docker exec -u postgres harbor-db psql -U postgres -tAc \"select 'AUTH_OK'\" 2>/dev/null | grep -q AUTH_OK; then
  sudo docker exec -u postgres harbor-db psql -U postgres -c \"ALTER USER postgres WITH PASSWORD '\$DPW';\" 2>&1 | tail -1
else
  echo '  WARN: harbor-db 本地 socket 认证失败, 跳过口令对齐'
fi
"

echo "=== [5/6] 拉起 Harbor 并验证 HTTPS ==="
ssh_node "$HARBOR_IP" "
cd /opt/harbor
sudo docker compose up -d 2>&1 | tail -4
for i in \$(seq 1 24); do
  code=\$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 https://harbor.yjscloud.local/v2/ 2>/dev/null || echo 000)
  [ \"\$code\" = '401' ] && break
  sleep 5
done
echo \"  https /v2/  -> \$code (401 = 正常, 需要认证)\"
curl -s -o /dev/null -w '  http  /v2/  -> %{http_code} (308 = 跳转 HTTPS)\n' --connect-timeout 5 http://harbor.yjscloud.local/v2/ || true
sudo docker ps --format '  {{.Names}}: {{.Status}}' | head -12
"

echo "=== [6/6] 导出 CA 并分发到全部 K8s 节点信任链 ==="
mkdir -p "$(dirname "${PROJECT_ROOT}/${HARBOR_CA_LOCAL}")"
ssh_node "$HARBOR_IP" "sudo cat ${HARBOR_CERT_DIR}/ca.crt" > "${PROJECT_ROOT}/${HARBOR_CA_LOCAL}"
echo "  已保存本地副本: ${HARBOR_CA_LOCAL}"

CA_SCRIPT='
sudo cp /tmp/harbor-ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
sudo update-ca-certificates 2>&1 | tail -2
curl -s -o /dev/null -w "  信任校验 (无 -k): %{http_code}\n" --connect-timeout 8 https://harbor.yjscloud.local/v2/
'
for ip in "${ALL_K8S_IPS[@]}"; do
  echo "  -> $ip"
  scp_node "${PROJECT_ROOT}/${HARBOR_CA_LOCAL}" "$ip" "/tmp/harbor-ca.crt"
  ssh_node "$ip" "$CA_SCRIPT"
done

state_done "$STATE_KEY"
echo "=== harbor-tls done: ${REGISTRY_HTTPS}/v2/ ==="
