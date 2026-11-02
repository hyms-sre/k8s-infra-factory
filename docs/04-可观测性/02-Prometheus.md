# Prometheus

## 架构

拉模型：Prometheus 定时抓取 targets 的 /metrics → 本地 TSDB → PromQL 查询 →
Grafana 展示 / Alertmanager 告警。

- **抓取发现**：K8s 场景用 `kubernetes_sd_configs`（按 Service/Pod 注解自动发现）
- **exporter**：node-exporter（节点）、kube-state-metrics（对象）、黑盒（blackbox）、应用自曝 /metrics
- **长期存储**：本地仅保 15 天左右；长期 → Thanos / VictoriaMetrics 远端写入

## PromQL 入门

```promql
rate(http_requests_total[5m])                     # 速率
sum by (pod) (rate(...[5m]))                      # 聚合
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_bucket[5m])))  # P95
up == 0                                           # 目标失联
kube_pod_status_phase{phase="Running"}            # K8s 对象状态
```

## 告警规则与 Alertmanager

```yaml
groups:
- rules:
  - alert: NodeDown
    expr: up{job="node"} == 0
    for: 5m
    labels: {severity: critical}
```

Alertmanager：分组/去重/静默/路由（邮件/webhook/钉钉企微）。

## 部署（本项目）

k8s-plugins/observability/prometheus：推荐 kube-prometheus-stack helm chart
（含 operator/CRD: Prometheus/ServiceMonitor/PodMonitor/Alertmanager/PrometheusRule），
指标用 ServiceMonitor CR 声明式接入。cn 环境镜像走 Harbor（docs/13-实战场景/02）。
