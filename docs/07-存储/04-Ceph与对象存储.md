# Ceph 与对象存储

## Ceph

统一存储（块 RBD + 文件 CephFS + 对象 RGW），生产级但**重**：每节点要求
OSD 盘 + 兆级内存 + 低延迟网络。K8s 上经 Rook 编排：

```yaml
kind: CephCluster          # rook-ceph
spec: {mon: {count: 3}, storage: {useAllDevices: false, devicePathFilter: ^/dev/sdc}}
```

选型建议：**≥3 个专用存储节点、有专人运维**才上 Ceph；
3-5 台小集群用 Longhorn 足够（docs/13-实战场景/07 有对比）。

## MinIO（对象存储）

S3 兼容，单二进制/容器即可跑，本项目用途：

- Longhorn/velero 的备份目标
- Loki 日志存储
- CI 制品缓存

```bash
helm install minio minio/minio --set mode=distributed --set replicas=4
```

生产：独立 VM 或 K8s 内 4+ 节点分布式模式 + 独立盘；凭据入 Secret。

## RustFS

新兴 Rust 实现的 S3 兼容对象存储（轻量、单二进制），可作为 MinIO 的轻量替代
（社区较新，生产采用需评估）。用法与 S3 生态一致：endpoint + ak/sk。

## 备份金字塔（对象存储的角色）

```
应用快照 (Longhorn snapshot)  →  节点级
Longhorn backup → MinIO       →  集群级异地
velero cluster backup → MinIO →  全集群恢复
```
