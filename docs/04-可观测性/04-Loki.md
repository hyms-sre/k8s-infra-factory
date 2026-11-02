# Loki

## 定位

"为日志设计的 Prometheus"：只索引 label 不索引全文 → 存储便宜、写入快；
查询用 LogQL（配合 label 过滤 + 全文正则）。与 Grafana 原生集成。

## 架构与采集

- 组件：distributor → ingester（内存+wal）→ store（对象存储/文件）；单机模式小环境够用
- 采集端：**Promtail**（DaemonSet，自动发现 Pod 日志路径）或新一代 **Alloy**
- label 设计（重要）：`namespace / pod / app` 等低基数 label；**禁止**把 pod 名/用户 ID 做独立 label（基数爆炸）

## LogQL

```logql
{namespace="prod", app="api"} |= "ERROR"                       # 过滤
{app="api"} | json | status >= 500                              # json 解析
sum by (pod) (rate({app="api"} |= "ERROR" [5m]))                # 指标化
```

## 保留与容量

- 保留期 compactor 配置（如 30d）；小环境单副本 + 文件存储即可
- 高可用/大容量：对象存储（MinIO）+读写分离部署

## 部署（本项目）

k8s-plugins/observability/loki：helm（单机模式）+ Promtail DaemonSet；
cn 环境镜像预拉取（ghcr 走 Harbor）。
