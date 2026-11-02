# Metrics Server

> 状态：**已实现并实测通过**（2026-10-19，集群 `test-cjl-k8s01` / K8s v1.36.4）

**定位**：为 `kubectl top` 与 HPA 提供资源指标（CPU / 内存）。

**版本**：`v0.9.0`（上游 2026-07 发布，基于 K8s 1.36.2 构建，与本集群 1.36.4 匹配）

**上游文档**：https://github.com/kubernetes-sigs/metrics-server

## 目录内容

| 文件 | 说明 |
|---|---|
| `components.yaml` | 上游 v0.9.0 官方清单 + **本集群所需的一处调整**（见下） |
| `README.md` | 本文 |

### 对上游清单的唯一改动

```yaml
- --kubelet-insecure-tls
```

**为什么加**：本集群 `kubelet` 的 `serverTLSBootstrap` 未开启（默认 `false`），
kubelet 服务证书是**自签**的。不加该参数，metrics-server 会因 x509 校验失败
拿不到指标，Pod 日志里会看到 `x509: cannot validate certificate`。

> 若后续改为启用 kubelet CSR 自动签发（`serverTLSBootstrap: true` + 批准 CSR），
> 可以移除该参数，安全性更好。

## 前置条件

1. 集群已就绪，`kubectl get nodes` 全部 `Ready`
2. **镜像可达**——本项目的 cn 方案依赖 Harbor Proxy Cache：
   - 节点 containerd 已配置 `/etc/containerd/certs.d/registry.k8s.io/hosts.toml`
   - 该文件把 `registry.k8s.io` 指向 Harbor 的 `k8s` 代理项目
3. **节点能解析 Harbor 域名**（`harbor.<你的域>`）

> ⚠️ **`.local` 域名的坑**：systemd-resolved 按 RFC 6762 把 `.local` 视为 mDNS 保留域，
> **不会**用单播 DNS 去查，直接查询会报
> `No appropriate name servers or networks for name found`。
> 因此节点上应保留 `/etc/hosts` 条目作为兜底：
>
> ```bash
> echo "172.16.222.207  harbor.yjscloud.local" | sudo tee -a /etc/hosts
> ```
>
> 这也是本项目文档里"DNS + /etc/hosts 双保险"的由来。

## 安装

### 方式 A：Harbor 正常时（推荐）

```bash
kubectl apply -f components.yaml
```

节点会经 Harbor 代理拉取 `registry.k8s.io/metrics-server/metrics-server:v0.9.0`。

### 方式 B：Harbor 不可用时（直连镜像站 + 重新打标签）

当 Harbor 的代理项目被标记 `unhealthy`（日志报
`current registry is unhealthy`）时，proxy pull 会返回 `not found`。
可临时绕过——从国内镜像站直接拉取，再打上原始标签，使清单无需改动：

```bash
# 在【每个】节点上执行
sudo crictl pull k8s.m.daocloud.io/metrics-server/metrics-server:v0.9.0
sudo ctr -n k8s.io images tag --force \
  k8s.m.daocloud.io/metrics-server/metrics-server:v0.9.0 \
  registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

> 清单里 `imagePullPolicy: IfNotPresent`，所以本地有同名镜像就不会再拉。
> 这是**应急手段**，Harbor 修好后建议删除本地镜像，回归 Proxy Cache 链路。

### 方式 C：完全离线

```bash
# 有网机器
crane pull registry.k8s.io/metrics-server/metrics-server:v0.9.0 metrics-server.tar

# 各节点
sudo ctr -n k8s.io images import metrics-server.tar
```

## 验证

```bash
# 1. Pod 就绪
kubectl -n kube-system get pods -l k8s-app=metrics-server

# 2. APIService 可用（关键）
kubectl get apiservice v1beta1.metrics.k8s.io
#   期望 AVAILABLE = True

# 3. 指标可用
kubectl top nodes
kubectl top pods -n kube-system
```

本集群实测输出：

```
NAME                       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
test-cjl-k8s01-master-01   129m         3%       2215Mi          58%
test-cjl-k8s01-worker-01   93m          2%       1784Mi          22%
test-cjl-k8s01-worker-02   220m         5%       1809Mi          23%
test-cjl-k8s01-worker-03   82m          2%       1983Mi          25%
```

> 首次 `kubectl top` 可能报 `error: Metrics API not available`，
> 这是指标尚未采集完成，等 30–60 秒再试（默认 `--metric-resolution=15s`）。

## 卸载

```bash
kubectl delete -f components.yaml
```

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| Pod `ImagePullBackOff` | 镜像拉不到 | 检查 Harbor 代理是否 healthy；或走方式 B |
| Pod Running 但 `top` 报错 | 证书校验失败 | 确认清单里有 `--kubelet-insecure-tls` |
| `Metrics API not available` | 采集未完成 | 等 30–60s；仍不行看 Pod 日志 |
| APIService `False` | 后端 Service 不通 | `kubectl describe apiservice v1beta1.metrics.k8s.io` |
| `x509: cannot validate certificate` | 缺 insecure-tls | 见上 |
| Harbor 报 `registry is unhealthy` | 代理上游健康检查失败 | 修 Harbor；或走方式 B |

查看日志：

```bash
kubectl -n kube-system logs -l k8s-app=metrics-server --tail=50
```

## 本集群实测记录（2026-10-19）

安装过程中遇到并绕过的环境问题，供后续复现参考：

| 问题 | 现象 | 处置 |
|---|---|---|
| 节点 DNS 指向公网 | `harbor.yjscloud.local` 无法解析 | 加 `/etc/hosts` 条目（见前置条件） |
| Harbor 服务未启动 | 443 拒绝连接 | 主机重启后 Harbor 未自启，`docker compose up -d` 拉起 |
| Harbor 代理全部 `unhealthy` | proxy pull 返回 `not found` | 走方式 B（直连镜像站 + 重打标签） |

> ⚠️ 注意：**不要把节点 DNS 直接指向 OpenWrt**。cn 方案下 OpenClash 返回 fake-ip
> （`198.18.x.x`），而节点流量并不经代理，会导致**外网完全不通**（实测
> `www.baidu.com` / `mirrors.aliyun.com` 全部超时）。节点 DNS 保持公网 DNS，
> 本地域用 `/etc/hosts` 兜底。
