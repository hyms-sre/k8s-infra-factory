# TIMELINE — test-cjl-k8s01 全程部署耗时记录

> 记录规则：每一步动作的时间戳、动作、结果、耗时。时区 Asia/Shanghai (UTC+8)。
> 环境探测/旧方案验证阶段（00:55-03:00）为前期可行性工作；正式部署从 03:20 配置清单批准起算。

## 阶段 0：规划与环境确认（00:55 – 03:20，约 2.5h）

| 时间 | 动作 | 结果/耗时 |
|---|---|---|
| 00:55 | 任务开始，抓取教程，确认 vCenter/模板/网络 | — |
| 01:00 | 安装 Terraform 1.9.8 + govc 0.30.7（Windows） | 5 min |
| 01:05 | 环境探测：CJL 数据中心、2×ESXi、date01 存储、VM Network、noble 模板（pvscsi/vmxnet3） | 5 min |
| 01:10-02:00 | 首轮 4VM 集群（教程默认拓扑）跑通 Terraform + cloud-init | 50 min |
| 02:00-02:45 | **国内镜像攻坚**：registry.k8s.io/docker.io 被墙；逐源实测（daocloud 403→全引用可用、1ms.run 可用、aliyun google_containers 可用、certs.d mirror 不兼容→确定"全引用拉取+tag"方案） | 45 min |
| 02:30 | v1.33 单 master 集群 + Cilium 跑通（验证中转方案） | — |
| 02:50 | **方案重定**：1 master + 3 worker + Harbor(.207) + OpenWrt(.210)，基础设施先行，Cilium + Envoy Gateway，无 Ansible 纯 Shell 编排 | — |
| 03:00 | 销毁旧 4VM；清理被中断 apply 的孤儿 VM（7 台，govc 转义路径） | 15 min |
| 03:10 | OpenWrt vmdk 制作方法验证（img.gz→zcat→truncate→qemu-img streamOptimized） | 10 min |
| **03:20** | **配置清单 v1.6 批准，正式部署开始** | **T0** |

## 阶段 A：基础设施（03:20 – 04:10，约 50 min）

| 时间 | 动作 | 结果/耗时 |
|---|---|---|
| 03:22 | Terraform apply：5 台 VM 新规格（4C4G/4C8G master+worker、4C4G harbor） | 2m45s 并行 |
| 03:30 | OpenWrt 40G vmdk 制作（worker-01 上 qemu-utils） | 5 min |
| 03:32 | OpenWrt 磁盘上传+VM 创建（import.vmdk 踩坑：datastore.upload 的裸 vmdk 不可挂载；名字 `[]` 需转义） | 8 min |
| 03:35 | 全项目脚本+工件分发到 master-01 /opt/iac；harbor 离线包 617MB 直传 harbor VM | 5 min |
| 03:45 | OpenWrt 配置：临时二级 IP 192.168.1.254 → 出厂 192.168.1.1 → 静态 .210/关 DHCP/root 密码/opkg 阿里云源 | 10 min |
| 03:55 | dnsmasq-full 替换 + 本地域 DNS（harbor.yjscloud.local→.207）验证通过 | 5 min |
| 04:00 | OpenClash 0.47.156 安装（ipk 需从 GitHub Releases 正式资产下载，master 分支 raw 是 HTML 404） | 5 min |
| 04:05 | OpenWrt 开启 lan forward + ip_forward；Harbor 网关切 .210 实测出海链路 | 3 min |
| 04:08 | **OpenWrt 完成**（订阅留空 → 记入 Manual Action Required） | — |

## 阶段 B：Harbor（04:10 – 04:40，约 30 min）

