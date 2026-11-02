#!/bin/bash
# =============================================================================
# 00-env.sh — 公共环境库 (所有模块脚本 source 它)
# 位置: scripts/lib/00-env.sh  (共享层)
# 提供: 目录布局 / secrets 加载 / 节点清单 / 远程执行 / 状态标记(resume) / 镜像中转
# =============================================================================
set -euo pipefail

# 本文件位于 scripts/lib/, 故项目根在上两级
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- 目录布局 (模块化: 共享层 + examples/<模块>) ----------
EXAMPLES_DIR="${PROJECT_ROOT}/examples"
MODULE_OPENWRT="${EXAMPLES_DIR}/openwrt"      # 模块: 出口 / DNS / OpenClash
MODULE_HARBOR="${EXAMPLES_DIR}/harbor"        # 模块: 镜像仓库 (Harbor)
MODULE_K8S="${EXAMPLES_DIR}/kubernetes"       # 模块: K8s 集群
FILES_DIR="${PROJECT_ROOT}/files"             # 共享工件缓存 (预下载的镜像/安装包)

# 部署控制机 master-01 上的项目根 (仓库同步到此处)
REMOTE_ROOT="/opt/iac"
REMOTE_FILES="${REMOTE_ROOT}/files"

SECRETS_FILE="${PROJECT_ROOT}/secrets/secrets.env"
STATE_DIR="${REMOTE_ROOT}/state"     # master-01 上的断点标记目录
PROFILE="${PROFILE:-cn}"

# ---------- secrets (不进 Git) ----------
load_secrets() {
  if [ ! -f "$SECRETS_FILE" ]; then
    echo "[FATAL] 缺少 $SECRETS_FILE — 复制 secrets/secrets.env.example 并填写" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
}

# ---------- 节点清单 (与 examples/kubernetes/terraform.tfvars 同步) ----------
MASTER_IP=172.16.222.201
WORKER_IPS=(172.16.222.202 172.16.222.203 172.16.222.204)
HARBOR_IP=172.16.222.207
OPENWRT_IP=172.16.222.210
ALL_K8S_IPS=("$MASTER_IP" "${WORKER_IPS[@]}")
SSH_USER=appuser
SSH_KEY="${HOME}/.ssh/id_ed25519"

REGISTRY_URL="harbor.yjscloud.local"     # 镜像仓库域名 (HTTPS)
REGISTRY_HTTPS="https://${REGISTRY_URL}"
HARBOR_CA_LOCAL="files/certs/harbor-ca.crt"   # 本地 CA 副本 (由 33-harbor-tls.sh 生成, 供分发)
HARBOR_CERT_DIR="/opt/harbor/certs"           # Harbor 节点上的证书目录
CONTAINERD_CERTS_D="/etc/containerd/certs.d"  # 节点 containerd 镜像映射目录

# Harbor Proxy Cache: <上游registry>|<Harbor项目名>|<Harbor type>|<上游URL>
# 上游选择原则: 直连可达用官方源; 被墙的用国内镜像 (docker.1ms.run / *.m.daocloud.io)
# ⚠️ 项目名必须与节点 certs.d 的路径段一致 (见 32-node-registry-mirrors.sh)
HARBOR_PROXY_MAP=(
  "docker.io|dockerhub|docker-registry|https://docker.1ms.run"
  "quay.io|quay|quay|https://quay.io"
  "ghcr.io|ghcr|github-ghcr|https://ghcr.io"
  "registry.k8s.io|k8s|docker-registry|https://k8s.m.daocloud.io"
  "gcr.io|gcr|docker-registry|https://gcr.m.daocloud.io"
  "mcr.microsoft.com|mcr|docker-registry|https://mcr.microsoft.com"
)

# 组件版本 (与 docs/01-版本说明.md 同步)
K8S_MINOR="v1.36"
METALLB_VER="v0.14.9"
ENVOY_GW_VER="v1.5.0"
LONGHORN_VER="v1.9.1"
HEADLAMP_VER="v0.45.0"
CILIUM_VER="v1.17.0"
HARBOR_VER="v2.12.2"
CRICTL_VER="v1.33.0"
NERDCTL_VER="v2.0.4"
HELM_VER="v3.17.3"

POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
METALLB_POOL="172.16.222.212-172.16.222.220"   # 注意: 不含 .211 (留给 headlamp-pool)
HEADLAMP_POOL="172.16.222.211/32"
HEADLAMP_LB_IP="172.16.222.211"

