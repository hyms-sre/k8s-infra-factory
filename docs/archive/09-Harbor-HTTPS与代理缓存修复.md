# 09 — Harbor HTTPS 与镜像链路修复报告

> 执行日期: 2026-09-12 ｜ 目标集群: test-cjl-k8s01 ｜ 全部改动**已在实机执行并验证**
> 覆盖问题: ① 客户端连不上 Harbor ② 镜像未缓存进 Harbor ③ 代理仓库漏项
> ④ crictl 直连 registry-1.docker.io 超时 ⑤ Harbor 未启用 HTTPS ⑥ shell 补全缺失

---

## 1. 现象

| 现象 | 具体表现 |
|---|---|
| 客户端连不上 Harbor | `https://harbor.yjscloud.local/v2/` 返回 `000`（无 TLS 监听） |
| crictl 直连上游超时 | `dial tcp 157.240.17.36:443 i/o timeout`（157.240.x 是 Facebook 段，属 DNS 污染） |
| 镜像未缓存 | Harbor registry 存储长期只有 `dockerhub/library/nginx` 一个仓库 |
| 代理仓库漏项 | 存在 `docker.io`、`docker_reg` 两个**多余的普通项目**，缺少应有的 `dockerhub` / `gcr` |

---

## 2. 根因（4 个独立缺陷叠加）

### 根因 A — containerd CRI 无法解析多路径 `config_path`（最关键，最隐蔽）

`containerd config default` 在 2.2.1 生成的默认值是：

```toml
[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = '/etc/containerd/certs.d:/etc/docker/certs.d'   # ← 冒号分隔
```

**CRI 插件遇到这个多路径值时会静默忽略整个 certs.d 目录**，于是 `crictl pull`
完全不读 `hosts.toml`，直接按镜像原始 host 去连 `registry-1.docker.io` → 超时。

误导性极强的一点：`nerdctl pull` 走的是 `io.containerd.transfer.v1.local`，
它的 `config_path` 解析正常，所以 **nerdctl 能走 Harbor、crictl 不能** ——
很容易误判成"映射没问题，是网络问题"。

验证方法（决定性）：

```bash
sudo crictl pull docker.io/library/busybox:1.36
sudo journalctl -u containerd --since "1 minute ago" | grep -E "host=|fetch failed"
# 若只看到 host=registry-1.docker.io，且没有 harbor.yjscloud.local 的尝试 → 就是本缺陷
```

修复：

```bash
sudo sed -i "s|config_path = '[^']*:[^']*'|config_path = '/etc/containerd/certs.d'|g" \
  /etc/containerd/config.toml
sudo sed -i "s|config_path = ''|config_path = '/etc/containerd/certs.d'|g" \
  /etc/containerd/config.toml
sudo systemctl restart containerd
```

> 参考项目 suyiiyii/terraform-script 也是把 `config_path` 设为**单一路径**
> `/etc/containerd/certs.d`，与本结论一致。

### 根因 B — 节点 certs.d 指向不存在的 Harbor 项目，且各节点不一致

| 节点 | `docker.io/hosts.toml` 指向 | 实际是否存在 |
|---|---|---|
| master-01 | `http://harbor.yjscloud.local/docker_reg` | ❌ 无此项目 |
| worker-01 | `http://harbor.yjscloud.local/v2/docker.io` | ⚠️ 存在但 upstream 不可达 |
| （应有） | `https://harbor.yjscloud.local/v2/dockerhub` | ✅ 修复后创建 |

Harbor 侧真实项目是 `docker.io`(registry 13) 与 `docker_reg`(registry 14)，两者
upstream 均为 `unhealthy`，而脚本/文档期望的 `dockerhub` **根本不存在**。

### 根因 C — `harbor.yml` 是手写精简版，导致配置从未真正生效

`docs/04` 早已写明"手写精简版会启动失败，必须基于 tmpl 打补丁"，但
`scripts/30-harbor-init.sh` 恰恰在写精简版。实测 `./prepare` 直接报：

```
KeyError: 'max_job_workers'
```

后果：配置改了也不生效（容器沿用上一次生成的配置）。更糟的是精简版里的
`database.password` 与 Postgres 实际口令不一致，一旦 `prepare` 成功反而会让
`harbor-core` 因 SASL 认证失败 crash-loop：

```
failed SASL auth (FATAL: password authentication failed for user "postgres")
```

修复：`harbor.yml` 一律从 `harbor.yml.tmpl` 生成；`prepare` 后同步
`ALTER USER postgres WITH PASSWORD ...` 对齐口令。

### 根因 D — 上游被墙，且 Harbor 回源未走 OpenClash

| 上游 | Harbor 视角可达性 | 处置 |
|---|---|---|
| `registry-1.docker.io` | ❌ 000 | 改用 `docker.1ms.run` |
| `gcr.io` | ❌ 000 | 改用 `gcr.m.daocloud.io` |
| `registry.k8s.io` | ⚠️ 307 跳 `pkg.dev` 后超时 | 改用 `k8s.m.daocloud.io` |
| `quay.io` / `ghcr.io` / `mcr.microsoft.com` | ✅ 401/200 | 保持官方源 |

同时发现 Harbor 默认路由是 `.254`（非设计的 OpenWrt `.210`），且其 DNS 被污染
（`registry-1.docker.io` 解析到 Facebook IPv6 `2a03:2880:...`）。

