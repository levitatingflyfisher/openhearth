// An offline link check for the built site.
//
// It reads href and src in every HTML file and url() in every CSS file.
// A link to another address (http, https, //, mailto, tel) is skipped and
// listed, never fetched. A data: URL needs no check. Everything else must
// resolve to a file under the site root, and a #fragment must match an id
// (or a name) on the page it points at.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, posix, relative, sep } from 'node:path';

/** True for a link that leaves the site. */
export function isExternal(url) {
  return /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(url) && !/^data:/i.test(url);
}

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) out.push(...walk(path));
    else out.push(path);
  }
  return out;
}

function linksIn(path, text) {
  if (extname(path) === '.html') {
    return [...text.matchAll(/\s(?:href|src)="([^"]*)"/gi)].map((m) => m[1].replace(/&amp;/g, '&'));
  }
  if (extname(path) === '.css') {
    // A quoted data: URL may hold url() of its own (an SVG filter's
    // url(%23n)). It needs no check, so take it out first.
    text = text.replace(/url\(\s*"data:[^"]*"\s*\)/gi, '').replace(/url\(\s*'data:[^']*'\s*\)/gi, '');
    return [...text.matchAll(/url\(\s*(['"]?)([^'")]*)\1\s*\)/gi)].map((m) => m[2]);
  }
  return [];
}

function idsIn(html) {
  return new Set([...html.matchAll(/\s(?:id|name)="([^"]*)"/gi)].map((m) => m[1]));
}

/** The file a site path names: a folder means its index.html. */
function fileFor(root, sitePath) {
  const local = join(root, ...decodeURIComponent(sitePath).split('/'));
  if (sitePath.endsWith('/')) return join(local, 'index.html');
  if (existsSync(local) && statSync(local).isDirectory()) return join(local, 'index.html');
  return local;
}

/**
 * Check every link under `root`.
 * Returns { broken: ["page -> link"], skipped: [unique outside urls], checked }.
 */
export function checkLinks(root) {
  const broken = [];
  const skipped = new Set();
  let checked = 0;
  const idCache = new Map();
  const ids = (file) => {
    if (!idCache.has(file)) idCache.set(file, idsIn(readFileSync(file, 'utf8')));
    return idCache.get(file);
  };

  for (const file of walk(root)) {
    const ext = extname(file);
    if (ext !== '.html' && ext !== '.css') continue;
    const page = relative(root, file).split(sep).join('/');
    for (const link of linksIn(file, readFileSync(file, 'utf8'))) {
      if (link === '' || /^data:/i.test(link)) continue;
      if (isExternal(link)) {
        skipped.add(link);
        continue;
      }
      checked += 1;
      const [pathAndQuery, fragment] = link.split('#');
      const path = pathAndQuery.split('?')[0];
      let target;
      if (path === '') target = file;
      else if (path.startsWith('/')) target = fileFor(root, path);
      else target = fileFor(root, posix.join('/', posix.dirname('/' + page), path) + (path.endsWith('/') ? '/' : ''));
      if (!existsSync(target)) {
        broken.push(`${page} -> ${link}`);
        continue;
      }
      if (fragment && extname(target) === '.html' && !ids(target).has(decodeURIComponent(fragment))) {
        broken.push(`${page} -> ${link}`);
      }
    }
  }
  return { broken, skipped: [...skipped].sort(), checked };
}

