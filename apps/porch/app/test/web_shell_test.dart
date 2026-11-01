// The PWA shell says what porch is before Flutter paints (audit
// design-for-hackers-07): a slow first load, a link preview or a search
// crawler sees the boot screen, the title and the description, never a
// bare spinner under a one-word title. Read from the files; no browser.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:test/test.dart';

void main() {
  final html = File('web/index.html').readAsStringSync();
  final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
      as Map<String, Object?>;

  test('the boot screen carries a heading and a sentence', () {
    final boot =
        RegExp(r'<div id="oh-boot">([\s\S]*?)</div>\s*<script').firstMatch(html);
    expect(boot, isNotNull, reason: 'no #oh-boot block');
    final inner = boot!.group(1)!;
    expect(inner, contains('<h1>Porch</h1>'));
    final p = RegExp(r'<p>([\s\S]*?)</p>').firstMatch(inner);
    expect(p, isNotNull, reason: 'no sentence in #oh-boot');
    expect(p!.group(1)!.split(' ').length, greaterThan(12));
  });

  test('the title says what the app is, not just its name', () {
    final title = RegExp(r'<title>(.*?)</title>').firstMatch(html)!.group(1)!;
    expect(title, isNot('Porch'));
    expect(title, contains('Porch'));
  });

  test('the shell copy follows the house typography', () {
    final description = RegExp(r'<meta name="description" content="([^"]*)"')
        .firstMatch(html)!
        .group(1)!;
    for (final text in [
      description,
      manifest['name']! as String,
      manifest['description']! as String,
    ]) {
      expect(text, isNot(contains(' — ')), reason: text);
      expect(RegExp(r"[A-Za-z]'[A-Za-z]").hasMatch(text), isFalse,
          reason: text);
    }
  });

  test('the shell colours are the app theme, light and dark', () {
    expect(html, contains('#FBF8F4')); // OhColors.linen50, light ground
    expect(html, contains('#1C1007')); // darkSurfaceBase, dark ground
    expect(html, contains('<meta name="theme-color" content="#845416">'));
    expect(manifest['theme_color'], '#845416');
  });

  // The web build keeps porch's keys in browser storage, which is per
  // origin. It must be served from an origin of its own, and a CSP keeps
  // any script that is not porch's own file from running there.
  group('the web build guards its origin', () {
    final csp = RegExp(
            r'<meta http-equiv="Content-Security-Policy" content="([^"]*)">')
        .firstMatch(html)
        ?.group(1);

    Map<String, String> directives() => {
          for (final d in csp!.split(';').map((d) => d.trim()))
            if (d.isNotEmpty)
              d.split(' ').first: d.split(' ').skip(1).join(' '),
        };

    test('a CSP: only porch\'s own scripts and wasm, connections to this '
        'origin and https only', () {
      expect(csp, isNotNull, reason: 'no CSP meta tag');
      final d = directives();
      expect(d['default-src'], "'self'");
      expect(d['script-src'], "'self' 'wasm-unsafe-eval'");
      expect(d['connect-src'], "'self' https:");
      expect(d['object-src'], "'none'");
      expect(d['base-uri'], "'self'");
    });

    test('the CSP comes before any script', () {
      expect(html.indexOf('Content-Security-Policy'),
          lessThan(html.indexOf('<script')));
    });

    test('no inline script: the CSP would block it', () {
      for (final m in RegExp(r'<script([^>]*)>([\s\S]*?)</script>')
          .allMatches(html)) {
        expect(m.group(1), contains('src='), reason: m.group(0));
        expect(m.group(2)!.trim(), isEmpty, reason: m.group(0));
      }
    });

    test('the boot script lives in its own file and keeps its jobs', () {
      expect(html, contains('<script src="boot.js"></script>'));
      final boot = File('web/boot.js').readAsStringSync();
      expect(boot, contains('navigator.storage.persist'));
      expect(boot, contains('controllerchange'));
      expect(boot, contains('oh-boot'));
    });

    test('the bootstrap no longer says porch shares the fleet origin', () {
      final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
      expect(bootstrap, isNot(contains('levitatingflyfisher.github.io')));
      expect(bootstrap, isNot(contains('every OpenHearth PWA')));
    });
  });

  test('the vendored sodium.js has its version and SHA-256 recorded, and '
      'the hash matches the file', () {
    final readme = File('web/sodium.README.md').readAsStringSync();
    final hash =
        sha256.convert(File('web/sodium.js').readAsBytesSync()).toString();
    expect(readme, contains(hash));
    expect(readme, contains('Version'));
  });
}
