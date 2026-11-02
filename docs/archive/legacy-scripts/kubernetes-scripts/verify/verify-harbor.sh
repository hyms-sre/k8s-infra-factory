#!/bin/bash
# verify-harbor.sh — Harbor 登录检查 (在 master-01 执行)
# 注意: Harbor 已启用 HTTPS, HTTP(80) 会 308 跳转, curl 不带 -L 时拿到 308 而非 200,
#       因此这里必须直接打 https 端点。
set -u
source /opt/iac/secrets/secrets.env
H="https://harbor.yjscloud.local"
code=$(curl -sk -o /dev/null -w '%{http_code}' -u "admin:${VAULT_HARBOR_ADMIN_PASSWORD}" "$H/api/v2.0/users/current")
[ "$code" = "200" ]
