# 在 K8s 上跑数据库

## 先想清楚：要不要

| 因素 | 倾向 K8s 内 | 倾向 K8s 外 (独立 VM/托管) |
|---|---|---|
| 团队 K8s 经验 | 深 | 浅 |
| 存储层 | 有副本化 PV（Longhorn/云盘） | 无把握 |
| 变更频率 | 高（随应用频繁发布） | 低（数据库求稳） |
| 规模 | 小中型 | 超大（专业 DBA + 专用机） |

## Operator 模式

数据库运维是状态机（选主/扩缩/备份/故障转移）→ 用 Operator 把知识编码：

```bash
kubectl apply -f https://.../postgres-operator.yaml   # 例如 CloudNativePG / Zalando
kubectl apply -f cluster.yaml                          # 声明一个 3 副本 PG 集群
```

Operator 负责：拉起 StatefulSet、配置流复制、故障自动切主、滚动升级、备份调度。
主流：CloudNativePG (PG)、Percona (MySQL/Mongo)、Strimzi (Kafka)、ECK (ES)。

## 通用基线（无论哪个数据库）

- **StorageClass 用块存储**（Longhorn RWO），副本数与数据库副本语义分开理解
- 资源必须设 requests/limits；连接数/内存参数按容器环境调
- anti-affinity 打散到不同节点；PVC `volumeBindingMode: WaitForFirstConsumer`
- 备份走两条腿：存储层快照 + 数据库逻辑导出
- 凭据 Secret + 轮换机制（docs/06-安全/03）
