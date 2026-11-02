# 阶段 2 — 主机初始化与 Cloud-Init

## 前置条件

- 阶段 1 检查点全部通过
- 有一个可用的 Ubuntu 24.04 Cloud Image 模板（见 [12-云平台](../12-云平台/index.md)）
- 能 `terraform apply` 真正建出 VM

## 学习目标

1. VM 从"裸系统盘"到"kubeadm-ready"之间发生了什么？
2. Cloud-Init 的 **数据源（datasource）** 是什么？本项目怎么把配置喂给它？
3. 为什么"装到 kubeadm-ready 就停"，而不顺手把集群也建了？
4. `user-data.yaml.tpl` 和 `meta-data.yaml.tpl` 各管什么？

## 核心概念

### 1. Cloud-Init 是什么

Ubuntu Cloud Image 是"半成品系统盘"：**没有**用户名密码、**没有**网络配置，首启时由 Cloud-Init 读取外部配置完成初始化。

配置来源叫 **datasource**。常见的有 NoCloud（ISO/目录）、EC2 metadata 等。

### 2. 本项目用的数据源：VMware guestinfo

vSphere 环境下，Cloud-Init 可以读 **VMware 的 guestinfo 键值**。
Terraform 把两个文件 base64 编码后塞进 VM 的 `extra_config`：

```
guestinfo.metadata     ← meta-data.yaml.tpl  (网络: IP/网关/DNS)
guestinfo.userdata     ← user-data.yaml.tpl  (要做的事)
```

这样**不需要额外挂 ISO 或跑 DHCP**，静态 IP 也能首启就配好。

### 3. 两个模板的分工

| 模板 | 管什么 | 典型内容 |
|---|---|---|
| `meta-data.yaml.tpl` | **这台机器是谁、在哪** | 主机名、静态 IP、网关、DNS |
| `user-data.yaml.tpl` | **这台机器要变成什么样** | 用户、SSH 公钥、装包、写文件、跑命令 |

**边界很重要**：网络配置放 meta-data，软件安装放 user-data。混放会导致难排查。

### 4. 为什么停在 kubeadm-ready

Cloud-Init 负责"把机器准备好"：
- 建用户、注入 SSH 公钥、配 sudo
- 关 swap、加载内核模块、设 sysctl（K8s 必需）
- 装 `containerd`、`kubeadm`、`kubelet`、`kubectl`、`helm`、`nerdctl`
- 预置镜像加速配置

**不负责** `kubeadm init`。因为：
- 集群引导是**一次性、有顺序**的动作（先控制面、后 worker）
- 把它塞进 Cloud-Init 会让"重建单台节点"变成"可能意外重建集群"
- 分层后，节点初始化可重复，集群引导可控

> 这就是本项目"**节点生成器 + 集群引导分离**"的设计理由。

## 对应仓库文件

| 文件 | 作用 |
|---|---|
| `terraform/vsphere/meta-data.yaml.tpl` | 网络与主机名模板 |
| `terraform/vsphere/user-data.yaml.tpl` | 初始化脚本模板（用户/SSH/装包/sysctl） |
| `terraform/vsphere/main.tf` | 把两个模板 base64 后写入 `guestinfo.*` |
| `terraform/vsphere/cluster.yaml` | `os` / `ssh` / `tools` 段决定装什么 |

## 动手实验

### 实验 1：看模板怎么被喂进去

```bash
grep -n -A12 "extra_config" terraform/vsphere/main.tf
```

找到 `guestinfo.userdata` 与 `guestinfo.metadata`，确认它们来自哪个模板文件。

### 实验 2：起一台 VM 并观察首启

```bash
cd terraform/vsphere
terraform apply            # 真建 VM
ssh <user>@<节点IP>        # 等 Cloud-Init 跑完（可能几分钟）
```

在节点上验证：

```bash
cloud-init status --long          # 应显示 done
kubeadm version                   # 应有输出
systemctl is-active containerd    # 应 active
free -h                           # 确认 swap 已关（Swap 行为 0）
lsmod | grep -E "overlay|br_netfilter"
sysctl net.ipv4.ip_forward        # 应为 1
```

### 实验 3：验证 SSH 公钥注入

```bash
cat ~/.ssh/authorized_keys        # 应包含 cluster.yaml 里配的公钥
```

### 实验 4：故意改坏一次

把 `cluster.yaml` 里某个节点的 DNS 改成不可用的地址，重建该 VM，观察：

- `cloud-init status` 会不会失败？
- DNS 不通会影响哪些后续步骤？

改回来。**理解"网络配错"的爆炸半径。**

## 检查点

- [ ] 能画出 `cluster.yaml → 模板 → guestinfo → Cloud-Init → kubeadm-ready` 的链路
- [ ] 能说清 `meta-data` 与 `user-data` 的职责边界
- [ ] 新 VM 上 `cloud-init status` 为 `done`
- [ ] `containerd` active、`kubeadm version` 有输出
- [ ] swap 已关闭、`overlay`/`br_netfilter` 已加载
- [ ] 能解释"为什么不在 Cloud-Init 里 `kubeadm init`"

## 常见坑

| 坑 | 现象 | 原因 / 解法 |
|---|---|---|
| Cloud-Init 没执行 | `cloud-init status` 报错或无 datasource | 检查 `guestinfo.*` 是否写入、模板是否渲染成功 |
| YAML 缩进错 | Cloud-Init 静默跳过部分配置 | 模板是 YAML，缩进敏感；改完先本地渲染检查 |
| swap 没关 | kubelet 启动失败 | 检查 `user-data` 里的 swapoff 与 fstab 注释 |
| SSH 进不去 | 公钥没注入 | 确认 `cluster.yaml` 的 `ssh` 段 |
| 静态 IP 没生效 | 节点不通 | 检查 `meta-data` 的 IP/网关/DNS 与网段是否匹配 |
| 改了模板没生效 | 配置还是旧的 | 模板改动需要重新 `apply`（会重建 VM） |

## 下一步

→ [阶段 3 — kubeadm 集群引导](04-阶段3-kubeadm集群引导.md)
