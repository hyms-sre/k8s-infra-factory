# 11 — OpenWrt DNS 添加使用教程

> 适用环境: OpenWrt **24.10.2** @ `172.16.222.210` ｜ dnsmasq-full **2.90-r4**
> 本文所有命令均在实机验证过（2026-09-12）。
> 配套工具: `scripts/22-openwrt-dns.sh`（幂等增删改查）

---

## 1. 先搞清楚：这套环境的 DNS 是谁在解析

```
K8s 节点 / Pod                OpenWrt .210                 上游
─────────────                ─────────────                ──────
resolv.conf
  nameserver 172.16.222.210
        │
        ├─ harbor.yjscloud.local ──┐
        ├─ 任意 *.yjscloud.local ──┤
        │                          ▼
        │                    dnsmasq-full 静态解析
        │                    (dhcp.@dnsmasq[0].address)
        │                          │ 命中 → 直接应答
        │                          │ 未命中
        │                          ▼
        └─ 其它域名 ────────► 上游 server
                               127.0.0.1#7874  ← OpenClash (fake-ip)
                                     │
                                     ▼
                             OpenClash 分流 → 真实上游 DNS
```

| 角色 | 值 |
|---|---|
| OpenWrt LAN IP | `172.16.222.210` |
| dnsmasq 监听 | `172.16.222.210:53`、`127.0.0.1:53`、`198.18.0.1:53`（OpenClash fake-ip） |
| 本地域 | `yjscloud.local` |
| 上游 DNS | `127.0.0.1#7874`（**已被 OpenClash 接管**，非公共 DNS） |
| 节点侧配置 | `terraform.tfvars` 的 `nameservers = ["172.16.222.210", ...]` |

**关键结论**：`yjscloud.local` 下所有域名默认走 OpenWrt 本地解析，**不出去**。
要让某个名字指向内网 IP，就是在这里加一条静态记录。

---

## 2. 三种添加方式对比

| 方式 | 适用场景 | 持久化 | 推荐度 |
|---|---|---|---|
| **uci 命令行** | 批量/脚本化/可复现 | ✅ 写 `/etc/config/dhcp` | ⭐⭐⭐ 首选 |
| **LuCI 网页** | 偶尔手改、不熟命令 | ✅ 同上 | ⭐⭐ |
| **`/etc/hosts`** | dnsmasq 会读取；但 OpenWrt 上 `/etc/hosts` 可能被重置 | ⚠️ 弱 | ⭐ 不推荐 |

> 三者最终都落到 dnsmasq。**推荐 uci**，因为它幂等可脚本化，且能写进 IaC。

---

## 3. 方式 A：uci 命令行（推荐）

### 3.1 添加一条主机记录

```bash
# 登到 OpenWrt（从 master-01 走 sshpass）
sshpass -p "$VAULT_OPENWRT_ROOT_PASSWORD" ssh root@172.16.222.210

# ⚠️ 幂等写法：先删同域名的旧条目，再加
uci del_list dhcp.@dnsmasq[0].address='/grafana.yjscloud.local/172.16.222.212' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/grafana.yjscloud.local/172.16.222.212'

# 提交 + 生效
uci commit dhcp
/etc/init.d/dnsmasq restart

# 验证
nslookup grafana.yjscloud.local 127.0.0.1
```

### 3.2 语法说明

`address` 的格式是 **`/域名/IP`**（三段，斜杠分隔）：

```
uci add_list dhcp.@dnsmasq[0].address='/<域名>/<IP>'
```

- 域名可以写**单个主机**，也可以写**整个域**
- 写整个域时，**它同时匹配所有子域**（见 §5.3）
- 同一个域名可以加多条（多 IP 轮询）

### 3.3 删除

