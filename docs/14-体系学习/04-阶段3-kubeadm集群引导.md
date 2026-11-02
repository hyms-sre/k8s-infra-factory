# 阶段 3 — kubeadm 集群引导

## 前置条件

- 阶段 2 检查点全部通过（节点已到 kubeadm-ready）
- 至少 1 台控制面 + 1 台 worker 可以 SSH

## 学习目标

1. `kubeadm init` 到底做了什么？为什么它能"一条命令建集群"？
2. 为什么 CNI 不装完，节点会一直 `NotReady`？这是 bug 还是设计？
3. worker 是怎么加入集群的？token 过期了怎么办？
4. 集群坏了，怎么"推倒重建"？

## 核心概念

### 1. kubeadm 做了什么

`kubeadm init` 不是"安装"，而是**引导（bootstrap）**：

1. 生成集群证书（CA、apiserver、etcd…）
2. 生成 kubeconfig（admin / kubelet / controller-manager / scheduler）
3. 用**静态 Pod** 方式拉起控制面：`kube-apiserver` / `etcd` / `kube-scheduler` / `kube-controller-manager`
4. 装 CoreDNS、kube-proxy 等附加组件
5. 输出一条 `kubeadm join` 命令给 worker 用

> 关键理解：控制面是**静态 Pod**（由 kubelet 直接管，不走 API Server）。
> 这就是为什么"API Server 挂了还能修"。

### 2. 为什么节点会 NotReady

kubelet 起来后需要 **CNI 插件**才能给 Pod 分配网络。没有 CNI：

- 节点状态是 `NotReady`
- CoreDNS 卡在 `Pending`（因为它需要网络才能调度）

**这是正常现象，不是故障。** 装完 CNI（阶段 5 的 Cilium）后自动转 `Ready`。

> ⚠️ 很多人在这里以为集群建坏了，反复 `kubeadm reset`。其实只差一个 CNI。

### 3. 版本联动

`cluster.yaml` 里的 K8s 版本不是孤立的，它会联动：

| 联动项 | 由谁决定 |
|---|---|
| apt 源路径 | K8s 小版本 |
| `pause`（sandbox）镜像 | `K8S_CATALOG` 目录 |
| `crictl` 版本 | 同上 |

真值源在 `terraform/vsphere/generate.py` 的 `K8S_CATALOG`，
详见 [99-参考/04-版本矩阵](../99-参考/04-版本矩阵.md)。

> 校验命令：`kubeadm config images list --kubernetes-version=<完整版本>`

## 对应仓库文件 / 文档

| 位置 | 作用 |
|---|---|
| `docs/02-Kubernetes/07-kubeadm实践.md` | **本阶段主教材**，跟着做 |
| `terraform/vsphere/cluster.yaml` | `kubernetes` 段决定版本与参数 |
| `docs/99-参考/04-版本矩阵.md` | 版本联动真值表 |
| `docs/99-参考/05-故障排查.md` | 卡住时先查这里 |

## 动手实验

### 实验 1：手工引导一次（强烈建议）

**不要**一上来就用脚本。先手工做一遍，理解每一步：

```bash
# 控制面
sudo kubeadm init --control-plane-endpoint <VIP或IP> --pod-network-cidr 10.244.0.0/16

# 配置 kubectl（按 init 输出照做）
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes        # 预期: NotReady  ← 正常!
kubectl get pods -A      # 观察 CoreDNS 状态
```

### 实验 2：确认"NotReady 是正常的"

```bash
kubectl get nodes
kubectl describe node <控制面> | grep -A5 Conditions
```

找到 `NetworkUnavailable` 或 `Ready=False` 的原因，确认是 CNI 缺失。

### 实验 3：加入 worker

```bash
# 在控制面获取 join 命令
kubeadm token create --print-join-command

# 在 worker 执行输出的命令
```

### 实验 4（重要）：推倒重建

```bash
# 在节点上
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd ~/.kube
sudo systemctl restart containerd kubelet
```

然后重新 `init`。**能干净地重来，才算真掌握。**

## 检查点

- [ ] 能说出 `kubeadm init` 的 5 个主要动作
- [ ] 理解控制面是静态 Pod
- [ ] 知道 `NotReady` 通常只差 CNI，不是集群坏了
- [ ] 能自己生成 join 命令并成功加入 worker
- [ ] 能干净地 `reset` 并重新引导
- [ ] 能说出改 K8s 版本会联动哪些东西

## 常见坑

| 坑 | 现象 | 原因 / 解法 |
|---|---|---|
| 反复 reset | 一直 NotReady | 缺 CNI，不是集群坏了 |
| token 过期 | join 报 `token not found` | 重新 `kubeadm token create --print-join-command` |
| 端口不通 | init 卡住 | 检查控制面所需端口与防火墙 |
| 版本不匹配 | kubelet/kubeadm 版本不一致 | 用版本矩阵校验 |
| `pause` 镜像拉不到 | 沙箱创建失败 | 检查 containerd 的 `sandbox_image` 与镜像源 |
| 时间不同步 | 证书校验失败 | 确认 NTP 正常 |

## 下一步

→ [阶段 4 — CN 网络环境与镜像仓库](05-阶段4-CN网络与镜像仓库.md)
（直连公网环境可跳到 [阶段 5](06-阶段5-平台插件与能力扩展.md)）
