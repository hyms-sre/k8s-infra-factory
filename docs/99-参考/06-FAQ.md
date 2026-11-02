# FAQ

**Q: 为什么要自己写 generate.py 而不是直接用 Terraform 变量？**
节点数量×规格×IP×主机名的组合用 HCL 变量表达笨重且易错；Python 十几行循环即可生成，
并且能做 IP 冲突检查、奇数校验、版本联动等逻辑。Python 只生成参数和 vm.tf，
生命周期仍归 Terraform——这是本项目的核心设计。

**Q: generate.py 会覆盖我手工改过的 vm.tf 吗？**
会（vm.tf 是生成物）。手工调整请改 cluster.yaml 后重新生成；确需手工修改请把它
改成 generate.py 模板的一部分。

**Q: Cloud-Init 会装 kubeadm init 吗？**
不会。Cloud-Init 只到 kubeadm-ready（三件套已装、containerd 就绪）。集群引导是
有状态的一次性操作，用文档驱动（docs/02-Kubernetes/07），明确、可排错、不藏在脚本里。

**Q: 固定 IP 是怎么实现的？DHCP 吗？**
非 DHCP。meta-data.yaml.tpl（network v2 格式）经 guestinfo.metadata 注入，
cloud-init 首启配置静态 IP/网关/DNS。IP 来自 cluster.yaml。

**Q: 想加一台 worker 怎么办？**
cluster.yaml workers.count+1 → `python generate.py` → plan（只出现新节点）→ apply。
for_each 保证已有节点不动。

**Q: 换网段/换集群名呢？**
改 cluster.yaml 对应字段重新 generate。**注意**：改已有节点的 IP/主机名 =
新建+销毁（对运行中集群是破坏性变更），扩缩容只动 count。

**Q: cn 和 default 是两套代码吗？**
不是。同一个 generate.py/Terraform/Cloud-Init，只是 cluster.yaml 的镜像源/Harbor
配置不同（live/lab/vsphere/cn/cluster/cluster.yaml.example）。

**Q: AWS/Aliyun 什么时候支持？**
预留中（terraform/aws、terraform/aliyun 只有 README）。实现时遵循 vsphere 层的
结构蓝本；不为未来平台提前抽象。

**Q: Terraform state 丢了怎么办？**
state 是账本：丢了 Terraform 不再认识现有 VM。恢复靠备份；无备份则手工
import 或按 IP 清理后重建（docs/01-Terraform/06、07）。

**Q: 文档为什么按主题分类而不是按代码结构？**
docs 是知识体系（是什么/为什么/怎么设计/怎么排错），不是代码目录的镜像；
未来用 Docusaurus 建站（docs/00-引言/05-学习路线 是入口）。
