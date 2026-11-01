// Visual coverage — responsive screenshot sweep for ohSite.
//
// First layer of VISUAL test coverage (visual-loop, Pillar A / Playwright).
// ohSite is a static Astro marketing site with no logic tests; the thing most
// worth verifying is that the pages LAY OUT correctly across breakpoints. This
// script renders every route at mobile / tablet / desktop, writes one PNG per
// (route x size), and stitches a per-route contact-sheet montage so a human (or
// agent) can read ONE image and judge responsiveness at a glance.
//
// It is deliberately self-contained: it does not import any project source and
// has no effect on `astro build`. Run it manually against a running dev server.
//
// Prereqs:
//   - `playwright` + chromium available (e.g. via the shared visual-loop
//     harness in ~/.cache/oh-visual-loop, or `npx playwright install chromium`).
//   - ImageMagick (`magick`) on PATH for the montage (optional — the per-size
//     PNGs are still written if it is missing).
//
// Usage:
//   1. Start the site:        npm run dev        (default http://localhost:4321)
//   2. Run the sweep:         node tests/visual/screenshots.mjs
//
//   Env overrides:
//     OHSITE_BASE_URL   base URL of the running site   (default http://localhost:4321)
//     OHSITE_OUT_DIR    output directory for PNGs       (default /tmp/ohsite-visual)
//     OHSITE_FULL_PAGE  "1" to capture full scrollable page instead of viewport
//
// NOTE on the home page: most below-the-fold sections fade in via an
// IntersectionObserver (`src/scripts/reveal.ts`), so a single full-page capture
// shows them blank. The default viewport (above-the-fold) capture plus the
// built-in scroll-through is the reliable way to judge layout here.

import { mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

// Resolve playwright whether it is a local devDependency OR only present in the
// shared visual-loop harness (~/.cache/oh-visual-loop). ESM `import` ignores
// NODE_PATH, so locate the package file and import it by URL.
async function loadChromium() {
  const candidates = [
    'playwright', // local node_modules (if ever added as a devDependency)
    `${homedir()}/.cache/oh-visual-loop/node_modules/playwright`, // shared harness
  ];
  const req = createRequire(import.meta.url);
  for (const spec of candidates) {
    try {
      const resolved = req.resolve(spec);
      const mod = await import(pathToFileURL(resolved).href);
      // Named export when resolved via package exports; on `.default` when the
      // CJS index.js is imported directly by file URL.
      const chromium = mod.chromium ?? mod.default?.chromium;
      if (chromium) return chromium;
    } catch {
      /* try next */
    }
  }
  console.error(
    "Could not find 'playwright'. Install it with one of:\n" +
      '  npx playwright install chromium   (after `npm i -D playwright`)\n' +
      '  bash <visual-loop>/scripts/web-setup.sh   (shared harness in ~/.cache/oh-visual-loop)',
  );
  process.exit(2);
}

const chromium = await loadChromium();

const BASE = (process.env.OHSITE_BASE_URL || 'http://localhost:4321').replace(/\/$/, '');
const OUT = process.env.OHSITE_OUT_DIR || '/tmp/ohsite-visual';
const FULL = process.env.OHSITE_FULL_PAGE === '1';

// Recon-specified breakpoints: 360 / 768 / 1440.
const SIZES = [
  { name: 'mobile', width: 360, height: 740 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'desktop', width: 1440, height: 900 },
];

// Every route the static site ships.
const ROUTES = [
  { name: 'home', path: '/' },
  { name: 'privacy', path: '/privacy/' },
  { name: 'terms', path: '/terms/' },
  { name: 'about', path: '/about/' },
];

const browser = await chromium.launch();
let failures = 0;

for (const route of ROUTES) {
  const dir = `${OUT}/${route.name}`;
  mkdirSync(dir, { recursive: true });
  const shots = [];

  for (const vp of SIZES) {
    const page = await browser.newPage({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 1,
    });
    const url = `${BASE}${route.path}`;
    const resp = await page
      .goto(url, { waitUntil: 'networkidle', timeout: 30000 })
      .catch((e) => {
        console.error(`  ! navigation failed: ${url} (${e.message})`);
        return null;
      });
    if (!resp || !resp.ok()) {
      failures++;
      console.error(`  ! ${url} -> ${resp ? resp.status() : 'no response'}`);
    }

    // Trigger scroll-based / lazy / fade-in-on-scroll content, then return to top.
    await page.evaluate(async () => {
      await new Promise((resolve) => {
        let y = 0;
        const step = () => {
          window.scrollBy(0, window.innerHeight);
          y += window.innerHeight;
          if (y < document.body.scrollHeight) setTimeout(step, 50);
          else resolve();
        };
        step();
      });
    });
    await page.waitForTimeout(400);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(300);

    const out = `${dir}/shot-${vp.name}.png`;
    await page.screenshot({ path: out, fullPage: FULL });
    shots.push(out);
    console.log(`captured ${route.name} ${vp.name} (${vp.width}x${vp.height}) full=${FULL} -> ${out}`);
    await page.close();
  }

  const montage = `${dir}/montage.png`;
  try {
    execFileSync(
      'magick',
      ['montage', ...shots, '-tile', `${shots.length}x1`, '-geometry', '360x+8+8',
        '-background', '#dddddd', '-bordercolor', '#888', '-border', '1',
        '-label', '%f', '-gravity', 'North', '-pointsize', '12', montage],
      { stdio: 'inherit' },
    );
    console.log(`montage -> ${montage}   (Read this image)`);
  } catch {
    console.log(`(montage skipped — is ImageMagick installed? read the per-size PNGs in ${dir}/)`);
  }
}

await browser.close();

if (failures > 0) {
  console.error(`\n${failures} route(s) did not return 200 — see errors above.`);
  process.exit(1);
}
console.log(`\nDone. Output under ${OUT}/<route>/ — read each montage.png.`);
