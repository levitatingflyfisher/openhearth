# Contributing to ohSite

Thank you for taking the time to contribute! This document explains how to report issues, suggest features, and submit code changes.

---

## Reporting Bugs

Before opening a new issue, search existing issues to avoid duplicates.

When filing a bug report, please include:
- Node.js version (`node --version`)
- npm version (`npm --version`)
- Operating system and version
- Steps to reproduce
- Expected behaviour vs. actual behaviour
- Any relevant console output

---

## Suggesting Features

Open an issue with the `enhancement` label. Describe the problem you are trying to solve rather than jumping straight to a solution — this helps discussion stay focused.

---

## Development Setup

```bash
git clone <repo-url>
cd ohSite
npm install
```

To start the local dev server:

```bash
npm run dev
```

---

## Code Style

All contributions must pass the following checks before review:

```bash
# Build (must succeed with zero errors)
npm run build

# Link check (must report zero broken internal links)
npm run check:links

# Both together
npm run verify
```

Keep components scoped: each `.astro` file carries its own `<style>` block. Use only the semantic CSS tokens defined in `src/styles/tokens.css` (`--bg`, `--text`, `--accent`, etc.) — never hard-code colour literals. Honour `@media (prefers-reduced-motion: reduce)` in any new transition or animation.

---

## Testing

- Visual regressions: run `npm run dev` and inspect the page in both light and dark modes.
- Broken links: run `npm run check:links` after every `npm run build`.
- Accessibility: check that all icon-only controls have `aria-label` attributes and that semantic landmarks (`<section>`, `<header>`, `<nav>`, `<footer>`) are present.

---

## Pull Request Workflow

1. Fork the repository and create a feature branch from `master`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. Make your changes, following the code style rules above.
3. Open a PR against the `master` branch with a clear description of what changed and why.
4. Link any related issues in the PR description (`Closes #123`).

PRs that fail `npm run build` or `npm run check:links` will not be merged.

---

## Architecture Notes

ohSite is a static Astro site. The content layer uses Astro content collections:

- `src/content/apps/` — one YAML file per app (slug, name, status, tagline, description, meta, focus, and githubUrl — optional: leave it out until the repo is public at that address, and the card renders without a link)
- `src/content/privacy/` — one Markdown file per app

When adding a new app:
1. Add a YAML file to `src/content/apps/<slug>.yaml`.
2. Add a Markdown privacy entry to `src/content/privacy/<slug>.md`.
3. Verify the card renders correctly in the `AppsGrid` on the home page.

The design token system lives in `src/styles/tokens.css`. Primitive `--oh-*` tokens are mapped to semantic tokens (`--bg`, `--text`, `--accent`, etc.) for light and dark mode. Add new components using semantic tokens only.

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

Questions? Open an issue.
