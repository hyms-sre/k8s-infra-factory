# Tekton

## 定位

K8s 原生 CI 框架：流水线本身是 CRD（Task/Pipeline/Run），每个 step 是一个 Pod 容器。
无独立服务端——完全复用 K8s 的调度/凭据/可观测能力。适合"想把 CI 也声明式化/平台化"的团队。

## 核心对象

```yaml
# Task: 一组可复用步骤
kind: Task
spec:
  params: [{name: image}]
  steps:
  - name: build
    image: gcr.io/kaniko-project/executor    # 无 docker-in-docker 的镜像构建
    args: ["--destination=$(params.image)"]
---
# Pipeline: Task 编排
kind: Pipeline
spec:
  tasks:
  - {name: build, taskRef: {name: build-task}}
  - {name: test, taskRef: {name: test-task}, runAfter: [build]}
---
# PipelineRun: 一次执行
kind: PipelineRun
spec: {pipelineRef: {name: build-pipeline}, params: [...]}
```

- **Workspace**（PVC）在 Task 间传文件；**Results** 传值
- **Triggers**：webhook 事件自动创建 PipelineRun
- Dashboard 可视化；k8s-plugins/cicd/tekton 预留

## 与 Jenkins 的取舍

Tekton：云原生/可版本化/与 K8s 权限体系一致；学习曲线陡、生态较新。
Jenkins：生态全、上手快；master 是单点且有历史包袱。新集群无存量可优先 Tekton/Argo Workflows。
