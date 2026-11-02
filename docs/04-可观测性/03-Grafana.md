# Grafana

## 定位

统一可视化层：对接 Prometheus/Loki/Tempo/ES 等任意数据源，Dashboard + 告警 + 权限。

## 关键实践

- **Dashboard as Code**：dashboard JSON 入 Git，经 Grafana provisioning 或 GitOps 同步
- 社区面板起步（node-exporter-full、K8s cluster overview）再定制
- 分层导航：全局健康 → 集群 → namespace → 应用
- 告警统一：Alertmanager 为主，Grafana Alerting 适合临时/多源场景
- 匿名只读 + 管理员凭据入 Secret；暴露方式 MetalLB LoadBalancer 或 Gateway API

## 常用数据源配置

```yaml
apiVersion: 1
datasources:
- {name: prometheus, type: prometheus, url: http://prometheus:9090, isDefault: true}
- {name: loki, type: loki, url: http://loki:3100}
```

Grafana 与 Loki 联动：日志面板从指标图"Explore from here"直接下钻。
