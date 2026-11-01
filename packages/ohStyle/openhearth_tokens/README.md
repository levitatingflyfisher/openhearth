# openhearth_tokens

Cross-platform design token files for the OpenHearth portfolio.

These files mirror the token values defined in `openHearthStyleGuide.md` and the Dart package `openhearth_design`. They exist so non-Flutter projects (Glean's React frontend, the Astro website) can consume the same tokens without depending on Dart tooling.

## Files

| File | Purpose |
|------|---------|
| `tokens.css` | CSS custom properties (`--oh-*`) for Astro and Glean's `index.css` |
| `tokens.ts` | TypeScript `const` objects for type-safe references in React components |

## Usage

**Astro site** — in your global stylesheet:
```css
@import '../../ohStyle/openhearth_tokens/tokens.css';
```

**Glean (React)** — in `src/index.css`:
```css
@import '../../../ohStyle/openhearth_tokens/tokens.css';
```

**Glean (TypeScript)** — in components:
```ts
import { OhColors, OhSpacing } from '../../../ohStyle/openhearth_tokens/tokens';
```

The files need no build step. Today neither project imports them in place: each keeps its own copy of the CSS, and both copies have drifted from `tokens.css` here. The top-level README lists the differences.

## Sync discipline

These files are maintained manually. When tokens change, update all four places:
1. `openHearthStyleGuide.md` — source of truth
2. `openhearth_design/lib/src/colors.dart` — Dart/Flutter
3. `openhearth_tokens/tokens.css` — CSS
4. `openhearth_tokens/tokens.ts` — TypeScript
