# 03 — OpenWrt 网络出口节点（172.16.222.210）

> 职责：国内软件源镜像、集群本地域 DNS（dnsmasq-full）、OpenClash 分流出口（供 Harbor 回源海外仓库）。
> 在 **K8s 搭建之前** 完成。执行脚本：`scripts/20-openwrt-create.sh` + `scripts/21-openwrt-config.sh`（在 master-01 上 `make openwrt && make openwrt-config`）。

## 1. 磁盘镜像制作（任一 Ubuntu VM 上执行，一次性）

```bash
sudo apt-get install -y qemu-utils
curl -O https://mirrors.aliyun.com/openwrt/releases/24.10.2/targets/x86/64/openwrt-24.10.2-x86-64-generic-squashfs-combined.img.gz
zcat openwrt-24.10.2-x86-64-generic-squashfs-combined.img.gz > openwrt.img
truncate -s 40G openwrt.img                      # 扩容到 40G (squashfs 首启自动把剩余空间做成 rootfs_data)
qemu-img convert -f raw -O vmdk -o subformat=streamOptimized openwrt.img openwrt.vmdk
# → 拷回部署机 files/openwrt.vmdk
```

> 注意必须用 **squashfs-combined**（非 efi、非 ext4），VM 用 BIOS 引导。

## 2. 创建 VM（govc，不经 Terraform）

```bash
# import.vmdk 会自动展开 streamOptimized (datastore.upload 的裸 vmdk 无法挂载)
govc import.vmdk -ds date01 files/openwrt.vmdk openwrt-img-222210
govc vm.create -dc=CJL -host.ipath=/CJL/host/172.16.222.243/172.16.222.243 \
  -pool=/CJL/host/172.16.222.243/Resources -ds=date01 \
  -net.adapter=vmxnet3 -net="VM Network" -m=4096 -c=2 \
  -g=other26xLinux64Guest -firmware=bios -on=false \
  -disk="openwrt-img-222210/openwrt.vmdk" \
  "k8s01-openwrt01[222.210]-20260907"
# 名字含 [] 时开机要转义:
govc vm.power -on '/CJL/vm/k8s01-openwrt01\[222.210\]-20260907'
```

## 3. 首次配置（21-openwrt-config.sh 自动执行）

出厂 IP 192.168.1.1、root 无密码。控制机 master-01 加临时二级 IP 访问：

```bash
sudo ip addr add 192.168.1.254/24 dev ens192        # 临时地址
ssh root@192.168.1.1   # 无密码
```

设置的 uci 命令（等价于 LuCI 操作）：

```bash
uci set network.lan.proto='static'
uci set network.lan.ipaddr='172.16.222.210'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='172.16.222.254'
uci add_list network.lan.dns='223.5.5.5'
uci set dhcp.lan.ignore='1'                 # 关 LAN DHCP, 避免污染生产网段
uci commit network; uci commit dhcp
echo 'root:<密码>' | chpasswd               # 密码 = secrets VAULT_OPENWRT_ROOT_PASSWORD
/etc/init.d/network restart
```

## 4. opkg 换阿里云源

```bash
sed -i 's|https://downloads.openwrt.org/releases/24.10.2|https://mirrors.aliyun.com/openwrt/releases/24.10.2|g' /etc/opkg/distfeeds.conf
opkg update
```

## 5. dnsmasq-full + 本地域 DNS

OpenClash 需要 dnsmasq-full（默认 dnsmasq 文件冲突）：

```bash
cp /etc/config/dhcp /tmp/dhcp.bak
opkg remove dnsmasq
opkg install dnsmasq-full
cp /tmp/dhcp.bak /etc/config/dhcp
/etc/init.d/dnsmasq restart
```

本地域解析（集群节点 DNS 首选 .210，节点 /etc/hosts 同时有 harbor 条目双保险）：

```bash
# ⚠️ uci add_list 是追加语义, 重复执行会累积重复条目 —— 务必"先删后加"
uci del_list dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/harbor.yjscloud.local/172.16.222.207'
uci del_list dhcp.@dnsmasq[0].address='/yjscloud.local/172.16.222.207' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].address='/yjscloud.local/172.16.222.207'
uci commit dhcp; /etc/init.d/dnsmasq restart
# 验证:
nslookup harbor.yjscloud.local 127.0.0.1     # → 172.16.222.207
```

> 📖 **DNS 的日常增删改查、通配与特例覆盖、幂等陷阱、排查方法**，
> 详见 **[docs/11-OpenWrt-DNS使用教程.md](11-OpenWrt-DNS使用教程.md)**；
> 也可用封装好的工具：`bash scripts/22-openwrt-dns.sh {list|add|del|sync|test}`。
>
> 注：上游 DNS (`dhcp.@dnsmasq[0].server`) 会被 OpenClash 接管为 `127.0.0.1#7874`，
> 故此处不再写死公共 DNS。静态 `address` 记录不受 OpenClash 影响。

## 6. OpenClash

```bash
opkg install ca-bash curl unzip ipset ip-full kmod-tun kmod-inet-diag luci-compat
scp files/luci-app-openclash.ipk root@172.16.222.210:/tmp/     # v0.47.156, Windows 侧下载
opkg install /tmp/luci-app-openclash.ipk
```

**⚠️ Manual Action Required（当前状态）**：OpenClash 需要订阅/节点才能分流。
登录 **http://172.16.222.210** → 服务 → OpenClash → 配置订阅 → 启动。
（把订阅 URL 填入 `secrets/secrets.env` 的 `VAULT_OPENCLASH_SUBSCRIPTION` 后 `make resume` 可自动写入。）

## 7. 开启转发（供 Harbor 出海回源）

```bash
uci set firewall.@zone[0].forward='ACCEPT'; uci commit firewall; /etc/init.d/firewall restart
sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
```

Harbor 侧（见 04）把默认网关切到 .210，出口流量即经 OpenClash 分流（国内直连、海外走代理）。

# 安装主题
```bash
curl -L -o luci-theme-argon_2.4.7_all.ipk \
https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7_all.ipk

curl -L -o luci-app-argon-config_2.4.7_all.ipk \
https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-app-argon-config_2.4.7_all.ipk

opkg install ./luci-theme-argon_2.4.7_all.ipk \
             ./luci-app-argon-config_2.4.7_all.ipk
```
