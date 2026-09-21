import {readFile, readdir, stat} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {parse} from 'parse5';

export async function checkDocsLinks(directory, base = '/', site = 'https://autoteam-ai.github.io') {
  const root = path.resolve(directory);
  const prefix = `/${base}/`.replace(/\/+/g, '/');
  const origin = new URL(site).origin;
  const failures = [];
  let checked = 0;
  async function walk(folder) {
    for (const entry of await readdir(folder, {withFileTypes: true})) {
      const file = path.join(folder, entry.name);
      if (entry.isDirectory()) { await walk(file); continue; }
      if (!entry.name.endsWith('.html')) continue;
      const relative = path.relative(root, file).split(path.sep).join('/');
      const page = new URL(prefix + relative.replace(/index\.html$/, ''), origin);
      const tree = parse(await readFile(file, 'utf8'));
      const hrefs = [];
      function visit(node) {
        if (node.tagName === 'a') {
          const href = node.attrs.find((attr) => attr.name === 'href')?.value;
          if (href !== undefined) hrefs.push(href);
        }
        for (const child of node.childNodes || []) visit(child);
      }
      visit(tree);
      for (const href of hrefs) {
        const url = new URL(href, page);
        if (url.origin !== origin || !['http:', 'https:'].includes(url.protocol)) continue;
        checked++;
        let exists = false;
        if (url.pathname.startsWith(prefix)) {
          const target = path.resolve(root, decodeURIComponent(url.pathname.slice(prefix.length)));
          if (target === root || target.startsWith(root + path.sep)) {
            try {
              const info = await stat(target);
              exists = info.isFile() || (info.isDirectory() && (await stat(path.join(target, 'index.html'))).isFile());
            } catch (error) {
              if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error;
            }
          }
        }
        if (!exists) failures.push(`${relative}: ${href}`);
      }
    }
  }
  await walk(root);
  if (failures.length) throw new Error(`Broken internal links (${failures.length}):\n${failures.join('\n')}`);
  console.log(`Checked ${checked} internal links in ${directory}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await checkDocsLinks(process.argv[2] || process.env.AUTOTEAM_DOCS_OUT_DIR || 'dist', process.argv[3] || process.env.AUTOTEAM_DOCS_BASE || '/');
}
