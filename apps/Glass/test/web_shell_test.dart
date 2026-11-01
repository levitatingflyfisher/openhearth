import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glass/features/weather/data/open_meteo_client.dart';

/// The PWA shell is what a search engine, a link preview and a slow first
/// load see before Flutter paints (audit design-for-hackers-01/10): the
/// title leads with what the app is, the description says it plainly, and
/// the boot screen carries real words, not only a spinner.
void main() {
  final html = File('web/index.html').readAsStringSync();

  test('the title says what the app is, not only its name', () {
    final title = RegExp(r'<title>(.*?)</title>').firstMatch(html)!.group(1)!;
    expect(title, isNot('WeatherGlass'));
    expect(title.toLowerCase(), contains('weather'));
    expect(title, contains('WeatherGlass'));
  });

  test('the description is plain and under 200 characters', () {
    final d = RegExp(r'<meta name="description" content="(.*?)">')
        .firstMatch(html)!
        .group(1)!;
    expect(d.length, inInclusiveRange(80, 200));
    expect(d, isNot(contains(' — ')));
  });

  test('the boot screen carries a heading and a sentence', () {
    final boot =
        RegExp(r'<div id="oh-boot"[^>]*>(.*?)</div>\s*<script', dotAll: true)
            .firstMatch(html)!
            .group(1)!;
    expect(boot, contains('<h1'));
    expect(boot, contains('<p'));
  });

  group('Content-Security-Policy', () {
    // The app's claim is "only Open-Meteo, nothing third party". With this
    // tag the browser enforces it instead of trusting the code.
    Map<String, List<String>> policy() {
      final m = RegExp(
              r'<meta http-equiv="Content-Security-Policy" content="(.*?)">',
              dotAll: true)
          .firstMatch(html);
      expect(m, isNotNull, reason: 'web/index.html has no CSP meta tag');
      return {
        for (final d in m!
            .group(1)!
            .split(';')
            .map((d) => d.trim())
            .where((d) => d.isNotEmpty))
          d.split(RegExp(r'\s+')).first:
              d.split(RegExp(r'\s+')).skip(1).toList(),
      };
    }

    test('the only remote hosts allowed are the two Open-Meteo hosts', () {
      final p = policy();
      expect(p['default-src'], ["'self'"]);
      expect(
          p['connect-src'],
          containsAll([
            "'self'",
            'https://${OpenMeteo.forecastHost}',
            'https://${OpenMeteo.geocodeHost}',
          ]));
      final remote = {
        for (final v in p.values)
          for (final t in v)
            if (t.startsWith('http') || t == '*') t,
      };
      expect(remote, {
        'https://${OpenMeteo.forecastHost}',
        'https://${OpenMeteo.geocodeHost}',
      });
    });

    test('no eval, no plugins, no foreign base or form target', () {
      final p = policy();
      expect(p['script-src'], isNot(contains("'unsafe-eval'")));
      expect(p['script-src'], isNot(contains("'unsafe-inline'")));
      expect(p['script-src'], contains("'wasm-unsafe-eval'"));
      expect(p['object-src'], ["'none'"]);
      expect(p['base-uri'], ["'self'"]);
      expect(p['form-action'], ["'none'"]);
    });

    test('fonts and the renderer stay on the app\'s own host', () {
      final p = policy();
      expect(p['font-src'], isNot(contains('https:')));
      expect(p['font-src'], contains("'self'"));
      expect(p['worker-src'], contains("'self'"));
      expect(p['script-src'], contains("'self'"));
    });

    test('no inline script is left, so none needs allowing', () {
      expect(RegExp(r'<script>').hasMatch(html), isFalse,
          reason: 'keep scripts in files so script-src needs no inline rule');
    });
  });
}
