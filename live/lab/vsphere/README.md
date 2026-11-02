# live/lab/vsphere — 实验环境 (vSphere)

| 目录 | 网络环境 | 部署顺序 |
|---|---|---|
| [default](default/) | 海外直连 | networking → cluster → platform → apps |
| [cn](cn/) | 中国网络 | networking → openwrt → harbor → cluster → platform → apps |

集群定义入口始终是 `terraform/vsphere/cluster.yaml` —— 本目录保存各环境变体与部署记录。
