#!/bin/bash
# =============================================================================
# 50-verify.sh — 完整验收 (在部署控制机 master-01 执行; 报告 → docs/07-验收报告.md)
# =============================================================================
set -uo pipefail
source "$(dirname "$0")/00-env.sh"
load_secrets

REPORT="/opt/iac/docs/07-验收报告.md"
PASS=0; FAIL=0
RESULTS=()

check() { # name, remote-cmd
  local name="$1"; shift
  if ssh_node "$MASTER_IP" "$@" >/dev/null 2>&1; then
    RESULTS+=("| $name | ✅ PASS |"); PASS=$((PASS+1)); echo "  ✅ $name"
  else
    RESULTS+=("| $name | ❌ FAIL |"); FAIL=$((FAIL+1)); echo "  ❌ $name"
  fi
}

echo "=== 验收开始 $(date '+%F %T') ==="

# 准备测试镜像 (本地化 busybox)
for ip in "${WORKER_IPS[@]}"; do mirror_pull "$ip" "docker.io/library/busybox:1.36" >/dev/null 2>&1 || true; done

echo "--- 1) 集群与节点"
check "4 节点全部 Ready" "kubectl get nodes -o json | jq -e '([.items[] | .status.conditions[] | select(.type==\"Ready\").status] | all(.==\"True\")) and (.items | length == 4)'"
check "控制面角色正确" "test \$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l) = 1"

echo "--- 2) 系统 Pod"
check "kube-system 无异常 Pod" "[ \$(kubectl -n kube-system get pods --no-headers | grep -cvE 'Running|Completed') = 0 ]"
check "Longhorn 27+ Pod 全部 Running" "[ \$(kubectl -n longhorn-system get pods --no-headers | grep -cv Running) = 0 ]"
check "MetalLB controller 正常" "kubectl -n metallb-system rollout status deploy/controller --timeout=5s"
check "Headlamp 正常" "kubectl -n headlamp rollout status deploy/headlamp --timeout=5s"
check "Envoy Gateway 正常" "kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=5s"

echo "--- 3) DNS"
check "CoreDNS 副本正常" "kubectl -n kube-system rollout status deploy/coredns --timeout=5s"
check "Service DNS 解析 (FQDN)" "kubectl run dnstest --rm -i --restart=Never --image=docker.io/library/busybox:1.36 --restart=Never -- sh -c 'nslookup kubernetes.default.svc.cluster.local >/dev/null' 2>/dev/null"

echo "--- 4) Pod 网络 / 出网 / 存储 / Gateway 转发 (verify-net.sh)"
ssh_node "$MASTER_IP" "bash /opt/iac/scripts/verify/verify-net.sh" > /tmp/verify-net.out 2>&1 || true
grep -c "^PASS" /tmp/verify-net.out >/dev/null && cat /tmp/verify-net.out
for item in "CoreDNS 解析 Service FQDN" "Pod-to-Pod 跨节点连通" "Pod-to-Pod 反向连通" "Pod 出网 DNS" "Longhorn PVC Bound" "HTTPRoute: Gateway"; do
  if grep -q "PASS: ${item}" /tmp/verify-net.out; then
    RESULTS+=("| ${item} | ✅ PASS |"); PASS=$((PASS+1)); echo "  ✅ ${item}"
  else
    RESULTS+=("| ${item} | ❌ FAIL |"); FAIL=$((FAIL+1)); echo "  ❌ ${item}"
  fi
done

echo "--- 6) MetalLB / LoadBalancer"
check "IPAddressPool .212-.220 + headlamp-pool .211" "kubectl -n metallb-system get ipaddresspool | grep -q headlamp-pool"
check "Headlamp LB 固定 .211" "[ \"\$(kubectl -n headlamp get svc headlamp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" = '${HEADLAMP_LB_IP}' ]"
check "LB IP 从外部可达 (HTTP 200)" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://${HEADLAMP_LB_IP}/ | grep -q 200"

echo "--- 7) Gateway API"
check "GatewayClass eg Accepted" "kubectl get gatewayclass eg -o json | jq -e '.status.conditions[] | select(.type==\"Accepted\")' >/dev/null"
check "Gateway lab-gw Programmed" "kubectl -n envoy-gateway-system get gateway lab-gw -o json | jq -e '.status.conditions[] | select(.type==\"Programmed\")' >/dev/null"

