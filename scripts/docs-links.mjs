import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function markdownLinks({base, source}) {
  const root = path.resolve(source);
  function rewrite(node, context) {
    if (/^(?:[a-z][a-z\d+.-]*:|[/#])/i.test(node.url)) return;
    const match = node.url.match(/^([^?#]+)\.md([?#].*)?$/i);
    if (!match) return;
    const target = path.resolve(path.dirname(fileURLToPath(context.fileURL)), decodeURIComponent(match[1]) + '.md');
    const relative = path.relative(root, target);
    if (relative.startsWith('../') || path.isAbsolute(relative)) {
      throw new Error(`Markdown link escapes docs source: ${node.url}`);
    }
    const route = relative.replace(/\\/g, '/').replace(/\.md$/i, '').replace(/(^|\/)README$/i, '$1');
    return {...node, url: `${base}/${route}/`.replace(/\/+/g, '/') + (match[2] || '')};
  }
  return {name: 'docs-markdown-links', link: rewrite, definition: rewrite};
}
