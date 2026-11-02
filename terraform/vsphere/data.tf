# =============================================================================
# data.tf — vSphere 环境数据源查询 (数据中心 / 主机 / 存储 / 网络 / 模板)
# =============================================================================

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
