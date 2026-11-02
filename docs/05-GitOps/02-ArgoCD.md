# ArgoCD

## 架构与部署

API Server + Repo Server（渲染 manifest）+ Application Controller（调和）+
UI。安装：`kubectl apply -n argocd -f install.yaml`（k8s-plugins/gitops/argocd）。

```bash
argocd admin initial-password -n argocd   # 初始 admin 密码
argocd login <host>
```

## Application

```yaml
kind: Application
spec:
  source:
    repoURL: https://git.example.com/ops/gitops.git
    targetRevision: main
    path: apps/api/overlays/dev
  destination: {server: https://kubernetes.default.svc, namespace: api}
  syncPolicy:
    automated: {prune: true, selfHeal: true}   # 自动同步 + 删除孤儿 + 自愈漂移
    syncOptions: [CreateNamespace=true]
```

健康状态：Synced/OutOfSync（Git vs 集群）+ Healthy/Degraded（运行状态）。

## App of Apps 与 ApplicationSet

- **App of Apps**：一个根 Application 管一组 Application（引导整个集群的组件清单）
- **ApplicationSet**：模板化批量生成 Application（多集群/多环境/多目录）

```yaml
kind: ApplicationSet
spec:
  generators: [{git: {repoURL: ..., directories: [{path: apps/*}]}}]
  template: {...path: '{{.path.path}}'...}
```

## 同步策略

- 手动 sync：审批发布（prod 常用）
- automated+selfHeal：全托管（dev 常用）
- Sync waves / hooks：有序发布（先 DB 迁移后应用）
- 重要的 Sync options：`ServerSideApply=true`（大 CRD 必备，本项目 Envoy Gateway 实测）

## 与本项目

部署 ArgoCD 后把 k8s-plugins 的组件接管成 App of Apps，实现"集群引导完 ArgoCD 接管一切"。
