# K8s 安全与 RBAC

## 安全四 C 模型（由外到内）

**Cloud/Cluster/Container/Code** —— 每层都要防，单层失守不应导致全盘失守。

## 认证 (Authentication)

- 人：x509 客户端证书（admin.conf 即证书）、OIDC（接企业 SSO）
- 服务：ServiceAccount token（1.24+ 为短期投影 token）
- 节点：TLS bootstrapping（kubeadm join 用的 bootstrap token + CSR）

## 鉴权 (Authorization) 与 RBAC

- 默认鉴权器：RBAC + Node（kubelet 用）
- 四对象：Role/ClusterRole × RoleBinding/ClusterRoleBinding
- 实践：`kubectl auth whoami`、`kubectl auth can-i --list` 自查；
  最小权限；审计先用 `kubectl auth can-i` 模拟再授权

## 控制面安全

- API Server 端口（6443）不对公网；anonymous-auth 关闭评估
- etcd 对外隔离 + 加密 at rest（EncryptionConfiguration）
- kubelet 只读端口 10255 默认应关闭
- 本项目：控制面在私有网段，admin.conf 凭据纪律见 docs/99-参考/02

## 安全基线检查

- kube-bench（CIS Benchmark 自动检查）
- 控制面组件最小权限运行、证书轮换（kubeadm certs renew）
- 审计日志（audit policy → 后端存储）
