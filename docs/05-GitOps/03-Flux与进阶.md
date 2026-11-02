# Flux 与进阶实践

## Flux CD

GitOps Toolkit（source-controller / kustomize-controller / helm-controller / …）：

```bash
flux bootstrap git --url=ssh://git@... --path=clusters/lab   # 引导即装好
```

- 概念映射：GitRepository/Kustomization/HelmRelease CR
- HelmRelease：Git 里只放 values，chart 由 helm-controller 渲染

```yaml
kind: HelmRelease
spec:
  chart: {spec: {chart: kube-prometheus-stack, sourceRef: {kind: HelmRepository, name: prom}}}
  values: {grafana: {enabled: true}}
```

- **ArgoCD vs Flux**：ArgoCD UI/应用模型友好、团队使用体验好；
  Flux 组件化轻量、与 CI 流水线集成顺滑。团队型选 ArgoCD，管道型选 Flux。二选一即可。

## Helm + GitOps

两种模式：Git 存完整渲染产物（直观、可 diff）vs Git 存 values 由 agent 渲染（简洁）。
小团队推荐 values 模式（ArgoCD 的 helm source 或 Flux HelmRelease）。

## 多环境 / 多集群

- 多环境：同 ApplicationSet 生成 dev/staging/prod 三套（path/cluster generator 区分）
- 多集群：ArgoCD 注册多个 destination cluster（secret 管理 kubeconfig）；
  或每集群一个 Flux bootstrap 指向同一仓库不同 path

## 回滚

- GitOps 回滚 = `git revert`（agent 自动调和回去）——最可靠
- 紧急热修：直接 kubectl 改集群 → 产生漂移 → selfHeal 会覆盖它（这正是设计行为）；
  正确姿势永远是改 Git

## Progressive Delivery（渐进交付）

金丝雀/蓝绿由 CR 驱动：Argo Rollouts（与 ArgoCD 同生态）或 Flagger（配 Prometheus 指标自动分析）：

```yaml
kind: Rollout      # Argo Rollouts: 替换 Deployment
strategy:
  canary: {steps: [{setWeight: 10}, {pause: {duration: 5m}}, {setWeight: 50}]}
```

配合 Gateway API/MetalLB 流量分割实现按百分比发布。
