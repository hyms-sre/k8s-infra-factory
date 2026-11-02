# cluster — Kubernetes 层 (cn)

cn 变体集群定义（国内源 + Harbor 启用）：

```bash
cp live/lab/vsphere/cn/cluster/cluster.yaml.example terraform/vsphere/cluster.yaml
# 编辑 harbor.host / harbor.ip / network 为实际值
cd terraform/vsphere && python generate.py && terraform apply
```
