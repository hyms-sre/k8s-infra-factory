# Aliyun（预留设计，未实现）

> 当前状态：只有本 README。正式实现前请以 terraform/vsphere 的结构为蓝本。

## 未来范围

| 层 | 阿里云对应物 | 说明 |
|---|---|---|
| 网络 | VPC / vSwitch / 安全组 | 对应端口组/路由 |
| 计算 | ECS | user-data 支持 cloud-init（阿里云镜像内置）|
| 集群 | ACK 或 自建 kubeadm | 自建可复用 generate.py + cloud-init 全链路 |
| 存储 | 云盘 ESSD / NAS / OSS | 数据盘/共享存储/备份对象存储 |
| 身份 | RAM 角色 | 替代静态 AK/SK |

## 与 cn 方案的关系

阿里云上通常不再需要 OpenWrt/Harbor（云内网到镜像服务快），cn profile 的
apt/镜像源配置仍然适用；`terraform/aliyun` 实现时应允许关闭 harbor 段。

## 设计约定

同 docs/12-云平台/02-AWS.md 的"设计约定"。
