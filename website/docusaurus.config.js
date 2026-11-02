// =============================================================================
// docusaurus.config.js — iac-k8s-esxi 知识库站点配置
//
// 文档源: 仓库根 docs/ (单源, 不复制) — docs.path = '../docs'
// 排除:   docs/archive/ (历史归档不入站)
// 样式:   classic 主题 + 本地离线搜索 (中文分词, 免 Algolia 账号)
// =============================================================================
// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'iac-k8s-esxi 知识库',
  tagline: 'vSphere Kubernetes IaC / Environment Generator — Terraform + Cloud-Init + kubeadm',

  url: 'https://example.com', // 部署时改成你的域名 (GitHub Pages/Vercel)
  baseUrl: '/',               // 子路径部署时改为 '/<repo>/'

  onBrokenLinks: 'warn',      // 链接解析失败时降级为告警

  // 纯 Markdown 解析 (无 JSX): 知识库正文大量使用 <占位符>, MDX 会误判为 JSX 组件
  markdown: {
    format: 'md',
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'zh-Hans',
    locales: ['zh-Hans'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          path: '../docs',          // ★ 单一数据源: 仓库根 docs/
          routeBasePath: 'docs',
          sidebarPath: './sidebars.js',
          exclude: ['**/archive/**', '**/_*.{js,jsx,ts,tsx,json}'],
        },
        blog: false,                // 不使用博客功能
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themes: ['@easyops-cn/docusaurus-search-local'],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig & any} */
    ({
      colorMode: {
        defaultMode: 'light',
      },
      // 右侧目录 (TOC): 支持到 5 级标题
      //
      // Docusaurus 默认 minHeadingLevel=2 / maxHeadingLevel=3,
      // 也就是【只显示 h2 和 h3】, h4/h5 会被静默丢弃 —— 文档里写了也看不到。
      //
      // ⚠️ minHeadingLevel 不能设为 1:
      //    Docusaurus 的配置校验会直接报错
      //    `"tableOfContents.minHeadingLevel" must be greater than or equal to 2`
      //    因为 h1 就是页面标题本身, 放进目录会重复。
      //    所以"1–5 级"实际落地为 **h2–h5**; 需要连 h6 也显示就把 max 改成 6。
      tableOfContents: {
        minHeadingLevel: 2,
        maxHeadingLevel: 5,
      },
      // 语法高亮: 补齐 Prism 默认集缺的语言
      //
      // 知识库实际用到的围栏语言 (grep 统计):
      //   bash 158 / yaml 30 / hcl 24 / toml 3 / text 1 / shell 1 /
      //   promql 1 / groovy 1 / dockerfile 1 / (ps) 1 / logql 1
      //
      // ⚠️ logql 特意不列入: prismjs 无 prism-logql 语言包,
      //    实测 require('prismjs/components/prism-logql') 报 MODULE_NOT_FOUND,
      //    加进来会让 npm run build 直接失败。该块以纯文本渲染
      //    (见 docs/04-可观测性/04-Loki.md), 徽标仍正常显示。
      prism: {
        additionalLanguages: [
          'hcl', 'docker', 'toml', 'ini', 'promql', // 计划内
          'groovy', 'diff', 'powershell',           // 知识库实际使用, 补齐
        ],
      },
      '@easyops-cn/docusaurus-search-local': {
        hashed: true,
        docsRouteBasePath: 'docs',
        language: ['zh', 'en'],
        highlightSearchTermsOnTargetPage: true,
      },
      navbar: {
        title: 'iac-k8s-esxi',
        items: [
          { to: '/', label: '首页', position: 'left' },
          { to: '/docs', label: '知识库', position: 'left' },
          {
            type: 'dropdown',
            label: '分类',
            position: 'left',
            items: [
              { to: '/docs/引言', label: '00 引言' },
              { to: '/docs/Terraform', label: '01 Terraform' },
              { to: '/docs/Kubernetes', label: '02 Kubernetes' },
              { to: '/docs/CI-CD', label: '03 CI/CD' },
              { to: '/docs/可观测性', label: '04 可观测性' },
              { to: '/docs/GitOps', label: '05 GitOps' },
              { to: '/docs/安全', label: '06 安全' },
              { to: '/docs/存储', label: '07 存储' },
              { to: '/docs/数据库', label: '08 数据库' },
              { to: '/docs/Platform-Engineering', label: '09 平台工程' },
              { to: '/docs/AI-Ops', label: '10 AI-Ops' },
              { to: '/docs/SRE', label: '11 SRE' },
              { to: '/docs/云平台', label: '12 云平台' },
              { to: '/docs/实战场景', label: '13 实战场景' },
              { to: '/docs/体系学习', label: '14 体系学习' },
              { to: '/docs/参考', label: '99 参考' },
            ],
          },
          {
            href: 'https://github.com/',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'light',
        copyright: `Copyright © ${new Date().getFullYear()} iac-k8s-esxi · Terraform + Cloud-Init + kubeadm`,
      },
    }),
};

export default config;
