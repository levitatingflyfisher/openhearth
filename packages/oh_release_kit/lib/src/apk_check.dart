import 'dart:convert';

import 'check_result.dart';
import 'version_check.dart';

/// What `aapt2 dump badging` says about an APK.
class ApkBadging {
  final String packageName;
  final int versionCode;
  final String versionName;
  final List<String> nativeCodes;
  const ApkBadging(
    this.packageName,
    this.versionCode,
    this.versionName,
    this.nativeCodes,
  );
}

ApkBadging parseBadging(String out) {
  final pkg = RegExp(
    r"^package: name='([^']*)' versionCode='(\d+)' "
    r"versionName='([^']*)'",
    multiLine: true,
  ).firstMatch(out);
  if (pkg == null) {
    throw const FormatException('no package line in the aapt2 output');
  }
  final native = RegExp(
    r"^native-code:(.*)$",
    multiLine: true,
  ).firstMatch(out)?.group(1);
  return ApkBadging(
    pkg.group(1)!,
    int.parse(pkg.group(2)!),
    pkg.group(3)!,
    native == null
        ? const []
        : RegExp(
            r"'([^']*)'",
          ).allMatches(native).map((m) => m.group(1)!).toList(),
  );
}

/// The values `android/app/build.gradle(.kts)` sets. A null version means
/// the gradle file takes it from Flutter, that is from pubspec.yaml.
class GradleValues {
  final String? applicationId;
  final int? versionCode;
  final String? versionName;
  const GradleValues(this.applicationId, this.versionCode, this.versionName);
}

/// Reads both Kotlin script (`applicationId = "x"`) and Groovy
/// (`applicationId "x"`).
GradleValues parseGradle(String gradle) {
  String? str(String key) => RegExp(
    '\\b$key\\s*=?\\s*["\']([^"\']+)["\']',
  ).firstMatch(gradle)?.group(1);
  final code = RegExp(
    r'\bversionCode\s*=?\s*(\d+)\b',
  ).firstMatch(gradle)?.group(1);
  return GradleValues(
    str('applicationId'),
    code == null ? null : int.parse(code),
    str('versionName'),
  );
}

class ApkSigner {
  final String dn;
  final String? sha256;
  const ApkSigner(this.dn, this.sha256);

  /// Flutter's default: every fleet app still signs with it until the
  /// owner decides on a release key.
  bool get isDebugKey => dn.contains('CN=Android Debug');
}

/// Reads `apksigner verify --print-certs` output.
List<ApkSigner> parseSigners(String out) {
  final dns = <String, String>{};
  final digests = <String, String>{};
  for (final m in RegExp(
    r'^Signer #(\d+) certificate DN: (.*)$',
    multiLine: true,
  ).allMatches(out)) {
    dns[m.group(1)!] = m.group(2)!.trim();
  }
  for (final m in RegExp(
    r'^Signer #(\d+) certificate SHA-256 digest: (\S+)',
    multiLine: true,
  ).allMatches(out)) {
    digests[m.group(1)!] = m.group(2)!;
  }
  return [for (final k in dns.keys) ApkSigner(dns[k]!, digests[k])];
}

