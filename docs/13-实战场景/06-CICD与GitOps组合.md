# 场景: CI/CD 与 GitOps 组合

## 目标

代码合并到发布的全自动且可审计：CI 管构建，Git 管部署，人只审 PR。

## 架构

```
开发者 → 应用仓库 (代码) ──CI──► 构建/测试/镜像 → Harbor
                              └─► PR 修改 GitOps 仓库 (image tag)
GitOps 仓库 (部署真值) ──ArgoCD──► 集群
```

## 落地要点

1. **镜像规范**：tag 用 commit SHA / 语义版本（禁 latest）；推 Harbor 自有项目
2. **CI 侧**（Jenkins/GitLabCI/Tekton 任选, docs/03-CI-CD）：
   构建 → trivy 扫描（高危阻断）→ push → 用 PR bot 更新 GitOps 仓库 dev overlay
3. **GitOps 侧**（docs/13-实战场景/04）：dev 自动同步；prod 手动 sync（审批）
4. **晋升**：dev 验证后 PR 把 image 提到 prod overlay——同镜像跨环境，绝不重构建
5. **回滚**：git revert 即回滚（CI 无需参与）

## 流水线模板（GitLab CI 示意）

```yaml
stages: [build, scan, promote]
build: {stage: build, script: [docker build -t $HARBOR/app:$CI_COMMIT_SHA ., docker push ...]}
scan:  {stage: scan,  script: [trivy image --exit-code 1 --severity CRITICAL $HARBOR/app:$CI_COMMIT_SHA]}
```

promote 阶段在 GitOps 仓库提 PR（bot 凭据最小权限）。

## 安全

- CI 凭据最小化：Harbor 推送账号只写 CI 项目；GitOps PR bot 只能改 apps/ 目录
- 供应链：签名（cosign）+ Kyverno 仅签名镜像准入（docs/06-安全/04-05）
- Secret 不进流水线日志；用 CI 变量 masking + Secret 管理（docs/06-安全/03）

## 度量（接入 docs/11-SRE）

DORA 四指标：部署频率、变更前置时间、变更失败率、MTTR——从 CI/ArgoCD 事件即可统计。
