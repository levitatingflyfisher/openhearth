import 'package:yaml/yaml.dart';

import 'check_result.dart';

/// The `version:` line of a pubspec, split into its two halves.
class PubspecVersion {
  final String name;
  final String version;

  /// Null when the pubspec has no `+build` part. Android needs one.
  final int? build;

  const PubspecVersion(this.name, this.version, this.build);
}

PubspecVersion parsePubspecVersion(String pubspecYaml) {
  final doc = loadYaml(pubspecYaml);
  if (doc is! YamlMap) throw const FormatException('pubspec is not a map');
  final name = doc['name']?.toString() ?? '';
  final raw = doc['version']?.toString();
  if (raw == null) throw const FormatException('pubspec has no version');
  final plus = raw.indexOf('+');
  if (plus < 0) return PubspecVersion(name, raw, null);
  final build = int.tryParse(raw.substring(plus + 1));
  if (build == null) {
    throw FormatException('build number is not a whole number: $raw');
  }
  return PubspecVersion(name, raw.substring(0, plus), build);
}

/// A version constant found in the app's source.
class VersionConstant {
  final String file;
  final String name;
  final String value;
  const VersionConstant(this.file, this.name, this.value);
}

// The documented rule: a `const appVersion` holding a string literal, at top
// level or `static` in a class, and optionally a `const appBuildNumber`
// holding an integer. These are the names the fleet already uses (a const
// rather than package_info_plus, so it exists before any platform call).
final _appVersion = RegExp(
  r'''\bconst\s+(?:String\s+)?(appVersion)\s*=\s*['"]([^'"]+)['"]''',
);
final _appBuild = RegExp(
  r'\bconst\s+(?:int\s+)?(appBuildNumber)\s*=\s*(\d+)\b',
);

/// Finds every version constant in [dartFiles] (path to text). Generated
/// files are skipped: they repeat what their source says.
List<VersionConstant> findVersionConstants(Map<String, String> dartFiles) {
  final found = <VersionConstant>[];
  final paths = dartFiles.keys.toList()..sort();
  for (final path in paths) {
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
    final text = dartFiles[path]!;
    for (final re in [_appVersion, _appBuild]) {
      for (final m in re.allMatches(text)) {
        found.add(VersionConstant(path, m.group(1)!, m.group(2)!));
      }
    }
  }
  return found;
}

/// True when [changelog] has a heading for [version]: `## 1.2.3`,
/// `## [1.2.3]` or `## v1.2.3`, with anything after it that is not part of
/// a longer version (so 1.2.1 is not found under 1.2.10).
bool changelogHasEntry(String changelog, String version) {
  final v = RegExp.escape(version);
  return RegExp(
    '^#{1,3} +\\[?v?$v(?![\\w.+-])',
    multiLine: true,
  ).hasMatch(changelog);
}

/// The fastlane changelog names that belong to [build]. Flutter's
/// `--split-per-abi` makes each APK's version code 1000 times the ABI's
/// number plus the build (armeabi-v7a 1, arm64-v8a 2, x86_64 4), and the
/// store reads the changelog named for the version code it received.
List<String> acceptedFastlaneNames(int build) => [
  build,
  1000 + build,
  2000 + build,
  4000 + build,
].map((c) => '$c.txt').toList();

/// Checks that the version and build number agree everywhere the release
/// habits say they must (rule 1).
///
/// [dartFiles] maps paths under `lib/` to their text. [changelog] is null
/// when the app has no CHANGELOG.md. [fastlaneChangelogs] maps each locale
/// to the file names in its `changelogs/` folder, and is null when the app
/// has no fastlane changelogs at all.
CheckResult checkVersion({
  required String pubspec,
  required Map<String, String> dartFiles,
  required String? changelog,
  required Map<String, Set<String>>? fastlaneChangelogs,
}) {
  final r = CheckResult();
  final PubspecVersion v;
  try {
    v = parsePubspecVersion(pubspec);
  } on FormatException catch (e) {
    r.failures.add('pubspec.yaml: ${e.message}');
    return r;
  }
  final build = v.build;
  if (build == null) {
    r.failures.add(
      'pubspec.yaml: version ${v.version} has no build number '
      '(write it as ${v.version}+N)',
    );
  } else {
    r.passes.add('pubspec.yaml: ${v.name} ${v.version}+$build');
  }

  final constants = findVersionConstants(dartFiles);
  if (constants.isEmpty) {
    r.notes.add(
      'no version constant in lib/ '
      "(the rule: const appVersion = '${v.version}')",
    );
  }
  for (final c in constants) {
    final want = c.name == 'appVersion' ? v.version : '$build';
    if (c.value == want) {
      r.passes.add('${c.file}: ${c.name} ${c.value}');
    } else {
      r.failures.add(
        '${c.file}: ${c.name} is ${c.value}, '
        'pubspec.yaml says $want',
      );
    }
  }

  if (changelog == null) {
    r.failures.add('no CHANGELOG.md');
  } else if (changelogHasEntry(changelog, v.version)) {
    r.passes.add('CHANGELOG.md: entry for ${v.version}');
  } else {
    r.failures.add(
      'CHANGELOG.md: no entry for ${v.version} '
      '(a heading like "## [${v.version}]")',
    );
  }

  if (fastlaneChangelogs != null && build != null) {
    final names = acceptedFastlaneNames(build);
    final locales = fastlaneChangelogs.keys.toList()..sort();
    for (final locale in locales) {
      final have = fastlaneChangelogs[locale]!;
      final match = names.where(have.contains).toList();
      if (match.isEmpty) {
        r.failures.add(
          'fastlane $locale: no changelog for build $build '
          '(expected one of ${names.join(', ')})',
        );
      } else {
        r.passes.add('fastlane $locale: ${match.join(', ')}');
      }
    }
  }
  return r;
}
