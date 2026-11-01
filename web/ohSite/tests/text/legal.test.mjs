// Run after `npm run build`: `npm test`.
//
// The owner's ruling (15 Nov 2026): the site names no governing law and no
// state, city or place of the owner. The apps need nothing beyond the MIT
// License, so the terms page is one short statement of it. The privacy page
// says only where the data lives: a fact, not a contract.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readTextFiles, toPlainText } from './claims.mjs';

const DIST = fileURLToPath(new URL('../../dist', import.meta.url));
const page = (name) =>
  toPlainText(readFileSync(join(DIST, name, 'index.html'), 'utf8'))
    .replace(/\s+/g, ' ');

const LAW = /governing law|governed by|laws of|jurisdiction|venue|arbitration/i;

test('no page names a governing law', () => {
  const hits = readTextFiles(DIST)
    .filter((f) => f.path.endsWith('.html'))
    .filter((f) => LAW.test(toPlainText(f.text)))
    .map((f) => f.path);
  assert.deepEqual(hits, []);
});

test('the terms page is the MIT License, as is, with a link to its text', () => {
  const html = readFileSync(join(DIST, 'terms', 'index.html'), 'utf8');
  const text = page('terms');
  assert.match(text, /free software under the MIT License/);
  assert.match(text, /as is, with no warranty of any kind/);
  assert.ok(html.includes('href="https://opensource.org/license/mit"'));
  assert.doesNotMatch(text, /\b(liability|indemnif|terminate|agree to)/i);
});

test('the privacy page says where data lives, and holds no clauses', () => {
  const text = page('privacy');
  assert.match(text, /on your own device/);
  assert.doesNotMatch(
    text,
    /constitutes acceptance|we may update|COPPA|Cloudflare|Named|Google Play/i,
  );
});
