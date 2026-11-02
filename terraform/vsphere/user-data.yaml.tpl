#cloud-config
# =============================================================================
# user-data.yaml.tpl — Kubernetes 节点 OS 初始化 (唯一入口, 不拆分 shell 脚本)
#
# 由 Terraform templatefile() 渲染后经 guestinfo 注入, 完成底层基础初始化:
#   hostname / timezone / NTP / 用户 / SSH / apt 源 / 基础包 / swap /
#   内核模块 / sysctl / containerd / crictl / kubelet / kubeadm / kubectl /
#   helm / nerdctl / bash 补全
#
# 不在此处做的事 (职责边界):
#   - kubeadm init / join          → 见 docs/09-kubernetes.md (集群引导)
#   - CNI / MetalLB / Longhorn 等  → 见 k8s-plugins/ (平台扩展)
#
# 幂等性约定:
#   - 所有配置文件用 write_files 覆盖写入, 不追加
#   - /etc/hosts 条目 grep 守卫, 且同步写入 cloud-init hosts 模板 (重启不丢)
#   - runcmd 仅做幂等操作 (apt install / systemctl enable / 覆盖式配置)
#
# 模板指令写法 (注释中用 %%{ 转义展示): %%{ if x } ... %%{ endif }, %%{ for k, v in m } ... %%{ endfor }
# =============================================================================

hostname: ${hostname}
timezone: ${timezone}
manage_etc_hosts: true
package_update: false
package_upgrade: false

%{ if length(ntp_servers) > 0 }
# 时间同步 (空列表 = 使用镜像默认时间同步配置)
ntp:
  enabled: true
  servers:
%{ for ns in ntp_servers ~}
    - ${ns}
%{ endfor ~}
%{ endif }

# ---------------------------------------------------------------- 用户与 SSH
users:
  - default
  - name: ${user}
    primary_group: ${group}
    groups: sudo, users
    lock_passwd: ${enable_password_auth && vm_password != "" ? "false" : "true"}
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
      - ${key}
%{ endfor ~}

ssh_pwauth: ${enable_password_auth && vm_password != "" ? "yes" : "no"}
%{ if enable_password_auth && vm_password != "" }
chpasswd:
  expire: false
  users:
    - name: ${user}
      password: ${vm_password}
      type: text
%{ endif }

# ---------------------------------------------------------------- 配置文件
write_files:
%{ if apt_mirror != "" }
  # apt 国内源 (Ubuntu 24.04 deb822 格式, 整文件覆盖, 幂等)
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

  # 内核模块 (containerd / iptables)
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # 内核参数 (Kubernetes 官方要求 + Longhorn/inotify 调优)
  - path: /etc/sysctl.d/70-k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
      fs.inotify.max_user_instances = 1024
      fs.inotify.max_user_watches = 1048576
      vm.max_map_count = 262144

  # crictl 运行时端点
  - path: /etc/crictl.yaml
    content: |
      runtime-endpoint: unix:///run/containerd/containerd.sock

  # Kubernetes apt 源 (key 由 runcmd 安装)
  - path: /etc/apt/sources.list.d/kubernetes.list
    content: |
      deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${k8s_apt_repo} /

  # 节点信息 (排障用)
  - path: /etc/k8s-node.conf
    content: |
      NODE_HOSTNAME=${hostname}
      NODE_ROLE=${role}
      K8S_VERSION=${k8s_version}
      K8S_APT_REPO=${k8s_apt_repo}
      K8S_PAUSE_IMAGE=${k8s_pause_image}
      CNI_PLUGIN=${cni_plugin}
      POD_CIDR=${pod_cidr}
      SERVICE_CIDR=${service_cidr}

  # kubectl 别名 + 补全加载 (profile.d 全局生效, 幂等)
  - path: /etc/profile.d/k8s-aliases.sh
    content: |
      alias k=kubectl
      [ -f /etc/bash_completion.d/kubectl ] && source /etc/bash_completion.d/kubectl

