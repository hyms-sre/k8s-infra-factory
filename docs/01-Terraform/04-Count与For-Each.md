# Count 与 For-Each

两者都让"一段 resource 代码"创建多份实例。

## count

```hcl
resource "aws_instance" "web" {
  count  = 3
  domain = "web${count.index}.example.com"
}
```

实例地址是 `web[0] web[1] web[2]`——**按下标**。列表中间删除一项时，
后面所有实例的下标位移 → 全部重建。适合"同质无个体身份"的资源。

## for_each（本项目选择）

```hcl
resource "vsphere_virtual_machine" "k8s_node" {
  for_each = local.nodes      # map: "主机名" => {vm_name, role, ip, cpu...}

  name     = each.value.vm_name
  num_cpus = each.value.cpu
}
```

实例地址是 `k8s_node["lab-hq-k8s01-master-01"]`——**按稳定键**。
增删节点只影响被增删的那个实例，其余不动。each.key / each.value 取键值。

## 为什么本项目用 for_each

- 节点有明确身份（主机名/IP），键稳定
- 扩容 = cluster.yaml 改 count → 重新 generate → plan 只出现新增节点
- 禁止为每个节点写 master01.tf/worker01.tf（一个 vm.tf + for_each 管全部）

## for 表达式（配合用）

```hcl
locals {
  nodes = { for n in var.node_list : n.hostname => n }   # list → map
  masters = [for h, n in local.nodes : h if n.role == "master"]
}
```

## 实战坑

- for_each 的键必须是**计划期已知**的字符串（不能是资源属性）
- 从 count 迁移到 for_each 需 `terraform state mv`（见 07 与 docs/99-参考/05）
