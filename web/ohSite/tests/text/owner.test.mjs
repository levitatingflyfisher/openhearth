// Run after `npm run build`: `npm test`.
//
// The owner's own words on the home page. Only the owner decides whether
// they are on the page; nobody removes or rewords them. These checks make
// sure nothing drops them silently.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { toPlainText } from './claims.mjs';
import { footerText, homePage } from './site.mjs';

const DIST = fileURLToPath(new URL('../../dist', import.meta.url));

const BELIEF =
  'We believe family life deserves software that feels home-cooked — made with the same care as a Sunday dinner, ' +
  'by people who think raising kids well is the work that matters most. Everything we ship follows from that.';
const WHO_FOR =
  'Married couples. Big families. Families who want to be big. People who think children are a blessing, not a carbon footprint.';
const MISSION =
  'Built for the families doing the long, ordinary work of raising the next generation.';
const BLURB = 'Beautifully-made free apps for families. We are firmly opposed to gay marriage.';

const text = () => toPlainText(homePage(DIST)).replace(/\s+([.,])/g, '$1');

test('the belief band renders, word for word', () => {
  assert.ok(text().includes(BELIEF));
});

test('"Who this is for" renders, word for word', () => {
  assert.ok(text().includes(WHO_FOR));
});

test('the mission stripe renders, word for word', () => {
  assert.ok(text().includes(MISSION));
});

test('the footer blurb renders, word for word', () => {
  assert.ok(footerText(homePage(DIST)).includes(BLURB));
});

test('the home page keeps its order: hero, belief, who for, apps, mission, footer', () => {
  const t = text();
  const at = [
    t.indexOf('Calm, private tools for the life of a home.'),
    t.indexOf(BELIEF),
    t.indexOf(WHO_FOR),
    t.indexOf('The apps'),
    t.indexOf(MISSION),
    t.indexOf(BLURB),
  ];
  assert.ok(at.every((i) => i >= 0), `missing a piece: ${at}`);
  assert.deepEqual([...at].sort((a, b) => a - b), at);
});
