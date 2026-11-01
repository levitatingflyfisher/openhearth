import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reckon overrides `sqlite3` to 3.x (flutter_gemma needs it). The web build
/// compiles drift's own web code (`package:drift/wasm.dart`) against that
/// sqlite3, so the drift in the lock must be one written for sqlite3 3.x.
///
/// drift 2.31 asks for `sqlite3: ^2.6.0`. Forced onto sqlite3 3.x it still
/// passes every native test, but `flutter build web` fails inside drift
/// (`web_protocol.dart`: "Too many positional arguments: 0 allowed, but 6
/// found", because sqlite3 3 made `SqliteException`'s arguments named).
/// This test catches that mismatch without a web build.
void main() {
  test('the locked drift is written for the locked sqlite3 major', () {
    final sqlite3Major = _lockedVersion('sqlite3').split('.').first;

    final driftPubspec = File.fromUri(_packageRoot('drift').resolve('pubspec.yaml'));
    final line = driftPubspec
        .readAsLinesSync()
        .firstWhere((l) => RegExp(r'^  sqlite3:').hasMatch(l));
    final constraint = line.split(':').last.split('#').first.trim();
    final wantedMajor =
        RegExp(r'\d+').firstMatch(constraint)!.group(0); // "^2.6.0" -> "2"

    expect(wantedMajor, sqlite3Major,
        reason: 'drift ${_lockedVersion('drift')} asks for sqlite3 '
            '"$constraint", but the lock has sqlite3 '
            '${_lockedVersion('sqlite3')}. The web build will not compile.');
  });
}

String _lockedVersion(String name) {
  final lines = File('pubspec.lock').readAsLinesSync();
  final start = lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: '$name is not in pubspec.lock');
  final versionLine = lines
      .skip(start + 1)
      .firstWhere((l) => l.startsWith('    version:'));
  return versionLine.split('"')[1];
}

Uri _packageRoot(String name) {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final entry = (config['packages'] as List)
      .cast<Map>()
      .firstWhere((p) => p['name'] == name);
  var root = entry['rootUri'] as String;
  if (!root.endsWith('/')) root = '$root/';
  return configFile.absolute.uri.resolve(root);
}
