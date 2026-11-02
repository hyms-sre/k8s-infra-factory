# 存储基础与 CSI

## 三种存储形态

| 形态 | 特点 | K8s 访问模式 | 典型 |
|---|---|---|---|
| Block（块） | 低延迟、单挂载 | RWO | Longhorn/Ceph RBD/云盘 |
| File（文件） | 共享、POSIX | RWX | NFS/CephFS |
| Object（对象） | 海量、HTTP API | S3 协议访问 | MinIO/Ceph RGW/OSS/S3 |

## K8s 存储对象速记

```
StorageClass = 动态供给模板 (provisioner + 参数)
PVC = 用户申请 (容量/SC/访问模式)
PV = 实际卷 (动态创建或静态手工)
CSI 驱动 = 实现"供给/挂载/快照"标准接口的存储插件
```

CSI 三阶段：Provision（CreateVolume）→ Attach（ControllerPublish）→ Mount（NodePublish）。
快照能力也是 CSI 标准接口（VolumeSnapshot CRD）。

## 选择决策

1. 单读写数据库类 → RWO 块存储（Longhorn）
2. 多 Pod 共享文件（配置/媒体/共享目录）→ RWX 文件（NFS）
3. 备份/静态资源/日志归档 → 对象存储（MinIO）
4. 无状态应用 → 不要 PVC
