#!/usr/bin/env python3
"""OpenHearth Pro Designer Multi-Format & TypeScript Icon Asset Kit Builder.

Deterministically builds vector masters, multi-resolution sRGB PNGs, multi-size
ICO favicons, WebP 512px icons, 512x512 pt vector PDFs, and strictly typed
TypeScript + JSON design tokens for all 17 OpenHearth apps.

Pure CPU (uses rsvg-convert and Pillow). Run from anywhere:
    python3 brand/icons/build_kit.py
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import yaml
from PIL import Image

KIT_DIR = Path(__file__).resolve().parent
REPO_ROOT = KIT_DIR.parents[1]
OHSITE_APPS = REPO_ROOT / "web/ohSite/src/content/apps"

ICON_SIZES = (16, 32, 48, 64, 128, 180, 192, 256, 512, 1024)
FULL_BLEED_SIZES = frozenset({180, 1024})
ICO_SIZES = (16, 32, 48)
DETERMINISTIC_EPOCH = "1763900000"

# Canonical palette metadata per app slug (surface tint, primary ink, accent ink, optional fixed adaptiveBg).
APP_PALETTES: dict[str, dict[str, str]] = {
    "bulwark": {"surface": "#4E5D66", "primary": "#5E7380", "accent": "#7B9154"},
    "furrow": {"surface": "#B07A2E", "primary": "#85571E", "accent": "#7D9E59"},
    "glean": {"surface": "#5E8B86", "primary": "#3C615C", "accent": "#5E8B86"},
    "hatch": {"surface": "#E59B2C", "primary": "#E89E2C", "accent": "#D6684B"},
    "lilt": {"surface": "#C9A26B", "primary": "#946E3C", "accent": "#C89A54"},
    "lullaby": {"surface": "#9A8FB5", "primary": "#9A8FB5", "accent": "#6E5F90"},
    "mantle": {"surface": "#A57A8C", "primary": "#98657B", "accent": "#DC876C"},
    "nightglass": {"surface": "#5F74B8", "primary": "#5F74B8", "accent": "#E8B84B"},
    "parlour": {"surface": "#3E8E78", "primary": "#326D5E", "accent": "#449D85"},
    "peckish": {"surface": "#8A4B6C", "primary": "#8E4E70", "accent": "#E0A838"},
    "porch": {"surface": "#E3A94D", "primary": "#4E6382", "accent": "#E3A94D"},
    "punctumtemporis": {"surface": "#C98A8A", "primary": "#C98A8A", "accent": "#9A4F4F"},
    "reckon": {"surface": "#7E94A8", "primary": "#58748E", "accent": "#8AA4BA"},
    "stilllife": {"surface": "#C08552", "primary": "#C08552", "accent": "#965B2E"},
    "sundial": {"surface": "#C8B89A", "primary": "#5E9478", "accent": "#C8B89A", "adaptiveBg": "#F5F0E8"},
    "trellis": {"surface": "#C47B6A", "primary": "#A85040", "accent": "#C47B6A"},
    "weatherglass": {"surface": "#3D82C9", "primary": "#3D82C9", "accent": "#E4A438"},
}


def hex_to_rgb(hx: str) -> tuple[int, int, int]:
    h = hx.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def blend_over_white(hx: str, alpha: float = 0.16) -> str:
    r, g, b = hex_to_rgb(hx)
    return rgb_to_hex(
        (
            round(255 * (1 - alpha) + r * alpha),
            round(255 * (1 - alpha) + g * alpha),
            round(255 * (1 - alpha) + b * alpha),
        )
    )


def normalize_svg_quotes(svg: str) -> str:
    """Convert single-quoted SVG attributes to canonical double-quoted XML."""
    return svg.replace("'", '"').strip()


def canonicalize_svg(slug: str, raw_svg: str) -> str:
    """Return clean 512x512 canonical color SVG for any OpenHearth app."""
    if slug == "sundial":
        # Lossless 0.5x normalization from 1024x1024 to canonical 512x512 with rx="118".
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<rect width="512" height="512" rx="118" fill="#F5F0E8"/>'
            '<path d="M106 340 A150 150 0 0 1 406 340" stroke="#C8B89A" stroke-width="26" fill="none" stroke-linecap="round"/>'
            '<path d="M106 340 A150 150 0 0 1 256 190" stroke="#5E9478" stroke-width="26" fill="none" stroke-linecap="round"/>'
            '<line x1="82" y1="340" x2="430" y2="340" stroke="#C8B89A" stroke-width="5" stroke-linecap="round"/>'
            '<line x1="256" y1="340" x2="256" y2="190" stroke="#5E9478" stroke-width="7" stroke-opacity="0.28" stroke-linecap="round"/>'
            '<circle cx="256" cy="190" r="25" fill="#5E9478"/>'
            "</svg>"
        )
    return normalize_svg_quotes(raw_svg)


def make_opaque_svg(canonical_svg: str, adaptive_bg: str, rounded: bool) -> str:
    """Replace outer backdrop rect with opaque warm-paper fill (rounded or full-bleed)."""
    rx_attr = ' rx="118"' if rounded else ""
    out, count = re.subn(
        r'<rect width="512" height="512" rx="118" fill="#[0-9A-Fa-f]{6}"(?: opacity="\.16")?/>',
        f'<rect width="512" height="512"{rx_attr} fill="{adaptive_bg}"/>',
        canonical_svg,
        count=1,
    )
    if count != 1:
        raise ValueError(f"Expected 1 backdrop rect in canonical SVG, replaced {count}: {canonical_svg[:140]}")
    return out


def strip_backdrop_rect(canonical_svg: str) -> str:
    """Remove only the outer 512x512 backdrop rect, keeping defs/masks and glyph layers."""
    out, count = re.subn(
        r'<rect width="512" height="512" rx="118" fill="#[0-9A-Fa-f]{6}"(?: opacity="\.16")?/>',
        "",
        canonical_svg,
        count=1,
    )
    if count != 1:
        raise ValueError(f"Expected 1 backdrop rect to strip, removed {count}: {canonical_svg[:140]}")
    return out


def make_adaptive_fg_svg(canonical_svg: str) -> str:
    """Transparent Android 108dp adaptive foreground vector scaled cleanly inside the 66dp safe circle.

    Scales the 512x512 glyph by 72/108 (0.6667) centered at (256, 256) so every
    launcher mask shape (circle, squircle, teardrop, rounded square) leaves
    generous breathing room around the artwork.
    """
    glyph_only = strip_backdrop_rect(canonical_svg)
    m = re.match(r'^<svg([^>]*)>(.*)</svg>$', glyph_only, flags=re.S)
    if not m:
        raise ValueError(f"Malformed SVG wrapper: {glyph_only[:120]}")
    attrs, inner = m.group(1), m.group(2)

    defs_block = ""
    defs_match = re.match(r"^(<defs>.*?</defs>)(.*)$", inner, flags=re.S)
    if defs_match:
        defs_block = defs_match.group(1)
        body = defs_match.group(2)
    else:
        body = inner

    return (
        f"<svg{attrs}>"
        f"{defs_block}"
        '<g transform="translate(256 256) scale(0.6667) translate(-256 -256)">'
        f"{body}"
        "</g>"
        "</svg>"
    )


def make_monochrome_svg(slug: str, canonical_svg: str) -> str:
    """Single-color currentColor vector master with negative-space cutouts preserved."""
    if slug == "punctumtemporis":
        holes = "".join(
            f'<rect x="{x}" y="{y}" width="26" height="22" rx="7" fill="black"/>'
            for y in (170, 320)
            for x in (147, 195, 243, 291, 339)
        )
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<defs><mask id="pt-mono">'
            '<rect x="116" y="152" width="280" height="208" rx="32" fill="white"/>'
            f"{holes}"
            '<circle cx="256" cy="256" r="38" fill="black"/>'
            "</mask></defs>"
            '<rect width="512" height="512" fill="currentColor" mask="url(#pt-mono)"/>'
            "</svg>"
        )

    if slug == "porch":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<g stroke="currentColor" stroke-width="18" stroke-linecap="round">'
            '<line x1="132" y1="260" x2="158" y2="260"/>'
            '<line x1="354" y1="260" x2="380" y2="260"/>'
            '<line x1="150" y1="212" x2="170" y2="224"/>'
            '<line x1="362" y1="212" x2="342" y2="224"/>'
            '<line x1="150" y1="308" x2="170" y2="296"/>'
            '<line x1="362" y1="308" x2="342" y2="296"/>'
            "</g>"
            '<circle cx="256" cy="140" r="15" fill="none" stroke="currentColor" stroke-width="15"/>'
            '<path d="M192 188 C198 160 222 152 256 152 C290 152 314 160 320 188 Z" fill="currentColor"/>'
            '<rect x="182" y="180" width="148" height="20" rx="10" fill="currentColor"/>'
            '<path d="M200 200 L312 200 L302 332 L210 332 Z" fill="none" stroke="currentColor" stroke-width="20" stroke-linejoin="round"/>'
            '<path d="M256 228 C276 254 278 282 256 298 C234 282 236 254 256 228 Z" fill="currentColor"/>'
            '<rect x="188" y="332" width="136" height="22" rx="11" fill="currentColor"/>'
            '<rect x="218" y="354" width="76" height="16" rx="8" fill="currentColor"/>'
            "</svg>"
        )

    if slug == "hatch":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<defs><mask id="hatch-mono">'
            '<rect width="512" height="512" fill="black"/>'
            '<g transform="rotate(-14 166 244) translate(0 -10)">'
            '<path d="M168 246 C172 164 210 134 256 134 C302 134 340 164 344 246 '
            'L314 226 L284 250 L256 226 L228 250 L198 226 Z" fill="white"/>'
            "</g>"
            '<circle cx="260" cy="268" r="64" fill="white"/>'
            '<circle cx="236" cy="256" r="13" fill="black"/>'
            '<circle cx="284" cy="256" r="13" fill="black"/>'
            '<path d="M154 274 L188 298 L222 270 L256 298 L290 270 L324 298 L358 274" '
            'fill="none" stroke="black" stroke-width="14" stroke-linejoin="round"/>'
            '<path d="M154 280 L188 304 L222 276 L256 304 L290 276 L324 304 L358 280 '
            'C358 352 316 388 256 388 C196 388 154 352 154 280 Z" fill="white"/>'
            "</mask></defs>"
            '<rect width="512" height="512" fill="currentColor" mask="url(#hatch-mono)"/>'
            "</svg>"
        )

    if slug == "stilllife":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<defs><mask id="sl-mono">'
            '<rect width="512" height="512" fill="black"/>'
            '<path d="M256 130 L368 190 L256 248 L144 190 Z" fill="white" stroke="white" stroke-width="16" stroke-linejoin="round"/>'
            '<line x1="204" y1="162" x2="308" y2="216" stroke="black" stroke-width="16" stroke-linecap="round"/>'
            '<path d="M134 214 L244 270 L244 382 L134 326 Z" fill="white" stroke="white" stroke-width="16" stroke-linejoin="round"/>'
            '<path d="M378 214 L268 270 L268 382 L378 326 Z" fill="white" stroke="white" stroke-width="16" stroke-linejoin="round"/>'
            '<path d="M156 266 L210 294 L210 322 L156 294 Z" fill="black" stroke="black" stroke-width="8" stroke-linejoin="round"/>'
            "</mask></defs>"
            '<rect width="512" height="512" fill="currentColor" mask="url(#sl-mono)"/>'
            "</svg>"
        )

    if slug == "peckish":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<g fill="none" stroke="currentColor" stroke-width="22" stroke-linecap="round">'
            '<path d="M188 200 C174 176 202 158 188 134"/>'
            '<path d="M256 190 C242 164 270 146 256 122"/>'
            '<path d="M324 200 C310 176 338 158 324 134"/>'
            "</g>"
            '<rect x="116" y="226" width="280" height="26" rx="13" fill="currentColor"/>'
            '<path d="M128 264 L384 264 C380 338 328 378 256 378 C184 378 132 338 128 264 Z" fill="currentColor"/>'
            '<rect x="204" y="370" width="104" height="20" rx="10" fill="currentColor"/>'
            "</svg>"
        )

    if slug == "reckon":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<defs><mask id="rk-mono">'
            '<rect width="512" height="512" fill="black"/>'
            '<g stroke="white" stroke-width="14" stroke-linecap="round" stroke-linejoin="round" fill="none">'
            '<polyline points="128,266 162,174 196,266"/>'
            '<polyline points="316,266 350,174 384,266"/>'
            "</g>"
            '<g stroke="white" stroke-linecap="round">'
            '<line x1="256" y1="154" x2="256" y2="366" stroke-width="24"/>'
            '<line x1="146" y1="174" x2="366" y2="174" stroke-width="22"/>'
            '<line x1="186" y1="368" x2="326" y2="368" stroke-width="26"/>'
            "</g>"
            '<circle cx="256" cy="154" r="22" fill="white"/>'
            '<circle cx="256" cy="154" r="9" fill="black"/>'
            '<path d="M120 264 L204 264 A42 38 0 0 1 120 264 Z" fill="white"/>'
            '<path d="M308 264 L392 264 A42 38 0 0 1 308 264 Z" fill="white"/>'
            "</mask></defs>"
            '<rect width="512" height="512" fill="currentColor" mask="url(#rk-mono)"/>'
            "</svg>"
        )

    if slug == "sundial":
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            '<path d="M106 340 A150 150 0 0 1 406 340" stroke="currentColor" stroke-width="16" stroke-opacity="0.38" fill="none" stroke-linecap="round"/>'
            '<path d="M106 340 A150 150 0 0 1 256 190" stroke="currentColor" stroke-width="28" fill="none" stroke-linecap="round"/>'
            '<line x1="82" y1="340" x2="430" y2="340" stroke="currentColor" stroke-width="8" stroke-linecap="round"/>'
            '<line x1="256" y1="340" x2="256" y2="190" stroke="currentColor" stroke-width="8" stroke-opacity="0.4" stroke-linecap="round"/>'
            '<circle cx="256" cy="190" r="26" fill="currentColor"/>'
            "</svg>"
        )

    # Default mechanical conversion: strip backdrop, preserve masks in <defs>, map hex fills/strokes to currentColor.
    glyph = strip_backdrop_rect(canonical_svg)
    defs_block = ""
    m = re.match(r'^<svg([^>]*)>(<defs>.*?</defs>)(.*)</svg>$', glyph, flags=re.S)
    if m:
        attrs, defs_block, body = m.group(1), m.group(2), m.group(3)
    else:
        m2 = re.match(r'^<svg([^>]*)>(.*)</svg>$', glyph, flags=re.S)
        if not m2:
            raise ValueError(f"Malformed SVG for {slug}")
        attrs, body = m2.group(1), m2.group(2)

    body_mono = re.sub(r'(fill|stroke)="#[0-9A-Fa-f]{6}"', r'\1="currentColor"', body)
    return f"<svg{attrs}>{defs_block}{body_mono}</svg>"


def rsvg_render_png(svg_str: str, size: int, rgb: bool = False) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".svg", mode="w", encoding="utf-8", delete=False) as tf:
        tf.write(svg_str)
        svg_path = tf.name
    png_path = svg_path + ".png"
    try:
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), svg_path, "-o", png_path],
            check=True,
        )
        with Image.open(png_path) as im:
            return im.convert("RGB") if rgb else im.convert("RGBA")
    finally:
        if os.path.exists(svg_path):
            os.unlink(svg_path)
        if os.path.exists(png_path):
            os.unlink(png_path)


def rsvg_render_pdf(svg_str: str, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".svg", mode="w", encoding="utf-8", delete=False) as tf:
        tf.write(svg_str)
        svg_path = tf.name
    try:
        env = dict(os.environ)
        env["SOURCE_DATE_EPOCH"] = DETERMINISTIC_EPOCH
        subprocess.run(
            ["rsvg-convert", "-f", "pdf", "-w", "512pt", "-h", "512pt", svg_path, "-o", str(out_path)],
            check=True,
            env=env,
        )
    finally:
        if os.path.exists(svg_path):
            os.unlink(svg_path)


def write_ico(images_by_size: dict[int, Image.Image], out_path: Path) -> None:
    """Write a true multi-resolution Windows/browser ICO containing 16x16, 32x32, and 48x48 PNG frames."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Pass explicit sizes alongside append_images so Pillow embeds exact 16, 32, 48 frames.
    frames = [images_by_size[s].convert("RGBA") for s in ICO_SIZES]
    frames[-1].save(
        out_path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=frames[:-1],
    )


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_apps() -> list[dict[str, str]]:
    apps = []
    for p in sorted(OHSITE_APPS.glob("*.yaml")):
        data = yaml.safe_load(p.read_text(encoding="utf-8"))
        slug = p.stem
        if slug not in APP_PALETTES:
            raise KeyError(f"Missing palette definition for app slug '{slug}'")
        apps.append(
            {
                "id": slug,
                "name": str(data["name"]),
                "raw_svg": str(data["icon"]),
            }
        )
    if len(apps) != 17:
        raise RuntimeError(f"Expected 17 OpenHearth apps in {OHSITE_APPS}, found {len(apps)}")
    return apps


