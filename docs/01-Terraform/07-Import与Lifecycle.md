# Import 与 Lifecycle

## Import：收编存量资源

手工建过的资源想交给 Terraform 管：先写好 resource 声明，再导入 state。

```bash
# Terraform ≥ 1.5 推荐配置式 import (可 review、可 plan):
import {
  to = vsphere_virtual_machine.k8s_node["legacy-vm"]
  id = "vm-1234"        # vSphere moref
}

# 旧语法 (立即写 state):
terraform import 'vsphere_virtual_machine.k8s_node["legacy-vm"]' vm-1234
```

导入后 `terraform plan` 会显示"配置与实际资源的差异"，把配置补齐到无 diff 即收编完成。

## Lifecycle

resource 内的生命周期钩子：

```hcl
lifecycle {
  ignore_changes = [name]           # 忽略指定属性的漂移 (本项目: vm_name 含日期段,
}                                   #  改名不应触发销毁重建)
```

其它常用项：

| 参数 | 作用 |
|---|---|
| `create_before_destroy = true` | 先建新再删旧（替换类更新不断服） |
| `prevent_destroy = true` | 禁止销毁（保护关键资源，如数据库 VM） |
| `replace_triggered_by` | 由其它资源/变量变化触发替换 |

## 本项目实践

- `vm.tf` 的 `ignore_changes = [name]`：防止 vSphere 显示名（含日期段）变更引发重建
- 已部署集群重构目录后：用 `state mv` 对齐地址而不是重新 apply
  （命令与注意事项见 docs/99-参考/05-故障排查.md）
