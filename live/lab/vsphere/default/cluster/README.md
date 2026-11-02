# cluster — Kubernetes 层 (default)

1. 复制集群定义：本目录的 `cluster.yaml.example` → `terraform/vsphere/cluster.yaml`
2. `cd terraform/vsphere && python generate.py && terraform apply`
3. 引导集群：docs/02-Kubernetes/07-kubeadm实践.md
