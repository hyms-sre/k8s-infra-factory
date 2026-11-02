# =============================================================================
# vm.tf — K8s 节点 VM 定义 (由 generate.py 自动生成, 勿手工编辑)
#
# 数据来源: cluster.yaml (改配置后重新执行 python generate.py)
# 结构: locals (cluster + nodes) + 一个 for_each 资源管理所有节点
# 生成时间: 2026-09-13 23:50:45
# =============================================================================

locals {
  # 集群级参数 (来源: cluster.yaml)
  cluster = {
    name                 = "lab-k8s01"
    environment          = "lab"
    location             = "hq"
    id                   = "k8s01"
    network_interface    = "ens192"
    user                 = "appuser"
    group                = "appowner"
    timezone             = "Asia/Shanghai"
    apt_mirror           = ""
    apt_suite            = "noble"
    ntp_servers          = []
    ssh_authorized_keys  = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyXs8z7Vm8m6L6yQ0dle3UTqFdCmaaRgUiNMrSYsOoC windows10@DESKTOP-7HA607D"]
    enable_password_auth = false
    vm_password          = ""
    k8s_version          = "1.36"
    k8s_apt_repo         = "https://pkgs.k8s.io/core:/stable:/v1.36/deb/"
    k8s_pause_image      = "registry.k8s.io/pause:3.10.1"
    crictl_version       = "v1.33.0"
    cni_plugin           = "cilium"
    pod_cidr             = "10.244.0.0/16"
    service_cidr         = "10.96.0.0/12"
    helm_enabled         = true
    helm_url             = "https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz"
    nerdctl_enabled      = true
    nerdctl_url          = "https://github.com/containerd/nerdctl/releases/download/v2.0.4/nerdctl-2.0.4-linux-amd64.tar.gz"
    bash_completion      = true
    harbor_enabled       = false
    harbor_host          = ""
    harbor_ip            = ""
    harbor_upstreams     = {}
  }

  # 节点集合: 键 = Linux 主机名 (稳定, 与 terraform state 对应)
  nodes = {
    "lab-hq-k8s01-master-01" = {
      vm_name     = "k8s01-master01[222.201]-20260913"
      role        = "master"
      index       = 1
      ip          = "172.16.222.201/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 4
      memory      = 6144
      disk        = 100
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
    "lab-hq-k8s01-master-02" = {
      vm_name     = "k8s01-master02[222.202]-20260913"
      role        = "master"
      index       = 2
      ip          = "172.16.222.202/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 4
      memory      = 6144
      disk        = 100
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
    "lab-hq-k8s01-master-03" = {
      vm_name     = "k8s01-master03[222.203]-20260913"
      role        = "master"
      index       = 3
      ip          = "172.16.222.203/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 4
      memory      = 6144
      disk        = 100
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
    "lab-hq-k8s01-worker-01" = {
      vm_name     = "k8s01-worker01[222.204]-20260913"
      role        = "worker"
      index       = 1
      ip          = "172.16.222.204/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 16
      memory      = 16384
      disk        = 200
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
    "lab-hq-k8s01-worker-02" = {
      vm_name     = "k8s01-worker02[222.205]-20260913"
      role        = "worker"
      index       = 2
      ip          = "172.16.222.205/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 16
      memory      = 16384
      disk        = 200
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
    "lab-hq-k8s01-worker-03" = {
      vm_name     = "k8s01-worker03[222.206]-20260913"
      role        = "worker"
      index       = 3
      ip          = "172.16.222.206/24"
      gateway     = "172.16.222.254"
      nameservers = ["172.16.222.210", "223.5.5.5"]
      cpu         = 16
      memory      = 16384
      disk        = 200
      data_disks = [
        {
          label = "disk1"
          size  = 50
          unit  = 1
        },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# 所有 K8s 节点 (master + worker) 由本资源批量管理, 禁止为单节点创建独立 .tf
# ---------------------------------------------------------------------------
resource "vsphere_virtual_machine" "k8s_node" {
  for_each = local.nodes

  # vSphere 显示名, 如 k8s01-master01[222.201]-20260907
  name                       = each.value.vm_name
  resource_pool_id           = data.vsphere_host.this.resource_pool_id
  datastore_id               = data.vsphere_datastore.this.id
  num_cpus                   = each.value.cpu
  memory                     = each.value.memory
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  scsi_type                  = data.vsphere_virtual_machine.template.scsi_type
  wait_for_guest_net_timeout = 0

  cdrom {
    client_device = true
  }

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # 系统盘 (置备参数沿用模板)
  disk {
    label            = "disk0"
    size             = each.value.disk
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  # 附加数据盘 (如 Longhorn 数据盘), 由 cluster.yaml 按角色生成
  dynamic "disk" {
    for_each = each.value.data_disks
    content {
      label            = disk.value.label
      size             = disk.value.size
      eagerly_scrub    = false
      thin_provisioned = true
      unit_number      = disk.value.unit
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # cloud-init via guestinfo (模板需 cloud-init >= 21.3)
  # metadata: 实例 ID + 静态网络;  userdata: OS 初始化 (见 user-data.yaml.tpl)
  extra_config = {
    "guestinfo.metadata" = base64encode(templatefile("${path.module}/meta-data.yaml.tpl", {
      hostname  = each.key
      interface = local.cluster.network_interface
      ip        = each.value.ip
      gateway   = each.value.gateway
      dns       = each.value.nameservers
    }))
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/user-data.yaml.tpl",
      merge(local.userdata_common, {
        hostname   = each.key
        role       = each.value.role
        data_disks = each.value.data_disks
    })))
    "guestinfo.userdata.encoding" = "base64"
  }

  lifecycle {
    # vm_name 含日期段; 改名不要通过 Terraform (避免销毁重建)
    ignore_changes = [name]
  }
}
