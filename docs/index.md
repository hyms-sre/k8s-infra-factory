# iac-k8s-esxi 知识库

> **vSphere Kubernetes IaC / Environment Generator** —— 用
> `Terraform + Python + Cloud-Init + kubeadm` 从 0 构建可反复重建的 Kubernetes 环境。

本站是 iac-k8s-esxi 的配套知识库：既讲**这个项目怎么用**，也讲**它背后的技术**。

## 两条入门路径

| 你是 | 走这条 |
|---|---|
| **想系统学** | 🎯 [14-体系学习](14-体系学习/index.md) —— 六阶段路径，每阶段有前置条件、动手实验、检查点 |
| **想快点用起来** | 🚀 [00-引言/04-快速开始](00-引言/04-快速开始.md) —— 从 0 到 VM 就绪 |
| **想先搞清栈是什么** | 🧭 [00-引言/06-技术栈](00-引言/06-技术栈.md) —— 分层选型权威表 |

## 分类导航

| 分类 | 内容 |
|---|---|
| [00 引言](00-引言/index.md) | 项目是什么、整体架构、核心工具、快速开始、学习路线、技术栈 |
| [01 Terraform](01-Terraform/index.md) | 从 0 学 IaC：HCL、Provider、State、`for_each`、`templatefile` |
| [02 Kubernetes](02-Kubernetes/index.md) | 从 0 到 1 学 K8s + 本项目 kubeadm 集群引导实践 |
| [03 CI/CD](03-CI-CD/index.md) | Jenkins / GitLab Runner / Tekton 与完整流水线 |
| [04 可观测性](04-可观测性/index.md) | Prometheus / Grafana / Loki / OTel 监控日志告警 |
| [05 GitOps](05-GitOps/index.md) | GitOps 原则、ArgoCD、Flux、渐进交付 |
| [06 安全](06-安全/index.md) | RBAC、NetworkPolicy、镜像供应链、Kyverno、PKI |
| [07 存储](07-存储/index.md) | CSI、NFS、Longhorn、备份恢复 |
| [08 数据库](08-数据库/index.md) | MySQL/PG/Redis/ES/Kafka 的 K8s 落地与 HA |
| [09 平台工程](09-Platform-Engineering/index.md) | IDP、Golden Path、多租户、环境管理 |
| [10 AI-Ops](10-AI-Ops/index.md) | SRE+AI、LLM Agent、安全执行（体系先行） |
| [11 SRE](11-SRE/index.md) | SLI/SLO/Error Budget、事件管理、灾备演练 |
| [12 云平台](12-云平台/index.md) | vSphere 主线 + AWS/Aliyun 预留设计 |
| [13 实战场景](13-实战场景/index.md) | CN 网络环境、入口暴露、监控栈、小型生产 |
| [14 体系学习](14-体系学习/index.md) | **阶段化学习路径**：前置条件 → 目标 → 实验 → 检查点 → 自测 |
| [99 参考](99-参考/index.md) | 文件/凭据/配置/版本矩阵/排障/FAQ/术语/命令 |

## 核心数据流

```
cluster.yaml  →  generate.py  →  vm.tf (for_each)  →  terraform apply
      →  vSphere VM × N  →  Cloud-Init  →  kubeadm-ready
      →  kubeadm init / join  →  Kubernetes  →  k8s-plugins
```

## 常用入口

- 遇到问题 → [99-参考/05-故障排查](99-参考/05-故障排查.md)
- 查命令 → [99-参考/08-命令参考](99-参考/08-命令参考.md)
- 查版本 → [99-参考/04-版本矩阵](99-参考/04-版本矩阵.md)
- 国内网络方案 → [13-实战场景/02-CN网络环境](13-实战场景/02-CN网络环境.md)
