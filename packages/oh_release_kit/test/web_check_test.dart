import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:test/test.dart';

const _html =
    '<html><head><base href="/Demo/"><title>Demo</title>'
    '</head><body><script src="flutter_bootstrap.js"></script></body></html>';
const _manifest =
    '{"name": "Demo", "short_name": "Demo", '
    '"background_color": "#FAF7F0"}';
const _bootstrap = '''
{"engineRevision":"abc","builds":[{"compileTarget":"dart2js"}],"useLocalCanvasKit":true}
// The engine default is fonts.gstatic.com/s/ until overridden below.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "/fonts/flutter-fallback/"
  }
});
''';
const _fonts =
    '[{"family":"Lora","fonts":[{"asset":"fonts/Lora.ttf"}]},'
    '{"family":"MaterialIcons","fonts":[{"asset":"fonts/MaterialIcons.otf"}]}]';
const _budgets = '{"main_dart_js_gz_max_bytes": 1000}';

final _files = {
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'main.dart.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.wasm',
  'assets/FontManifest.json',
  'assets/fonts/Lora.ttf',
  'assets/fonts/MaterialIcons.otf',
};

// The engine keeps its CDN defaults in main.dart.js even when the bootstrap
// overrides them; those two exact URLs are allowed, nothing else.
const _mainJs =
    'var a="https://fonts.gstatic.com/s/";'
    'var b="https://www.gstatic.com/flutter-canvaskit/'
    '0123456789abcdef0123456789abcdef01234567/";';

CheckResult _check({
  String? html = _html,
  String? manifest = _manifest,
  String? bootstrap = _bootstrap,
  String? fonts = _fonts,
  String? budgets = _budgets,
  int? mainGz = 900,
  Set<String>? files,
  Map<String, String>? text,
  String? expectedBaseHref,
}) => checkWebBuild(
  indexHtml: html,
  manifestJson: manifest,
  bootstrapJs: bootstrap,
  fontManifestJson: fonts,
  budgetsJson: budgets,
  mainJsGzipBytes: mainGz,
  files: files ?? _files,
  textFiles: text ?? {'main.dart.js': _mainJs, 'index.html': _html},
  expectedBaseHref: expectedBaseHref,
);

void main() {
  test('a good build passes', () {
    final r = _check();
    expect(r.failures, isEmpty);
    expect(r.passes.join('\n'), contains('base href /Demo/'));
    expect(r.passes.join('\n'), contains('900'));
  });

  group('base href', () {
    test('missing fails', () {
      expect(
        _check(html: '<html></html>').failures.single,
        contains('no <base href>'),
      );
    });
    test('the unfilled placeholder fails', () {
      expect(
        _check(html: '<base href="\$FLUTTER_BASE_HREF">').failures.single,
        contains('placeholder'),
      );
    });
    test('the root fails: fleet PWAs are served under /<App>/', () {
      expect(
        _check(html: '<base href="/">').failures.single,
        contains('/<App>/'),
      );
    });
    test('a mismatch with the expected value fails', () {
      expect(
        _check(expectedBaseHref: '/Other/').failures.single,
        contains('/Other/'),
      );
    });
  });

  group('manifest', () {
    test('missing fails', () {
      expect(
        _check(manifest: null).failures.single,
        contains('no manifest.json'),
      );
    });
    test('unparseable fails', () {
      expect(
        _check(manifest: '{nope').failures.single,
        contains('not valid JSON'),
      );
    });
    test("Flutter's template manifest fails", () {
      expect(
        _check(
          manifest: '{"name":"demo","description":"A new Flutter project."}',
        ).failures.single,
        contains('template'),
      );
    });
  });

  group('size budget', () {
    test('over budget fails', () {
      expect(_check(mainGz: 1001).failures.single, contains('over'));
    });
    test('no budget file is a note', () {
      final r = _check(budgets: null);
      expect(r.ok, isTrue);
      expect(r.notes.join(), contains('no web budget'));
    });
    test('no main.dart.js fails', () {
      expect(_check(mainGz: null).failures.single, contains('no main.dart.js'));
    });
  });

  group('no CDN', () {
    test('a font host in any built file fails and names the file', () {
      final r = _check(
        text: {
          'main.dart.js': _mainJs,
          'index.html':
              '<link href="https://fonts.googleapis.com/css?family=X">',
        },
      );
      expect(r.failures.single, contains('index.html'));
      expect(r.failures.single, contains('fonts.googleapis.com'));
    });
    test('unpkg, jsdelivr and cdnjs fail', () {
      for (final host in [
        'unpkg.com/x',
        'cdn.jsdelivr.net/npm/x',
        'cdnjs.cloudflare.com/ajax/x',
      ]) {
        final r = _check(text: {'a.js': 'fetch("https://$host")'});
        expect(r.ok, isFalse, reason: host);
      }
    });
    test(
      'the engine defaults are not allowed when the override is missing',
      () {
        final r = _check(
          bootstrap:
              '{"useLocalCanvasKit":true}\n'
              '_flutter.loader.load({});',
        );
        expect(r.failures.join('\n'), contains('canvasKitBaseUrl'));
        expect(r.failures.join('\n'), contains('fonts.gstatic.com/s/'));
      },
    );
    test('built without --no-web-resources-cdn fails', () {
      final r = _check(bootstrap: _bootstrap.replaceAll('true', 'false'));
      expect(r.failures.join('\n'), contains('--no-web-resources-cdn'));
    });
    test('an absolute fallback font URL fails', () {
      final r = _check(
        bootstrap: _bootstrap.replaceAll(
          '"/fonts/flutter-fallback/"',
          '"https://cdn.exampledomain.org/f/"',
        ),
      );
      expect(r.failures.join('\n'), contains('fontFallbackBaseUrl'));
    });
    test('a commented-out override does not count', () {
      final r = _check(
        bootstrap: _bootstrap.replaceAll(
          'canvasKitBaseUrl: "canvaskit/",',
          '// canvasKitBaseUrl: "canvaskit/",',
        ),
      );
      expect(r.failures.join('\n'), contains('canvasKitBaseUrl'));
    });
    test('a missing self-hosted CanvasKit fails', () {
      final r = _check(files: _files.difference({'canvaskit/canvaskit.wasm'}));
      expect(r.failures.single, contains('canvaskit/canvaskit.wasm'));
    });
  });

  group('fonts self-hosted', () {
    test('no FontManifest fails', () {
      expect(
        _check(fonts: null).failures.single,
        contains('FontManifest.json'),
      );
    });
    test('only icon fonts fails: no text would render', () {
      final r = _check(
        fonts:
            '[{"family":"MaterialIcons","fonts":'
            '[{"asset":"fonts/MaterialIcons.otf"}]}]',
      );
      expect(r.failures.single, contains('no text font'));
    });
    test('a listed font file that is not in the build fails', () {
      final r = _check(files: _files.difference({'assets/fonts/Lora.ttf'}));
      expect(r.failures.single, contains('fonts/Lora.ttf'));
    });
  });

  test('gzipSize compresses at level 9', () {
    final bytes = List<int>.filled(10000, 65);
    expect(gzipSize(bytes), lessThan(200));
  });
}
