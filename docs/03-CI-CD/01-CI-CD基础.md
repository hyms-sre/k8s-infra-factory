# CI/CD 基础

## 概念

- **CI (持续集成)**：代码合入后自动 构建 + 测试 → 快速发现集成问题
- **CD (持续交付/部署)**：构建产物自动流转到可发布/已发布状态
- 区别：交付 (delivery) 到"随时可发"，部署 (deployment) 直接到生产（通常靠 GitOps 控制）

## 流水线的标准阶段

```
Git commit → Build (编译/打包) → Test (单测/集成) → Container Image (构建镜像)
→ Push Registry → Deploy (K8s manifest/helm) → 验证
```

## Git 在流水线中的角色

- 触发器：push / MR / tag 触发不同级别的流水线
- 版本唯一真值：commit SHA / git tag 即镜像 tag（可追溯）
- **Everything as Code**：流水线定义本身入库（Jenkinsfile/.gitlab-ci.yml/tekton yaml）

## Container Image 与 Registry

```dockerfile
FROM python:3.12-slim          # 小基础镜像
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt   # 依赖层先变少变
COPY . .
USER 1000                       # 非 root
```

多阶段构建（builder/runtime 分离）可把镜像压到几十 MB。Registry：Harbor
（本项目 examples/harbor，兼做 proxy cache）。

## 制品管理

- 制品类型：镜像、helm chart、二进制、单测报告
- 原则：**一次构建，多环境部署**（同一镜像 tag 流转到 dev/prod，禁止每环境重构建）
- Harbor 支持 chart 仓库与镜像保留策略

## 供应链安全

- 基础镜像来源可信 + 固定 digest
- 镜像签名 (cosign) / SBOM (syft) / 漏洞扫描 (Trivy) → docs/06-安全/04
- CI 凭据最小化（流水线 token 而非长期密码）
