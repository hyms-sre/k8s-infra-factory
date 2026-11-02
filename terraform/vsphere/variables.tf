# =============================================================================
# variables.tf — 仅保留 vSphere 环境连接参数
#
# 集群拓扑 / 节点规格 / K8s 参数等一切"数据"不在这里定义:
# 它们由 generate.py 读取 cluster.yaml 生成到 vm.tf (locals: cluster + nodes)。
#
# 凭据注入方式 (二选一, 禁止提交明文到 Git):
#   1. terraform/vsphere/terraform.tfvars  (从 examples/k8s/terraform.tfvars.example 复制)
#   2. 环境变量:  export TF_VAR_vsphere_password='...'
# =============================================================================

variable "vsphere_user" {
  description = "vCenter 用户名"
  type        = string
}

variable "vsphere_password" {
  description = "vCenter 密码"
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "vCenter 地址"
  type        = string
}

variable "vsphere_datacenter" {
  description = "数据中心名称"
  type        = string
}

variable "vsphere_host" {
  description = "独立 ESXi 主机地址 (无集群环境)"
  type        = string
}

variable "vsphere_datastore" {
  description = "虚拟机创建目标数据存储"
  type        = string
}

variable "vsphere_network" {
  description = "VM 网络端口组"
  type        = string
}

variable "vm_template_name" {
  description = "克隆用 Ubuntu Cloud Image 模板名 (需已安装 cloud-init >= 21.3 以支持 guestinfo 数据源)"
  type        = string
}
