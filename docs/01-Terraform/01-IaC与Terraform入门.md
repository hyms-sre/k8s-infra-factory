# IaC 与 Terraform 入门

## IaC（Infrastructure as Code）

用代码声明基础设施，而不是控制台点点点：

- **声明式**：描述期望状态（"要 3 台 4C8G 的 VM"），工具计算怎么到达
- **可重复**：同一份代码在任何环境产出相同结果
- **可版本化**：Git 管理变更历史，可 review、可回滚
- **可销毁重建**：destroy 后 apply 即从零复原

## 安装

见 docs/00-引言/04-快速开始.md（winget / apt / brew）。
本项目要求 Terraform ≥ 1.5（versions.tf 中约束）。

## HCL 基础

```hcl
# 块 (block): 类型 + 标签 + {}
resource "vsphere_virtual_machine" "k8s_node" {
  # 参数 (argument): key = value
  name = "k8s01-master01"

  # 嵌套块
  disk {
    label = "disk0"
    size  = 100
  }
}
```

常用语法：

```hcl
"字符串 ${var.name} 插值"          # 插值
local.x  /  var.x  /  data.x.y    # 值引用
[for n in var.list : n.cpu]       # for 表达式
{for n in var.list : n.name => n} # map for 表达式
condition ? a : b                 # 三元
try(a.b, "默认")                   # 容错取值
```

## 标准工作流

```bash
terraform init      # 初始化: 下载 provider
terraform plan      # 预览变更 (+创建 -删除 ~更新)
terraform apply     # 执行
terraform destroy   # 销毁
terraform fmt       # 格式化
terraform validate  # 语法/引用校验
```

plan 是 IaC 的灵魂：执行前先看清楚会发生什么。
