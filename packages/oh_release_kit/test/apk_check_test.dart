import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:test/test.dart';

// Canned `aapt2 dump badging` output, trimmed to the lines the check reads
// plus a few it must skip.
const _badging = '''
package: name='com.openhearth.demo' versionCode='2031' versionName='1.4.2' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
application-label:'Demo'
native-code: 'arm64-v8a'
''';

const _signer = '''
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
Signer #1 certificate SHA-256 digest: 36b3418800239896
Signer #1 certificate SHA-1 digest: 37a1e55d7ca516bc
''';

const _pubspec = 'name: demo\nversion: 1.4.2+31\n';
const _gradleKts = '''
android {
    namespace = "com.openhearth.demo"
    defaultConfig {
        applicationId = "com.openhearth.demo"
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
''';

CheckResult _check({
  String badging = _badging,
  String pubspec = _pubspec,
  String gradle = _gradleKts,
  String? signer = _signer,
  int apkBytes = 900,
  String? budgets = '{"apk_arm64_max_bytes": 1000}',
}) => checkApk(
  apkBytes: apkBytes,
  budgetsJson: budgets,
  badging: parseBadging(badging),
  pubspec: pubspec,
  gradle: gradle,
  sha256: 'ab' * 32,
  signers: signer == null ? null : parseSigners(signer),
);

void main() {
  group('parseBadging', () {
    test('reads the package line and the native code', () {
      final b = parseBadging(_badging);
      expect(b.packageName, 'com.openhearth.demo');
      expect(b.versionCode, 2031);
      expect(b.versionName, '1.4.2');
      expect(b.nativeCodes, ['arm64-v8a']);
    });

    test('a fat APK lists several ABIs', () {
      final b = parseBadging(
        "package: name='a' versionCode='3' versionName='1'\n"
        "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'\n",
      );
      expect(b.nativeCodes, ['arm64-v8a', 'armeabi-v7a', 'x86_64']);
    });

    test('no package line is a format error', () {
      expect(() => parseBadging('nothing'), throwsA(isA<FormatException>()));
    });
  });

  group('parseGradle', () {
    test('Kotlin script', () {
      final g = parseGradle(_gradleKts);
      expect(g.applicationId, 'com.openhearth.demo');
      expect(g.versionCode, isNull, reason: 'taken from Flutter');
      expect(g.versionName, isNull);
    });

    test('Groovy with literal values', () {
      final g = parseGradle('''
        defaultConfig {
            applicationId "com.openhearth.old"
            versionCode 7
            versionName "0.9.0"
        }''');
      expect(g.applicationId, 'com.openhearth.old');
      expect(g.versionCode, 7);
      expect(g.versionName, '0.9.0');
    });
  });

  test('parseSigners reads each signer DN and digest', () {
    final s = parseSigners(_signer);
    expect(s.single.dn, 'C=US, O=Android, CN=Android Debug');
    expect(s.single.sha256, '36b3418800239896');
    expect(s.single.isDebugKey, isTrue);
  });

  test('pickBuildTools takes the highest version, by number', () {
    expect(pickBuildTools(['9.0.0', '35.0.0', '34.0.0', 'notes']), '35.0.0');
    expect(pickBuildTools(['34.0.0', '34.0.10', '34.0.2']), '34.0.10');
    expect(pickBuildTools([]), isNull);
  });

  group('checkApk', () {
    test('a split arm64 APK of the right build passes and prints sha256', () {
      final r = _check();
      expect(r.failures, isEmpty);
      final all = r.passes.join('\n');
      expect(all, contains('sha256 ${'ab' * 32}'));
      expect(all, contains('version code 2031'));
    });

    test('the plain build number passes too (no ABI split)', () {
      final r = _check(badging: _badging.replaceAll("'2031'", "'31'"));
      expect(r.failures, isEmpty);
    });

    test('a version code from another build fails', () {
      final r = _check(badging: _badging.replaceAll("'2031'", "'2030'"));
      expect(r.failures.single, contains('2030'));
    });

    test('the arm64 code on an x86_64 APK fails', () {
      final r = _check(badging: _badging.replaceAll("'arm64-v8a'", "'x86_64'"));
      expect(r.failures.single, contains('version code'));
    });

    test('a version name that differs fails', () {
      final r = _check(pubspec: 'name: demo\nversion: 1.4.3+31\n');
      expect(r.failures.single, contains('version name'));
    });

    test('a package name that differs from applicationId fails', () {
      final r = _check(
        gradle: _gradleKts.replaceAll(
          'applicationId = "com.openhearth.demo"',
          'applicationId = "com.openhearth.other"',
        ),
      );
      expect(r.failures.single, contains('com.openhearth.other'));
    });

    test('a literal gradle versionCode that disagrees with pubspec fails', () {
      final r = _check(
        gradle: _gradleKts.replaceAll('flutter.versionCode', '30'),
      );
      expect(r.failures.join('\n'), contains('build.gradle'));
    });

    test('the debug key is a note, not a failure', () {
      final r = _check();
      expect(r.notes.join('\n'), contains('debug key'));
      expect(r.passes.join('\n'), contains('signer C=US, O=Android'));
    });

    test('an arm64 APK over its budget fails', () {
      expect(_check(apkBytes: 1001).failures.single, contains('over'));
    });

    test('within budget passes and says so', () {
      expect(_check().passes.join('\n'), contains('900 bytes, budget 1000'));
    });

    test('no APK budget is a note', () {
      expect(_check(budgets: null).notes.join('\n'), contains('no APK budget'));
    });

    test('no apksigner is a note', () {
      expect(_check(signer: null).notes.join('\n'), contains('apksigner'));
    });
  });
}
