// Read the built home page and pull out its app cards and footer.
//
// Plain string work, no HTML parser: the cards are flat <article> elements
// and never nest, so a non-greedy match finds each one whole.

import { readFileSync } from 'node:fs';
import { toPlainText } from './claims.mjs';

/** The built home page, as HTML. */
export function homePage(dist) {
  return readFileSync(`${dist}/index.html`, 'utf8');
}

/** Each app card on a page, as { id, name, line, html, text }. */
export function cards(html) {
  const out = [];
  for (const m of html.matchAll(/<article\b([^>]*)>([\s\S]*?)<\/article>/gi)) {
    const attrs = m[1];
    if (!/\bclass="[^"]*\bcard\b/.test(attrs)) continue;
    const body = m[2];
    const id = attrs.match(/\bid="([^"]*)"/)?.[1] ?? null;
    const name = body.match(/<h3\b[^>]*>([\s\S]*?)<\/h3>/i)?.[1];
    const line = body.match(/<p\b[^>]*class="[^"]*\bline\b[^"]*"[^>]*>([\s\S]*?)<\/p>/i)?.[1];
    out.push({
      id,
      name: name === undefined ? null : toPlainText(name).trim(),
      line: line === undefined ? null : toPlainText(line).trim(),
      html: m[0],
      text: toPlainText(body).trim(),
    });
  }
  return out;
}

/** The page's <footer>, as plain text, or null when it has none. */
export function footerText(html) {
  const m = html.match(/<footer\b[^>]*>([\s\S]*?)<\/footer>/i);
  return m ? toPlainText(m[1]).trim() : null;
}

/** Every href in a piece of HTML, in order. */
export function hrefs(html) {
  return [...html.matchAll(/\bhref="([^"]*)"/gi)].map((m) => m[1].replace(/&amp;/g, '&'));
}
