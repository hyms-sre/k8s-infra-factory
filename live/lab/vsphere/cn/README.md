# cn — 中国网络环境

CN 不是另一套 K8s Terraform，而是"中国网络环境优化方案"：

```
networking → openwrt (出口/DNS/NAT/代理) → harbor (镜像缓存/Proxy Cache)
          → cluster (Kubernetes, 优先从 Harbor 拉镜像) → platform → apps
```

三段基础设施相互独立：K8s Terraform 不得硬依赖 OpenWrt/Harbor
（没有它们集群也能部署，只是拉镜像可能不稳定）。
方案详解见 docs/13-实战场景/02-CN网络环境.md。
