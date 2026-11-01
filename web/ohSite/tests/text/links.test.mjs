// Run after `npm run build`: `npm test`.
//
// Every link inside the built site must land on a file the build made, and
// every #fragment on an id that page has. Links to other addresses are
// skipped, never fetched: the check runs offline. It lists what it skipped.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { checkLinks, isExternal } from './links.mjs';

const DIST = fileURLToPath(new URL('../../dist', import.meta.url));

test('the link check tells an outside address from an inside one', () => {
  assert.ok(isExternal('https://github.com/levitatingflyfisher'));
  assert.ok(isExternal('//example.com/x'));
  assert.ok(isExternal('mailto:someone@example.com'));
  assert.ok(!isExternal('/about/'));
  assert.ok(!isExternal('#apps'));
  assert.ok(!isExternal('fonts.css'));
});

test('the link check finds a missing page and a missing id', () => {
  const { broken } = checkLinks(fileURLToPath(new URL('./fixtures/broken', import.meta.url)));
  assert.deepEqual(broken.sort(), [
    'index.html -> /gone/',
    'index.html -> /other/#nowhere',
    'other/index.html -> style.css',
  ]);
});

test('every link inside the site lands on a built file and id', (t) => {
  const { broken, skipped, checked } = checkLinks(DIST);
  t.diagnostic(`checked ${checked} links inside the site`);
  t.diagnostic(`skipped ${skipped.length} outside links (not fetched):`);
  for (const url of skipped) t.diagnostic(`  skip ${url}`);
  assert.ok(checked > 0, 'no inside links found');
  assert.deepEqual(broken, []);
});
