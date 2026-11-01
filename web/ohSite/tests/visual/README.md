# Visual coverage

First layer of **visual** test coverage for ohSite. The site is a static Astro
marketing site with no logic to unit-test — the thing worth verifying is that
the pages **lay out** correctly across screen sizes. This harness renders every
route at mobile / tablet / desktop, screenshots each, and stitches a per-route
contact sheet so you can read one image and judge responsiveness at a glance.

This is the [`visual-loop`](https://) Pillar A (Playwright) approach: don't
guess layout from the source — render it and read the screenshot.

## Run it

```bash
# 1. install a browser for Playwright (one-time)
npx playwright install chromium

# 2. start the site
npm run dev            # http://localhost:4321

# 3. in another shell, run the sweep
node tests/visual/screenshots.mjs
```

Output lands in `/tmp/ohsite-visual/<route>/` — open each `montage.png` and
look for: overflow/clipping at 360px, grid reflow at the right breakpoints,
text wrapping/contrast, wasted desktop space, and touch-target sizing.

### Options (env vars)

| Var | Default | Purpose |
|---|---|---|
| `OHSITE_BASE_URL` | `http://localhost:4321` | point at a preview/built server |
| `OHSITE_OUT_DIR`  | `/tmp/ohsite-visual` | where PNGs are written |
| `OHSITE_FULL_PAGE`| _(unset)_ | set `1` for full-page (see caveat) |

### Breakpoints

`360` (mobile), `768` (tablet), `1440` (desktop) — matching the responsive
breakpoints used across the components (Hero, AppsGrid, Nav).

### Caveat: scroll-reveal sections on the home page

Most below-the-fold home sections fade in via an `IntersectionObserver`
(`src/scripts/reveal.ts`), so a single **full-page** capture shows them blank.
The default **viewport** (above-the-fold) capture plus the built-in
scroll-through is the reliable way to judge layout. The `privacy` and `terms`
pages are not reveal-gated and render fully in either mode.

## What this is not

This is a manual, read-the-pixels loop — not an automated pixel-regression
gate. For CI regression you would pin a Dockerized Linux + fonts and use
Playwright's `toHaveScreenshot()`; that is a deliberate future step, not this
first layer.
