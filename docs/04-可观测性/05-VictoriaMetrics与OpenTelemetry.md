# VictoriaMetrics 与 OpenTelemetry

## VictoriaMetrics (VM)

Prometheus 兼容的高性能时序库：

- 存储压缩率高（同数据量磁盘约为 P 的 1/5~1/10）、写入/查询更快、运维更简单（单二进制）
- **vmagent** 替代 Prometheus 抓取（PromQL 兼容），**vmalert** 替代告警规则执行
- VictoriaLogs：同厂日志库（比 ES 便宜，与 VM 同生态）
- 选型：小团队自维护、长期存储成本敏感 → VM 系很值；生态集成优先 → Prometheus 栈

迁移路径：vmagent 抓取（完全兼容 relabel/service discovery）→ Grafana 数据源指向 VM。

## OpenTelemetry (OTel)

CNCF 的可观测性**标准**（不是存储/展示产品）：

- **OTel SDK/自动探针**：应用内产生 traces/metrics/logs
- **Collector**：接收 → 处理（采样/脱敏）→ 导出（后端无关）
- 核心价值：**应用代码与后端解耦**——换 Prometheus/Vendor 不改代码

```yaml
receivers: {otlp: {protocols: {grpc: {}}}}
exporters: {prometheus: {endpoint: "0.0.0.0:8889"}}
service: {pipelines: {traces: {receivers: [otlp], exporters: [jaeger]}}}
```

## 组合建议

| 需求 | 方案 |
|---|---|
| 起步 | Prometheus + Loki + Grafana（本项目默认） |
| 长期/大规模指标 | vmagent + VM |
| 微服务链路排障 | OTel SDK → Collector → Tempo/Jaeger |
