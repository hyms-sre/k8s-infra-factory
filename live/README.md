# live/ — 环境组织

live/ 不是核心 Terraform 源代码库（核心在 `terraform/`），用于：

- **本地实验环境**的实际配置记录（lab）
- **实际环境**的分层组织与长期参考（prod）
- 每个环境按层拆分：networking（网络）→ cluster（Kubernetes）→ platform（平台组件）→ apps（业务应用）

```
live/
├── lab/vsphere/
│   ├── default/    # 海外直连网络环境
│   └── cn/         # 中国网络环境 (networking → openwrt → harbor → cluster → platform → apps)
└── prod/vsphere/   # 生产参考结构
```

使用方式：把对应环境的 cluster.yaml 变体复制到 `terraform/vsphere/cluster.yaml`
后执行 `python generate.py`；环境级凭据永远不进 Git（见 docs/99-参考/02-凭据说明）。
