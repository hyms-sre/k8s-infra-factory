# 依赖与 Module

## 依赖

Terraform 自动按引用关系构建依赖图：A 引用了 B，就先创建 B。

```hcl
resource "vsphere_virtual_machine" "k8s_node" {
  # 引用了 data.vsphere_datacenter.this → 自动先查 datacenter
  datacenter_id = data.vsphere_datacenter.this.id
}
```

显式控制（引用不足以表达时才用）：

```hcl
depends_on = [vsphere_virtual_machine.k8s_node]
```

原则：**优先靠引用**，depends_on 是最后手段（它会强行串行化）。

## Module

Module 是"可复用的 Terraform 代码目录"：

```hcl
module "network" {
  source = "./modules/network"
  cidr   = "10.0.0.0/16"
}
```

- 每个 module 有自己的 variables/outputs，通过它们传参/取值
- 根模块（root module）= terraform 执行的工作目录

## 本项目的克制

**不要为了模块化而模块化**。本项目刻意不用多层 module：
- 只有 vsphere 一个平台一个 root，目录即结构
- "模块化"的价值 < 增加的间接层成本时，直接写平
- 经验法则：一个模块少于 ~100 行且只有一处调用 → 不值得抽
