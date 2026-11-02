# Jenkins

## 定位

最经典的自动化服务器：插件生态最全，适合复杂/异构流水线。在 K8s 时代的定位：
存量资产维护 + 复杂编排（多系统联动、遗留系统集成）。

## K8s 上部署形态

- Deployment + PVC（JENKINS_HOME 持久化）或 k8s-plugins/cicd/jenkins 的 helm chart
- **Kubernetes 插件**：Jenkins master 动态创建 agent Pod 跑构建任务（按需伸缩、环境隔离）

```groovy
// Jenkinsfile (声明式)
pipeline {
  agent { kubernetes { yamlFile 'pod.yaml' } }
  stages {
    stage('Build')  { steps { sh 'make build' } }
    stage('Test')   { steps { sh 'make test' } }
    stage('Image')  { steps { sh 'docker build -t harbor.example.local/app:$GIT_COMMIT .' } }
    stage('Push')   { steps { withCredentials([usernamePassword(credentialsId:'harbor',...)])
                             { sh 'docker push ...' } } }
  }
}
```

## 要点

- 凭据进 Jenkins Credentials（不进代码、不进日志）
- agent Pod 需要 RBAC（只需操作自己 namespace 的 Pod）
- 产物推送 Harbor；部署动作交给 GitOps（ArgoCD）——CI/CD 解耦，见 05-完整流水线
