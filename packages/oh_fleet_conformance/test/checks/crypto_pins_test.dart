import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

/// C15: the fleet pins cryptographic dependencies to exact versions, so a
/// new release cannot reach a backup key or a recovery phrase without a
/// deliberate change. sanctuary_auth_core and Reckon had caret ranges for
/// months with the rule written down; a check holds it in every app.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_pins_'));
  tearDown(() => root.deleteSync(recursive: true));

  void pubspec(String body) =>
      File('${root.path}/pubspec.yaml').writeAsStringSync(body);

  List<String> messages() =>
      [for (final f in checkCryptoPins(root: root)) f.message];

  test('a caret range on a crypto package is a finding, with the line', () {
    pubspec('''
name: app
dependencies:
  flutter:
    sdk: flutter
  cryptography: ^2.7.0 # AES-GCM
''');
    final m = messages();
    expect(m, hasLength(1));
    expect(
        m.single,
        allOf(contains('pubspec.yaml:5'), contains('cryptography'),
            contains('^2.7.0')));
  });

  test('exact pins pass, with a build suffix or a comment', () {
    pubspec('''
name: app
dependencies:
  crypto: 3.0.7
  sodium_libs: 3.4.6+4 # bundles libsodium
  bip39_mnemonic: "4.1.0"
  cryptography: '2.9.0'
''');
    expect(messages(), isEmpty);
  });

  test('ranges on packages that are not cryptographic pass', () {
    pubspec('''
name: app
dependencies:
  http: ^1.2.2
  flutter_secure_storage: ^9.2.4
''');
    expect(messages(), isEmpty);
  });

  test('the map form is read: a range in version: is a finding', () {
    pubspec('''
name: app
dependencies:
  pointycastle:
    version: ">=3.7.0 <4.0.0"
  crypto:
    hosted: https://pub.dev
    version: 3.0.7
''');
    final m = messages();
    expect(m, hasLength(1));
    expect(m.single, allOf(contains('pointycastle'), contains('pubspec.yaml:3')));
  });

  test('a crypto package from git or a path is a finding', () {
    pubspec('''
name: app
dependencies:
  cryptography:
    git: https://example.invalid/cryptography.git
''');
    expect(messages().single, contains('cryptography'));
  });

  test('an override with a range is a finding; dev dependencies are not', () {
    pubspec('''
name: app
dependencies:
  crypto: 3.0.7
dev_dependencies:
  crypto: ^3.0.0
dependency_overrides:
  cryptography: ^2.9.0
''');
    final m = messages();
    expect(m, hasLength(1));
    expect(m.single, allOf(contains('cryptography'), contains('pubspec.yaml:7')));
  });

  test('no pubspec.yaml is a finding, never a free pass', () {
    expect(messages().single, contains('pubspec.yaml'));
  });

  group('Dart Pub Workspace parent-walk', () {
    late Directory ws;
    late Directory wsApp;

    setUp(() {
      ws = Directory.systemTemp.createTempSync('ohfc_pins_ws_');
      wsApp = Directory('${ws.path}/apps/my_app')..createSync(recursive: true);
      File('${ws.path}/pubspec.yaml').writeAsStringSync('''
name: ws
workspace:
  - apps/my_app
''');
      File('${wsApp.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
resolution: workspace
dependencies:
  crypto: 3.0.8
''');
    });

    tearDown(() => ws.deleteSync(recursive: true));

    test('passes when workspace root overrides and lock agree with exact pins',
        () {
      File('${ws.path}/pubspec.lock').writeAsStringSync('''
packages:
  crypto:
    dependency: transitive
    source: hosted
    version: "3.0.8"
''');
      expect(checkCryptoPins(root: wsApp), isEmpty);
    });

    test('flags an unpinned crypto dependency_override in workspace root pubspec',
        () {
      File('${ws.path}/pubspec.yaml').writeAsStringSync('''
name: ws
workspace:
  - apps/my_app
dependency_overrides:
  cryptography: ^2.9.0
''');
      final findings = checkCryptoPins(root: wsApp);
      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        allOf(contains('workspace pubspec.yaml:5'), contains('cryptography'),
            contains('^2.9.0')),
      );
    });

    test('flags when workspace pubspec.lock disagrees with the pinned version',
        () {
      File('${ws.path}/pubspec.lock').writeAsStringSync('''
packages:
  crypto:
    dependency: transitive
    source: hosted
    version: "3.0.7"
''');
      final findings = checkCryptoPins(root: wsApp);
      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        allOf(contains('pubspec.lock'), contains('crypto'), contains('3.0.7'),
            contains('3.0.8')),
      );
    });

    test('flags when workspace pubspec.lock resolves a crypto package from path',
        () {
      File('${ws.path}/pubspec.lock').writeAsStringSync('''
packages:
  crypto:
    dependency: transitive
    source: path
    version: "3.0.8"
''');
      final findings = checkCryptoPins(root: wsApp);
      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        allOf(contains('pubspec.lock'), contains('crypto'), contains('path')),
      );
    });
  });
}
