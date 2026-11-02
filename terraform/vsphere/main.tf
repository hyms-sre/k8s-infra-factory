# =============================================================================
# main.tf — 核心 Terraform 逻辑 (公共参数装配)
#
# vm.tf (generate.py 生成) 持有 cluster/nodes 数据与 for_each 资源;
# 本文件负责把集群级公共参数装配成 cloud-init 模板的公共变量集,
# 供 vm.tf 中每个节点 merge(本地差异) 后注入 guestinfo。
#
# 凭据 (vsphere_*) 走 variables.tf + terraform.tfvars / TF_VAR_*, 禁止入库。
# =============================================================================

locals {
  # 附加数据盘挂载点 (Longhorn 数据目录)
  data_mount = "/var/lib/longhorn"

  # user-data.yaml.tpl 的公共变量 (与模板中的引用一一对应, 见 docs/99-参考/03-配置参考)
  userdata_common = {
    # --- 主机与账号 ---
    user                 = local.cluster.user
    group                = local.cluster.group
    timezone             = local.cluster.timezone
    ssh_authorized_keys  = local.cluster.ssh_authorized_keys
    enable_password_auth = local.cluster.enable_password_auth
    vm_password          = local.cluster.vm_password
    # --- apt / 时间同步 ---
    apt_mirror  = local.cluster.apt_mirror
    apt_suite   = local.cluster.apt_suite
    ntp_servers = local.cluster.ntp_servers
    # --- Kubernetes (版本联动值由 generate.py 从目录解析) ---
    k8s_version     = local.cluster.k8s_version
    k8s_apt_repo    = local.cluster.k8s_apt_repo
    k8s_pause_image = local.cluster.k8s_pause_image
    crictl_version  = local.cluster.crictl_version
    pod_cidr        = local.cluster.pod_cidr
    service_cidr    = local.cluster.service_cidr
    cni_plugin      = local.cluster.cni_plugin
    # --- 工具开关与下载地址 ---
    helm_enabled    = local.cluster.helm_enabled
    helm_url        = local.cluster.helm_url
    nerdctl_enabled = local.cluster.nerdctl_enabled
    nerdctl_url     = local.cluster.nerdctl_url
    bash_completion = local.cluster.bash_completion
    # --- 镜像仓库 (Harbor proxy 映射, disabled 时模板内条件跳过) ---
    harbor_enabled   = local.cluster.harbor_enabled
    harbor_host      = local.cluster.harbor_host
    harbor_ip        = local.cluster.harbor_ip
    harbor_upstreams = local.cluster.harbor_upstreams
    # --- 数据盘挂载点 ---
    data_mount = local.data_mount
  }
}