| 时间 | 动作 | 结果/耗时 |
|---|---|---|
| 04:10 | Harbor 脚本：数据盘、docker 29.1.3、解压离线包、harbor.yml | 10 min |
| 04:20 | 踩坑×3：/dev/sdb 已被 userdata 挂载（改用 /var/lib/longhorn 做 data_volume）；install.sh 需 bash；需 docker-compose shim（docker-compose-v2） | 15 min |
| 04:25 | harbor.yml 手写精简版缺字段启动失败 → 改用官方 tmpl 逐行补丁 | 5 min |
| 04:35 | **Harbor 安装成功**：10 容器全部 healthy，HTTP 200 | 3 min |
| 04:38 | Proxy Cache 项目创建 → 500 "registry is unhealthy"（docker hub 被墙健康检查失败）→ **按设计进入 MANUAL ACTION REQUIRED**（等 OpenClash 订阅后 `make resume` 补齐） | — |

## 阶段 C：K8s 集群（04:40 – 06:25，约 1h45m）

| 时间 | 动作 | 结果/耗时 |
|---|---|---|
| 04:45 | OS 初始化（4 节点并行）：apt 阿里云、内核参数、hosts、Longhorn 数据盘、k 别名 | 6 min |
| 04:52 | 客户端工具：crictl 1.33 / nerdctl 2.0.4 / helm 3.17.3 + 全套 bash 补全（`k` 别名验证 `type k` OK） | 5 min |
| 05:00 | containerd 2.2.1 + kubeadm/kubelet/kubectl **v1.36.4**（阿里云源）；sandbox→阿里云；节点 certs.d 映射 Harbor | 8 min |
| 05:10 | `kubeadm init`（--image-repository=阿里云）成功 | 3 min |
| 05:15 | 预拉 pause:3.10.1 到 workers（daocloud k8s 中转）| 5 min |
| 05:22 | 3 workers `kubeadm join` 全部成功（4/4 节点，NotReady 待 CNI） | 4 min |
| 05:30 | Cilium v1.17.0：3 镜像 × 4 节点 daocloud 预拉取 + tag | 12 min |
| 05:42 | `cilium install`（KPR=false + Hubble）；cilium/cilium-envoy DS 4/4 就绪，**节点全部 Ready** | 5 min |
| 05:50 | MetalLB v0.14.9（本地 manifest + 镜像预拉取）；踩坑：L2Advertisement 是 **v1beta1** 非 v1beta2；CRD 后 kubectl 需清 ~/.kube/cache | 10 min |
| 06:00 | Envoy Gateway v1.5.0：CRD 大注解超限→`--server-side` apply；数据面镜像 distroless-v1.35.0 预拉取；GatewayClass 需手工创建（Accepted）；**lab-gw Programmed，数据面 LB=.212** | 15 min |
| 06:10 | Longhorn v1.9.1：13 镜像 1ms.run 预拉取；27 pods 全 Running；StorageClass longhorn 设默认；PVC 测试 Bound | 8 min |
| 06:15 | Headlamp：ghcr 全被阻断 → **Windows 侧 crane 拉取 v0.45.0** → OCI tar 分发 ctr import；LB 固定 .211（headlamp-pool 与 lab-pool 重叠→lab-pool 改 .212-.220） | 8 min |

## 阶段 D：验收（06:10 – 06:25，约 15 min）

| 时间 | 动作 | 结果/耗时 |
|---|---|---|
| 06:10 | 验收脚本 v1：18/25 通过（DNS 用短名测法错误、pod-to-pod 引号 bug、harbor 检查引号） | 5 min |
| 06:15 | 逐项排查：**CoreDNS 实际健康**（busybox nslookup 不走 search 域名导致误报；FQDN 解析 OK、ClusterIP HTTP OK）| 5 min |
| 06:20 | 验收脚本 v2（复杂检查拆独立脚本文件） | 5 min |
| 06:24 | **最终验收：27 通过 / 1 失败**（唯一失败 = Harbor Proxy 项目，等待 OpenClash 订阅，预期内） | — |

## 总耗时

| 阶段 | 耗时 |
|---|---|
| 前期规划/环境确认/方案验证 | ~2.5 h |
| A 基础设施（VM+OpenWrt） | ~50 min |
| B Harbor | ~30 min |
| C K8s 集群+Addons | ~1h45m |
| D 验收+文档 | ~40 min |
| **正式部署（T0 起）合计** | **约 3h45m** |
