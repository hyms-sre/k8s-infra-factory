# Provider / Resource / Data Source

## Provider

Provider 是 Terraform 与某个平台 API 的适配器。

```hcl
# versions.tf: 声明依赖
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.0"
    }
  }
}

# provider.tf: 配置连接
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}
```

注意：vsphere provider 的官方源是 `vmware/vsphere`（不是 hashicorp/vsphere）。

## Resource

Resource 声明"要创建/管理的对象"，是 Terraform 的核心：

```hcl
resource "vsphere_virtual_machine" "k8s_node" {
  for_each = local.nodes          # 批量 (见 04)
  name     = each.value.vm_name
  num_cpus = each.value.cpu
  memory   = each.value.memory
  ...
}
```

引用方式：`vsphere_virtual_machine.k8s_node["lab-hq-k8s01-master-01"]`。

## Data Source

Data Source 查询"已存在的信息"（只读，不创建）：

```hcl
data "vsphere_datacenter" "this" { name = var.vsphere_datacenter }
data "vsphere_host" "this" { name = var.vsphere_host; datacenter_id = data.vsphere_datacenter.this.id }
data "vsphere_datastore" "this" { ... }
data "vsphere_network" "this" { ... }
data "vsphere_virtual_machine" "template" { name = var.vm_template_name; ... }  # 克隆源模板
```

本项目 data.tf 用 5 个 data source 定位环境（数据中心/主机/存储/网络/模板），
vm.tf 中通过 `data.xxx.this.<属性>` 引用。

## 经验

- Resource 管"要变成什么"，Data Source 管"现在是什么"——别用 resource 去读环境
- provider 版本用 `~>` 锁 minor（如 `~> 2.0` 允许 2.x），配 .terraform.lock.hcl 精确锁定
