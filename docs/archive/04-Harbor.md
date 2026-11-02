# 04 — Harbor 镜像仓库（172.16.222.207 / **https://harbor.yjscloud.local**）

> 在 K8s 之前部署。执行：master-01 上 `make harbor`（= 30-harbor-init + **33-harbor-tls** + 31-harbor-proxies + 32-node-registry-mirrors，幂等可 resume）。
> 登录：`https://harbor.yjscloud.local`，用户 `admin`，密码 `secrets.env: VAULT_HARBOR_ADMIN_PASSWORD`。
> HTTP(80) 会 308 跳转到 HTTPS(443)。
>
> ⚠️ **`harbor.yml` 必须由 `harbor.yml.tmpl` 生成**。手写精简版不会报错退出，而是在
> `./prepare` 阶段抛 `KeyError: 'max_job_workers'`，导致**配置悄悄不生效**
> （容器继续沿用上一次生成的配置）。改配置后必须重跑 `./prepare` 再 `docker compose up -d`。

## 0. HTTPS（scripts/33-harbor-tls.sh）

```bash
make harbor-tls      # 生成内网 CA + 服务器证书 → 改 harbor.yml → prepare → 重启 → 分发 CA
```

- 证书落盘 `/opt/harbor/certs/`，SAN 覆盖 `harbor.yjscloud.local` / `harbor` / `localhost` /
  `172.16.222.207` / `127.0.0.1`，有效期 3650 天
- CA 分发到全部 K8s 节点 → `/usr/local/share/ca-certificates/harbor-ca.crt` + `update-ca-certificates`
- 验证：`curl -s -o /dev/null -w '%{http_code}' https://harbor.yjscloud.local/v2/` → `401`

> 若 `prepare` 后 `harbor-core` 反复重启并报
> `password authentication failed for user "postgres"`，说明 `harbor.yml` 里的
> `database.password` 与 Postgres 实际口令不一致，需同步对齐：
> `sudo docker exec -u postgres harbor-db psql -U postgres -c "ALTER USER postgres WITH PASSWORD '<yml 中的口令>';"`
> （`33-harbor-tls.sh` 已自动处理这一步）

## 1. 数据盘

cloud-init userdata 已把第二块盘（200G `/dev/sdb`）挂载到 `/var/lib/longhorn`，直接作为 Harbor `data_volume`：

```
/dev/sdb1  196G  /var/lib/longhorn  ext4
```

## 2. Docker 与 compose

