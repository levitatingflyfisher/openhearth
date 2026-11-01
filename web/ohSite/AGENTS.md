# AGENTS.md: ohSite

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

The OpenHearth landing page, built with Astro as static HTML. It was written by AI assistants, so check a claim before you rely on it. Order of authority: reality, tests, code, comments, prose.

**Check this first.** This repo is the one source of the public landing page at `levitatingflyfisher.github.io` (the link on the family's Christmas card). `npm run landing` runs `verify`, then copies `dist/` into the landing repo beside this one (`../levitatingflyfisher.github.io`). It keeps that repo's `glean/`, `porch/` and `fonts/` and anything else the build did not make. It commits nothing; the board reviews and pushes.

## Map

| You want | Go to |
|---|---|
| The home page | `src/pages/index.astro`, `src/components/Hero.astro`, `src/components/AppCard.astro` |
| The app cards | `src/content/apps/*.yaml` (the file name is the card's `#id`), with the strict schema in `src/content/config.ts` |
| The footer, with the sideload line | `src/components/Footer.astro` |
| The copy into the landing repo | `scripts/landing.mjs` |
| Fonts (self-hosted) | `public/fonts/`, the same files as the landing repo's `fonts/` |
| The About page and its manifesto | `src/pages/about/` |
| Privacy and terms | `src/pages/privacy/`, `src/pages/terms/`, `src/content/privacy/` |
| Colours and type | `src/styles/tokens.css`, `src/styles/global.css` |
| Layout shell | `src/layouts/Base.astro` |
| Screenshots for review | `tests/visual/` |
| Checks on the built site: cards, footer, claims, links (offline) | `tests/text/` (`npm test`, after a build) |
| Continuous checks | `.github/workflows/ci.yml` |

## How to work

- `npm install`, then `npm run dev` to view it.
- `npm run verify` builds the site and runs the checks in `tests/text/`, links included. The link check never fetches an outside address; it lists the ones it skipped. It must pass before a commit.
- `npm run landing` builds into the landing repo. Commit there as a separate step.
- One concern per commit, with a message that says why. Commit as `OpenHearth Development`. No attribution lines.
- No push and no deploy from a working branch.

## What the site must stay

- No ads, no tracking, no account, no analytics.
- No script or font fetched from another company's servers. Fraunces and Nunito are self-hosted under `public/fonts/`.
- Every app card keeps its "Android app ↓" button, and the footer keeps the sideload line word for word. The owner: "sideloading is FOSS freedom."
- Each card's line is one plain sentence with no em dash.
- Never say that something is available, filed or finished when it is not.
- No personal name, organisation backstory, home path, host name or machine detail in anything committed. One exception, by the owner's choice: the About page carries the a3f manifesto. The apps themselves stay neutral.
- a3f is not a tax-exempt 501(c)(3). Any mention of 501(c)(3) says "not" beside it. No donate button, giving portal or "tax-deductible" wording.
- Nothing points at a3f.org. The site URL is `https://levitatingflyfisher.github.io` until the owner picks a domain.
- Do not name the publisher of the apps until the owner settles its legal name.
