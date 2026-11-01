import 'package:yaml/yaml.dart';

/// A package the app takes by path: one of the fleet's shared libraries
/// (oh_fleet_conformance, sanctuary_*, openhearth_*, the ranking engine,
/// domovoi) or any other local package.
class PathPackage {
  final String name;
  final String version;
  final String path;
  final String dependency;
  const PathPackage(this.name, this.version, this.path, this.dependency);
}

/// Reads every `source: path` package from a pubspec.lock. Every path
/// package is listed, not a fixed set of names: a shared library added
/// later must show up in the ledger without a change here (rule 11).
List<PathPackage> parsePathPackages(String lockYaml) {
  final doc = loadYaml(lockYaml);
  final pkgs = doc is YamlMap ? doc['packages'] : null;
  if (pkgs is! YamlMap) return const [];
  final out = <PathPackage>[];
  for (final entry in pkgs.entries) {
    final v = entry.value;
    if (v is! YamlMap || v['source'] != 'path') continue;
    final desc = v['description'];
    out.add(
      PathPackage(
        entry.key.toString(),
        v['version']?.toString() ?? '?',
        desc is YamlMap ? desc['path']?.toString() ?? '?' : '?',
        v['dependency']?.toString() ?? '?',
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// The text block for the release ledger. [commits] maps a package name to
/// the commit its folder was at, when that could be read: a shared library
/// can change without a version bump, and the commit pins what was tested.
String renderSharedVersions({
  required String app,
  required List<PathPackage> packages,
  Map<String, String> commits = const {},
}) {
  final lines = <String>['Shared packages tested with $app (pubspec.lock):'];
  if (packages.isEmpty) lines.add('  (no path packages)');
  for (final p in packages) {
    final commit = commits[p.name];
    lines.add(
      '  ${p.name}  ${p.version}  ${p.path}'
      '${commit == null ? '' : '  commit $commit'}',
    );
  }
  return lines.join('\n');
}
