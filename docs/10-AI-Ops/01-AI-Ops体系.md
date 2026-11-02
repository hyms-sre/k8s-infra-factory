# AI-Ops 体系（知识框架，随项目演进逐步落地）

> 当前只建立体系与约定，不为 AI-Ops 写复杂代码。

## AI-Ops 的层次

1. **辅助排障**：LLM 阅读 alert/日志/manifest，生成假设与排查步骤（人执行）
2. **半自动化**：Agent 调用工具（kubectl/查询 API）执行只读诊断，人确认修复
3. **自动化闭环**：明确的 Runbook 场景（磁盘清理、Pod 重启）授权 Agent 自动执行
4. **预测性**：容量预测、异常检测（时序模型）前置到告警之前

## LLM Agent 的基本构成

```
LLM (推理) + 工具 (kubectl/HTTP API/SQL) + 记忆 (事件/知识库)
+ 策略 (何时升级给人) + 审计 (每一步可回放)
```

工具即能力：Agent 能做什么取决于给它什么工具与什么权限——这使"权限设计"成为
AI-Ops 的核心安全议题。

## 落地场景（本项目语境）

| 场景 | 输入 | 输出 |
|---|---|---|
| Pod CrashLoop 诊断 | events/logs/deployment yaml | 原因假设 + 修复建议 |
| 容量巡检 | Prometheus 指标 | 扩容建议（cluster.yaml diff） |
| 告警分诊 | Alertmanager webhook | 严重性/归属/关联 Runbook |
| 知识库问答 | docs/ 与 runbook | 操作指引（引用出处） |

## 安全执行（铁律）

- **只读优先**：诊断类工具只授 get/list/describe/logs；写操作必须人确认
- **最小凭据**：专用 ServiceAccount + RBAC，绝不复用 admin.conf
- **可审计**：Agent 每次工具调用留痕（谁、何时、什么命令、结果）
- **爆炸半径**：危险动词（delete/apply）走双人复核或仅生成建议
- **手册即代码**：Runbook 结构化入 Git，Agent 引用而非"自由发挥"

## 演进路线

本仓库的自然路径：docs 知识结构化（已做）→ 诊断 Runbook 模板化 →
只读诊断 Agent（对接 Prometheus/Loki API）→ 授权自动化（按 Runbook 逐条放开）。
