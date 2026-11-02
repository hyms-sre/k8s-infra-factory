# =============================================================================
# examples/harbor/main.tf — Harbor 镜像仓库 VM (独立 IaC, 不依赖 examples/k8s)
#
# Terraform 创建 VM 并注入 cloud-init; cloud-init 完成:
#   数据盘挂载 → Docker 安装 → Harbor 离线安装器部署
# 后续步骤 (HTTPS/TLS、Proxy Cache 项目、节点 certs.d 分发) 见本目录 README.md
# 与 docs/13-实战场景/02-CN网络环境.md。
# =============================================================================

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "this" {
  name = var.vsphere_datacenter
}

data "vsphere_host" "this" {
  name          = var.vsphere_host
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_datastore" "this" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.this.id
}

resource "vsphere_virtual_machine" "harbor" {
  name                       = var.vm_name
  resource_pool_id           = data.vsphere_host.this.resource_pool_id
  datastore_id               = data.vsphere_datastore.this.id
  num_cpus                   = var.cpu
  memory                     = var.memory
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  scsi_type                  = data.vsphere_virtual_machine.template.scsi_type
  wait_for_guest_net_timeout = 0

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.disk
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  # Harbor 镜像数据盘
  disk {
    label            = "disk1"
    size             = var.data_disk
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.metadata" = base64encode(templatefile("${path.module}/../../terraform/vsphere/meta-data.yaml.tpl", {
      hostname  = var.hostname
      interface = var.interface
      ip        = "${var.ip}/${var.prefix}"
      gateway   = var.gateway
      dns       = var.nameservers
    }))
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/user-data.yaml.tpl", {
      hostname            = var.hostname
      user                = var.vm_user
      group               = var.vm_group
      timezone            = var.vm_timezone
      ssh_authorized_keys = var.ssh_authorized_keys
      apt_mirror          = var.apt_mirror
      apt_suite           = var.apt_suite
      data_mount          = var.data_volume
      harbor_domain       = var.harbor_domain
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  lifecycle {
    ignore_changes = [name]
  }
}

output "harbor_ip" {
  value = var.ip
}

output "ssh_command" {
  value = "ssh ${var.vm_user}@${var.ip}"
}
