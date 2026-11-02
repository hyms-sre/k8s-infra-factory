# GitLab CI

## 定位

GitLab 内置 CI/CD：配置即仓库里的 `.gitlab-ci.yml`，与代码 review/issue 天然一体。
自托管 GitLab 的团队首选（Runner 可跑在 K8s 内，见 k8s-plugins/cicd/gitlab-runner）。

## 核心概念

- **Pipeline**：一次完整执行，由 stages 组成
- **Stage**：阶段（build→test→deploy），同 stage 内 job 并行，失败即停
- **Job**：具体任务，跑在 **Runner** 上
- **Runner**：执行器；Kubernetes executor → 每个 job 一个临时 Pod

## .gitlab-ci.yml 骨架

```yaml
stages: [build, test, deploy]
build:
  stage: build
  image: docker:27
  script: [docker build -t $IMAGE:$CI_COMMIT_SHA .]
  only: {refs: [main, tags]}
test:
  stage: test
  image: python:3.12-slim
  script: [pip install -r requirements.txt && pytest]
deploy-dev:
  stage: deploy
  script: [kubectl -n dev set image ...]   # 或改 GitOps 仓库触发 ArgoCD
  environment: dev
```

## 与本项目

- Runner 部署在集群内（helm，gitlabUrl + registration token 走 Secret）
- 构建/缓存用集群内 Registry（Harbor）
- 部署阶段推荐改为"提交 GitOps 仓库"而非直接 kubectl（见 05-完整流水线）
