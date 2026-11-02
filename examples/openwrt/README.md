# examples/openwrt — OpenWrt 网络出口网关（独立 IaC）

OpenWrt 在 cn 方案中承担：**DNS（dnsmasq 本地域解析）/ NAT / 默认路由 / 代理出口
（OpenClash）**。推荐部署顺序：OpenWrt → Harbor → Kubernetes，但三者相互独立。

完整教程（概念、DNS 管理、排错）见 `docs/13-实战场景/02-CN网络环境.md`。

## 目录内容

| 文件 | 作用 |
|---|---|
| `main.tf` / `variables.tf` | 从 OpenWrt 模板克隆创建 VM |
| `terraform.tfvars.example` | 参数模板 |
| `files/make-vmdk.sh` | 官方 img → vmdk 制作脚本（一次性） |
| `files/configure.sh` | 首启 uci 配置（LAN IP / 关 DHCP / DNS / 转发） |
| `files/*.ipk` | OpenClash 等 luci 插件离线包（不入 Git，见 `docs/99-参考/01-文件说明.md`） |

## 1. 制作 OpenWrt 模板（一次性）

OpenWrt 官方镜像不带 cloud-init，先把 `squashfs-combined` 镜像做成 vSphere 模板：

```bash
# 任一 Linux 机器 (或 Ubuntu VM) 上:
bash files/make-vmdk.sh 24.10.2        # 生成 openwrt.vmdk (40G 虚拟大小)
# 之后任选其一:
#   a) vSphere UI: 上传 vmdk → 新建 VM 挂载该盘 (BIOS 引导) → 转为模板
#   b) govc: govc import.vmdk ... ; govc vm.create ... (docs/13-实战场景/02-CN网络环境.md 第 2 节)
```

> 必须用 **squashfs-combined**（非 efi / 非 ext4），VM 用 BIOS 引导。

## 2. 创建 VM

```bash
cd examples/openwrt
cp terraform.tfvars.example terraform.tfvars    # 填入 vSphere 凭据与 IP
terraform init
terraform apply
```

## 3. 首次配置

出厂 IP 192.168.1.1、root 无密码。给控制机加临时二级 IP 后运行配置脚本：

```bash
# 控制机 (能 SSH 到 192.168.1.1 的临时地址后):
sudo ip addr add 192.168.1.254/24 dev ens192
ssh root@192.168.1.1 "uci set network.lan.ipaddr='172.16.222.210'"  # 先改成目标 IP
# 等价完整流程:
bash files/configure.sh 172.16.222.210
```

`files/configure.sh` 等价于以下 uci 命令（可手工执行）：

```bash
uci set network.lan.proto='static'
uci set network.lan.ipaddr='172.16.222.210'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='172.16.222.254'
uci add_list network.lan.dns='223.5.5.5'
uci set dhcp.lan.ignore='1'              # 关 LAN DHCP, 避免污染生产网段
uci commit network; uci commit dhcp
echo 'root:<密码>' | chpasswd            # 密码自行保管, 禁止写入仓库
/etc/init.d/network restart
```

## 4. 软件源 / DNS / OpenClash

```bash
# opkg 换国内源 (cn)
sed -i 's|https://downloads.openwrt.org/releases/24.10.2|https://mirrors.aliyun.com/openwrt/releases/24.10.2|g' /etc/opkg/distfeeds.conf
opkg update

# dnsmasq-full (OpenClash 依赖)
cp /etc/config/dhcp /tmp/dhcp.bak
opkg remove dnsmasq && opkg install dnsmasq-full
cp /tmp/dhcp.bak /etc/config/dhcp && /etc/init.d/dnsmasq restart

# 本地域解析 (⚠️ uci add_list 是追加语义, 先删后加保证幂等)
uci del_list dhcp.@dnsmasq[0].address='/harbor.example.local/172.16.222.207' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/harbor.example.local/172.16.222.207'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

OpenClash 安装与订阅配置见 `docs/13-实战场景/02-CN网络环境.md` 第 5 节。

## 5. 开启转发（供 Harbor 出海回源）

```bash
uci set firewall.@zone[0].forward='ACCEPT'; uci commit firewall; /etc/init.d/firewall restart
sysctl -w net.ipv4.ip_forward=1
```

Harbor 侧把默认网关指向 OpenWrt 后，出口流量即经 OpenClash 分流（国内直连、海外走代理）。
