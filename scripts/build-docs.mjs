import {execFileSync, spawnSync} from 'node:child_process';
import {mkdir, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const output = path.join(root, 'build', 'docs-site');
const temp = path.join(root, '.docs-version');
const repository = process.env.GITHUB_REPOSITORY || 'autoteam-ai/autoteam';
const siteRoot = normalizeRoot(process.env.AUTOTEAM_DOCS_ROOT || '/');
const customDomain = process.env.AUTOTEAM_DOCS_DOMAIN || 'autoteam.hdgcs.com';

const tags = execFileSync('git', ['tag', '--list', 'v[0-9]*', '--sort=-v:refname'], {
  encoding: 'utf8',
})
  .trim()
  .split('\n')
  .filter(Boolean);
const versions = tags.map((tag) => tag.replace(/^v/, ''));
const publishedVersions = ['next', ...versions].join(',');

await rm(output, {recursive: true, force: true});
await rm(temp, {recursive: true, force: true});
await mkdir(output, {recursive: true});
await mkdir(temp, {recursive: true});

await buildVersion({
  source: path.join(root, 'docs'),
  version: 'next',
  base: `${siteRoot}next/`,
  destination: path.join(output, 'next'),
});

for (const [index, tag] of tags.entries()) {
  const version = versions[index];
  const checkout = path.join(temp, version);
  await mkdir(checkout, {recursive: true});

  const archive = execFileSync('git', ['archive', tag, 'docs']);
  const extracted = spawnSync('tar', ['-x', '-C', checkout], {input: archive});
  if (extracted.status !== 0) {
    throw new Error(`无法提取 ${tag} 的 docs：${extracted.stderr?.toString() || 'tar 失败'}`);
  }

  const docsSource = path.join(checkout, 'docs');
  await prepareHistoricalDocs(docsSource, tag);
  await buildVersion({
    source: docsSource,
    version,
    base: `${siteRoot}${version}/`,
    destination: path.join(output, version),
  });
}

const latest = versions[0] || 'next';
await writeFile(
  path.join(output, 'versions.json'),
  `${JSON.stringify({latest, versions, development: 'next'}, null, 2)}\n`
);
await writeFile(path.join(output, 'CNAME'), `${customDomain}\n`);
await writeFile(path.join(output, '.nojekyll'), '');
await writeFile(
  path.join(output, 'index.html'),
  `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="refresh" content="0;url=./${latest}/">
    <title>autoteam 文档</title>
    <script>location.replace('./${latest}/' + location.search + location.hash)</script>
  </head>
  <body><a href="./${latest}/">前往 autoteam 文档</a></body>
</html>
`
);

await rm(temp, {recursive: true, force: true});
console.log(`文档站已生成：${path.relative(root, output)}（${versions.length} 个发布版本 + 开发版）`);

function buildVersion({source, version, base, destination}) {
  console.log(`构建文档版本 ${version}`);
  execFileSync(path.join(root, 'node_modules', '.bin', 'astro'), ['build'], {
    cwd: root,
    env: {
      ...process.env,
      AUTOTEAM_DOCS_SOURCE: source,
      AUTOTEAM_DOCS_VERSION: version,
      AUTOTEAM_DOCS_VERSIONS: publishedVersions,
      AUTOTEAM_DOCS_ROOT: siteRoot,
      AUTOTEAM_DOCS_BASE: base,
      AUTOTEAM_DOCS_OUT_DIR: destination,
    },
    stdio: 'inherit',
  });
}

async function prepareHistoricalDocs(directory, tag) {
  for (const file of await markdownFiles(directory)) {
    let content = await readFile(file, 'utf8');
    if (!content.startsWith('---\n')) {
      const title = content.match(/^#\s+(.+)$/m)?.[1];
      if (!title) throw new Error(`${tag}:${path.relative(directory, file)} 没有一级标题`);
      const slug = path.basename(file).toLowerCase() === 'readme.md' ? '\nslug: /' : '';
      content = `---\ntitle: ${JSON.stringify(title)}${slug}\n---\n\n${content}`;
    }

    content = content.replace(
      /\]\(\.\.\/\.\.\/(skills\/[^)]+)\)/g,
      `](https://github.com/${repository}/blob/${tag}/$1)`
    );
    await writeFile(file, content);
  }
}

async function markdownFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await markdownFiles(fullPath)));
    else if (/\.mdx?$/.test(entry.name)) files.push(fullPath);
  }
  return files;
}

function normalizeRoot(value) {
  return `/${value}/`.replace(/\/+/g, '/');
}
