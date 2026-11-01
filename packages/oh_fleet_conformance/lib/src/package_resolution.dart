import 'dart:convert';
import 'dart:io';

/// The root folder of [package] as pub resolved it for the app at
/// [appRoot], read from the app's `.dart_tool/package_config.json` (or an
/// enclosing Dart Pub Workspace's `.dart_tool/package_config.json`).
///
/// Why pub and not a path like `../ohStyle/openhearth_design`: a fixed
/// sibling path holds only for a clone sitting directly beside ohStyle. A
/// worktree or a CI checkout has no such sibling, and the token checks then
/// failed in every app for a reason that had nothing to do with the app.
/// Pub already knows where the package is, from pubspec.yaml or from
/// pubspec_overrides.yaml, and writes it to package_config.json on every
/// `pub get` (which `flutter test` runs first).
///
/// Throws [StateError] with a plain reason when the package cannot be
/// resolved: the token checks must fail loudly then, never run against an
/// empty token set.
Directory resolvePackageRoot(Directory appRoot, String package) {
  final configFile = findPackageConfig(appRoot);
  if (configFile == null) {
    throw StateError(
      'cannot find $package: ${appRoot.absolute.path}/.dart_tool/package_config.json '
      'does not exist (and no parent workspace package_config.json was found); run '
      '`flutter pub get` so pub records where its packages are',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(configFile.readAsStringSync());
  } on FormatException catch (e) {
    throw StateError(
        'cannot find $package: ${configFile.path} is not valid JSON ($e)');
  }
  final packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! List) {
    throw StateError(
        'cannot find $package: ${configFile.path} has no "packages" list');
  }
  for (final entry in packages) {
    if (entry is! Map || entry['name'] != package) continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) {
      throw StateError(
          'cannot find $package: its entry in ${configFile.path} has no rootUri');
    }
    // A relative rootUri is relative to package_config.json itself, as the
    // package_config format specifies.
    final resolved = configFile.absolute.uri.resolve(rootUri);
    if (resolved.scheme != 'file') {
      throw StateError(
        'cannot find $package: ${configFile.path} places it at $resolved, '
        'which is not a folder on this machine',
      );
    }
    return Directory.fromUri(resolved.normalizePath());
  }
  throw StateError(
    'cannot find $package: ${configFile.path} does not list it; the app '
    'must depend on $package and have run `flutter pub get`',
  );
}

/// Walks up from [start] to find [relativePath], supporting both standalone
/// packages and Dart Pub Workspaces where shared files live at the workspace
/// root.
File? findUpwards(Directory start, String relativePath) {
  var dir = _normalizedDir(start);
  while (true) {
    final candidate = File('${dir.path}/$relativePath');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Nearest `.dart_tool/package_config.json` at or above [appRoot].
File? findPackageConfig(Directory appRoot) =>
    findUpwards(appRoot, '.dart_tool/package_config.json');

/// Nearest `pubspec.lock` at or above [appRoot].
File? findPubspecLock(Directory appRoot) =>
    findUpwards(appRoot, 'pubspec.lock');

/// Enclosing Dart Pub Workspace root `pubspec.yaml` when [appRoot] declares
/// `resolution: workspace`, or null for a standalone package.
File? findWorkspacePubspec(Directory appRoot) {
  final member = File('${_normalizedDir(appRoot).path}/pubspec.yaml');
  if (!member.existsSync()) return null;
  if (!_resolutionWorkspacePattern.hasMatch(member.readAsStringSync())) {
    return null;
  }
  var dir = _normalizedDir(appRoot).parent;
  while (true) {
    final candidate = File('${dir.path}/pubspec.yaml');
    if (candidate.existsSync() &&
        _workspaceKeyPattern.hasMatch(candidate.readAsStringSync())) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Directory _normalizedDir(Directory dir) {
  var path = Directory.fromUri(dir.absolute.uri.normalizePath()).path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Directory(path);
}

final _resolutionWorkspacePattern =
    RegExp(r'^resolution:\s*workspace\b', multiLine: true);
final _workspaceKeyPattern = RegExp(r'^workspace:\s*(?:#.*)?$', multiLine: true);
