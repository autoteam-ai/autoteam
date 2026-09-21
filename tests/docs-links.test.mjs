import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {markdownLinks} from '../scripts/docs-links.mjs';
import {checkDocsLinks} from '../scripts/check-docs-links.mjs';

test('relative Markdown links retain their version and fragment', () => {
  for (const base of ['/', '/autoteam/next/', '/autoteam/0.1.0/']) {
    const plugin = markdownLinks({base, source: '/docs'});
    const context = {fileURL: pathToFileURL('/docs/concepts/why.md')};
    for (const type of ['link', 'definition']) {
      const node = {type, url: '../limitations.md#限制', children: []};
      assert.equal(plugin[type](node, context).url, `${base}limitations/#限制`);
      assert.equal(plugin[type]({...node, url: '../README.md'}, context).url, base);
    }
    for (const url of ['#local', 'https://example.com/file.md', '//example.com/file.md', '/file.md', 'mailto:a@example.com']) {
      assert.equal(plugin.link({type: 'link', url: url}, context), undefined);
    }
    assert.throws(() => plugin.link({url: '../../outside.md'}, context), /escapes docs source/);
  }
});

test('checks parsed anchors and rejects a deliberately broken internal link', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'docs-links-'));
  try {
    await mkdir(path.join(directory, 'guide'));
    await writeFile(path.join(directory, 'guide/index.html'), '<a href="../#home">Home</a>');
    await writeFile(path.join(directory, 'index.html'), '<a href="guide/?x=1&amp;y=2#part">Guide</a><a href="https://example.com/missing">External</a>');
    await checkDocsLinks(directory, '/autoteam/next/');
    await writeFile(path.join(directory, 'index.html'), '<a href="/autoteam/next/missing/">Broken</a>');
    await assert.rejects(checkDocsLinks(directory, '/autoteam/next/'), /index.html: \/autoteam\/next\/missing\//);
    await writeFile(path.join(directory, 'index.html'), '<a href="https://autoteam-ai.github.io/autoteam/wrong/">Wrong version</a>');
    await assert.rejects(checkDocsLinks(directory, '/autoteam/next/'), /Broken internal links/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