/// The newest build-tools folder name, compared as numbers so 34.0.10
/// beats 34.0.2. Names that are not versions are ignored.
String? pickBuildTools(List<String> names) {
  List<int>? parse(String n) {
    final parts = n.split('.').map(int.tryParse).toList();
    return parts.contains(null) ? null : parts.cast<int>();
  }

  int cmp(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  String? best;
  List<int>? bestV;
  for (final n in names) {
    final v = parse(n);
    if (v == null) continue;
    if (bestV == null || cmp(v, bestV) > 0) {
      best = n;
      bestV = v;
    }
  }
  return best;
}

/// Flutter's `--split-per-abi` adds 1000 times this number to the version
/// code of each ABI's APK.
const abiVersionCodes = {'armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 4};

/// Checks a built APK against the app's sources (release step 5).
/// [signers] is null when apksigner could not be found.
CheckResult checkApk({
  required ApkBadging badging,
  required String pubspec,
  required String gradle,
  required String sha256,
  required List<ApkSigner>? signers,
  required int apkBytes,
  required String? budgetsJson,
}) {
  final r = CheckResult();
  final v = parsePubspecVersion(pubspec);
  final g = parseGradle(gradle);

  if (g.applicationId == null) {
    r.failures.add('build.gradle: no applicationId');
  } else if (g.applicationId != badging.packageName) {
    r.failures.add(
      'package ${badging.packageName}, but build.gradle '
      'says applicationId ${g.applicationId}',
    );
  } else {
    r.passes.add('package ${badging.packageName}');
  }

  final build = v.build;
  if (g.versionCode != null && g.versionCode != build) {
    r.failures.add(
      'build.gradle hard-codes versionCode ${g.versionCode}, '
      'pubspec.yaml says $build',
    );
  }
  final base = g.versionCode ?? build;
  if (base == null) {
    r.failures.add('pubspec.yaml has no build number');
  } else {
    // One ABI means a split APK, whose code carries the ABI's offset.
    final accepted = {base};
    if (badging.nativeCodes.length == 1) {
      final abi = abiVersionCodes[badging.nativeCodes.single];
      if (abi != null) accepted.add(abi * 1000 + base);
    }
    if (accepted.contains(badging.versionCode)) {
      r.passes.add(
        'version code ${badging.versionCode} '
        '(build $base, ${badging.nativeCodes.join(' ')})',
      );
    } else {
      r.failures.add(
        'version code ${badging.versionCode}, expected '
        '${accepted.join(' or ')} for build $base '
        '(${badging.nativeCodes.join(' ')})',
      );
    }
  }

  if (g.versionName != null && g.versionName != v.version) {
    r.failures.add(
      'build.gradle hard-codes versionName ${g.versionName}, '
      'pubspec.yaml says ${v.version}',
    );
  }
  if (badging.versionName == v.version) {
    r.passes.add('version name ${badging.versionName}');
  } else {
    r.failures.add(
      'version name ${badging.versionName}, '
      'pubspec.yaml says ${v.version}',
    );
  }

  r.passes.add('sha256 $sha256');
  _checkApkBudget(r, badging, apkBytes, budgetsJson);

  if (signers == null) {
    r.notes.add('apksigner not found: signer not checked');
  } else if (signers.isEmpty) {
    r.failures.add('apksigner printed no signer');
  } else {
    for (final s in signers) {
      r.passes.add(
        'signer ${s.dn}'
        '${s.sha256 == null ? '' : ' (cert sha256 ${s.sha256})'}',
      );
      if (s.isDebugKey) {
        r.notes.add(
          'signed with the Android debug key '
          '(the fleet waits on a release key)',
        );
      }
    }
  }
  return r;
}

/// The budgets.json key for each split ABI's APK size. The fleet ships
/// arm64; the others are named the same way should an app budget them.
const _apkBudgetKeys = {
  'arm64-v8a': 'apk_arm64_max_bytes',
  'armeabi-v7a': 'apk_armv7_max_bytes',
  'x86_64': 'apk_x86_64_max_bytes',
};

void _checkApkBudget(
  CheckResult r,
  ApkBadging badging,
  int bytes,
  String? budgetsJson,
) {
  final key = badging.nativeCodes.length == 1
      ? _apkBudgetKeys[badging.nativeCodes.single]
      : null;
  Object? max;
  if (key != null && budgetsJson != null) {
    final doc = jsonDecode(budgetsJson);
    if (doc is Map) max = doc[key];
  }
  if (max is! int) {
    r.notes.add(
      'no APK budget${key == null ? '' : ' ($key in budgets.json)'}; '
      'the APK is $bytes bytes',
    );
  } else if (bytes > max) {
    r.failures.add(
      'the APK is $bytes bytes, ${bytes - max} over the '
      'budget of $max',
    );
  } else {
    r.passes.add('APK $bytes bytes, budget $max');
  }
}
