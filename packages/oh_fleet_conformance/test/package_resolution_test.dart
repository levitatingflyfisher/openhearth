import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/package_resolution.dart';

void main() {
  late Directory parent;
  late Directory app;

  setUp(() {
    parent = Directory.systemTemp.createTempSync('ohfc_resolve_');
    app = Directory('${parent.path}/clones/app')..createSync(recursive: true);
  });

  tearDown(() => parent.deleteSync(recursive: true));

  void writeConfig(Object json) {
    File('${app.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(json is String ? json : jsonEncode(json));
  }

  Map<String, Object> config(Map<String, String> rootUris) => {
        'configVersion': 2,
        'packages': [
          for (final e in rootUris.entries)
            {'name': e.key, 'rootUri': e.value, 'packageUri': 'lib/'},
        ],
      };

  String canonical(Directory d) => d.absolute.uri.normalizePath().toFilePath();

  test('a relative rootUri resolves against the .dart_tool folder', () {
    // Pub writes a relative path dependency relative to package_config.json.
    writeConfig(config({'openhearth_design': '../../../ohStyle/openhearth_design'}));
    final root = resolvePackageRoot(app, 'openhearth_design');
    expect(canonical(root),
        canonical(Directory('${parent.path}/ohStyle/openhearth_design')));
  });

  test('a relative rootUri with a trailing slash resolves the same', () {
    writeConfig(config({'openhearth_design': '../../../ohStyle/openhearth_design/'}));
    final root = resolvePackageRoot(app, 'openhearth_design');
    expect(canonical(root),
        canonical(Directory('${parent.path}/ohStyle/openhearth_design')));
  });

  test('an absolute file: rootUri (a pubspec_overrides.yaml path) is used as is',
      () {
    final elsewhere = Directory('${parent.path}/far/away/openhearth_design')
      ..createSync(recursive: true);
    writeConfig(config({'openhearth_design': elsewhere.uri.toString()}));
    expect(canonical(resolvePackageRoot(app, 'openhearth_design')),
        canonical(elsewhere));
  });

  test('a relative app root still resolves to an absolute folder', () {
    writeConfig(config({'openhearth_design': '../../../ohStyle/openhearth_design'}));
    final previous = Directory.current;
    Directory.current = parent;
    try {
      final root = resolvePackageRoot(Directory('clones/app'), 'openhearth_design');
      expect(root.isAbsolute, isTrue);
      expect(canonical(root),
          canonical(Directory('${parent.path}/ohStyle/openhearth_design')));
    } finally {
      Directory.current = previous;
    }
  });

  test('no package_config.json is a StateError that says to run pub get', () {
    expect(
      () => resolvePackageRoot(app, 'openhearth_design'),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('package_config.json'))
          .having((e) => e.message, 'message', contains('pub get'))),
    );
  });

  test('a package missing from package_config.json is a StateError', () {
    writeConfig(config({'some_other': '../'}));
    expect(
      () => resolvePackageRoot(app, 'openhearth_design'),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('openhearth_design'))),
    );
  });

  test('an unreadable package_config.json is a StateError, not a crash', () {
    writeConfig('{ not json');
    expect(() => resolvePackageRoot(app, 'openhearth_design'),
        throwsA(isA<StateError>()));
    writeConfig({'configVersion': 2});
    expect(() => resolvePackageRoot(app, 'openhearth_design'),
        throwsA(isA<StateError>()));
    writeConfig(config({'openhearth_design': 'https://example.com/x/'}));
    expect(() => resolvePackageRoot(app, 'openhearth_design'),
        throwsA(isA<StateError>()));
  });

  test('walks up to a parent Dart Pub Workspace package_config.json', () {
    final ws = Directory('${parent.path}/monorepo')..createSync();
    final wsApp = Directory('${ws.path}/apps/furrow')
      ..createSync(recursive: true);
    final design = Directory('${ws.path}/packages/ohStyle/openhearth_design')
      ..createSync(recursive: true);
    File('${ws.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(
          config({'openhearth_design': '../packages/ohStyle/openhearth_design'})));

    final root = resolvePackageRoot(wsApp, 'openhearth_design');
    expect(canonical(root), canonical(design));
  });

  test('prefers app-local package_config.json over a parent workspace one', () {
    final ws = Directory('${parent.path}/monorepo')..createSync();
    final wsApp = Directory('${ws.path}/apps/furrow')
      ..createSync(recursive: true);
    final parentDesign = Directory('${ws.path}/packages/ohStyle/openhearth_design')
      ..createSync(recursive: true);
    final localDesign = Directory('${ws.path}/local_override/openhearth_design')
      ..createSync(recursive: true);
    File('${ws.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(config(
          {'openhearth_design': parentDesign.uri.toString()})));
    File('${wsApp.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(config(
          {'openhearth_design': localDesign.uri.toString()})));

    final root = resolvePackageRoot(wsApp, 'openhearth_design');
    expect(canonical(root), canonical(localDesign));
  });
}
