# OpenHearth Website — Framework Comparison
*Written April 2026 — revisit if site scope changes significantly*

---

## What we're building

About 8 to 10 pages:
- **The app hub** — per-app download pages, FOSS mission
- Per-app privacy policy pages (mostly static text)
- Hosted on Cloudflare Pages, auto-deploy from git

We already have a polished 384-line HTML prototype (`openHearthLandingView.html`) with all design tokens as CSS custom properties, scroll animations, and correct typography. Whatever we pick needs to carry this forward without rewriting it.

---

## Options

### Option A — Plain HTML (what we have)
Copy-paste the prototype, duplicate nav/footer manually across pages.

| | |
|---|---|
| **Easy?** | Yes to start, painful at page 4+ |
| **Secure?** | Maximum — pure static files, zero build surface |
| **Lightweight?** | Minimal output, zero dependencies |
| **Workable long-term?** | No — shared nav/footer changes mean editing 10 files |
| **Private?** | Complete |

**Verdict:** Only viable for a true one-pager. Breaks down immediately once privacy policies and per-app pages are added.

---

### Option B — Astro *(current spec)*
Component-based static site generator. `.astro` files are near-identical to HTML with a frontmatter block at the top. Outputs pure HTML by default — zero JS unless you opt in.

| | |
|---|---|
| **Easy?** | Mild learning curve (~1 hour). After that, faster than plain HTML |
| **Secure?** | Pure static output — same attack surface as Option A |
| **Lightweight?** | Zero-JS output by default. Build tooling is Node but that's dev-only |
| **Workable long-term?** | Yes — shared layouts, Markdown for privacy policies, TypeScript throughout |
| **Private?** | Complete — no tracking baked in |

**Why it fits well:**
- The existing HTML prototype converts to `.astro` almost unchanged — the CSS custom properties, fonts, and structure carry over directly
- Markdown pages for privacy policies (write prose, get formatted HTML, no boilerplate)
- File-based routing: `src/pages/apps/sundial.astro` → `/apps/sundial`
- Native Cloudflare Pages adapter (`@astrojs/cloudflare`) — zero config deploy
- Content collections for app cards (one `.md` file per app, auto-generates download pages)

**Downside:** Node.js build pipeline. But this is dev-only — the output is pure HTML/CSS files.

---

### Option C — Eleventy (11ty)
Minimal static site generator using HTML/Nunjucks/Liquid templates. Lower-level than Astro — closer to "HTML with includes."

| | |
|---|---|
| **Easy?** | Simpler mental model than Astro, but template syntax (Nunjucks) is less ergonomic |
| **Secure?** | Same as Astro |
| **Lightweight?** | Slightly lighter build tool than Astro |
| **Workable long-term?** | Yes, but component reuse is more manual |
| **Private?** | Complete |

**Why it's not better than Astro here:** The existing prototype uses modern CSS and clean HTML — Astro's component model carries it forward more naturally than Nunjucks template inheritance. Eleventy would work but requires more boilerplate for the same outcome.

---

### Option D — Hugo
Go-based static site generator. No Node dependency. Very fast builds.

| | |
|---|---|
| **Easy?** | Go templates are unintuitive. Steep learning curve relative to value |
| **Secure?** | Same |
| **Lightweight?** | Lightest build tooling — single Go binary |
| **Workable long-term?** | Possible, but Go template syntax fights you for non-Go developers |
| **Private?** | Complete |

**Why not:** The learning investment isn't justified for 10 pages. Go templates are verbose and counterintuitive for HTML-centric work. Astro's component model is dramatically more ergonomic.

---

## Recommendation: **Astro** (confirm the spec)

The CLAUDE.md decision was right even if the reasoning wasn't documented. Astro is the best fit because:

1. The existing HTML prototype migrates almost unchanged
2. Shared layout (nav, footer, head) means one change updates all pages
3. Markdown-native for privacy policies and text-heavy content
4. Zero JS output — lighter than the prototype since no inline script is needed for scroll-reveal (Astro has View Transitions built in)
5. Cloudflare Pages deploy is first-class and free
6. Content collections let per-app pages be data-driven (add a new `.md` file, get a new download page)

The Node dev dependency is the only real cost, and it's build-time only.

---

## What to do now

Nothing yet — website is Tier 1 but not actively in progress. When ready:
1. `npm create astro@latest openhearthSite`
2. Port `openHearthLandingView.html` into a base layout + home page component
3. Extract CSS custom properties into `src/styles/tokens.css` (this also feeds the design system)
4. Add `@astrojs/cloudflare` adapter

*Set aside. Revisit if the hub moves to active build.*