```bash
uci del_list dhcp.@dnsmasq[0].address='/grafana.yjscloud.local/172.16.222.212'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

### 3.4 一键工具（推荐日常用这个）

```bash
# 在 master-01 上执行
cd /opt/iac
bash scripts/22-openwrt-dns.sh list                          # 查看全部条目
bash scripts/22-openwrt-dns.sh add grafana.yjscloud.local 172.16.222.212
bash scripts/22-openwrt-dns.sh del grafana.yjscloud.local
bash scripts/22-openwrt-dns.sh dedupe                        # 清理重复条目
bash scripts/22-openwrt-dns.sh sync                          # 去重 + 补齐项目必需记录
bash scripts/22-openwrt-dns.sh test grafana.yjscloud.local   # 从 OpenWrt + 4 节点验证
```

工具内部已封装"先删后加"的幂等逻辑，**重复执行不会累积**。

---

## 4. 方式 B：LuCI 网页

1. 浏览器打开 `http://172.16.222.210`，用 `root` + `VAULT_OPENWRT_ROOT_PASSWORD` 登录
2. **网络 → DHCP/DNS**
3. 切到 **「主机名映射」**（Hostnames）标签页 → **添加**
   - 主机名：`grafana.yjscloud.local`（可写完整域名）
   - IP 地址：`172.16.222.212`
4. 或者切到 **「域名」**（Domain）标签页，用 **「自定义域名/IP 对」** 添加
   - 这里等价于 `address=/域名/IP`，**支持整域通配**
5. 点 **「保存并应用」**

> LuCI 底层就是写 `dhcp.@dnsmasq[0]`，与 uci 完全等价。
> 保存后可用 §7 的命令验证。

---

## 5. 常见场景

### 5.1 单个主机名 → IP

```bash
uci add_list dhcp.@dnsmasq[0].address='/grafana.yjscloud.local/172.16.222.212'
```

### 5.2 整个域（含所有子域）→ 同一 IP

本环境的 Harbor 就是这么配的：

```bash
uci add_list dhcp.@dnsmasq[0].address='/yjscloud.local/172.16.222.207'
```

效果：`yjscloud.local`、`a.yjscloud.local`、`b.c.yjscloud.local` **全部**解析到 `.207`。

### 5.3 ⭐ 通配 + 特例覆盖（最长匹配优先）

dnsmasq 对 `address` 采用**最长后缀匹配**。所以可以"整体通配 + 个别覆盖"：

```bash
# 全部 *.yjscloud.local → .207
uci add_list dhcp.@dnsmasq[0].address='/yjscloud.local/172.16.222.207'
# 例外: grafana 单独指向 .212
uci add_list dhcp.@dnsmasq[0].address='/grafana.yjscloud.local/172.16.222.212'
```

实测结果：

| 查询 | 结果 |
|---|---|
| `harbor.yjscloud.local` | `172.16.222.207` |
| `grafana.yjscloud.local` | `172.16.222.212` ← 更长的匹配胜出 |
| `随便什么.yjscloud.local` | `172.16.222.207` |
| `grafana.yjscloud.local`（删除特例后） | `172.16.222.207` ← 回落到通配 |

> 这是本环境最有用的技巧：**加一条通配兜底，再按需加特例**，
> 就不用为每个新服务都改 DNS。

### 5.4 配置上游 DNS

```bash
# 查看当前上游
uci get dhcp.@dnsmasq[0].server

# 添加公共 DNS
uci add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

> ⚠️ **本环境上游已被 OpenClash 接管为 `127.0.0.1#7874`**。
> 直接加公共 DNS 会被 OpenClash 覆盖。要改上游请改 OpenClash 配置，
> 或先停用 OpenClash 再设置。详见 §6.2。

### 5.5 屏蔽某个域名

不给 IP 即为返回 NXDOMAIN / 0.0.0.0：

```bash
# 返回 NXDOMAIN
uci add_list dhcp.@dnsmasq[0].address='/ads.example.com/'
# 或指向黑洞地址
uci add_list dhcp.@dnsmasq[0].address='/ads.example.com/0.0.0.0'
```

### 5.6 CNAME 别名

```bash
# /etc/dnsmasq.conf 追加（uci 不直接支持 cname）
echo 'cname=git.yjscloud.local,harbor.yjscloud.local' >> /etc/dnsmasq.conf
/etc/init.d/dnsmasq restart
```

