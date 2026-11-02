#!/bin/bash
# =============================================================================
# 31-harbor-proxies.sh — Harbor Proxy Cache 一键配置 (在 master-01 执行)
#
# 设计原则 (本项目重构要点):
#   - 上游选择"能用优先": 直连可达的用官方源, 被墙的用国内镜像
#     (docker.io → docker.1ms.run; gcr.io → gcr.m.daocloud.io;
#      registry.k8s.io → k8s.m.daocloud.io, 因为它 307 跳 pkg.dev 被墙)
#     这样 Harbor 回源【不依赖 OpenClash】, 可用性更高。
#   - 项目名必须与节点 certs.d 的路径段一致 (32-node-registry-mirrors.sh 依赖)
#   - 清理历史误建的普通项目 (registry_id 为空) 与不可达的 registry endpoint
#
# 幂等: registry/project 已存在(409) 视为成功; 每次全量校验
# 用法: make harbor 或 bash scripts/31-harbor-proxies.sh
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

HARBOR_PWD="${VAULT_HARBOR_ADMIN_PASSWORD}"
STATE_KEY="harbor-proxy"
H="${REGISTRY_HTTPS}"
C="curl -sk -u admin:${HARBOR_PWD}"

echo "=== Harbor Proxy Cache 配置 (${#HARBOR_PROXY_MAP[@]} 个上游) ==="

# --- 0) 等待 Harbor API 就绪 ---
for i in $(seq 1 30); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$H/api/v2.0/systeminfo" 2>/dev/null || echo 000)
  [ "$code" = "200" ] && break
  sleep 5
done
[ "$code" = "200" ] || mar "Harbor API 不可用 ($H/api/v2.0/systeminfo -> $code)。
处理: 登录 Harbor 节点执行 cd /opt/harbor && sudo docker compose ps 查看容器状态。"

# --- 1) 清理: 删除不在 HARBOR_PROXY_MAP 中的 proxy 项目 + 不可达 registry ---
echo "--- [1/3] 清理历史遗留项目 / registry endpoint"
WANT_PROJ=""
for entry in "${HARBOR_PROXY_MAP[@]}"; do
  IFS='|' read -r _reg proj _t _u <<<"$entry"
  WANT_PROJ="$WANT_PROJ $proj"
done

$C "$H/api/v2.0/projects?page_size=100" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for p in d:
    rid = p.get("registry_id")
    if rid:  # 只处理 proxy 项目, 跳过 library 等普通项目
        print("%s|%s" % (p["name"], rid))
' | while IFS='|' read -r pname rid; do
  case " $WANT_PROJ " in
    *" $pname "*) : ;;
    *) echo "    - 删除多余 proxy 项目 $pname"; $C -o /dev/null -w '      -> %{http_code}\n' -X DELETE "$H/api/v2.0/projects/$pname" ;;
  esac
done

# --- 2) 逐个上游: 探测 → 建 registry endpoint → 建 proxy 项目 ---
echo "--- [2/3] 创建/校验 registry endpoint 与 proxy 项目"
BLOCKED=""
for entry in "${HARBOR_PROXY_MAP[@]}"; do
  IFS='|' read -r reg proj rtype url <<<"$entry"
  printf '    %-22s -> %s\n' "$reg" "$proj"

  # 从 Harbor 视角探测上游 (401/200/30x 都算可达)
  probe="${url}/v2/"
  code=$(ssh_node "$HARBOR_IP" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 8 '$probe'" 2>/dev/null || echo 000)
  case "$code" in
    401|200|30*) echo "      上游可达 ($code)" ;;
    *) echo "      ⛔ 上游不可达 ($code) — 跳过"; BLOCKED="$BLOCKED $proj"; continue ;;
  esac

  # registry endpoint (409=已存在)
  rcode=$($C -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d "{\"name\":\"$proj\",\"type\":\"$rtype\",\"url\":\"$url\",\"insecure\":false}" \
    "$H/api/v2.0/registries")
  case "$rcode" in
    201) echo "      registry 已创建" ;;
    409) echo "      registry 已存在" ;;
    *)   echo "      ❌ registry 创建失败 HTTP $rcode"; BLOCKED="$BLOCKED $proj"; continue ;;
  esac

  rid=$($C "$H/api/v2.0/registries?name=$proj" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')
  if [ -z "$rid" ]; then echo "      ❌ 取不到 registry_id"; BLOCKED="$BLOCKED $proj"; continue; fi

  # proxy 项目 (必须带 registry_id, 否则会建成普通项目!)
  pcode=$($C -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d "{\"project_name\":\"$proj\",\"public\":true,\"registry_id\":$rid}" \
    "$H/api/v2.0/projects")
  case "$pcode" in
    201) echo "      proxy 项目已创建 (registry=$rid)" ;;
    409) echo "      proxy 项目已存在 (registry=$rid)" ;;
    *)   echo "      ❌ proxy 项目创建失败 HTTP $pcode"; BLOCKED="$BLOCKED $proj" ;;
  esac
done

# --- 3) 汇总 ---
echo "--- [3/3] 当前状态"
$C "$H/api/v2.0/registries?page_size=50" | python3 -c '
import sys, json
for r in json.load(sys.stdin):
    print("    reg id=%-3s %-10s %-16s %-34s [%s]" % (r["id"], r["name"], r["type"], r["url"], r.get("status")))'
$C "$H/api/v2.0/projects?page_size=50" | python3 -c '
import sys, json
for p in json.load(sys.stdin):
    print("    proj %-12s registry_id=%s" % (p["name"], p.get("registry_id")))'

if [ -n "$BLOCKED" ]; then
  mar "以下上游不可达, 未建立代理:$BLOCKED
处理: 1) 确认镜像地址是否变更 (见 scripts/00-env.sh 的 HARBOR_PROXY_MAP)
      2) 或在 OpenWrt 上确认 OpenClash 订阅有效后重试
      3) 重新执行: make resume"
fi

state_done "$STATE_KEY"
echo "=== Harbor Proxy Cache 配置完成 ==="
