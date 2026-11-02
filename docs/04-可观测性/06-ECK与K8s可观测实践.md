# ECK 与 K8s 可观测实践

## ECK (Elastic Cloud on Kubernetes)

Elastic 官方 Operator：用 CR 声明式管理 Elasticsearch/Kibana/Agent 全栈。

```yaml
kind: Elasticsearch
spec: {version: 8.x, nodeSets: [{name: masters, count: 3, config: {node.roles: [master, data]}}]}
---
kind: Kibana
spec: {version: 8.x, count: 1, elasticsearchRef: {name: es}}
```

- 自带 TLS/凭据生成（ Secret 引用）、滚动升级、扩缩容
- 代价：重（JVM 栈），小集群慎用；资源规划 ≥ 3C/8G 起步

## ELK vs Loki（选型）

| 维度 | ELK/ECK | Loki |
|---|---|---|
| 索引 | 全文倒排（查询强、成本高） | 仅 label（便宜、查询受 label 设计约束） |
| 运维 | 重（JVM/分片） | 轻 |
| 适用 | 需要复杂全文检索/安全分析 | 常规排障日志 |

## 本项目实践清单

1. 基础三件套：kube-prometheus-stack（Prometheus+Grafana+Alertmanager）
2. 日志：Loki + Promtail（DaemonSet）
3. 节点面板：node-exporter-full；集群面板：kube-prometheus 内置
4. 告警通道：Alertmanager → 企业 webhook（凭据入 Secret）
5. ES 需求（全文检索/审计）才上 ECK：k8s-plugins/observability/eck
6. cn 环境：全部镜像预拉取或走 Harbor；trivy/grafana 等注意 ghcr 阻断问题