def emit_typescript(manifest_apps: list[dict], svg_data_map: dict[str, str], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    app_ids = [a["id"] for a in manifest_apps]
    lines: list[str] = [
        "/* Auto-generated by brand/icons/build_kit.py. Do not edit by hand. */",
        "",
        "export const ICON_SIZES = [16, 32, 48, 64, 128, 180, 192, 256, 512, 1024] as const;",
        "export type IconSize = (typeof ICON_SIZES)[number];",
        "",
        "export const OPENHEARTH_APP_IDS = [",
    ]
    for slug in app_ids:
        lines.append(f'  "{slug}",')
    lines.extend(
        [
            "] as const;",
            "export type OpenHearthAppId = (typeof OPENHEARTH_APP_IDS)[number];",
            "",
            "export interface OpenHearthIconPalette {",
            "  surface: string;",
            "  primary: string;",
            "  accent: string;",
            "  adaptiveBg: string;",
            "}",
            "",
            "export interface OpenHearthIconAsset {",
            "  id: OpenHearthAppId;",
            "  name: string;",
            "  palette: OpenHearthIconPalette;",
            "  svg: string;",
            "  monochromeSvg: string;",
            "  adaptiveFgSvg: string;",
            "  ico: string;",
            "  webp512: string;",
            "  pdf: string;",
            "  png: Record<IconSize, string>;",
            "}",
            "",
            "export const OPENHEARTH_ICONS: Record<OpenHearthAppId, OpenHearthIconAsset> = {",
        ]
    )

    for app in manifest_apps:
        slug = app["id"]
        pal = app["palette"]
        lines.extend(
            [
                f"  {slug}: {{",
                f'    id: "{slug}",',
                f'    name: {json.dumps(app["name"])},',
                "    palette: {",
                f'      surface: "{pal["surface"]}",',
                f'      primary: "{pal["primary"]}",',
                f'      accent: "{pal["accent"]}",',
                f'      adaptiveBg: "{pal["adaptiveBg"]}",',
                "    },",
                f'    svg: "{app["svg"]}",',
                f'    monochromeSvg: "{app["monochromeSvg"]}",',
                f'    adaptiveFgSvg: "{app["adaptiveFgSvg"]}",',
                f'    ico: "{app["ico"]}",',
                f'    webp512: "{app["webp512"]}",',
                f'    pdf: "{app["pdf"]}",',
                "    png: {",
            ]
        )
        for sz in ICON_SIZES:
            lines.append(f'      {sz}: "{app["png"][str(sz)]}",')
        lines.extend(["    },", "  },"])

    lines.extend(
        [
            "};",
            "",
            "export const OPENHEARTH_ICON_SVG_DATA: Record<OpenHearthAppId, string> = {",
        ]
    )
    for slug in app_ids:
        lines.append(f"  {slug}: {json.dumps(svg_data_map[slug])},")
    lines.extend(
        [
            "};",
            "",
            "export function getIconPath(id: OpenHearthAppId, size?: IconSize): string {",
            "  const asset = OPENHEARTH_ICONS[id];",
            "  return size === undefined ? asset.svg : asset.png[size];",
            "}",
            "",
        ]
    )
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    apps = load_apps()
    svg_dir = KIT_DIR / "svg"
    png_root = KIT_DIR / "png"
    ico_dir = KIT_DIR / "ico"
    webp_dir = KIT_DIR / "webp"
    pdf_dir = KIT_DIR / "pdf"
    tokens_dir = KIT_DIR / "tokens"
    for d in (svg_dir, png_root, ico_dir, webp_dir, pdf_dir, tokens_dir):
        d.mkdir(parents=True, exist_ok=True)

    manifest_apps: list[dict] = []
    svg_data_map: dict[str, str] = {}
    all_checksums: dict[str, str] = {}

    for app in apps:
        slug = app["id"]
        name = app["name"]
        pal_cfg = APP_PALETTES[slug]
        adaptive_bg = pal_cfg.get("adaptiveBg") or blend_over_white(pal_cfg["surface"], 0.16)
        palette = {
            "surface": pal_cfg["surface"],
            "primary": pal_cfg["primary"],
            "accent": pal_cfg["accent"],
            "adaptiveBg": adaptive_bg,
        }

        canonical_svg = canonicalize_svg(slug, app["raw_svg"])
        mono_svg = make_monochrome_svg(slug, canonical_svg)
        adaptive_fg_svg = make_adaptive_fg_svg(canonical_svg)
        opaque_rx_svg = make_opaque_svg(canonical_svg, adaptive_bg, rounded=True)
        opaque_sq_svg = make_opaque_svg(canonical_svg, adaptive_bg, rounded=False)

        svg_data_map[slug] = canonical_svg

        # 1. Vector Masters
        p_svg = svg_dir / f"{slug}.svg"
        p_mono = svg_dir / f"{slug}-monochrome.svg"
        p_fg = svg_dir / f"{slug}-adaptive-fg.svg"
        p_svg.write_text(canonical_svg + "\n", encoding="utf-8")
        p_mono.write_text(mono_svg + "\n", encoding="utf-8")
        p_fg.write_text(adaptive_fg_svg + "\n", encoding="utf-8")

        # 2. Standard Raster Resolutions (sRGB PNGs)
        app_png_dir = png_root / slug
        app_png_dir.mkdir(parents=True, exist_ok=True)
        png_paths: dict[str, str] = {}
        ico_frames: dict[int, Image.Image] = {}
        img_512_rx: Image.Image | None = None

        for sz in ICON_SIZES:
            out_png = app_png_dir / f"{sz}.png"
            if sz in FULL_BLEED_SIZES:
                # Apple Touch (180) and App Store / Print (1024): opaque full-bleed sRGB RGB
                im = rsvg_render_png(opaque_sq_svg, sz, rgb=True)
                im.save(out_png, "PNG", optimize=True)
            else:
                # Web / Favicon / PWA / Desktop: opaque warm-paper squircle RGBA
                im = rsvg_render_png(opaque_rx_svg, sz, rgb=False)
                im.save(out_png, "PNG", optimize=True)
                if sz in ICO_SIZES:
                    ico_frames[sz] = im
                if sz == 512:
                    img_512_rx = im
            rel = out_png.relative_to(KIT_DIR).as_posix()
            png_paths[str(sz)] = rel

        # 3. Multi-Format Exports (.ico, .webp, .pdf)
        p_ico = ico_dir / f"{slug}.ico"
        write_ico(ico_frames, p_ico)

        p_webp = webp_dir / f"{slug}-512.webp"
        assert img_512_rx is not None
        img_512_rx.save(p_webp, "WEBP", quality=95, method=6)

        p_pdf = pdf_dir / f"{slug}.pdf"
        rsvg_render_pdf(opaque_rx_svg, p_pdf)

        # Record relative paths + SHA-256 checksums
        app_files = [
            p_svg,
            p_mono,
            p_fg,
            p_ico,
            p_webp,
            p_pdf,
            *[app_png_dir / f"{sz}.png" for sz in ICON_SIZES],
        ]
        app_checksums: dict[str, str] = {}
        for fp in app_files:
            rel = fp.relative_to(KIT_DIR).as_posix()
            digest = sha256_file(fp)
            app_checksums[rel] = digest
            all_checksums[rel] = digest

        manifest_apps.append(
            {
                "id": slug,
                "name": name,
                "palette": palette,
                "svg": p_svg.relative_to(KIT_DIR).as_posix(),
                "monochromeSvg": p_mono.relative_to(KIT_DIR).as_posix(),
                "adaptiveFgSvg": p_fg.relative_to(KIT_DIR).as_posix(),
                "ico": p_ico.relative_to(KIT_DIR).as_posix(),
                "webp512": p_webp.relative_to(KIT_DIR).as_posix(),
                "pdf": p_pdf.relative_to(KIT_DIR).as_posix(),
                "png": png_paths,
                "sha256": app_checksums,
            }
        )
        print(f"  built {slug:16s} (3 SVG, 10 PNG, ICO, WebP, PDF)")

    # 4. Strictly Typed TypeScript & JSON Design Tokens
    ts_path = tokens_dir / "openhearth-icons.ts"
    emit_typescript(manifest_apps, svg_data_map, ts_path)

    json_path = tokens_dir / "openhearth-icons.json"
    manifest = {
        "schemaVersion": "1.0.0",
        "kitVersion": "v1",
        "sizes": list(ICON_SIZES),
        "appCount": len(manifest_apps),
        "apps": {a["id"]: a for a in manifest_apps},
        "checksums": dict(sorted(all_checksums.items())),
    }
    json_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"\nGenerated tokens: {ts_path.relative_to(KIT_DIR)}, {json_path.relative_to(KIT_DIR)}")
    print(f"Total icon assets emitted: {len(all_checksums)} files across {len(manifest_apps)} apps.")


if __name__ == "__main__":
    main()
