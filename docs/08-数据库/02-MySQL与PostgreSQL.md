# MySQL 与 PostgreSQL

## MySQL

- Operator：Percona XtraDB Cluster Operator（Galera 多写）或 InnoDB Cluster (orchestrator)
- 单实例起步：

```bash
helm install mysql bitnami/mysql --set primary.persistence.size=50Gi \
  --set auth.rootPassword=$(openssl rand -hex 16)   # 凭据进 Secret
```

- 主从复制：StatefulSet + mysql 客户端配置 replica（简单场景 binlog 异步复制即可）

## PostgreSQL

- **CloudNativePG（推荐）**：CNCF 沙箱，同步复制/自动 failover/备份到 S3 开箱即用

```yaml
kind: Cluster                      # cnpg
spec:
  instances: 3                     # 1 主 2 同步副本
  storage: {size: 50Gi, storageClass: longhorn}
  backup: {barmanObjectStore: {destinationPath: s3://pg-backup}}
```

- 连接：Service 指向当前 primary（读写），replica Service 读；`-rw`/`-ro` 后缀自动维护

## 共同实践

- 参数调优进 ConfigMap/CR（shared_buffers/max_connections…）
- 大版本升级用 Operator 流程，禁止跳级
- 监控：postgres_exporter / mysqld_exporter 接 Prometheus（docs/04-可观测性）
- 慢查询日志 → Loki
