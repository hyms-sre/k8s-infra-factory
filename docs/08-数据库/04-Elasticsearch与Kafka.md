# Elasticsearch 与 Kafka

## Elasticsearch（ECK Operator）

```yaml
kind: Elasticsearch
spec:
  version: 8.15.0
  nodeSets:
  - {name: master, count: 3, config: {node.roles: [master]}, resources: {requests: {memory: 4Gi}}}
  - {name: data, count: 2, config: {node.roles: [data, ingest]}}
```

- 角色分离（master/data/ingest）是集群稳定的前提；master 3 节点防脑裂
- ILM 管理索引生命周期（热-温-冷-删除）；安全默认开启 TLS+用户
- 用途：全文检索/日志（重）；轻量日志需求优先 Loki（docs/04-可观测性/06 对比）

## Kafka（Strimzi Operator）

```yaml
kind: Kafka
spec:
  kafka: {replicas: 3, listeners: [{name: plain, port: 9092, type: internal}],
          storage: {type: persistent-claim, size: 200Gi}}
  zookeeper: {replicas: 3}          # 或 KRaft 模式免 ZK
```

- Strimzi 管：broker、Topic CR（`kind: KafkaTopic`）、User CR（SASL 凭据）、MirrorMaker2（跨集群）
- 副本因子 ≥ 2、min.insync.replicas=2 搭配 acks=all
- 资源大户：每 broker ≥ 2C/4G + 独立 PVC；小规模消息场景可先用 Redis Stream/NATS

## 通用运维

两者都是"有状态 + 重"的典型：务必 anti-affinity 打散、独立 StorageClass、
专门的备份方案（ES snapshot → 对象存储；Kafka 依赖多副本+镜像）。
