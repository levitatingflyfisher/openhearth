# OpenHearth

**The OpenHearth landing page: free, local-first software for families.**

![License: MIT](https://img.shields.io/badge/license-MIT-yellow)
![Built with Astro](https://img.shields.io/badge/built%20with-Astro-FF5D01?logo=astro&logoColor=white)

---

## About

OpenHearth is a catalog of beautifully-made, free, open-source apps for the everyday rhythms of family life. The apps live under [github.com/levitatingflyfisher](https://github.com/levitatingflyfisher).

No ads. No tracking. No accounts required. Everything is MIT licensed.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | [Astro](https://astro.build) (static HTML output) |
| Content | Astro content collections (YAML + Markdown) |
| Hosting | GitHub Pages, from the `levitatingflyfisher.github.io` repo (`npm run landing` builds into it) |
| Fonts | Fraunces · Nunito, self-hosted (`public/fonts/`, SIL OFL 1.1) |
| Styles | CSS custom properties (`src/styles/tokens.css`) |

---

## Development

```bash
# Install dependencies
npm install

# Start the local dev server (http://localhost:4321)
npm run dev

# Build for production (output → dist/)
npm run build

# Preview the production build locally
npm run preview

# Build, then check cards, claims and links (offline)
npm run verify

# Verify, then copy dist/ into ../levitatingflyfisher.github.io
npm run landing
```

---

## Structure

```
src/
├── pages/        # Route files (index.astro, about/, privacy/, terms/)
├── components/   # Reusable Astro components
├── content/      # Content collections — apps/ (YAML), privacy/ (Markdown)
└── styles/       # tokens.css (design tokens), global.css
```

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

---

## License

MIT — see [LICENSE](LICENSE).

