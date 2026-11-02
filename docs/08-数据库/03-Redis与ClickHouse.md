# Redis 与 ClickHouse

## Redis

- 缓存/会话/队列（轻量）。模式：单机（可丢）→ Sentinel（主从+哨兵）→ Cluster（分片）
- K8s 落地：

```bash
helm install redis bitnami/redis --set architecture=replication \
  --set auth.password=...          # 或 masterhost/sentinel 模式
```

- 缓存类可接受重启丢数据 → 用 emptyDir/PVC 都行；持久队列必须 AOF + PVC
- 指标：redis_exporter；内存上限必须设置（maxmemory + 淘汰策略），防 OOM 连坐

## ClickHouse

- OLAP 列式库（日志分析/用户行为）。官方 clickhouse-operator 或 Altinity operator
- K8s 落地要点：
  - ClickHouseInstallation CR：分片 (shards) × 副本 (replicas) 拓扑声明式定义
  - 每实例独立 PVC，本地 NVMe 优先；ZooKeeper/ClickHouse Keeper 3 节点
  - 数据量大：查询层 (clickhouse-server) 与存储分离，或接对象存储 (S3 disk)
- 替代考虑：中小规模日志/指标分析，Loki+Prometheus 已够（运维成本低一个数量级）
