# templatefile 与 Cloud-Init

这是本项目"基础设施 → 机器初始化"的桥梁，务必理解。

## templatefile()

Terraform 内置函数：渲染文本模板。

```hcl
templatefile("${path.module}/user-data.yaml.tpl", {
  hostname = each.key
  role     = each.value.role
  ...      # 模板里引用的所有变量 (少了会报错, 多了会被忽略)
})
```

模板语法：

```text
${var}                     插值
%{ if cond }...%{ endif }  条件块
%{ for x in list }...%{ endfor }  循环
%%{ ... }                  注释中展示指令本身要转义 (否则注释里的 %{ 会被当真!)
```

⚠️ 实测坑：模板**注释**里写 `%{ if x }` 示例会被当成真指令导致
"Unexpected end of template"——注释中一律写 `%%{`。

## Cloud-Init 与 guestinfo

VMware 云镜像内置的 cloud-init 有 VMware 数据源，首启读取 VM 的 extra_config：

```hcl
extra_config = {
  "guestinfo.metadata"          = base64encode(templatefile("meta-data.yaml.tpl", {...}))
  "guestinfo.metadata.encoding" = "base64"
  "guestinfo.userdata"          = base64encode(templatefile("user-data.yaml.tpl", {...}))
  "guestinfo.userdata.encoding" = "base64"
}
```

- `meta-data.yaml.tpl`：instance-id + local-hostname + **静态网络配置**（network v2 格式）
  ——这是本项目实现固定 IP 的机制（IP 来自 cluster.yaml，不用 DHCP）
- `user-data.yaml.tpl`：#cloud-config，OS 初始化的全部逻辑（到 kubeadm-ready）

要求：模板内 cloud-init ≥ 21.3（Ubuntu noble 满足）。

## 调试

- 节点上：`cloud-init status --long`、`cat /var/log/cloud-init-output.log`
- 本地预览渲染结果：`terraform console` 里执行同款 templatefile 表达式，
  输出贴给 `python -c 'import yaml,sys; yaml.safe_load(sys.stdin.read())'` 验证
- 注意：cloud-init 是 **per-instance** 的——修改模板后对已有 VM 重跑 apply
  更新了 extra_config 也不会重跑，需重建 VM