> 注意：CNAME 目标必须本身能被 dnsmasq 解析（来自 hosts / DHCP / 静态 address）。

### 5.7 按 MAC 绑定固定 IP（DHCP 场景）

```bash
uci add dhcp host
uci set dhcp.@host[-1].name='myhost'
uci set dhcp.@host[-1].mac='00:50:56:xx:xx:xx'
uci set dhcp.@host[-1].ip='172.16.222.150'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

---

## 6. ⚠️ 关键陷阱（都是本项目实际踩过的）

### 6.1 `uci add_list` 不是幂等写入 —— 会累积重复

`add_list` 是**追加**语义。裸用它配 DNS，每次重跑脚本都会多一条：

```bash
# 反面教材（本项目原脚本就是这么写的）
uci add_list dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207'
```

实测在 `make resume` 多次后，同一条记录**累积了 3 份**：

```
dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207' '/yjscloud.local/172.16.222.207' \
                          '/harbor.yjscloud.local/172.16.222.207' '/yjscloud.local/172.16.222.207' \
                          '/harbor.yjscloud.local/172.16.222.207' '/yjscloud.local/172.16.222.207'
```

**正确写法**（先删后加）：

```bash
uci del_list dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207'
```

**清理已有重复**：

```bash
bash scripts/22-openwrt-dns.sh dedupe     # 或 sync
```

> `scripts/21-openwrt-config.sh` 已修正为幂等写法。

### 6.2 OpenClash 会接管上游 DNS

OpenClash 启动后会把 `dhcp.@dnsmasq[0].server` 改成 `127.0.0.1#7874`
（fake-ip 模式），并额外监听 `198.18.0.1:53`。

后果：
- 你在 uci 里设的 `223.5.5.5` **不会生效**
- 某些域名会解析成 `198.18.x.x` 这类假地址（由 OpenClash 接管转发）

**但静态 `address` 记录不受影响** —— 它优先级高于上游转发，
所以本地域名解析始终可靠。这也是本项目把 Harbor 域名走静态解析的原因。

### 6.3 `address=/域/IP` 是通配，会吃掉所有子域

`/yjscloud.local/172.16.222.207` 不仅匹配 `yjscloud.local`，
还匹配 `任何子域.yjscloud.local`。

**好处**：一条兜底规则覆盖所有服务。
**风险**：如果你以为它只管裸域名，会疑惑为什么新加的 `xxx.yjscloud.local`
自动解析到了 `.207`。要特例就用 §5.3 的更长匹配覆盖。

### 6.4 busybox 的 `nslookup` 会打一行假 NXDOMAIN

OpenWrt / 集群节点上是 busybox 版 `nslookup`，它**同时查 A 和 AAAA**。
没有 IPv6 记录时会多打一行：

```
Name:	grafana.yjscloud.local
Address: 172.16.222.212
** server can't find grafana.yjscloud.local: NXDOMAIN     ← 这是 AAAA 查询的结果, 不是错误
```

**看到 `Name/Address` 有正确结果就说明成功了**，忽略那行 NXDOMAIN。

### 6.5 `rebind_protection` 会拦截来自上游的私网地址

本机 `dhcp.@dnsmasq[0].rebind_protection='1'`，dnsmasq 会拒绝
**上游返回的**私有 IP（防 DNS rebinding）。

- 静态 `address` 记录**不受影响** ✅
- 但如果你指望上游 DNS 把一个公网域名解析到内网 IP，会被拦掉

确实需要时可临时放开（**不推荐长期关闭**）：

```bash
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

### 6.6 改了不生效？确认是 `commit` + `restart`

```bash
uci commit dhcp                    # 不 commit 只改内存, 重启即丢
/etc/init.d/dnsmasq restart        # 不 restart 不生效
```

`uci show dhcp` 看到的是**未提交的候选配置**；要确认落盘：

```bash
cat /etc/config/dhcp | grep -A2 dnsmasq
```

---

## 7. 验证方法

### 7.1 从 OpenWrt 自身

```bash
nslookup grafana.yjscloud.local 127.0.0.1
```

### 7.2 从集群节点（真实使用路径）

```bash
# master-01
nslookup grafana.yjscloud.local 172.16.222.210

