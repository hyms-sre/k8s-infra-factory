# =============================================================================
# examples/openwrt/main.tf — OpenWrt 出口网关 VM (独立 IaC)
#
# OpenWrt 官方镜像不带 cloud-init, 因此采用两步法:
#   1. 一次性: 由 openwrt.vmdk 制作 vSphere 模板 (见 README.md 第 1 节)
#   2. 本 Terraform: 克隆模板创建 VM; 网络配置用 files/configure.sh (uci) 完成
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

resource "vsphere_virtual_machine" "openwrt" {
  name                       = var.vm_name
  resource_pool_id           = data.vsphere_host.this.resource_pool_id
  datastore_id               = data.vsphere_datastore.this.id
  num_cpus                   = var.cpu
  memory                     = var.memory
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  wait_for_guest_net_timeout = 0

  # OpenWrt x86-64 squashfs-combined 镜像为 BIOS 引导 (见 README 制作模板一节)
  firmware = "bios"

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = "vmxnet3"
  }

  disk {
    label            = "disk0"
    size             = var.disk
    eagerly_scrub    = false
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # OpenWrt 无 cloud-init/guestinfo: 首启后用 files/configure.sh 通过 SSH 配置
  lifecycle {
    ignore_changes = [name]
  }
}

output "ssh_command" {
  value = "ssh root@${var.ip}   # 首次配置: bash files/configure.sh <ip>"
}
