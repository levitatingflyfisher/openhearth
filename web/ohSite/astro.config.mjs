import { defineConfig } from 'astro/config';

// Static HTML. `npm run landing` copies dist/ into the landing repo (GitHub Pages).
export default defineConfig({
  site: 'https://levitatingflyfisher.github.io',
  base: process.env.OH_SITE_BASE || '/',
  output: 'static',
  // Astro 7 defaults to 'jsx', which drops the space between inline elements.
  // true keeps the whitespace rules the pages were written and checked under.
  compressHTML: true,
  build: {
    format: 'directory',
  },
});
