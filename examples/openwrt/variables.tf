# =============================================================================
# examples/openwrt/variables.tf — OpenWrt VM 参数
# =============================================================================

variable "vsphere_user" { type = string }
variable "vsphere_password" {
  type      = string
  sensitive = true
}
variable "vsphere_server" { type = string }
variable "vsphere_datacenter" { type = string }
variable "vsphere_host" { type = string }
variable "vsphere_datastore" { type = string }
variable "vsphere_network" { type = string }

variable "vm_template_name" {
  description = "OpenWrt vSphere 模板名 (由 openwrt.vmdk 制作, 见 README.md)"
  type        = string
}

variable "vm_name" {
  description = "vSphere 显示名, 如 k8s01-openwrt01[222.210]-20260907"
  type        = string
}
variable "cpu" {
  type    = number
  default = 2
}
variable "memory" {
  type    = number
  default = 4096
}
variable "disk" {
  type    = number
  default = 40
}

variable "ip" {
  description = "OpenWrt LAN IP (集群出口/DNS)"
  type        = string
}
