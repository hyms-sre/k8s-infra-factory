# NFS

## 定位

最简单的 RWX 共享存储：一台 NFS server（独立 VM/群晖/云 NAS），K8s 挂载共享目录。
适合：共享配置、媒体文件、开发环境、多副本读密集负载。

## 部署

1. NFS server（可复用本项目的 Harbor VM 或独立 VM）：

```bash
apt install nfs-kernel-server
mkdir -p /export/k8s && echo '/export/k8s *(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports
exportfs -ra
```

2. 节点预装 nfs-common（本项目 Cloud-Init 已装）

3. 动态供给：nfs-subdir-external-provisioner（k8s-plugins/storage/nfs）：

```bash
helm install nfs-provisioner nfs-subdir-external-provisioner \
  --set nfs.server=<nfs-ip> --set nfs.path=/export/k8s \
  --set storageClass.name=nfs --set storageClass.defaultClass=false
```

## 注意

- 性能有限（网络文件系统），数据库等 I/O 密集不推荐
- `no_root_squash` 放宽安全，仅内网受控环境使用
- 单点 = NFS server；重要数据靠 server 侧备份（或改用 Longhorn RWX/CephFS）