%{ if harbor_enabled }
  # ------------------------------------------------ 镜像仓库: containerd certs.d
  # 每个上游 registry 一个 hosts.toml: 优先走 Harbor proxy 项目, 未命中回源上游。
  # ⚠️ 项目名必须与 Harbor 实际 proxy 项目一致, 否则 404 → 回退直连 → 超时。
  # ⚠️ config_path 必须是单一路径 (见 runcmd 中 containerd 配置说明)。
%{ for reg, proj in harbor_upstreams }
  - path: /etc/containerd/certs.d/${reg}/hosts.toml
    content: |
      server = "https://${reg}"

      [host."https://${harbor_host}/v2/${proj}"]
        capabilities = ["pull", "resolve"]
        override_path = true
%{ endfor }
%{ endif }

  # ------------------------------------------------ SSH 安全基线 (登录管理 + 空闲超时)
  # 作为 drop-in 放在 sshd_config.d 下:
  #   - Ubuntu 的 /etc/ssh/sshd_config 顶部有 Include /etc/ssh/sshd_config.d/*.conf,
  #     而 sshd 对同一选项采用"首次取到的值生效", 故本文件优先级高于主配置。
  #   - 空闲 30 分钟自动断开 = ClientAliveInterval 300s × ClientAliveCountMax 6
  #     (每 5 分钟探测一次, 连续 6 次无响应即断开 = 1800s)
  #   - TCPKeepAlive no: 交给 SSH 层探测, 避免"客户端掉线但连接被 TCP 保活挂住"
  - path: /etc/ssh/sshd_config.d/99-iac-hardening.conf
    permissions: '0644'
    content: |
      # 由 iac-k8s-esxi cloud-init 生成, 请勿手工修改 (改模板: user-data.yaml.tpl)
      # ---- 认证方式 ----
      PubkeyAuthentication yes
      PasswordAuthentication ${enable_password_auth && vm_password != "" ? "yes" : "no"}
      KbdInteractiveAuthentication no
      PermitEmptyPasswords no
      PermitRootLogin no
      MaxAuthTries 3
      MaxSessions 10
      LoginGraceTime 30
      # ---- 空闲超时: 30 分钟无任何活动自动断开 ----
      ClientAliveInterval 300
      ClientAliveCountMax 6
      TCPKeepAlive no
      # ---- 减少暴露面 ----
      X11Forwarding no

runcmd:
  # ---------------------------------------------------------------- SSH 安全基线
  # 先校验 drop-in 是否合法: 不合法就删掉并保留默认配置, 避免把自己锁在门外。
  - |
    if sshd -t 2>/dev/null; then
      systemctl reload ssh 2>/dev/null || systemctl restart ssh
      echo "[cloud-init] sshd hardening applied (idle timeout 30m)"
    else
      rm -f /etc/ssh/sshd_config.d/99-iac-hardening.conf
      echo "[cloud-init] WARN: sshd config invalid, hardening reverted"
    fi

  # ---------------------------------------------------------------- 基础系统
  - [ swapoff, -a ]
  # fstab 交换行注释掉 (已注释的行不重复处理, 幂等)
  - sed -i 's|^\([^#].*\sswap\s\)|# \1|' /etc/fstab
  - [ modprobe, overlay ]
  - [ modprobe, br_netfilter ]
  - [ sysctl, --system ]
  - DEBIAN_FRONTEND=noninteractive apt-get update -qq
  - DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget jq vim bash-completion ca-certificates gnupg apt-transport-https open-iscsi nfs-common socat conntrack
  - systemctl enable --now iscsid