# ---------- 远程执行 ----------
ssh_node() { # ip, cmd...  (-n: 不吞 stdin, 保证 bash -s 脚本流安全)
  local ip="$1"; shift
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -i "$SSH_KEY" "${SSH_USER}@${ip}" "$@"
}

scp_node() { # src, ip, dst
  local src="$1" ip="$2" dst="$3"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no -i "$SSH_KEY" "$src" "${SSH_USER}@${ip}:${dst}"
}

all_k8s() { # 并行对所有 K8s 节点执行命令
  local cmd="$1"
  for ip in "${ALL_K8S_IPS[@]}"; do ssh_node "$ip" "$cmd" & done
  wait
}

# ---------- 断点状态标记 (resume) ----------
state_done() { # phase 名; 在 master-01 上标记
  ssh_node "$MASTER_IP" "sudo mkdir -p ${STATE_DIR} && sudo touch ${STATE_DIR}/$1.done"
}
state_check() { # 已完成返回 0
  ssh_node "$MASTER_IP" "test -f ${STATE_DIR}/$1.done" 2>/dev/null
}

# ---------- Manual Action Required ----------
mar() { # msg — 打印阻塞信息, 落盘报告, 退出码 42 (不无限重试)
  local msg="$1"
  echo "=========================================================="
  echo "  MANUAL ACTION REQUIRED"
  echo "  $msg"
  echo "  人工处理后执行: make resume PROFILE=${PROFILE}"
  echo "=========================================================="
  ssh_node "$MASTER_IP" "sudo mkdir -p ${STATE_DIR} && echo '${msg}' | sudo tee ${STATE_DIR}/BLOCKED >/dev/null" 2>/dev/null || true
  exit 42
}

# ---------- 镜像中转: 全引用拉取 + tag 回原名 (cn profile) ----------
# 用法: mirror_pull <node_ip> <canonical-image>   例: mirror_pull $MASTER_IP quay.io/metallb/speaker:v0.14.9
mirror_pull() {
  local node="$1" img="$2"
  # 无 registry 前缀的镜像 (如 envoyproxy/gateway:v1) 归一化为 docker.io
  case "$img" in
    */*) : ;;
    *) img="docker.io/$img" ;;
  esac
  local host="${img%%/*}" rest="${img#*/}"
  local mirror=""
  case "$host" in
    quay.io)        mirror="quay.m.daocloud.io" ;;
    ghcr.io)        mirror="ghcr.m.daocloud.io" ;;
    docker.io)      mirror="docker.1ms.run" ;;
    registry.k8s.io) mirror="k8s.m.daocloud.io" ;;
    *) mirror="" ;;
  esac
  [ -z "$mirror" ] && return 0    # 非 docker.io/quay/ghcr/k8s (如 aliyun) 直接拉
  # containerd 2.x 的 ctr 无 -q, 用输出重定向静默
  ssh_node "$node" "sudo ctr -n k8s.io images pull '${mirror}/${rest}' >/dev/null 2>&1" \
    && ssh_node "$node" "sudo ctr -n k8s.io images tag '${mirror}/${rest}' '${img}' && sudo ctr -n k8s.io images tag '${mirror}/${rest}' '${img#docker.io/}'"
}

# 从 manifest 提取全部镜像并在节点上预拉取 (离线部署通用方法)
# 用法: prepull_manifest <node-ip> <yaml-on-master>
prepull_manifest() {
  local node="$1" yaml="$2" img
  # 匹配带 registry 的镜像 + 裸名称镜像 (longhornio/xxx:v1)
  ssh_node "$MASTER_IP" "grep -oE '[a-z0-9.-]+\.(io|com|dev|org|net)/[a-zA-Z0-9_./-]+:[a-zA-Z0-9._-]+|[^\"/@ ]+[a-zA-Z0-9_-]+/[a-zA-Z0-9_./-]+:[a-zA-Z0-9._-]+' '$yaml' | sort -u" | while read -r img; do
    case "$img" in
      harbor.yjscloud.local/*|registry.aliyuncs.com/*|registry.k8s.io/*) continue ;;
      *:*:*) continue ;;
    esac
    echo "    ${node} ← ${img}"
    mirror_pull "$node" "$img" || echo "    (WARN miss: $img)"
  done
}
