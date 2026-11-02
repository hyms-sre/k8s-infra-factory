# Variable / Local / Output

## Variable（输入）

```hcl
variable "vsphere_password" {
  description = "vCenter 密码"
  type        = string
  sensitive   = true          # plan/apply 输出中打码
}

variable "vm_features" {
  type = object({
    helm = optional(bool, true)   # 可选字段 + 默认值
  })
  default = {}

  validation {                     # 输入校验
    condition     = ...
    error_message = "..."
  }
}
```

注入方式：`terraform.tfvars`（gitignore!）、`-var`、`TF_VAR_<name>` 环境变量。
本项目 variables.tf 只保留 vSphere 连接参数 + 模板名——凭据永远走 tfvars/env。

## Local（内部计算值）

```hcl
locals {
  data_mount = "/var/lib/longhorn"
  userdata_common = {            # 可嵌套 map/复杂表达式
    user = local.cluster.user
    ...
  }
}
```

Local 是"中间变量"，避免同一表达式重复出现。注意：locals 命名空间全局共享，
可分布在多个 .tf 文件（本项目 vm.tf 的 cluster/nodes 与 main.tf 的 userdata_common）。

## Output（输出）

```hcl
output "nodes" {
  description = "节点清单"
  value = [for host, n in local.nodes : { hostname = host, ip = n.ip }]
}
```

用途：apply 后的人读摘要、跨模块/跨 root 传值（remote state）、给 CI 消费。
本项目 outputs.tf 输出 cluster_name / nodes / ssh_commands。

## 选择原则

| 值 | 用什么 |
|---|---|
| 用户/环境要注入的 | variable |
| 派生/复用的中间值 | local |
| 要给"人/下游"看的 | output |
