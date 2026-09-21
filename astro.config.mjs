import {existsSync} from 'node:fs';
import path from 'node:path';
import {markdownLinks} from './scripts/docs-links.mjs';
import starlight from '@astrojs/starlight';
import {satteri} from '@astrojs/markdown-satteri';
import {defineConfig} from 'astro/config';
import {renderMermaidSVG} from 'beautiful-mermaid';

const base = process.env.AUTOTEAM_DOCS_BASE || '/';
const source = process.env.AUTOTEAM_DOCS_SOURCE || './docs';
const mermaidPlugin = {
  name: 'mermaid',
  code(node, context) {
    if (node.lang !== 'mermaid') return;

    try {
      const svg = renderMermaidSVG(node.value, {
        bg: 'var(--sl-color-bg)',
        fg: 'var(--sl-color-white)',
        accent: 'var(--sl-color-accent)',
        transparent: true,
      }).replace(/\s*@import url\('[^']+'\);\n?/g, '');

      return {
        type: 'html',
        value: `<figure class="mermaid-diagram">${svg}</figure>`,
      };
    } catch (error) {
      const file = context?.fileURL?.pathname || 'unknown file';
      throw new Error(`Unable to render Mermaid diagram in ${file}`, {cause: error});
    }
  },
};

export default defineConfig({
  site: 'https://autoteam-ai.github.io',
  base,
  outDir: process.env.AUTOTEAM_DOCS_OUT_DIR || './dist',
  markdown: {
    processor: satteri({mdastPlugins: [markdownLinks({base, source}), mermaidPlugin]}),
  },
  integrations: [
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
            // Historical versions may predate this page.
            ...(existsSync(path.join(source, 'concepts/invariants.md'))
              ? ['concepts/invariants'] : []),
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
        processedDirs: [source],
      },
      components: {
        LanguageSelect: './src/components/VersionSelect.astro',
        PageTitle: './src/components/PageTitle.astro',
      },
      credits: true,
    }),
  ],
});
