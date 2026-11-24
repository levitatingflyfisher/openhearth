# OpenHearth Fleet Icon Asset Kit (v1)

Complete multi-format vector, raster, print, and TypeScript icon kit for all **17 OpenHearth apps**. Every file in this directory is generated deterministically from the canonical app definitions in `web/ohSite/src/content/apps/*.yaml` via `python3 brand/icons/build_kit.py`.

## Directory Layout

```text
brand/icons/
├── build_kit.py                 # Deterministic pure-CPU asset generator (rsvg-convert + Pillow)
├── README.md                    # This designer specification sheet
├── svg/
│   ├── <slug>.svg               # Canonical color SVG master (512x512 viewBox, 16% tinted rx="118" squircle)
│   ├── <slug>-monochrome.svg    # Single-color currentColor vector (Android 13+ themed, UI glyphs, laser/print)
│   └── <slug>-adaptive-fg.svg   # Transparent Android 108dp adaptive foreground (66dp safe circle)
├── png/<slug>/
│   ├── 16.png                   # Favicon / compact UI (sRGB RGBA squircle)
│   ├── 32.png                   # High-DPI favicon / toolbar (sRGB RGBA squircle)
│   ├── 48.png                   # Android mdpi legacy / launcher list (sRGB RGBA squircle)
│   ├── 64.png                   # Desktop taskbar / Retina 32pt (sRGB RGBA squircle)
│   ├── 128.png                  # Web cards / macOS small icon (sRGB RGBA squircle)
│   ├── 180.png                  # Apple Touch Icon (opaque full-bleed sRGB RGB, zero alpha)
│   ├── 192.png                  # PWA manifest icon / Android xxxhdpi legacy (sRGB RGBA squircle)
│   ├── 256.png                  # Windows Explorer / Electron tray (sRGB RGBA squircle)
│   ├── 512.png                  # Play Store / PWA splash (sRGB RGBA squircle)
│   └── 1024.png                 # App Store Connect / Print master (opaque full-bleed sRGB RGB, zero alpha)
├── ico/<slug>.ico               # Multi-resolution Windows & browser favicon (16x16, 32x32, 48x48)
├── webp/<slug>-512.webp         # High-efficiency 512x512 WebP for web catalogs and docs
├── pdf/<slug>.pdf               # Vector PDF master (512x512 pt, ready for Figma, Illustrator, and print)
└── tokens/
    ├── openhearth-icons.ts      # Strictly typed TypeScript manifest, palettes, helpers, and inline SVGs
    └── openhearth-icons.json    # Machine-readable manifest with SHA-256 checksums for every exported file
```

## Safe-Zone & Optical Geometry Rules

1. **Canonical Canvas:** All vector masters share a `512x512` coordinate system with an `rx="118"` squircle backdrop (`23%` corner radius).
2. **Android Adaptive Safe Circle (`66%`):** In `svg/<slug>-adaptive-fg.svg`, each glyph is centered on a transparent `512x512` (`108dp`) canvas scaled to `72/108` (`66.67%`). Every stroke and shape sits strictly inside the central `66dp` (`61.1%` diameter) guaranteed safe circle so no launcher mask (circle, squircle, teardrop, rounded square) clips any artwork.
3. **Opaque Adaptive Background:** Pair `svg/<slug>-adaptive-fg.svg` with the app's exact `palette.adaptiveBg` hex color (from `tokens/openhearth-icons.ts` or `tokens/openhearth-icons.json`). For tinted apps, `adaptiveBg` is the exact `16%` blend of `palette.surface` over `#FFFFFF`; Sundial uses its warm linen `#F5F0E8`.
4. **Minimum Legible Sizes:**
   - **Full color (`svg/<slug>.svg` / `png`):** Legible down to `16x16 px` (`ico` and browser tabs). Prefer `24px` or larger in navigation rails and app switchers.
   - **Monochrome (`svg/<slug>-monochrome.svg`):** Legible down to `16x16 px` for UI glyphs and `24dp` for Android status-bar notifications. Inherits CSS `color` via `currentColor`.

