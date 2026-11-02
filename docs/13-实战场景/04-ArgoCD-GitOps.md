# 场景: ArgoCD GitOps 落地

## 目标

"集群里跑什么由 Git 决定"：组件与应用全部声明式、可审计、可回滚。

## 步骤

### 1. 安装（k8s-plugins/gitops/argocd）

```bash
kubectl apply -n argocd -f https://.../install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
# UI 经 MetalLB/Gateway 暴露; CLI: argocd login
```

### 2. GitOps 仓库结构

```
gitops/
├── bootstrap/root-app.yaml        # App of Apps 入口
├── infrastructure/                # metal.yaml, longhorn.yaml, prometheus/ ...
└── apps/<app>/{base,overlays/{dev,prod}}
```

### 3. App of Apps 接管平台组件

```yaml
kind: Application
metadata: {name: infrastructure, namespace: argocd}
spec:
  source: {repoURL: <gitops>, path: infrastructure, directory: {recurse: true}}
  destination: {server: https://kubernetes.default.svc}
  syncPolicy: {automated: {selfHeal: true, prune: true}}
```

之后 k8s-plugins 的每个组件变成 infrastructure/ 下的目录（值文件入库）。

### 4. 应用发布流

CI 构建镜像 → PR 改 `apps/api/overlays/prod/kustomization.yaml` 的 image tag
→ merge → ArgoCD 自动同步（sync wave 控制顺序，prod 可选手动 sync 审批）。

## 运维要点

- 漂移处理：selfHeal 开启 = 手工 kubectl 改动会被还原（这是特性）；紧急热修先改 Git
- 大 CRD（Envoy Gateway）的 Application 记得 `ServerSideApply=true`
- 多集群：argocd cluster add <context> 注册，ApplicationSet 批量分发
- 回滚 = git revert；ArgoCD history 仅作应急

## 验证

```bash
argocd app list && argocd app get <app>     # Synced + Healthy
kubectl get applications -A                  # 资源视角
```
