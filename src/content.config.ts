import {defineCollection} from 'astro:content';
import {glob} from 'astro/loaders';
import {i18nLoader} from '@astrojs/starlight/loaders';
import {docsSchema, i18nSchema} from '@astrojs/starlight/schema';

const docsSource = process.env.AUTOTEAM_DOCS_SOURCE || './docs';

export const collections = {
  docs: defineCollection({
    loader: glob({
      base: docsSource,
      pattern: '**/[^_]*.{md,mdx}',
    }),
    schema: docsSchema(),
  }),
  i18n: defineCollection({
    loader: i18nLoader(),
    schema: i18nSchema(),
  }),
};