## Light & Dark Surface Guidance

- **Adaptive UI (Web, Docs, React/Astro/Solid):** Use `svg/<slug>.svg` (or `OPENHEARTH_ICON_SVG_DATA[id]`). Its `16%` tinted backdrop blends naturally onto both warm parchment (`#FBF8F4`) and dark hearth (`#1C1007`) surfaces while preserving strong figure contrast.
- **Browser Tabs, Launchers, and Uncontrolled Surfaces:** Use `png/<slug>/<size>.png`, `ico/<slug>.ico`, `webp/<slug>-512.webp`, or `pdf/<slug>.pdf`. These bake in the opaque warm-paper `adaptiveBg` tile so the mark never turns muddy over black system chrome, arbitrary wallpapers, or print stock.
- **Apple Platforms (`180.png`, `1024.png`):** Exported as full-bleed opaque `RGB` PNGs with zero alpha channel because iOS and App Store Connect apply their own superellipse mask and reject or black-fill transparency.

## Format Cheat Sheet (What to Hand to Each Target)

| Target Platform / Tool | Recommended Files | Notes |
| --- | --- | --- |
| **Android (Adaptive + Themed)** | `svg/<slug>-adaptive-fg.svg`, `svg/<slug>-monochrome.svg`, `palette.adaptiveBg` | Set `ic_launcher_background` to `palette.adaptiveBg`; tint monochrome layer to `#FFFFFF` for Android 13+ |
| **iOS / macOS / App Store** | `png/<slug>/1024.png`, `png/<slug>/180.png` | Full-bleed opaque sRGB; no alpha channel; let Apple apply corner masking |
| **Web & PWA** | `svg/<slug>.svg`, `ico/<slug>.ico`, `png/<slug>/180.png`, `png/<slug>/192.png`, `png/<slug>/512.png`, `webp/<slug>-512.webp` | Use `.ico` + `.svg` in `<head>`, `180.png` for `apple-touch-icon`, `192`/`512` in `manifest.webmanifest` |
| **Electron / Desktop** | `ico/<slug>.ico`, `png/<slug>/256.png`, `png/<slug>/512.png`, `png/<slug>/1024.png` | Bundle `.ico` for Windows, `512`/`1024` for `.icns` and Linux freedesktop hicolor icons |
| **Figma / Illustrator / Print** | `pdf/<slug>.pdf`, `svg/<slug>.svg`, `svg/<slug>-monochrome.svg` | `pdf/<slug>.pdf` is crisp 512x512 pt vector; monochrome SVG works cleanly for laser engraving and single-ink print |
| **TypeScript / React / Astro / Solid** | `tokens/openhearth-icons.ts`, `tokens/openhearth-icons.json` | Zero-network inline SVGs via `OPENHEARTH_ICON_SVG_DATA[id]` and typed paths via `getIconPath(id, size)` |

## TypeScript Usage Example

```ts
import {
  OPENHEARTH_ICONS,
  OPENHEARTH_ICON_SVG_DATA,
  getIconPath,
  type OpenHearthAppId,
} from "./tokens/openhearth-icons";

const id: OpenHearthAppId = "trellis";
const png512 = getIconPath(id, 512);           // "png/trellis/512.png"
const canonicalSvg = getIconPath(id);          // "svg/trellis.svg"
const bgHex = OPENHEARTH_ICONS[id].palette.adaptiveBg; // "#F6EAE7"
const inlineSvg = OPENHEARTH_ICON_SVG_DATA[id];
```

## Regenerating the Kit

```bash
python3 brand/icons/build_kit.py
```

Requires `rsvg-convert`, Python 3.10+, `Pillow`, and `PyYAML` (pure CPU, deterministic output).
