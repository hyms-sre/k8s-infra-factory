# 网络策略与 Secrets

## NetworkPolicy

默认 K8s 网络**全通**。启用策略后：被选中的 Pod 未被允许的流量一律拒绝。

```yaml
kind: NetworkPolicy
metadata: {name: db-allow-api, namespace: prod}
spec:
  podSelector: {matchLabels: {app: db}}          # 目标 Pod
  policyTypes: [Ingress]
  ingress:
  - from:
    - {podSelector: {matchLabels: {app: api}}}   # 只允许 api
    ports: [{protocol: TCP, port: 5432}]
```

要点：
- 需要 CNI 支持（Cilium/Calico 是，flannel 否）
- 空规则 `policyTypes: [Ingress]` = 全拒绝（默认拒绝的写法）
- egress 同理；DNS 放行别忘（egress deny 时放行 kube-dns）
- 更细粒度（L7）用 Cilium NetworkPolicy

## Secrets 管理

| 方案 | 适用 |
|---|---|
| 原生 Secret | 起步；配合 RBAC + etcd 加密 |
| Sealed Secrets | GitOps 场景：密文可安全入 Git，集群内解密 |
| External Secrets | 从 Vault/云 KMS 同步为 K8s Secret |
| Vault | 完整密钥生命周期（动态凭据/轮换） |

原则：
- Secret 不进明文 Git（本项目 .gitignore + example 占位符模式）
- 值得入 Git 的"密文"用 Sealed Secrets；真正的明文只存 Secret 管理系统/密码管理器
- 轮换：数据库口令、镜像拉取凭据定期换（docs/99-参考/02-凭据说明）