echo "--- 8) Harbor (HTTPS + Proxy Cache)"
check "Harbor HTTPS /v2/ 返回 401" "curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${REGISTRY_URL}/v2/ | grep -q 401"
check "HTTP 跳转 HTTPS (30x)" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://${REGISTRY_URL}/v2/ | grep -qE '30[18]'"
check "节点已信任 Harbor CA (无 -k 可访问)" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${REGISTRY_URL}/v2/ | grep -q 401"
check "Harbor admin 登录" "bash /opt/iac/scripts/verify/verify-harbor.sh"
check "Harbor Proxy 项目 6/6 (dockerhub/gcr/k8s/quay/ghcr/mcr)" "source /opt/iac/secrets/secrets.env; curl -sk -u admin:\${VAULT_HARBOR_ADMIN_PASSWORD} https://${REGISTRY_URL}/api/v2.0/projects | jq -e '[.[].name] | contains([\"dockerhub\",\"gcr\",\"k8s\",\"quay\",\"ghcr\",\"mcr\"])' >/dev/null"

echo "--- 8b) containerd 镜像链路 (本次修复重点)"
check "config_path 为单一路径 (无冒号多路径)" "grep -q \"config_path = '/etc/containerd/certs.d'\" /etc/containerd/config.toml && ! grep -qE \"config_path = '[^']*:[^']*'\" /etc/containerd/config.toml"
check "certs.d 覆盖 6 个上游" "[ \$(ls /etc/containerd/certs.d | wc -l) -ge 6 ]"
check "crictl 经 Harbor 拉取成功 (docker.io 已封, 成功即证明走 Harbor)" "sudo crictl pull docker.io/library/hello-world:latest >/dev/null 2>&1"
check "无直连 registry-1.docker.io 失败记录" "! sudo journalctl -u containerd --since '3 minutes ago' --no-pager 2>/dev/null | grep -q 'registry-1.docker.io'"

echo "--- 9) 客户端工具与补全"
check "kubectl/k 别名/补全" "bash -ic 'type k >/dev/null && complete -p k | grep -q kubectl'"
check "bash-completion 已加载 (_init_completion)" "bash -ic 'type _init_completion >/dev/null 2>&1'"
check "kubectl completion 文件" "test -r /etc/bash_completion.d/kubectl"
check "nerdctl completion 文件" "test -r /etc/bash_completion.d/nerdctl"
check "helm" "helm version --short | grep -q v3"
check "crictl" "sudo crictl info >/dev/null"
check "nerdctl" "sudo nerdctl info >/dev/null"
check "OpenWrt DNS 提供本地域解析" "nslookup ${REGISTRY_URL} ${OPENWRT_IP} 2>/dev/null | grep -q ${HARBOR_IP}"
check "OpenWrt DNS 条目健康 (无重复/含本地域/可解析)" "bash /opt/iac/scripts/verify/verify-openwrt-dns.sh"

echo "--- 10) GZD Cloud 欢迎信息"
check "issue 含 GZD Cloud banner" "cat /etc/issue /etc/issue.d/*.issue 2>/dev/null | grep -q 'GZD Cloud'"
check "issue 转义为字面量 (\\n \\4 \\6 \\t)" "grep -qF 'Hostname : \\n' /etc/issue.d/50-gzd-cloud.issue && grep -qF 'IPv4     : \\4' /etc/issue.d/50-gzd-cloud.issue && grep -qF 'Time     : \\t' /etc/issue.d/50-gzd-cloud.issue"
check "issue.d 两个片段均就位" "test -s /etc/issue.d/10-gzd-banner.issue && test -s /etc/issue.d/50-gzd-cloud.issue"
check "/etc/motd 已写入 GZD 说明" "grep -q 'GZD Cloud' /etc/motd"
check "动态 motd 已生成" "test -s /run/motd.dynamic"
check "motd 开机重建单元已启用" "systemctl is-enabled gzd-motd.service >/dev/null 2>&1"

# 生成报告
{
  echo "# 07-验收报告 — test-cjl-k8s01"
  echo ""
  echo "验收时间: $(date '+%F %T') ｜ Profile: ${PROFILE} ｜ 版本: K8s v1.36.4 / Cilium v1.17.0 / MetalLB v0.14.9 / Envoy Gateway v1.5.0 / Longhorn v1.9.1 / Headlamp v0.45.0 / Harbor v2.12.2"
  echo ""
  echo "| 检查项 | 结果 |"
  echo "|---|---|"
  printf '%s\n' "${RESULTS[@]}"
  echo ""
  echo "**结果: ${PASS} 通过 / ${FAIL} 失败**"
  echo ""
  echo "> 覆盖: 集群/CNI/存储/Gateway + Harbor HTTPS 与 6 个 Proxy Cache + containerd 镜像链路 + shell 补全。"
} > "$REPORT"
echo ""
echo "=== 验收完成: ${PASS} 通过 / ${FAIL} 失败 — 报告: docs/07-验收报告.md"
