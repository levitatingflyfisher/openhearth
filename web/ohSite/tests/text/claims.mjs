// Text checks on the built site: claims the hub must never make.
//
// Owner rulings (board-0166):
//   - a3f is not a tax-exempt 501(c)(3). Any mention of 501(c)(3) must say
//     "not" in the same sentence, before the mention.
//   - Nothing points at a3f.org until the owner picks a domain.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const TEXT_EXTS = new Set(['.html', '.xml', '.txt', '.json', '.js', '.css', '.svg', '.webmanifest']);

/** Turn HTML into plain text: drop scripts, styles and tags, decode a few entities. */
export function toPlainText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&#39;|&#x27;|&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, ' ');
}

const TAX_FORM = /501\s*\(?\s*c\s*\)?\s*\(?\s*3\s*\)?/gi;

/** Each 501(c)(3) mention whose sentence has no "not" before it. */
export function unnegatedTaxClaims(text) {
  const hits = [];
  for (const m of text.matchAll(TAX_FORM)) {
    const before = text.slice(0, m.index);
    const cut = Math.max(before.lastIndexOf('. '), before.lastIndexOf('! '), before.lastIndexOf('? '));
    const sentence = before.slice(cut + 1);
    if (!/\bnot\b/i.test(sentence)) {
      hits.push(text.slice(Math.max(0, m.index - 60), m.index + m[0].length + 20).trim());
    }
  }
  return hits;
}

/** Each a3f.org mention, in any case. */
export function a3fDomainHits(text) {
  return [...text.matchAll(/a3f\.org/gi)].map((m) =>
    text.slice(Math.max(0, m.index - 40), m.index + 40).trim(),
  );
}

/** Every text file under a folder, as { path, text }. */
export function readTextFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      out.push(...readTextFiles(path));
    } else if (TEXT_EXTS.has(extname(name))) {
      out.push({ path, text: readFileSync(path, 'utf8') });
    }
  }
  return out;
}
