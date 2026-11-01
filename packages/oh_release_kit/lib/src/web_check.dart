import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'check_result.dart';

/// The size the web budget is measured in: main.dart.js at gzip level 9,
/// as Trellis's web check and the apps' budgets.json notes measure it.
int gzipSize(List<int> bytes) => GZipCodec(level: 9).encode(bytes).length;

/// The value of `<base href="...">`, or null when there is none.
String? baseHref(String html) => RegExp(
  r'''<base\s+href\s*=\s*["']([^"']*)["']''',
).firstMatch(html)?.group(1);

/// Where the fleet serves Flutter's fallback fonts: one mirror at the site
/// root, shared by every PWA (conformance C13).
const fleetFontFallbackBaseUrl = '/fonts/flutter-fallback/';

// Every host a built file must not reach. A visitor's browser would send it
// a request on load: a third party on every visit, from apps that promise
// privacy by default.
final _cdn = RegExp(
  r'''[a-z0-9.-]*(?:gstatic\.com|googleapis\.com|fonts\.google\.com|unpkg\.com|jsdelivr\.(?:net|com)|cdnjs\.cloudflare\.com|google-analytics\.com|googletagmanager\.com)[^"'\s)`]*''',
  caseSensitive: false,
);

// The engine keeps these defaults in main.dart.js and flutter.js even when
// the bootstrap overrides them; they are dead only when the override holds.
final _fontDefault = RegExp(r'^fonts\.gstatic\.com/s/$');
final _canvasKitDefault = RegExp(
  r'^www\.gstatic\.com/flutter-canvaskit(?:/[0-9a-f]{40}/)?$',
);
// A bare tracker host with no path is a name in a blocklist, not a request.
final _bareTracker = RegExp(
  r'^(?:www\.)?(?:google-analytics|googletagmanager)\.com$',
);

/// The value of [key] in the app's own `_flutter.loader.load(...)` call:
/// the text after the last call, with comments removed so a commented-out
/// key does not count.
String? loaderConfigValue(String bootstrapJs, String key) {
  final at = bootstrapJs.lastIndexOf('_flutter.loader.load(');
  if (at < 0) return null;
  final cfg = bootstrapJs
      .substring(at)
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      // A `//` comment, but not the one inside a scheme like https://.
      .replaceAll(RegExp(r'(^|[\s;,{])//[^\n]*', multiLine: true), r'$1');
  return RegExp(
    '''$key["']?\\s*:\\s*["']([^"']*)["']''',
  ).firstMatch(cfg)?.group(1);
}

bool _absolute(String url) =>
    RegExp(r'^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)').hasMatch(url);

/// Checks a built web folder (release step 6). Every argument is what the
/// command read from the build; a null text means the file is missing.
/// [files] lists every path in the build, relative to it. [textFiles] maps
/// each text file (js, html, json, css) to its contents, for the CDN scan.
CheckResult checkWebBuild({
  required String? indexHtml,
  required String? manifestJson,
  required String? bootstrapJs,
  required String? fontManifestJson,
  required String? budgetsJson,
  required int? mainJsGzipBytes,
  required Set<String> files,
  required Map<String, String> textFiles,
  String? expectedBaseHref,
}) {
  final r = CheckResult();
  _checkBaseHref(r, indexHtml, expectedBaseHref);
  _checkManifest(r, manifestJson, indexHtml);
  _checkBudget(r, budgetsJson, mainJsGzipBytes);
  _checkSelfHosted(r, bootstrapJs, files, textFiles);
  _checkFonts(r, fontManifestJson, files);
  return r;
}

void _checkBaseHref(CheckResult r, String? html, String? expected) {
  final href = html == null ? null : baseHref(html);
  if (href == null) {
    r.failures.add('index.html: no <base href> (the app would serve blank)');
  } else if (href.contains(r'$FLUTTER_BASE_HREF')) {
    r.failures.add('index.html: base href is the unfilled placeholder');
  } else if (expected != null && href != expected) {
    r.failures.add('index.html: base href is $href, expected $expected');
  } else if (expected == null && href == '/') {
    r.failures.add(
      'index.html: base href is /, but fleet PWAs are served '
      'under /<App>/ (pass --base-href / if this app really is at the root)',
    );
  } else {
    r.passes.add('base href $href');
  }
}

void _checkManifest(CheckResult r, String? manifest, String? html) {
  if (manifest == null) {
    r.failures.add('no manifest.json');
    return;
  }
  try {
    jsonDecode(manifest);
  } on FormatException {
    r.failures.add('manifest.json is not valid JSON');
    return;
  }
  final both = '$manifest${html ?? ''}'.toLowerCase();
  if (both.contains('a new flutter project') || both.contains('#0175c2')) {
    r.failures.add(
      "manifest.json or index.html still holds Flutter's "
      'template name or colour',
    );
    return;
  }
  r.passes.add('manifest.json parses');
}