# 全部 4 个节点
for ip in 172.16.222.201 172.16.222.202 172.16.222.203 172.16.222.204; do
  printf '%-16s -> ' "$ip"
  ssh appuser@$ip "nslookup grafana.yjscloud.local 172.16.222.210 | awk '/^Address: /{print \$2}' | tail -1"
done
```

### 7.3 用工具一次跑完

```bash
bash scripts/22-openwrt-dns.sh test grafana.yjscloud.local
```

输出会同时给出 OpenWrt 侧、master 侧、4 个节点侧的解析结果。

### 7.4 端到端（DNS + 服务）

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://harbor.yjscloud.local/v2/   # → 401
```

---

## 8. 排查清单

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 解析不到 | 没 `commit` / 没 `restart` | `uci commit dhcp && /etc/init.d/dnsmasq restart` |
| 解析到通配的 IP | 只加了特例但域名写错，落到通配规则 | `bash scripts/22-openwrt-dns.sh list` 核对拼写 |
| 上游 DNS 不生效 | 被 OpenClash 接管 | §6.2 |
| 条目出现多份 | `add_list` 重复执行 | `dedupe` |
| 节点解析不了但 OpenWrt 能 | 节点 `nameservers` 没指向 `.210` | 检查 `terraform.tfvars` 的 `nameservers` |
| 公网域名解析到私网失败 | `rebind_protection` | §6.5 |
| dnsmasq 起不来 | 配置语法错 | `logread \| tail -20`；`uci show dhcp` 检查 |

查看日志与配置：

```bash
logread | tail -30                    # 系统日志
uci show dhcp | grep dnsmasq          # 候选配置
cat /var/etc/dnsmasq.conf.* | head    # dnsmasq 实际加载的配置
```

---

## 9. 附录：当前配置快照（2026-09-12 实测）

```bash
# uci get dhcp.@dnsmasq[0].address
/harbor.yjscloud.local/172.16.222.207
/yjscloud.local/172.16.222.207

# uci get dhcp.@dnsmasq[0].server
127.0.0.1#7874                     # OpenClash fake-ip

# 其他相关项
dhcp.@dnsmasq[0].domain='lan'
dhcp.@dnsmasq[0].local='/lan/'
dhcp.@dnsmasq[0].rebind_protection='1'
dhcp.@dnsmasq[0].localise_queries='1'
```

解析实测：

| 域名 | 结果 | 来源 |
|---|---|---|
| `harbor.yjscloud.local` | `172.16.222.207` | 精确记录 |
| `yjscloud.local` | `172.16.222.207` | 通配记录 |
| `任意.yjscloud.local` | `172.16.222.207` | 通配记录 |

---

## 10. 速查卡

```bash
# ---- 查看 ----
uci show dhcp | grep address
uci get dhcp.@dnsmasq[0].server
bash scripts/22-openwrt-dns.sh list

# ---- 添加（幂等）----
uci del_list dhcp.@dnsmasq[0].address='/<域名>/<IP>' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/<域名>/<IP>'
uci commit dhcp && /etc/init.d/dnsmasq restart

# ---- 删除 ----
uci del_list dhcp.@dnsmasq[0].address='/<域名>/<IP>'
uci commit dhcp && /etc/init.d/dnsmasq restart

# ---- 一键 ----
bash scripts/22-openwrt-dns.sh add <域名> <IP>
bash scripts/22-openwrt-dns.sh del <域名>
bash scripts/22-openwrt-dns.sh dedupe
bash scripts/22-openwrt-dns.sh sync
bash scripts/22-openwrt-dns.sh test <域名>

# ---- 验证 ----
nslookup <域名> 127.0.0.1            # OpenWrt 本机
nslookup <域名> 172.16.222.210       # 集群侧
```
