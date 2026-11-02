# Linux 与容器安全

## 节点基线（本项目 Cloud-Init 已覆盖的部分）

- 最小化安装（Ubuntu server cloud image + 仅必要包）
- SSH 仅密钥（ssh_pwauth: no）、运维用户 sudo 免密可控
- 无手工追加式配置（幂等 write_files），配置漂移可审计
- 内核参数基线（sysctl.d/70-k8s.conf）

延伸加固方向：自动安全更新（unattended-upgrades）、auditd、fail2ban、
磁盘加密（敏感行业）、主机防火墙（nftables 限定端口）。

## 容器隔离边界

容器**不是**虚拟机——共享内核，隔离靠：

- **namespaces**：PID/网络/mount/user 等视图隔离
- **cgroups**：资源限额
- **capabilities**：默认删除大部分特权能力；`--privileged` 等于放弃隔离，禁止
- rootless 容器 / user namespace 重映射：把容器 root 映射到宿主普通用户
- seccomp/AppArmor：系统调用过滤（Ubuntu 自带 docker-default profile）

## 威胁模型要点

- 内核漏洞 = 全部容器沦陷 → 及时打内核补丁
- 挂载 docker.sock / hostPath 敏感目录 = 变相 root → Pod Security 限制（见 06）
- 镜像里带密钥是最常见泄漏源 → 构建时最小化 COPY + secret 扫描
