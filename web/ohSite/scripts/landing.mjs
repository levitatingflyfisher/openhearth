// Copy the built site (dist/) into the landing repo, the public front door.
//
//   node scripts/landing.mjs <landing repo>
//
// `npm run landing` runs `verify` first, then this, with the landing repo
// beside this one. It commits nothing; the board reviews and pushes.
//
// What it keeps: everything in the landing repo the build did not make. The
// glean/ and porch/ web builds and the fonts/ folder are never touched, even
// when dist/ has a folder of the same name (dist/fonts is for `npm run dev`).
// What it replaces: each top-level entry the last run wrote (listed in
// .ohsite-build.json), then each top-level entry of dist/. So a page taken
// out of the site is taken out of the landing repo too.

import { cpSync, existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const KEEP = new Set(['.git', '.gitignore', '.nojekyll', 'glean', 'porch', 'fonts']);
export const MANIFEST = '.ohsite-build.json';

/** Copy `dist` into `target`. Returns { written, kept }. */
export function landing(dist, target) {
  if (!existsSync(join(dist, 'index.html'))) throw new Error(`${dist} has no index.html: build first`);
  if (!existsSync(join(target, '.git'))) throw new Error(`${target} is not a git repo`);

  const manifest = join(target, MANIFEST);
  const before = existsSync(manifest) ? JSON.parse(readFileSync(manifest, 'utf8')) : [];
  for (const name of before) {
    if (KEEP.has(name) || name.includes('/') || name.startsWith('..')) continue;
    rmSync(join(target, name), { recursive: true, force: true });
  }

  const written = [];
  const kept = [];
  for (const name of readdirSync(dist).sort()) {
    if (KEEP.has(name)) {
      kept.push(name);
      continue;
    }
    rmSync(join(target, name), { recursive: true, force: true });
    cpSync(join(dist, name), join(target, name), { recursive: true });
    written.push(name);
  }
  writeFileSync(manifest, JSON.stringify(written, null, 2) + '\n');
  return { written, kept };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const target = process.argv[2];
  if (!target) {
    console.error('usage: node scripts/landing.mjs <landing repo>');
    process.exit(2);
  }
  const dist = fileURLToPath(new URL('../dist', import.meta.url));
  const { written, kept } = landing(dist, resolve(target));
  console.log(`wrote ${written.join(', ')}`);
  console.log(`kept as they were: ${kept.join(', ') || 'none from dist'}`);
}
