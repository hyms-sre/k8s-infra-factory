# cert-manager

> 状态：**规划中** (结构已建, 实现待补)

**定位**：证书自动签发与续期 (ACME/自建 CA)

**预期安装方式**：

```bash
kubectl apply cert-manager manifest
```

**上游文档**：https://cert-manager.io/

## 本目录约定

- 实现时在此放置 `README.md`(实际步骤) / `values.yaml` / `*.yaml` manifest / 离线包
- 安装命令写清: 前置条件 → 安装 → 验证 → 卸载
- 国内环境镜像拉取问题参考 `docs/10-cn-profile.md` (Harbor proxy cache)
