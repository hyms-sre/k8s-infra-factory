# Elastic Cloud on K8s (ECK)

> 状态：**规划中** (结构已建, 实现待补)

**定位**：Elasticsearch/Kibana 编排

**预期安装方式**：

```bash
kubectl apply -f eck-crds + eck-operator
```

**上游文档**：https://www.elastic.co/guide/en/cloud-on-k8s/

## 本目录约定

- 实现时在此放置 `README.md`(实际步骤) / `values.yaml` / `*.yaml` manifest / 离线包
- 安装命令写清: 前置条件 → 安装 → 验证 → 卸载
- 国内环境镜像拉取问题参考 `docs/10-cn-profile.md` (Harbor proxy cache)
