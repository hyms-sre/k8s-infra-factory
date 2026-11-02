# examples/harbor — Harbor 镜像仓库（独立 IaC）

Harbor 是本项目的镜像仓库层：VM 由 Terraform 创建，Docker 与 Harbor 由 Cloud-Init 安装。
**与 examples/k8s 相互独立**——不依赖 K8s IaC，可单独部署；cn profile 推荐部署顺序：
OpenWrt → Harbor → Kubernetes。

完整说明（概念、架构、排错）见 `docs/13-实战场景/02-CN网络环境.md`。

## 目录内容

| 文件 | 作用 |
|---|---|
| `main.tf` / `variables.tf` | 创建 Harbor VM（1 系统盘 + 1 数据盘） |
| `user-data.yaml.tpl` | OS 初始化：数据盘挂载 → Docker → compose shim → 域名解析 |
| `terraform.tfvars.example` | 参数模板（复制为 `terraform.tfvars` 后填写） |
| `files/` | 离线安装包缓存（`*.tgz` / 证书，不入 Git） |

## 部署步骤

```bash
cd examples/harbor
cp terraform.tfvars.example terraform.tfvars    # 填入 vSphere 凭据/IP/域名/SSH 公钥
terraform init
terraform apply
```

Cloud-Init 完成后（约 2-3 分钟），SSH 进 VM 执行 Harbor 安装（cloud-init 不做，
因为安装包体积大且需要交互确认）：

```bash
ssh appuser@<harbor-ip>

# 1. 上传或拉取离线安装包 (617MB, 见 docs/99-参考/01-文件说明.md)
sudo tar -xzf harbor-offline-installer-v2.12.2.tgz -C /opt/

# 2. 基于 tmpl 生成 harbor.yml (⚠️ 不要手写精简版——会缺字段且 prepare 阶段静默失败)
sudo cp /opt/harbor/harbor.yml.tmpl /opt/harbor/harbor.yml
sudo python3 - <<'PY'
import re
p = "/opt/harbor/harbor.yml"
s = open(p).read()
s = re.sub(r"^hostname: .*", "hostname: harbor.example.local", s, flags=re.M)   # 换成你的域名
s = re.sub(r"^data_volume: .*", "data_volume: /var/lib/harbor", s, flags=re.M)
open(p, "w").write(s)
PY

# 3. 安装 (必须 bash, sh 会报 source: not found)
cd /opt/harbor && sudo bash ./install.sh --with-trivy
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/     # → 200
```

## 后续配置（cn 方案）

1. **HTTPS/TLS**：生成内网 CA + 服务器证书，改 `harbor.yml` 的 https 段后重跑
   `./prepare` + `docker compose up -d`；CA 分发到 K8s 节点
   （`/usr/local/share/ca-certificates/` + `update-ca-certificates`）。
   完整命令与排错见 `docs/13-实战场景/02-CN网络环境.md` 第 3 节。
2. **Proxy Cache 项目**：为每个上游 registry 创建 proxy 项目（API 示例见
   `docs/13-实战场景/02-CN网络环境.md` 第 4 节），项目名必须与 `terraform/vsphere/cluster.yaml` 的
   `harbor.upstreams` 一致。
3. **K8s 节点接入**：由 terraform/vsphere 的 user-data 模板按 `harbor.upstreams` 自动生成
   `/etc/containerd/certs.d/<registry>/hosts.toml`，无需手工配置。

## 常用运维

```bash
cd /opt/harbor
sudo docker compose ps        # 10 个容器应全部 healthy
sudo docker compose down      # 停止 (数据在数据盘, 不丢失)
sudo docker compose up -d
```

> ⚠️ 改 `harbor.yml` 后必须重跑 `sudo ./prepare` 再 `docker compose up -d`，
> 否则配置不生效。若 harbor-core 报 `password authentication failed for user "postgres"`，
> 见 `docs/99-参考/05-故障排查.md`。
