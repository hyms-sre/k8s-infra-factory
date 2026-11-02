# State 与 Backend

## State 是什么

`terraform.tfstate` 是 Terraform 的**账本**：记录它管理的每个真实资源的
ID 与属性映射（VM 的 moref、IP、磁盘…）。plan/apply 都依赖"配置 ↔ state ↔ 真实
环境"三方对比。

## 关键纪律（本项目强约束）

- **不入 Git**（含敏感明文；已在 .gitignore）
- **不随手删除**：删了 = Terraform 不再认识现有 VM，下次 apply 会试图重建
- **要备份**：与 tfvars 同级重要；本项目默认 local state，备份即复制
  `terraform/vsphere/terraform.tfstate`(+`.backup`)
- **重构目录时跟着 Terraform 根走**；资源地址变了用 `terraform state mv` 迁移
  （本项目实录见 docs/99-参考/05-故障排查.md）

## 常用 state 命令

```bash
terraform state list                    # 列出管理的资源
terraform state mv <旧地址> <新地址>     # 地址迁移 (重构/改名)
terraform state rm <地址>               # 脱管 (不销毁真实资源)
terraform show                          # 查看全部状态
```

## Backend

Backend 决定 state 存哪里。默认 `local`（当前目录文件）。

```hcl
terraform {
  backend "s3" {                        # 或 oss / consul / pg ...
    bucket = "my-tfstate"
    key    = "k8s/vsphere.tfstate"
    region = "..."
  }
}
```

远端 backend 的价值：团队协作加锁防并发写、集中备份、敏感数据集中管控。
单人/实验环境 local 足够——**按需启用，不过度工程化**。