```bash
sudo apt-get install -y docker.io docker-compose-v2
# Harbor install.sh 依赖 docker-compose 命令, 而 Ubuntu 只有插件, 做 shim:
printf '#!/bin/sh\nexec docker compose "$@"\n' | sudo tee /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## 3. 出海回源路由

```bash
sudo ip route replace default via 172.16.222.210        # 默认网关 → OpenWrt
sudo sed -i 's|via: 172.16.222.254|via: 172.16.222.210|' /etc/netplan/50-cloud-init.yaml   # 持久化
# 验证: curl -sI https://mirrors.aliyun.com (国内直连) + docker hub (等 openclash)
```

## 4. 离线安装

```bash
# files/harbor-offline-installer-v2.12.2.tgz (617MB, Windows 侧 GitHub 下载) → /tmp
sudo tar -xzf /tmp/harbor-offline-installer-v2.12.2.tgz -C /opt/
sudo python3 - <<'PY'   # 从模板生成 harbor.yml (逐行替换, 全文见 scripts/30-harbor-init.sh)
# hostname: harbor.yjscloud.local / http only / data_volume: /var/lib/longhorn
# trivy: skip_update: true + offline_scan: true (国内无法在线更新漏洞库)
PY
sudo bash ./install.sh --with-trivy     # 必须用 bash (sh 会报 source: not found)
# 预期: ✔ ----Harbor has been installed and started successfully.----
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/    # → 200
```

> 注意：harbor.yml 手写精简版会因缺 `max_job_workers` 等字段启动失败 —— 必须基于 `harbor.yml.tmpl` 打补丁。

## 5. Proxy Cache 项目（自动化：`make harbor` 或 `scripts/31-harbor-proxies.sh`）

一键配置 6 个常见上游（幂等，可重复跑）。每个上游先从 Harbor VM 探测可达性——**通的立即建，被墙的记录到 BLOCKED 等 OpenClash 后 `make resume` 自动重试**：

| 项目 | 上游 | Harbor type | 状态 |
|---|---|---|---|
| `dockerhub` | **docker.1ms.run** | docker-registry | ✅ 已通（docker.io 被墙，改走国内镜像） |
| `gcr` | **gcr.m.daocloud.io** | docker-registry | ✅ 已通（gcr.io 被墙，改走国内镜像） |
| `k8s` | **k8s.m.daocloud.io** | docker-registry | ✅ 已通（registry.k8s.io 307 跳 pkg.dev 被墙） |
| `quay` | quay.io | quay | ✅ 已通（官方源直连可达） |
| `ghcr` | ghcr.io | github-ghcr | ✅ 已通（官方源直连可达） |
| `mcr` | mcr.microsoft.com | docker-registry | ✅ 已通（官方源直连可达） |

> **上游选择原则（2026-09-12 修订）**：直连可达的用官方源，被墙的换国内镜像，
> 使 Harbor 回源**不依赖 OpenClash**，可用性更高。真值定义在
> `scripts/00-env.sh` 的 `HARBOR_PROXY_MAP`，新增/调整上游只改这一处。
>
> ⚠️ 项目名必须与节点 `certs.d` 的路径段一致（`docker.io` → `dockerhub`），
> 否则 containerd 会 404 后回退直连上游而超时。详见 `docs/09`。

API 用法（手工等价操作）：

```bash
# 创建 endpoints (type 是关键: docker-hub / quay / github-ghcr / docker-registry)
curl -u admin:$PWD -X POST -H 'Content-Type: application/json' \
  -d '{"name":"dockerhub","type":"docker-hub","url":"https://hub.docker.com","insecure":false}' \
  http://harbor.yjscloud.local/api/v2.0/registries
# 创建 Proxy 项目 (必须带数字 registry_id, 否则会建成普通项目!)
rid=$(curl -s -u admin:$PWD 'http://harbor.yjscloud.local/api/v2.0/registries?name=dockerhub' | jq '.[0].id')
curl -u admin:$PWD -X POST -H 'Content-Type: application/json' \
  -d "{\"project_name\":\"dockerhub\",\"public\":true,\"registry_id\":$rid}" \
  http://harbor.yjscloud.local/api/v2.0/projects
```

节点使用方式（certs.d 已自动映射，透明）：

```bash
# 原: docker.io/library/nginx:1.27   → 自动走 harbor dockerhub 项目 (等 openclash)
# 原: quay.io/cilium/cilium:v1.17.0  → 自动走 harbor quay 项目 (✅ 现在就能用)
# 显式: ctr pull --plain-http harbor.yjscloud.local/quay/cilium/cilium:v1.17.0
```

## 6. K8s 节点接入（41-k8s-install.sh 已配置）

节点 `/etc/containerd/certs.d/<registry>/hosts.toml`：

```toml
server = "https://docker.io"

[host."http://harbor.yjscloud.local/v2/dockerhub"]
  capabilities = ["pull", "resolve"]
  override_path = true
```

（quay.io→/v2/quay，ghcr.io→/v2/ghcr 同理）——拉取 `docker.io/nginx` 时 containerd 先问 Harbor 的 `dockerhub/library/nginx`，未命中回源上游。

## 7. 常用运维

```bash
cd /opt/harbor
sudo docker compose ps                 # 组件状态 (10 个容器应全部 healthy)
sudo docker compose down               # 停止 (数据在 /var/lib/longhorn)
sudo docker compose up -d              # 启动
# 修改配置后重生效:
sudo bash ./install.sh --with-trivy    # 或 prepare + compose restart
```
