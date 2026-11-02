#cloud-config
# =============================================================================
# examples/harbor/user-data.yaml.tpl — Harbor VM OS 初始化
#
# 完成: 用户/SSH → apt → 基础包 → 数据盘挂载 → Docker → Harbor 离线安装。
# 不完成 (见 README.md): HTTPS/TLS、Proxy Cache 项目、节点 certs.d 分发。
#
# 前置条件: Harbor 离线安装包需预先放到 VM 可达的位置 —
#   下载 harbor-offline-installer-<版本>.tgz 到本地 HTTP 服务, 或先手工 scp 进 VM。
#   本模板通过 installer_url 拉取; 若走 files/ 本地包, 部署后手工执行 README 第 3 步。
# =============================================================================

hostname: ${hostname}
timezone: ${timezone}
manage_etc_hosts: true
package_update: false
package_upgrade: false

users:
  - default
  - name: ${user}
    primary_group: ${group}
    groups: sudo, users
    lock_passwd: true
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
      - ${key}
%{ endfor ~}

ssh_pwauth: false

%{ if apt_mirror != "" }
write_files:
  - path: /etc/apt/sources.list.d/ubuntu.sources
    content: |
      Types: deb
      URIs: ${apt_mirror}
      Suites: ${apt_suite} ${apt_suite}-updates ${apt_suite}-backports
      Components: main restricted universe multiverse
      Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

      Types: deb
      URIs: ${apt_mirror}
      Suites: ${apt_suite}-security
      Components: main restricted universe multiverse
      Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
%{ endif }

runcmd:
  # ---------------------------------------------------------------- 基础系统
  - DEBIAN_FRONTEND=noninteractive apt-get update -qq
  - DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget jq vim bash-completion python3

  # ------------------------------------------------ 数据盘 (Harbor data_volume)
  - mkdir -p ${data_mount}
  - blkid /dev/sdb || mkfs.ext4 -F /dev/sdb
  - grep -q "/dev/sdb" /etc/fstab || echo '/dev/sdb ${data_mount} ext4 defaults,nofail 0 2' >> /etc/fstab
  - [ mount, -a ]

  # ---------------------------------------------------------------- Docker
  # Harbor 官方 install.sh 依赖 docker-compose 命令, Ubuntu 只有 compose 插件 → shim
  - DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
  - printf '#!/bin/sh\nexec docker compose "$@"\n' > /usr/local/bin/docker-compose
  - chmod +x /usr/local/bin/docker-compose
  - systemctl enable --now docker

  # ------------------------------------------------ Harbor 域名 (本地解析)
  - grep -q " ${harbor_domain}" /etc/hosts || echo "127.0.0.1 ${harbor_domain}" >> /etc/hosts
  - grep -q " ${harbor_domain}" /etc/cloud/templates/hosts.debian.tmpl || echo "127.0.0.1 ${harbor_domain}" >> /etc/cloud/templates/hosts.debian.tmpl

final_message: |
  Harbor VM base ready: ${hostname}
  Next: 上传/指定离线安装包并执行 install.sh, 见 examples/harbor/README.md 第 3-4 步。
