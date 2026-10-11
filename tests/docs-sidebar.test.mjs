import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {filterSidebar} from '../site/scripts/docs-sidebar.mjs';

test('version navigation omits missing pages and empty nested groups', async () => {
  const source = await mkdtemp(path.join(tmpdir(), 'docs-sidebar-'));
  try {
    await mkdir(path.join(source, 'guide'));
    await writeFile(path.join(source, 'README.md'), '');
    await writeFile(path.join(source, 'guide/existing.mdx'), '');
    const home = {slug: '/', label: '首页'};
    const page = {slug: 'guide/existing', label: '已有页面'};
    const external = {label: 'GitHub', link: 'https://github.com'};
    const sidebar = [home, {label: '指南', items: [
      'guide/new', page, {label: '空组', items: ['missing']},
    ]}, external];
    assert.deepEqual(filterSidebar(sidebar, source), [
      home, {label: '指南', items: [page]}, external,
    ]);
    await writeFile(path.join(source, 'guide/new.md'), '');
    assert.deepEqual(filterSidebar(sidebar, source)[1].items, ['guide/new', page]);
    assert.equal(sidebar[1].items.length, 3);
  } finally {
    await rm(source, {recursive: true, force: true});
  }
});
