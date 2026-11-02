# =============================================================================
# examples/harbor/variables.tf — Harbor VM 参数
# =============================================================================

# --- vSphere 连接 (凭据注入方式同 terraform/vsphere, 禁止提交明文) ---
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
variable "vm_template_name" { type = string }

# --- VM 定义 ---
variable "vm_name" {
  description = "vSphere 显示名, 如 k8s01-harbor01[222.207]-20260907"
  type        = string
}
variable "hostname" {
  description = "Linux 主机名, 如 test-cjl-harbor-registry-01"
  type        = string
}
variable "cpu" {
  type    = number
  default = 4
}
variable "memory" {
  type    = number
  default = 4096
}
variable "disk" {
  description = "系统盘 GB"
  type        = number
  default     = 40
}
variable "data_disk" {
  description = "Harbor 镜像数据盘 GB"
  type        = number
  default     = 200
}

# --- 网络 ---
variable "ip" {
  description = "固定 IP (不含掩码长度)"
  type        = string
}
variable "prefix" {
  description = "子网掩码长度"
  type        = number
  default     = 24
}
variable "gateway" { type = string }
variable "nameservers" {
  type    = list(string)
  default = ["223.5.5.5"]
}
variable "interface" {
  type    = string
  default = "ens192"
}

# --- 系统与 Harbor ---
variable "vm_user" {
  type    = string
  default = "appuser"
}
variable "vm_group" {
  type    = string
  default = "appowner"
}
variable "vm_timezone" {
  type    = string
  default = "Asia/Shanghai"
}
variable "ssh_authorized_keys" {
  type = list(string)
}
variable "apt_mirror" {
  description = "apt 镜像源, 空 = 官方源 (cn 环境用 https://mirrors.aliyun.com/ubuntu/)"
  type        = string
  default     = ""
}
variable "apt_suite" {
  type    = string
  default = "noble"
}
variable "harbor_version" {
  type    = string
  default = "v2.12.2"
}
variable "harbor_domain" {
  description = "Harbor 对外域名 (写入 /etc/hosts 与 harbor.yml hostname)"
  type        = string
}
variable "data_volume" {
  description = "数据盘挂载点 (harbor.yml data_volume)"
  type        = string
  default     = "/var/lib/harbor"
}
