// =============================================================================
// index.jsx — 知识库落地页: hero + 分类卡片 (对齐 docs.youdianzhishi.com 风格的
// "docs-first" 首页: 直奔主题, 分类导航清晰)
// =============================================================================
import React from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

const categories = [
  { emoji: '🚀', to: '/docs/引言', title: '00 引言', desc: '项目是什么、整体架构、核心工具、快速开始、学习路线' },
  { emoji: '🧱', to: '/docs/Terraform', title: '01 Terraform', desc: '从 0 学 IaC：HCL、Provider、State、for_each、templatefile' },
  { emoji: '☸️', to: '/docs/Kubernetes', title: '02 Kubernetes', desc: '从 0 到 1 学 K8s + 本项目 kubeadm 集群引导实践' },
  { emoji: '🔁', to: '/docs/CI-CD', title: '03 CI/CD', desc: 'Jenkins / GitLab CI / Tekton 与完整流水线' },
  { emoji: '📈', to: '/docs/可观测性', title: '04 可观测性', desc: 'Prometheus / Grafana / Loki / OTel 监控日志告警' },
  { emoji: '🧭', to: '/docs/GitOps', title: '05 GitOps', desc: 'GitOps 原则、ArgoCD、Flux、渐进交付' },
  { emoji: '🔐', to: '/docs/安全', title: '06 安全', desc: 'RBAC、NetworkPolicy、镜像供应链、Kyverno、PKI' },
  { emoji: '💾', to: '/docs/存储', title: '07 存储', desc: 'CSI、NFS、Longhorn、Ceph/MinIO、备份恢复' },
  { emoji: '🗄️', to: '/docs/数据库', title: '08 数据库', desc: 'MySQL/PG/Redis/ES/Kafka 的 K8s 落地与 HA' },
  { emoji: '🏗️', to: '/docs/Platform-Engineering', title: '09 平台工程', desc: 'IDP、Golden Path、多租户、环境管理' },
  { emoji: '🤖', to: '/docs/AI-Ops', title: '10 AI-Ops', desc: 'SRE+AI、LLM Agent、安全执行（体系先行）' },
  { emoji: '🚨', to: '/docs/SRE', title: '11 SRE', desc: 'SLI/SLO/Error Budget、事件管理、灾备演练' },
  { emoji: '☁️', to: '/docs/云平台', title: '12 云平台', desc: 'vSphere 主线 + AWS/Aliyun 预留设计' },
  { emoji: '🧪', to: '/docs/实战场景', title: '13 实战场景', desc: 'CN 网络环境、入口暴露、监控栈、小型生产' },
  { emoji: '🎯', to: '/docs/体系学习', title: '14 体系学习', desc: '六阶段学习路径：前置条件→目标→实验→检查点，含自测验收' },
  { emoji: '📚', to: '/docs/参考', title: '99 参考', desc: '文件/凭据/配置/版本矩阵/排障/FAQ/术语/命令' },
];

function CategoryCard({ emoji, to, title, desc }) {
  return (
    <Link className="category-card" to={to}>
      <div className="category-card__emoji">{emoji}</div>
      <div className="category-card__body">
        <h3>{title}</h3>
        <p>{desc}</p>
      </div>
    </Link>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout title="知识库" description={siteConfig.tagline}>
      <header className="home-hero">
        <h1>{siteConfig.title}</h1>
        <p>{siteConfig.tagline}</p>
        <div className="home-hero__buttons">
          <Link className="button button--primary button--lg" to="/docs/引言">
            从这里开始 →
          </Link>
          <Link className="button button--secondary button--lg" to="/docs/体系学习">
            体系学习路径
          </Link>
        </div>
      </header>
      <main className="home-main">
        <section className="home-section">
          <h2>知识分类</h2>
          <div className="category-grid">
            {categories.map((c) => (
              <CategoryCard key={c.to} {...c} />
            ))}
          </div>
        </section>
        <section className="home-section">
          <h2>核心数据流</h2>
          <pre className="home-flow">{`cluster.yaml → generate.py → vm.tf (for_each) → terraform apply
    → vSphere VM × N → Cloud-Init → kubeadm-ready
    → kubeadm init / join → Kubernetes → k8s-plugins`}</pre>
        </section>
      </main>
    </Layout>
  );
}
