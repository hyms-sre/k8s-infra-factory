# kubeadm 实践（本项目的集群引导）

Cloud-Init 完成后节点已是 kubeadm-ready。本篇是集群引导的完整命令，实测可复现。

## 1. kubeadm init（master 上）

```bash
kubeadm init \
  --image-repository=registry.aliyuncs.com/google_containers \  # cn; 海外 registry.k8s.io
  --apiserver-advertise-address=<master-ip> \
  --pod-network-cidr=10.244.0.0/16 \    # = cluster.yaml 的 kubernetes.pod_cidr
  --service-cidr=10.96.0.0/12 \
  --node-name=$(hostname)
# 期望: "Your Kubernetes control-plane has initialized successfully."
```

init 做了什么：预检 → 生成 CA/证书 → 写静态 Pod 清单（/etc/kubernetes/manifests）→
起 etcd/apiserver/scheduler/cm → 生成 bootstrap token 与 admin.conf。

## 2. kubeconfig

```bash
mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl get nodes      # NotReady (还没装 CNI)
# 集群外控制机: scp master:/etc/kubernetes/admin.conf ~/.kube/config
```

## 3. kubeadm join（worker 上）

```bash
# master 上生成 (token 24h 有效):
kubeadm token create --print-join-command
# worker 上执行:
sudo <join命令> --node-name=$(hostname)
```

join 过程：token 认证 → 下载 CA 公钥校验 → 签发 kubelet 证书 → kubelet 注册节点。
高可用控制面：init 时加 `--control-plane-endpoint=<VIP:6443>`，其余 master 用
`kubeadm join ... --control-plane` 加入。

## 4. 升级

```bash
# 每个节点 (先 drain):
apt-get install -y kubeadm=1.37.x-1.1 && kubeadm upgrade plan && kubeadm upgrade apply v1.37.x
kubectl drain <node> --ignore-daemonsets && apt-get install -y kubelet=1.37.x-1.1 kubectl=1.37.x-1.1 && kubeadm upgrade node
kubectl uncordon <node>
```

小版本升级走 cluster.yaml 改 version → generate → apply（重建 VM）也可以——
实验环境更简单；生产用原地升级。注意 kubelet/kubeadm/kubectl 被 apt-mark hold。

## 5. 备份 / 恢复

- **etcd 快照**（最重要）：
  `etcdctl snapshot save /backup/etcd.db --endpoints=... --cacert=... --cert=... --key=...`
  恢复：`etcdctl snapshot restore` 后用新 data-dir 重启 etcd/static pods
- 证书备份：`/etc/kubernetes/pki` + admin.conf
- 应用层数据：StorageClass/PVC 由存储插件负责（Longhorn 自带备份，见 docs/07-存储）

## 6. 排障

| 现象 | 处理 |
|---|---|
| join token 失效 | master 重新 `kubeadm token create --print-join-command` |
| 节点 NotReady | CNI 未装/未就绪: `kubectl -n kube-system get pods` |
| init 卡 preflight | swap/containerd/内核参数 → 查 Cloud-Init 是否 done |
| 证书过期 | `kubeadm certs check-expiration` / `kubeadm certs renew all` |
| 拉镜像超时 (cn) | 预拉取+tag 或 Harbor → docs/13-实战场景/02 |
