import 'dart:io';

import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory _dir;

String _write(String rel, String text) {
  final f = File(p.join(_dir.path, rel))..createSync(recursive: true);
  f.writeAsStringSync(text);
  return f.path;
}

Future<(int, String)> _run(List<String> args) async {
  final out = StringBuffer();
  final code = await runRelease(args, out: out, err: out);
  return (code, out.toString());
}

void main() {
  setUp(() {
    final root = Directory(p.join('.dart_tool', 'kit_test_tmp'))
      ..createSync(recursive: true);
    _dir = root.createTempSync('cli_');
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  test('no command prints usage and exits 2', () async {
    final (code, out) = await _run([]);
    expect(code, 2);
    expect(out, contains('usage'));
  });

  test('an unknown command exits 2', () async {
    expect((await _run(['nope'])).$1, 2);
  });

  group('version', () {
    setUp(() {
      _write('pubspec.yaml', 'name: demo\nversion: 1.0.0+5\n');
      _write('lib/app_version.dart', "const appVersion = '1.0.0';\n");
      _write('CHANGELOG.md', '## [1.0.0]\n');
      _write('fastlane/metadata/android/en-US/changelogs/2005.txt', 'x\n');
    });

    test('a consistent app exits 0', () async {
      final (code, out) = await _run(['version', _dir.path]);
      expect(code, 0, reason: out);
      expect(out, contains('fastlane en-US: 2005.txt'));
    });

    test('a stale constant exits 1', () async {
      _write('lib/app_version.dart', "const appVersion = '0.9.0';\n");
      final (code, out) = await _run(['version', _dir.path]);
      expect(code, 1);
      expect(out, contains('FAIL'));
    });

    test('a folder with no pubspec exits 2', () async {
      final (code, _) = await _run(['version', p.join(_dir.path, 'none')]);
      expect(code, 2);
    });
  });

  test('shared-versions prints the ledger block', () async {
    _write('pubspec.yaml', 'name: demo\nversion: 1.0.0+5\n');
    _write('pubspec.lock', '''
packages:
  oh_fleet_conformance:
    dependency: "direct dev"
    description:
      path: "../oh_fleet_conformance"
      relative: true
    source: path
    version: "0.17.0"
''');
    final (code, out) = await _run(['shared-versions', _dir.path]);
    expect(code, 0, reason: out);
    expect(out, contains('demo 1.0.0+5'));
    expect(out, contains('oh_fleet_conformance  0.17.0'));
  });

  test('shared-versions walks up in a Dart Pub Workspace and scopes to app deps',
      () async {
    _write('pubspec.yaml', '''
name: openhearth_workspace
workspace:
  - apps/demo
  - packages/sanctuary_backup_ui
  - packages/sanctuary_auth_core
  - packages/oh_fleet_conformance
''');
    // Unrelated non-workspace path package used only by another app.
    _write('pubspec.lock', '''
packages:
  unrelated_native_pkg:
    dependency: transitive
    description:
      path: "native/unrelated_native_pkg"
      relative: true
    source: path
    version: "0.1.0"
''');
    _write('native/unrelated_native_pkg/pubspec.yaml',
        'name: unrelated_native_pkg\nversion: 0.1.0\n');
    _write('packages/sanctuary_auth_core/pubspec.yaml',
        'name: sanctuary_auth_core\nversion: 0.1.0\nresolution: workspace\n');
    _write('packages/sanctuary_backup_ui/pubspec.yaml', '''
name: sanctuary_backup_ui
version: 0.3.0
resolution: workspace
dependencies:
  sanctuary_auth_core:
    path: ../sanctuary_auth_core
''');
    _write('packages/oh_fleet_conformance/pubspec.yaml',
        'name: oh_fleet_conformance\nversion: 0.18.0\nresolution: workspace\n');
    _write('apps/demo/pubspec.yaml', '''
name: demo
version: 1.0.0+5
resolution: workspace
dependencies:
  sanctuary_backup_ui:
    path: ../../packages/sanctuary_backup_ui
dev_dependencies:
  oh_fleet_conformance: any
''');
    _write('.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {"name": "demo", "rootUri": "../apps/demo", "packageUri": "lib/"},
    {"name": "sanctuary_backup_ui", "rootUri": "../packages/sanctuary_backup_ui", "packageUri": "lib/"},
    {"name": "sanctuary_auth_core", "rootUri": "../packages/sanctuary_auth_core", "packageUri": "lib/"},
    {"name": "oh_fleet_conformance", "rootUri": "../packages/oh_fleet_conformance", "packageUri": "lib/"},
    {"name": "unrelated_native_pkg", "rootUri": "../native/unrelated_native_pkg", "packageUri": "lib/"}
  ]
}
''');
    final (code, out) =
        await _run(['shared-versions', p.join(_dir.path, 'apps', 'demo')]);
    expect(code, 0, reason: out);
    expect(out, contains('demo 1.0.0+5'));
    expect(out, contains('sanctuary_backup_ui  0.3.0  ../../packages/sanctuary_backup_ui'));
    expect(out, contains('sanctuary_auth_core  0.1.0  ../../packages/sanctuary_auth_core'));
    expect(out, contains('oh_fleet_conformance  0.18.0  ../../packages/oh_fleet_conformance'));
    expect(out, isNot(contains('unrelated_native_pkg')));
  });

  group('leakscan', () {
    const diff =
        'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -0,0 +1 @@\n'
        '+hello examplename\n';

    test('clean without private patterns', () async {
      final (code, out) = await _run(['leakscan', _write('d.diff', diff)]);
      expect(code, 0, reason: out);
      expect(out, contains('clean'));
    });

    test('a private hit exits 1', () async {
      final (code, out) = await _run([
        'leakscan',
        _write('d.diff', diff),
        '--private',
        _write('private.txt', '# words\nexamplename\n'),
      ]);
      expect(code, 1);
      expect(out, contains('x:1: private pattern (line 2)'));
    });

    test('a missing private file exits 2, never scans without it', () async {
      final (code, _) = await _run([
        'leakscan',
        _write('d.diff', diff),
        '--private',
        p.join(_dir.path, 'missing.txt'),
      ]);
      expect(code, 2);
    });

    test('an empty diff exits 2: a failed git diff must not read as clean',
        () async {
      final (code, out) = await _run(['leakscan', _write('d.diff', '')]);
      expect(code, 2);
      expect(out, contains('empty'));
    });

    test('--all-lines scans plain text such as commit messages', () async {
      final (code, _) = await _run([
        'leakscan',
        _write(
          'msg.txt',
          'Co-'
              'Authored-By: someone\n',
        ),
        '--all-lines',
      ]);
      expect(code, 1);
    });
  });

  test('web-check reads the build folder and exits 1 on a failure', () async {
    _write('budgets.json', '{"main_dart_js_gz_max_bytes": 10}');
    final web = p.join(_dir.path, 'build', 'web');
    _write('build/web/index.html', '<base href="/Demo/">');
    _write('build/web/main.dart.js', 'x' * 5000);
    final (code, out) = await _run(['web-check', _dir.path, web]);
    expect(code, 1);
    expect(out, contains('base href /Demo/'));
    expect(out, contains('no manifest.json'));
  });

  test('apk-check without aapt2 exits 2 and says where it looked', () async {
    _write('pubspec.yaml', 'name: demo\nversion: 1.0.0+5\n');
    final (code, out) = await _run([
      'apk-check',
      _write('app.apk', 'not an apk'),
      _dir.path,
      '--build-tools',
      p.join(_dir.path, 'no-sdk'),
    ]);
    expect(code, 2);
    expect(out, contains('aapt2'));
  });

  test('export refuses an existing destination with exit 2', () async {
    final (code, out) = await _run(['export', _dir.path, 'HEAD', _dir.path]);
    expect(code, 2);
    expect(out, contains('already exists'));
  });
}
