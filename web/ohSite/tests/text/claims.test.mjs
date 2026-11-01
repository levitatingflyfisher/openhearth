// Run after `npm run build`: `npm test`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { a3fDomainHits, readTextFiles, toPlainText, unnegatedTaxClaims } from './claims.mjs';

const DIST = fileURLToPath(new URL('../../dist', import.meta.url));

test('the check catches a 501(c)(3) claim without "not"', () => {
  assert.equal(unnegatedTaxClaims('a3f is a 501(c)(3) charity.').length, 1);
  assert.equal(unnegatedTaxClaims('We are a 501c3.').length, 1);
  assert.equal(unnegatedTaxClaims('This is not ours. A 501(c)(3) funds it.').length, 1);
});

test('the check passes a 501(c)(3) mention with "not" before it', () => {
  assert.deepEqual(unnegatedTaxClaims('a3f is not a tax-exempt 501(c)(3) yet.'), []);
  assert.deepEqual(unnegatedTaxClaims(toPlainText('<p>a3f is <em>not</em> a 501(c)(3).</p>')), []);
});

test('the check catches a3f.org in any case', () => {
  assert.equal(a3fDomainHits('see https://openhearth.a3f.org/apps').length, 1);
  assert.equal(a3fDomainHits('mail privacy@A3F.ORG').length, 1);
  assert.deepEqual(a3fDomainHits('a3f is not a tax-exempt 501(c)(3) yet.'), []);
});

test('the built site exists', () => {
  assert.ok(existsSync(DIST), 'dist/ is missing: run `npm run build` first');
});

test('no built page claims a 501(c)(3) without "not"', () => {
  const files = readTextFiles(DIST);
  assert.ok(files.length > 0, 'no text files in dist/');
  const hits = files.flatMap(({ path, text }) =>
    unnegatedTaxClaims(path.endsWith('.html') ? toPlainText(text) : text).map((h) => `${path}: ${h}`),
  );
  assert.deepEqual(hits, []);
});

test('no built file points at a3f.org', () => {
  const hits = readTextFiles(DIST).flatMap(({ path, text }) =>
    a3fDomainHits(text).map((h) => `${path}: ${h}`),
  );
  assert.deepEqual(hits, []);
});

test('the About page says a3f is not a tax-exempt 501(c)(3)', () => {
  const about = readTextFiles(DIST).find(({ path }) => path.endsWith('/about/index.html'));
  assert.ok(about, 'dist/about/index.html is missing');
  assert.match(toPlainText(about.text), /a3f is not a tax-exempt 501\(c\)\(3\) yet\./);
  assert.match(toPlainText(about.text), /Gifts to a3f are not tax-deductible\./);
  assert.doesNotMatch(toPlainText(about.text), /filing is planned/);
});