%{ if harbor_enabled }
  # harbor 域名解析 (grep 守卫幂等; 同写 cloud-init hosts 模板防止重启丢失)
  - grep -q " ${harbor_host}" /etc/hosts || echo "${harbor_ip} ${harbor_host} harbor" >> /etc/hosts
  - grep -q " ${harbor_host}" /etc/cloud/templates/hosts.debian.tmpl || echo "${harbor_ip} ${harbor_host} harbor" >> /etc/cloud/templates/hosts.debian.tmpl
%{ endif }

  # ------------------------------------------------ containerd (CRI 运行时)
  - DEBIAN_FRONTEND=noninteractive apt-get install -y containerd
  - mkdir -p /etc/containerd/certs.d
  - containerd config default > /etc/containerd/config.toml
  # SystemdCgroup = true (kubeadm 要求)
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  # ⚠️ config_path 必须是【单一路径】: containerd 2.x CRI 无法解析 "a:b" 多路径,
  #    会静默忽略整个 certs.d (表现为 crictl 直连上游超时而 nerdctl 正常)。
  - sed -i "s|config_path = '[^']*:[^']*'|config_path = '/etc/containerd/certs.d'|g" /etc/containerd/config.toml
  - sed -i "s|config_path = ''|config_path = '/etc/containerd/certs.d'|g" /etc/containerd/config.toml
  # pause/sandbox 镜像跟随 K8s 版本目录 (由 generate.py 解析)
  - sed -i "s|sandbox_image = \"registry.k8s.io/pause[^\"]*\"|sandbox_image = \"${k8s_pause_image}\"|" /etc/containerd/config.toml
  - sed -i "s|sandbox = .registry.k8s.io/pause.*|sandbox = '${k8s_pause_image}'|" /etc/containerd/config.toml
  - systemctl enable containerd
  - systemctl restart containerd

  # ---------------------------------------------- Kubernetes apt 源与三件套
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL "${k8s_apt_repo}Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - apt-get update -qq
  - DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl

%{ if helm_enabled }
  # --------------------------------------------------------------- helm
  - echo "[cloud-init] installing helm"
  - curl -fsSL "${helm_url}" | tar -xz -C /tmp
  - install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
  - rm -rf /tmp/linux-amd64
  - helm completion bash > /etc/bash_completion.d/helm
%{ endif }

%{ if nerdctl_enabled }
  # --------------------------------------------------------------- nerdctl
  # 下载地址可在 config 中指向镜像或预下载的离线包 (cn 网络环境见 docs/10)
  - echo "[cloud-init] installing nerdctl"
  - curl -fsSL "${nerdctl_url}" -o /tmp/nerdctl.tgz
  - tar -xzf /tmp/nerdctl.tgz -C /usr/local/bin nerdctl
  - rm -f /tmp/nerdctl.tgz
%{ endif }

%{ if bash_completion }
  # ------------------------------------------------- kubectl/kubeadm 补全
  - kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null
  - kubeadm completion bash | tee /etc/bash_completion.d/kubeadm > /dev/null
  - chmod a+r /etc/bash_completion.d/kubectl /etc/bash_completion.d/kubeadm
%{ endif }

%{ if length(data_disks) > 0 }
  # ------------------------------------------------ 附加数据盘 (Longhorn 数据盘)
  # 首块附加盘 (unit 1, /dev/sdb) 格式化挂载; mkfs.x 已存在时强制重建无意义,
  # 用 blkid 守卫保证幂等 (仅首次格式化)
  - mkdir -p ${data_mount}
  - blkid /dev/sdb || mkfs.ext4 -F /dev/sdb
  - grep -q "/dev/sdb" /etc/fstab || echo '/dev/sdb ${data_mount} ext4 defaults,nofail 0 2' >> /etc/fstab
  - [ mount, -a ]
  - [ chown, -R, ${user}:${group}, ${data_mount} ]
%{ endif }

final_message: |
  K8s node ready: ${hostname} (role=${role}, k8s=${k8s_version}, cni=${cni_plugin})
  Next: see docs/09-kubernetes.md for kubeadm init / join.
