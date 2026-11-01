// Run after `npm run build`: `npm test`.
//
// The home page is the public landing page (board-0176: the one link on the
// Christmas card). These checks hold the owner's rulings for its app cards.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { cards, footerText, homePage, hrefs } from './site.mjs';
import { toPlainText } from './claims.mjs';

const DIST = fileURLToPath(new URL('../../dist', import.meta.url));

// The 17 apps, by name and link target, as the hand-kept landing page had
// them. A card's id is a public link target (for example #trellis): keep it.
const APPS = [
  ['Sundial', 'sundial'],
  ['Furrow', 'furrow'],
  ['Bulwark', 'bulwark'],
  ['Peckish', 'peckish'],
  ['WeatherGlass', 'weatherglass'],
  ['NightGlass', 'nightglass'],
  ['Parlour', 'parlour'],
  ['Lilt', 'lilt'],
  ['Punctum Temporis', 'punctumtemporis'],
  ['Lullaby', 'lullaby'],
  ['Trellis', 'trellis'],
  ['Hatch', 'hatch'],
  ['StillLife', 'stilllife'],
  ['Reckon', 'reckon'],
  ['Mantle', 'mantle'],
  ['Porch', 'porch'],
  ['glean', 'glean'],
];

// The final line for each card and the intro (14 Nov 2026), word for word.
// They passed blind reads; change them only with a new read.
const LINES = {
  Trellis: 'Read your own books and articles, listen to podcasts, and quiz yourself to remember.',
  Peckish: 'Plan the week’s dinners, keep family recipes, and get the grocery list.',
  Lullaby: 'Log your baby’s feeds, sleep and diapers.',
  StillLife: 'A list of everything in your home, for insurance or a move.',
  WeatherGlass: 'Today’s weather and the week ahead, with no tracking.',
  NightGlass: 'Tonight’s stars and planets from your campsite, even with no signal.',
  Sundial: 'Time how long you spend outside, and watch the hours add up over the year.',
  Furrow: 'Track the habits you choose, one tick a day, on a simple grid.',
  Bulwark: 'Health habits picked for you from research, a few at a time.',
  Parlour: 'Classic games like tic-tac-toe to pass around the family table.',
  Hatch: 'Children learn their times tables and hatch a critter for each one.',
  Lilt: 'Two of you pick a baby name by choosing between pairs.',
  'Punctum Temporis': 'Film one second every day and watch your year as a short movie.',
  Reckon: 'Write down a big decision and what you think will happen. Later, see how it went.',
  Mantle: 'Choose between pictures of homes, rooms and clothes to find your family’s style.',
  Porch: 'Share with close friends when you’re free to talk. Still being tested.',
  glean: 'A family budget app for your computer. You can also read it in a browser.',
};
const INTRO =
  'Free apps for family life. Open any of them in your browser, on a phone or a computer. ' +
  'What you save stays on your device unless you choose to share it. No accounts, no ads.';

// Owner: "sideloading is FOSS freedom." Never remove or reword this line.
const SIDELOAD =
  'Each app is a Progressive Web App — open it in your phone\'s browser and choose ' +
  '“Install” / “Add to Home screen” to keep it offline. Android users can also sideload the APK.';

const home = () => homePage(DIST);
const byId = (id) => cards(home()).find((c) => c.id === id);

test('every one of the 17 apps has a card, with its link target id', () => {
  const found = cards(home()).map((c) => [c.name, c.id]);
  assert.deepEqual(found, APPS);
});

test('every card has one plain line, and no line has an em dash', () => {
  for (const c of cards(home())) {
    assert.ok(c.line, `${c.name} has no line`);
    assert.ok(!c.line.includes('—'), `${c.name}'s line has an em dash: ${c.line}`);
  }
});

test('every card shows its final line, word for word', () => {
  const found = Object.fromEntries(cards(home()).map((c) => [c.name, c.line]));
  assert.deepEqual(found, LINES);
});

test('the hero shows the final intro, word for word', () => {
  assert.ok(toPlainText(home()).includes(INTRO));
});

test('every card with an APK link shows "Android app ↓"', () => {
  const withApk = cards(home()).filter((c) => hrefs(c.html).some((h) => /\.apk$/i.test(h)));
  assert.ok(withApk.length >= 15, `only ${withApk.length} cards link an APK`);
  for (const c of withApk) {
    assert.match(c.text, /Android app ↓/, `${c.name} links an APK without the button text`);
  }
});

test('the sideload line is in the footer, word for word', () => {
  const footer = footerText(home());
  assert.ok(footer, 'the home page has no footer');
  assert.ok(footer.includes(SIDELOAD), `footer is: ${footer}`);
});

test('Trellis keeps its web app and APK links', () => {
  const links = hrefs(byId('trellis').html);
  assert.ok(links.includes('https://levitatingflyfisher.github.io/Trellis/'));
  assert.ok(links.includes('https://github.com/levitatingflyfisher/Trellis/releases/latest/download/Trellis.apk'));
});

test('porch says its web preview is paused and keeps the APK', () => {
  const c = byId('porch');
  assert.match(c.text, /Web preview: paused →/);
  assert.match(c.text, /Android app ↓/);
  const links = hrefs(c.html);
  assert.ok(links.includes('https://levitatingflyfisher.github.io/porch/'));
  assert.ok(links.includes('https://github.com/levitatingflyfisher/levitatingflyfisher.github.io/releases/download/porch-preview/Porch.apk'));
});

test('glean keeps its web viewer, desktop downloads by OS and "All platforms"', () => {
  const c = byId('glean');
  assert.match(c.text, /Web viewer →/);
  assert.match(c.text, /All platforms/);
  const all = c.html;
  const base = 'https://github.com/levitatingflyfisher/levitatingflyfisher.github.io/releases/';
  for (const asset of [
    'download/glean-desktop-v0/glean-windows-setup.exe',
    'download/glean-desktop-v0/glean-macos.dmg',
    'download/glean-desktop-v0/glean-x86_64.AppImage',
    'tag/glean-desktop-v0',
  ]) {
    assert.ok(all.includes(base + asset), `glean is missing ${asset}`);
  }
  assert.ok(hrefs(all).includes('https://levitatingflyfisher.github.io/glean/'));
});

test('no font or script comes from another server', () => {
  const html = home();
  const outside = [
    ...html.matchAll(/<link\b[^>]*href="(https?:)?\/\/[^"]*"[^>]*>/gi),
    ...html.matchAll(/<script\b[^>]*src="(https?:)?\/\/[^"]*"[^>]*>/gi),
  ].map((m) => m[0]);
  assert.deepEqual(outside, []);
  assert.match(html, /href="\/fonts\/fonts\.css"/);
});