void _checkBudget(CheckResult r, String? budgetsJson, int? mainGz) {
  if (mainGz == null) {
    r.failures.add('no main.dart.js in the build');
    return;
  }
  int? max;
  if (budgetsJson != null) {
    final doc = jsonDecode(budgetsJson);
    if (doc is Map && doc['main_dart_js_gz_max_bytes'] is int) {
      max = doc['main_dart_js_gz_max_bytes'] as int;
    }
  }
  if (max == null) {
    r.notes.add(
      'no web budget (main_dart_js_gz_max_bytes in budgets.json); '
      'main.dart.js is $mainGz bytes at gzip -9',
    );
  } else if (mainGz > max) {
    r.failures.add(
      'main.dart.js is $mainGz bytes at gzip -9, '
      '${mainGz - max} over the budget of $max',
    );
  } else {
    r.passes.add('main.dart.js $mainGz bytes at gzip -9, budget $max');
  }
}

void _checkSelfHosted(
  CheckResult r,
  String? bootstrap,
  Set<String> files,
  Map<String, String> textFiles,
) {
  var canvasKitOk = false, fontsOk = false;
  if (bootstrap == null) {
    r.failures.add('no flutter_bootstrap.js: not a Flutter web build');
  } else {
    if (!RegExp(r'"useLocalCanvasKit"\s*:\s*true').hasMatch(bootstrap)) {
      r.failures.add(
        'built without --no-web-resources-cdn: CanvasKit would '
        'load from Google',
      );
    } else {
      canvasKitOk = true;
    }
    final ck = loaderConfigValue(bootstrap, 'canvasKitBaseUrl');
    if (ck == null) {
      r.failures.add(
        'canvasKitBaseUrl is not set in the load() config '
        "(web/flutter_bootstrap.js): the engine's default is a CDN",
      );
      canvasKitOk = false;
    } else if (_absolute(ck)) {
      r.failures.add('canvasKitBaseUrl is absolute ($ck)');
      canvasKitOk = false;
    }
    final ff = loaderConfigValue(bootstrap, 'fontFallbackBaseUrl');
    if (ff == null) {
      r.failures.add(
        'fontFallbackBaseUrl is not set in the load() config: '
        "the engine's default is fonts.gstatic.com",
      );
    } else if (ff != fleetFontFallbackBaseUrl) {
      r.failures.add(
        'fontFallbackBaseUrl is $ff; the fleet serves fallback '
        'fonts at $fleetFontFallbackBaseUrl',
      );
    } else {
      fontsOk = true;
    }
  }
  for (final f in [
    'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.wasm',
  ]) {
    if (!files.contains(f)) {
      r.failures.add(
        'missing $f: the self-hosted CanvasKit is not in the build',
      );
    }
  }

  final hits = <String>[];
  final paths = textFiles.keys.toList()..sort();
  for (final path in paths) {
    for (final m in _cdn.allMatches(textFiles[path]!)) {
      final url = m.group(0)!;
      if (fontsOk && _fontDefault.hasMatch(url)) continue;
      if (canvasKitOk && _canvasKitDefault.hasMatch(url)) continue;
      if (_bareTracker.hasMatch(url)) continue;
      hits.add('$path: $url');
    }
  }
  if (hits.isNotEmpty) {
    r.failures.add(
      'CDN or font host requests in the build:\n'
      '${hits.toSet().map((h) => '        $h').join('\n')}',
    );
  } else if (bootstrap != null && canvasKitOk && fontsOk) {
    r.passes.add('no CDN or font host requests; CanvasKit self-hosted');
  }
}

void _checkFonts(CheckResult r, String? fontManifest, Set<String> files) {
  if (fontManifest == null) {
    r.failures.add('no assets/FontManifest.json');
    return;
  }
  final Object? doc;
  try {
    doc = jsonDecode(fontManifest);
  } on FormatException {
    r.failures.add('assets/FontManifest.json is not valid JSON');
    return;
  }
  if (doc is! List) {
    r.failures.add('assets/FontManifest.json is not a list');
    return;
  }
  final textFamilies = <String>[];
  final missing = <String>[];
  for (final fam in doc) {
    if (fam is! Map) continue;
    final name = '${fam['family']}';
    if (!name.toLowerCase().endsWith('icons')) textFamilies.add(name);
    final fonts = fam['fonts'];
    if (fonts is! List) continue;
    for (final f in fonts) {
      if (f is! Map || f['asset'] is! String) continue;
      final asset = f['asset'] as String;
      if (!files.contains('assets/$asset') &&
          !files.contains('assets/${Uri.decodeFull(asset)}')) {
        missing.add(asset);
      }
    }
  }
  if (textFamilies.isEmpty) {
    r.failures.add(
      'no text font in FontManifest.json: without a CDN font, '
      'no text would render',
    );
  }
  for (final m in missing) {
    r.failures.add('font $m is listed but not in the build');
  }
  if (textFamilies.isNotEmpty && missing.isEmpty) {
    r.passes.add('fonts self-hosted: ${textFamilies.join(', ')}');
  }
}
