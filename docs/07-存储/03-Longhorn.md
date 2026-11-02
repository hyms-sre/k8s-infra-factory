# Longhorn

## 定位

Rancher 开源的分布式块存储：聚合**每个节点的本地数据盘**，提供
副本化 PVC、快照、备份（到 S3/NFS）、UI。是"VM 里挂了数据盘"场景的天然方案
——本项目节点数据盘统一挂 /var/lib/longhorn。

## 部署（k8s-plugins/storage/longhorn）

前置（本项目 Cloud-Init 已备）：open-iscsi（iscsid 启用）+ 每节点数据盘 + socat/conntrack。

```bash
kubectl apply -f longhorn.yaml     # 或 helm install longhorn longhorn/longhorn
kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=900s
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## 关键配置

- **副本数**：默认 3；3 节点以下建议 2（要改 StorageClass 的 numberOfReplicas）
- 节点数据盘：Longhorn UI → Node → 添加 disk 指向 /var/lib/longhorn
- 备份目标：UI 设置 backup-target（s3://minio:9000/bucket 或 nfs://...）
- Volume Attachment 需要节点间 9500-9504 等端口互通

## 日常

```bash
kubectl -n longhorn-system get pods          # manager/instance-manager/driver
kubectl get pvc,volumes.rook.io 2>/dev/null  # 卷状态
```

- 快照（即时，留本节点）vs 备份（写远端对象存储）——容灾必须用备份
- 单节点集群：副本只能 1，无冗余——Longhorn 的价值在 ≥2 节点