**决策：不依赖 OpenClash**，把被墙上游直接换成国内镜像 —— 可用性更高，
也不受订阅有效期影响。

---

## 3. 修复动作

```bash
# 1) 生成内网 CA + 带 SAN 的服务器证书, 从 tmpl 生成 harbor.yml 并启用 https
make harbor-tls          # = scripts/33-harbor-tls.sh

# 2) 补全 Proxy Cache: 清理多余项目, 建 6 个正确上游
make harbor              # = 30-harbor-init + 33-harbor-tls + 31-harbor-proxies + 32-node-registry-mirrors

# 3) 修正节点 config_path 与 certs.d, 分发 CA 信任链
bash scripts/32-node-registry-mirrors.sh

# 4) bash 补全
bash scripts/39b-shell-completion.sh
```

证书 SAN 覆盖：`DNS:harbor.yjscloud.local, DNS:harbor, DNS:localhost,
IP:172.16.222.207, IP:127.0.0.1`，有效期 3650 天。

---

## 4. 验证结果（实机）

### 4.1 Harbor HTTPS

| 检查 | 结果 |
|---|---|
| `https://harbor.yjscloud.local/v2/` | ✅ `401`（需认证 = 正常） |
| `http://harbor.yjscloud.local/v2/` | ✅ `308` 永久跳转 HTTPS |
| 证书链 | ✅ `subject=CN=harbor.yjscloud.local` / `issuer=CN=YJS-Lab-Internal-CA` |
| 容器状态 | ✅ 10 个容器全部 healthy |

### 4.2 Proxy Cache 最终状态

| Harbor 项目 | 上游 | 类型 | 状态 |
|---|---|---|---|
| `dockerhub` | `https://docker.1ms.run` | docker-registry | ✅ healthy |
| `gcr` | `https://gcr.m.daocloud.io` | docker-registry | ✅ healthy |
| `k8s` | `https://k8s.m.daocloud.io` | docker-registry | ✅ healthy |
| `quay` | `https://quay.io` | quay | ✅ healthy |
| `ghcr` | `https://ghcr.io` | github-ghcr | ✅ healthy |
| `mcr` | `https://mcr.microsoft.com` | docker-registry | ✅ healthy |

6/6 全部 healthy（修复前仅 3 个可用，且 `dockerhub`/`gcr` 缺失）。

### 4.3 节点拉取（决定性验收）

| 命令 | 结果 |
|---|---|
| `crictl pull docker.io/library/redis:7-alpine` | ✅ 成功，Harbor 缓存出现 `dockerhub/library/redis` |
| `crictl pull docker.io/library/hello-world:latest` | ✅ 7s（本地清空后重新拉取） |
| `nerdctl -n k8s.io pull docker.io/library/alpine:3.20` | ✅ 成功 |
| 修复后新增 `registry-1.docker.io` 直连记录 | ✅ **0 次** |
| Harbor registry 存储 | 14M → 35M（证明真的落盘缓存） |

### 4.4 shell 补全（4 节点 × root/appuser）

```
root  _init_completion: OK      appuser _init_completion: OK
root  k 补全: OK                appuser k 补全: OK
```

---

## 5. 版本适配改造（参考 suyiiyii/terraform-script）

把"K8s 版本"收敛为**唯一变量** `var.k8s_version`，联动组件由 `locals.tf`
的 `k8s_catalog` 派生，新增版本只需加一行：

| `k8s_version` | apt 源路径段 | sandbox 镜像 | crictl |
|---|---|---|---|
| `v1.33` | `.../v1.33/deb/` | `pause:3.10` | `v1.33.0` |
| `v1.34` | `.../v1.34/deb/` | `pause:3.10` | `v1.34.0` |
| `v1.35` | `.../v1.35/deb/` | `pause:3.10` | `v1.35.0` |
| `v1.36` ★ | `.../v1.36/deb/` | `pause:3.10.1` | `v1.33.0` |
| `v1.37` | `.../v1.37/deb/` | `pause:3.11` | `v1.34.0` |

配套改动：
- `main.tf` 的规格解析改为 `coalesce(显式值, role 默认值)` → 可用 `role` 声明式配置
- 新增 `examples/kubernetes/vm-specs/{k8s-v1.33,k8s-v1.36,k8s-v1.37}.tfvars` 预设
- 新增 `examples/kubernetes/userdata-v2.tftpl` 版本感知 cloud-init（内含单路径
  `config_path` 与 HTTPS certs.d，从模板层面根除本次踩的坑）

**零漂移验证**：用 `terraform` 对比重构前后，同一批 VM 解析出的
`cpu / memory / disk_size / addl_disks` **完全一致**；且 `terraform validate` 通过。

---

## 6. 关键教训（供后续维护）

1. **containerd 2.x 的 `config_path` 必须单一路径** —— 冒号形式会让 CRI 静默失效，
   而 nerdctl 仍正常，极具误导性。
2. **`harbor.yml` 永远从 tmpl 生成** —— 精简版不会报错退出，只会让配置悄悄不生效。
3. **改 Harbor 配置后必须 `./prepare`**，否则改的是"未来某次"的配置。
4. **DB 口令要与 Postgres 实际值对齐**，`prepare` 后顺带 `ALTER USER` 最稳。
5. **代理缓存优先选可达上游**，不要为了"架构纯粹"把可用性押在 OpenClash 上。
6. 用 `journalctl -u containerd | grep host=` 判断镜像到底走了哪个 registry ——
   比看 `crictl` 报错直观得多。
