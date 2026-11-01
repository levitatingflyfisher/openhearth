// The copy into the landing repo keeps what the build did not make.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { landing } from '../../scripts/landing.mjs';

function put(path, text) {
  mkdirSync(join(path, '..'), { recursive: true });
  writeFileSync(path, text);
}

test('landing replaces the page, keeps glean, porch and fonts, and drops old build files', () => {
  const root = mkdtempSync(join(tmpdir(), 'ohsite-landing-'));
  try {
    const dist = join(root, 'dist');
    const site = join(root, 'site');
    put(join(dist, 'index.html'), 'new home');
    put(join(dist, 'about', 'index.html'), 'about');
    put(join(dist, '_astro', 'a.css'), 'css');
    put(join(dist, 'fonts', 'fonts.css'), 'dev copy');
    put(join(dist, 'glean', 'index.html'), 'must not land');

    put(join(site, '.git', 'HEAD'), 'ref');
    put(join(site, 'index.html'), 'old hand-kept page');
    put(join(site, 'glean', 'index.html'), 'glean viewer');
    put(join(site, 'porch', 'index.html'), 'porch preview');
    put(join(site, 'fonts', 'fonts.css'), 'real fonts');
    put(join(site, 'fonts', 'flutter-fallback', 'x'), 'x');
    put(join(site, 'other.txt'), 'not ours');

    const first = landing(dist, site);
    assert.deepEqual(first.written, ['_astro', 'about', 'index.html']);
    assert.deepEqual(first.kept, ['fonts', 'glean']);
    assert.equal(readFileSync(join(site, 'index.html'), 'utf8'), 'new home');
    assert.equal(readFileSync(join(site, 'glean', 'index.html'), 'utf8'), 'glean viewer');
    assert.equal(readFileSync(join(site, 'porch', 'index.html'), 'utf8'), 'porch preview');
    assert.equal(readFileSync(join(site, 'fonts', 'fonts.css'), 'utf8'), 'real fonts');
    assert.ok(existsSync(join(site, 'fonts', 'flutter-fallback', 'x')));
    assert.ok(existsSync(join(site, 'other.txt')));

    // A page taken out of the site leaves the landing repo on the next run.
    rmSync(join(dist, 'about'), { recursive: true });
    landing(dist, site);
    assert.ok(!existsSync(join(site, 'about')));
    assert.ok(existsSync(join(site, 'other.txt')));
    assert.ok(existsSync(join(site, 'glean', 'index.html')));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('landing refuses a folder that is not a git repo', () => {
  const root = mkdtempSync(join(tmpdir(), 'ohsite-landing-'));
  try {
    put(join(root, 'dist', 'index.html'), 'x');
    mkdirSync(join(root, 'site'));
    assert.throws(() => landing(join(root, 'dist'), join(root, 'site')), /not a git repo/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
