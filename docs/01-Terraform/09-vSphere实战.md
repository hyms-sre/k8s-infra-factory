# vSphere 实战（terraform/vsphere 精读）

本项目 terraform/vsphere/ 是 Terraform + Cloud-Init 的完整可运行参考。

## 文件分工

| 文件 | 职责 | 生成者 |
|---|---|---|
| cluster.yaml | 集群定义（数量/规格/网段/版本） | 用户 |
| generate.py | 节点计算 + vm.tf 生成 | 人维护 |
| vm.tf | locals(cluster+nodes) + for_each 资源 | **generate.py** |
| provider.tf / versions.tf | Provider 配置/版本约束 | 人维护 |
| variables.tf / data.tf | 凭据变量 / 环境数据源 | 人维护 |
| locals.tf / main.tf | 公共参数 / cloud-init 公共变量装配 | 人维护 |
| outputs.tf | 节点摘要 | 人维护 |
| user-data/meta-data.yaml.tpl | Cloud-Init 模板 | 人维护 |

## 设计要点

1. **generate.py → vm.tf → for_each → vsphere_virtual_machine**：
   Python 生成"参数和 VM 定义"，Terraform 管"资源生命周期"；一个资源管全部节点
2. **main.tf 的 userdata_common**：集群级模板变量集中装配；vm.tf 中每节点
   `merge(local.userdata_common, { hostname=..., role=..., data_disks=... })`
   ——公共与个体清晰分离
3. **data.tf 五个数据源**定位环境；模板/网卡/SCSI/置备参数全部继承自克隆源
4. **固定 IP**：meta-data.yaml.tpl（network v2）经 guestinfo.metadata 注入
5. **命名规范集中在 generate.py**：
   - hostname: `<env>-<loc>-<id>-<role>-<NN>`（如 test-cjl-k8s01-master-01）
   - vm_name: `<id>-<role><NN>[<IP后两段>]-<date>`（如 k8s01-master01[222.201]-20260907）

## 工作流

```bash
cd terraform/vsphere
python generate.py     # cluster.yaml → vm.tf + 摘要输出
terraform init / plan / apply
```

扩容：cluster.yaml 改 count → 重新 generate → plan 只见新增节点 → apply。
改规格：同上；num_cpus/memory/disk 变化对运行中 VM 是原地更新（部分需重启）。

## 验证清单（改完必跑）

```bash
python generate.py            # 检查输出: 节点数/IP/主机名/规格/版本
terraform fmt -recursive && terraform validate
```

模板渲染联检：terraform console 渲染 user-data/meta-data → YAML 校验
（方法见 08-templatefile与Cloud-Init.md）。
