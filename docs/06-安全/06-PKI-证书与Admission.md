# PKI / 证书 / Admission / CKS 实践

## K8s 内置 PKI

kubeadm 一键生成的证书体系（/etc/kubernetes/pki）：

- 集群 CA → 签发 apiserver/etcd/kubelet 等组件证书 + admin.conf 客户端证书
- 检查与续期：`kubeadm certs check-expiration` / `kubeadm certs renew all`
- etcd 加密 Secret：EncryptionConfiguration（apiserver 配置）

## cert-manager

集群内证书签发自动化（ACME/自建 CA/Vault issuer）：

```yaml
kind: ClusterIssuer
spec: {selfSigned: {}}          # 或 acme/CA
---
kind: Certificate
spec:
  secretName: app-tls
  dnsNames: [app.example.com]
  issuerRef: {name: ca-issuer}
```

自动续期 + 与 Ingress/Gateway API 集成（automate-tls annotation）。
本项目场景：Harbor HTTPS 的 CA 分发也可迁移到 cert-manager 自建 CA 体系。

## Admission 链路

```
请求 → 认证/鉴权 → mutating webhooks (按名称排序) → schema 校验
    → validating webhooks → 持久化 etcd
```

注意 webhook 故障会阻塞所有写操作——豁免 namespace（kube-system）+ 高可用 webhook。

## CKS 实践清单（基于本环境可练）

1. RuntimeClass/gVisor 沙箱跑不受信负载
2. Pod Security restricted 基线全 namespace 推广
3. etcd 加密 at rest + 备份加密
4. API 审计日志 → Loki
5.Kyverno 供应链策略（仅签名镜像）
6. kube-bench 修复到 CIS 基本项全过
