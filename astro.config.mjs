import starlight from '@astrojs/starlight';
import {defineConfig} from 'astro/config';
import mermaid from 'astro-mermaid';

const base = process.env.AUTOTEAM_DOCS_BASE || '/';

export default defineConfig({
  site: 'https://autoteam.hdgcs.com',
  base,
  outDir: process.env.AUTOTEAM_DOCS_OUT_DIR || './dist',
  integrations: [
    mermaid({autoTheme: true, enableLog: false}),
    starlight({
      title: 'autoteam',
      description: '让 agent 团队自己完成交付，人只负责批准任务',
      favicon: 'favicon.svg',
      locales: {
        root: {label: '简体中文', lang: 'zh-CN'},
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/autoteam-ai/autoteam',
        },
      ],
      sidebar: [
        {slug: '/', label: '文档首页'},
        {
          label: '概念',
          items: [
            'concepts/why',
            'concepts/roles',
            'concepts/lifecycle',
            'concepts/quota-routing',
            'concepts/guardrails',
          ],
        },
        {
          label: '搭建',
          items: [
            'setup/prerequisites',
            'setup/quickstart',
            'setup/repo',
            'setup/github',
            'setup/multica',
            'setup/first-run',
          ],
        },
        {
          label: '日常操作',
          items: [
            'operations/daily',
            'operations/metrics',
            'operations/troubleshooting',
          ],
        },
        {
          label: '参考',
          items: [
            'reference/cli',
            'reference/config',
            'reference/files',
            'limitations',
          ],
        },
      ],
      customCss: ['./src/styles/docs.css'],
      markdown: {
        processedDirs: [process.env.AUTOTEAM_DOCS_SOURCE || './docs'],
      },
      components: {
        LanguageSelect: './src/components/VersionSelect.astro',
        PageTitle: './src/components/PageTitle.astro',
      },
      credits: true,
    }),
  ],
});
