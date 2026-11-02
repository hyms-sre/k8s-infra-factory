# 场景: MetalLB + Gateway API（入口流量暴露）

## 问题

裸 K8s（无云 LB）如何把服务暴露到局域网：LoadBalancer 类型无人实现、L7 路由没有入口。

## 架构

```
局域网客户端
   → MetalLB (L2 模式: 把 IP 池中的 IP 借给 Service, 节点应答 ARP)
   → Gateway API (Envoy Gateway 数据面 Pod)
   → HTTPRoute 按 host/path 分发 → Service → Pod
```

## 1. MetalLB

```bash
kubectl apply -f k8s-plugins/networking/metallb/metallb-native.yaml
kubectl -n metallb-system apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1          # ⚠️ v0.14.x 是 v1beta1
kind: IPAddressPool
metadata: {name: lab-pool, namespace: metallb-system}
spec: {addresses: ["172.16.222.211-172.16.222.220"]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: lab-l2, namespace: metallb-system}
spec: {ipAddressPools: [lab-pool]}
EOF
```

- IP 池与节点同网段、避开已用地址（与 cluster.yaml 网段规划联动）
- CRD 刚建完 kubectl 报 not found → 清 ~/.kube/cache
- Service 加 `metallb.io/address-pool: <池名>` 可固定 IP

## 2. Gateway API + Envoy Gateway

```bash
kubectl apply -f k8s-plugins/networking/gateway-api/gateway-api-crds.yaml
kubectl apply -f k8s-plugins/networking/gateway-api/envoy-gateway-install.yaml \
  --server-side --force-conflicts          # 大 CRD 必须 server-side
# GatewayClass 'eg' 未自动创建时手工创建 (controllerName: gateway.envoyproxy.io/gatewayclass-controller)
```

```yaml
kind: Gateway
spec:
  gatewayClassName: eg
  listeners: [{name: http, protocol: HTTP, port: 8080, allowedRoutes: {namespaces: {from: All}}}]
---
kind: HTTPRoute
spec:
  parentRefs: [{name: lab-gw}]
  hostnames: ["app.example.com"]
  rules: [{backendRefs: [{name: web, port: 80}]}]
```

Gateway 的 Service 是 LoadBalancer → 自动从 MetalLB 池分配 IP。

## 验证

```bash
kubectl get gateway,gatewayclass        # 程序化: ADDRESS 已分配
curl -H 'Host: app.example.com' http://<LB-IP>:8080/
```

## 延伸

TLS：cert-manager 签证书 + Gateway TLS listener（docs/06-安全/06）。
Ingress-nginx 与 Gateway API 并存或迁移的取舍见 docs/02-Kubernetes/03-网络.md。
