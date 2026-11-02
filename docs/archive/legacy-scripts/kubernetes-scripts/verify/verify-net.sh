#!/bin/bash
# verify-net.sh — Pod 网络 / DNS / Gateway 转发实测 (在 master-01 执行)
set -u
source /opt/iac/secrets/secrets.env 2>/dev/null || true
PASS=0; FAIL=0
r() { if [ "$1" = 0 ]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi; }

cleanup() { kubectl delete pod netdbg nettgt --force --grace-period=0 >/dev/null 2>&1; kubectl -n default delete deploy vt-nginx >/dev/null 2>&1; kubectl -n default delete svc svc-vt >/dev/null 2>&1; kubectl -n default delete httproute vt >/dev/null 2>&1; kubectl delete pvc vt-pvc --force --grace-period=0 >/dev/null 2>&1; }
cleanup

# --- DNS (FQDN) ---
kubectl run netdbg --image=docker.io/library/busybox:1.36 --command -- sleep 120 >/dev/null 2>&1
sleep 6
kubectl exec netdbg -- sh -c "nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1"
r $? "CoreDNS 解析 Service FQDN"

# --- pod-to-pod 跨节点 ---
kubectl run nettgt --image=docker.io/library/busybox:1.36 --overrides='{"spec":{"nodeName":"test-cjl-k8s01-worker-03"}}' --command -- sleep 300 >/dev/null 2>&1
sleep 6
IPB=$(kubectl get pod nettgt -o jsonpath='{.status.podIP}')
kubectl exec netdbg -- sh -c "ping -c2 -W2 $IPB >/dev/null 2>&1"
r $? "Pod-to-Pod 跨节点连通 (ping $IPB)"
IPB2=$(kubectl get pod netdbg -o jsonpath='{.status.podIP}')
kubectl exec nettgt -- sh -c "ping -c2 -W2 $IPB2 >/dev/null 2>&1"
r $? "Pod-to-Pod 反向连通 (ping $IPB2)"

# --- pod 出网 ---
kubectl exec netdbg -- sh -c "nslookup mirrors.aliyun.com 223.5.5.5 >/dev/null 2>&1"
r $? "Pod 出网 DNS (223.5.5.5)"

# --- Longhorn PVC ---
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: vt-pvc}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Gi}}}
EOF
sleep 10
[ "$(kubectl get pvc vt-pvc -o jsonpath='{.status.phase}')" = "Bound" ]
r $? "Longhorn PVC Bound (1Gi)"
cleanup

# --- Gateway HTTPRoute 转发 ---
echo "== 预拉 nginx 测试镜像 =="
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no appuser@$(kubectl get node $n -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') \
    "sudo ctr -n k8s.io images pull docker.1ms.run/library/nginx:1.27-alpine >/dev/null 2>&1 && sudo ctr -n k8s.io images tag docker.1ms.run/library/nginx:1.27-alpine docker.io/library/nginx:1.27-alpine" || true
done
kubectl -n default create deploy vt-nginx --image=docker.io/library/nginx:1.27-alpine --replicas=1 >/dev/null 2>&1
kubectl -n default rollout status deploy/vt-nginx --timeout=180s >/dev/null 2>&1
kubectl -n default expose deploy vt-nginx --port=80 --name=svc-vt >/dev/null 2>&1
kubectl -n default apply -f - >/dev/null <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: vt}
spec:
  parentRefs:
  - {name: lab-gw, namespace: envoy-gateway-system, sectionName: http}
  hostnames: ['vt.yjscloud.local']
  rules:
  - backendRefs: [{name: svc-vt, port: 80}]
EOF
sleep 12
GWIP=$(kubectl -n envoy-gateway-system get svc -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .status.loadBalancer.ingress[0].ip' | head -1)
if [ -n "$GWIP" ]; then
  curl -s -o /dev/null --connect-timeout 5 -H 'Host: vt.yjscloud.local' "http://$GWIP:8080/"
  r $? "HTTPRoute: Gateway($GWIP:8080) → Service → Pod 转发"
else
  echo "FAIL: Gateway 数据面 Service (lab-gw-eg) 未就绪"; FAIL=$((FAIL+1))
fi
cleanup

echo "== summary: $PASS pass / $FAIL fail =="
exit $FAIL
