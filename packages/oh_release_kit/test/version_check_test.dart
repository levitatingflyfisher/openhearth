import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:test/test.dart';

const _pubspec = '''
name: demo
description: A demo app.
version: 1.4.2+31
''';

const _changelog = '''
# Changelog

## [Unreleased]

## [1.4.2] - 2026-11-01
- A fix.

## 1.4.10
''';

void main() {
  group('parsePubspecVersion', () {
    test('reads the name, version and build number', () {
      final v = parsePubspecVersion(_pubspec);
      expect(v.name, 'demo');
      expect(v.version, '1.4.2');
      expect(v.build, 31);
    });

    test('a version with no build number has a null build', () {
      final v = parsePubspecVersion('name: demo\nversion: 1.0.0\n');
      expect(v.version, '1.0.0');
      expect(v.build, isNull);
    });

    test('a pubspec with no version is a format error', () {
      expect(
        () => parsePubspecVersion('name: demo\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('findVersionConstants', () {
    test('finds a top-level and a static appVersion', () {
      final found = findVersionConstants({
        'lib/app_version.dart': "const appVersion = '1.4.2';",
        'lib/core/app_info.dart':
            "class AppInfo {\n  static const String appVersion = \"1.4.2\";\n}",
        'lib/other.dart': "const schemaVersion = 3;",
      });
      expect(found.map((c) => c.file), [
        'lib/app_version.dart',
        'lib/core/app_info.dart',
      ]);
      expect(found.every((c) => c.value == '1.4.2'), isTrue);
    });

    test('finds an appBuildNumber', () {
      final found = findVersionConstants({
        'lib/app_version.dart': 'const appBuildNumber = 31;',
      });
      expect(found.single.name, 'appBuildNumber');
      expect(found.single.value, '31');
    });

    test('ignores generated files', () {
      final found = findVersionConstants({
        'lib/a.g.dart': "const appVersion = '9.9.9';",
        'lib/b.freezed.dart': "const appVersion = '9.9.9';",
      });
      expect(found, isEmpty);
    });
  });

  group('changelogHasEntry', () {
    test('matches a bracketed heading', () {
      expect(changelogHasEntry(_changelog, '1.4.2'), isTrue);
    });

    test('matches a plain heading', () {
      expect(changelogHasEntry(_changelog, '1.4.10'), isTrue);
    });

    test('1.4.1 is not matched by 1.4.10 or 1.4.2', () {
      expect(changelogHasEntry(_changelog, '1.4.1'), isFalse);
    });

    test('a v prefix counts', () {
      expect(changelogHasEntry('## v2.0.0\n', '2.0.0'), isTrue);
    });

    test('a version in body text does not count', () {
      expect(changelogHasEntry('Moved to 2.0.0 later.\n', '2.0.0'), isFalse);
    });
  });

  group('acceptedFastlaneNames', () {
    test('the build number itself and the split-per-ABI codes', () {
      expect(acceptedFastlaneNames(31), [
        '31.txt',
        '1031.txt',
        '2031.txt',
        '4031.txt',
      ]);
    });
  });

  group('checkVersion', () {
    test('a consistent app passes', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: {'lib/app_version.dart': "const appVersion = '1.4.2';"},
        changelog: _changelog,
        fastlaneChangelogs: {
          'en-US': {'2030.txt', '2031.txt'},
        },
      );
      expect(r.failures, isEmpty);
      expect(r.ok, isTrue);
    });

    test('a constant that disagrees fails and names the file', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: {'lib/app_version.dart': "const appVersion = '1.4.1';"},
        changelog: _changelog,
        fastlaneChangelogs: null,
      );
      expect(r.ok, isFalse);
      expect(r.failures.single, contains('lib/app_version.dart'));
      expect(r.failures.single, contains('1.4.1'));
    });

    test('an appBuildNumber that disagrees fails', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: {'lib/v.dart': 'const appBuildNumber = 30;'},
        changelog: _changelog,
        fastlaneChangelogs: null,
      );
      expect(r.failures.single, contains('appBuildNumber'));
    });

    test('no version constant is a note, not a failure', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: const {},
        changelog: _changelog,
        fastlaneChangelogs: null,
      );
      expect(r.ok, isTrue);
      expect(r.notes.join('\n'), contains('no version constant'));
    });

    test('a missing build number fails', () {
      final r = checkVersion(
        pubspec: 'name: demo\nversion: 1.4.2\n',
        dartFiles: const {},
        changelog: _changelog,
        fastlaneChangelogs: null,
      );
      expect(r.failures.single, contains('build number'));
    });

    test('a missing CHANGELOG fails', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: const {},
        changelog: null,
        fastlaneChangelogs: null,
      );
      expect(r.failures.single, contains('CHANGELOG.md'));
    });

    test('a CHANGELOG with no entry for the version fails', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: const {},
        changelog: '## [Unreleased]\n',
        fastlaneChangelogs: null,
      );
      expect(r.failures.single, contains('no entry for 1.4.2'));
    });

    test('each locale without a changelog for the build fails', () {
      final r = checkVersion(
        pubspec: _pubspec,
        dartFiles: const {},
        changelog: _changelog,
        fastlaneChangelogs: {
          'en-US': {'2030.txt'},
          'de-DE': {'31.txt'},
        },
      );
      expect(r.failures.single, contains('en-US'));
      expect(r.failures.single, contains('2031.txt'));
    });
  });
}
