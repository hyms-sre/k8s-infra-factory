# networking — 网络层 (default)

default 环境使用现有网络（网关/DNS 由机房提供），无额外网络基础设施。

配置入口：`terraform/vsphere/cluster.yaml` 的 `network` 段
（cidr / gateway / dns / ip_start）。
