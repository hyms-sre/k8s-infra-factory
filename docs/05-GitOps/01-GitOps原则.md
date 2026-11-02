# GitOps 原则

## 四原则（OpenGitOps）

1. **声明式**：系统期望状态用声明式描述（K8s manifest/Helm/Kustomize）
2. **版本化且不可变**：期望状态在 Git，变更=commit（可审计可回滚）
3. **自动拉取**：agent 自动从 Git 拉取期望状态并应用到集群
4. **持续调和**：agent 持续对比"实际 vs Git"，发现漂移自动纠正或告警

## Pull vs Push

| | Push (CI 直接 kubectl/helm) | Pull (GitOps agent) |
|---|---|---|
| 谁有集群凭据 | CI 系统 | 仅集群内 agent |
| 漂移检测 | 无 | 持续 |
| 真值 | 难说 | Git |
| 安全边界 | CI 权限很大 | CI 只需写 Git |

生产推荐 Pull。Push 适合小团队起步/开发环境。

## 仓库布局（推荐 monorepo 分目录）

```
gitops-repo/
├── apps/          应用 (每应用一目录: base + overlays)
│   └── api/{base,overlays/dev,overlays/prod}
├── infrastructure/ 集群组件 (ingress/存储/观测)
└── clusters/      每集群的根 Application/解耦入口
```

环境差异用 Kustomize overlays 或 helm values 文件表达，**不用分支区分环境**（分支易漂移）。
