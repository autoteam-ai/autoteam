import {existsSync} from 'node:fs';
import path from 'node:path';

// 各版本共用导航顺序，但只展示该版本实际包含的文档。
export function filterSidebar(items, source) {
  return items.flatMap((item) => {
    if (typeof item === 'object' && 'items' in item) {
      const children = filterSidebar(item.items, source);
      return children.length ? [{...item, items: children}] : [];
    }
    const slug = typeof item === 'string' ? item : item.slug;
    if (slug === undefined) return [item];
    const file = slug === '/' ? 'README' : slug;
    return ['.md', '.mdx'].some((extension) => existsSync(path.join(source, file + extension)))
      ? [item] : [];
  });
}
