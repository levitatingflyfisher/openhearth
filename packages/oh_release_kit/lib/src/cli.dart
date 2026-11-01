import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'apk_check.dart';
import 'check_result.dart';
import 'export.dart';
import 'leakscan.dart';
import 'shared_versions.dart';
import 'version_check.dart';
import 'web_check.dart';

const usage = '''
usage: dart run oh_release_kit:release <command> ...

  version <app>                       version and build agree everywhere
  shared-versions <app>               path packages, for the release ledger
  leakscan <diff> [--private <file>] [--all-lines]
                                      nothing private in what the diff adds
  web-check <app> <built web folder> [--base-href </App/>]
                                      the PWA is ready to publish
  apk-check <apk> <app> [--build-tools <dir>]
                                      the APK matches the app's sources
  export <repo> <commit> <dest>       clean git archive into a new folder

Exit 0: every check passed. 1: a check failed. 2: the command could not run.''';

/// A problem that stops a command before it can check anything: a missing
/// file, a bad argument. Exit 2, so it is never read as a pass or a fail.
class _Stop implements Exception {
  final String message;
  _Stop(this.message);
}

/// Runs one command and returns its exit code. The commands only read
/// files and print; every rule lives in the pure checks.
Future<int> runRelease(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? env,
}) async {
  final o = out ?? stdout;
  final e = err ?? stderr;
  final environment = env ?? Platform.environment;
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    o.writeln(usage);
    return args.isEmpty ? 2 : 0;
  }
  try {
    final (pos, opts, flags) = _split(args.skip(1).toList());
    switch (args.first) {
      case 'version':
        return _report(o, _version(_one(pos, 'version <app>')));
      case 'shared-versions':
        o.writeln(await _shared(_one(pos, 'shared-versions <app>')));
        return 0;
      case 'leakscan':
        return _leakscan(
          o,
          _one(pos, 'leakscan <diff>'),
          opts['--private'],
          flags.contains('--all-lines'),
        );
      case 'web-check':
        _need(pos, 2, 'web-check <app> <built web folder>');
        return _report(o, _webCheck(pos[0], pos[1], opts['--base-href']));
      case 'apk-check':
        _need(pos, 2, 'apk-check <apk> <app>');
        return _report(
          o,
          await _apkCheck(pos[0], pos[1], opts['--build-tools'], environment),
        );
      case 'export':
        _need(pos, 3, 'export <repo> <commit> <dest>');
        final sha = await exportCommit(pos[0], pos[1], pos[2]);
        o.writeln('exported $sha into ${p.absolute(pos[2])}');
        return 0;
      default:
        e.writeln('unknown command: ${args.first}\n\n$usage');
        return 2;
    }
  } on _Stop catch (s) {
    e.writeln(s.message);
    return 2;
  } on ExportException catch (x) {
    e.writeln(x.message);
    return 2;
  } on FormatException catch (x) {
    e.writeln(x.message);
    return 2;
  }
}

const _valueOptions = {'--private', '--base-href', '--build-tools'};
const _flagOptions = {'--all-lines'};

(List<String>, Map<String, String>, Set<String>) _split(List<String> args) {
  final pos = <String>[];
  final opts = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (_valueOptions.contains(a)) {
      if (i + 1 >= args.length) throw _Stop('$a needs a value');
      opts[a] = args[++i];
    } else if (_flagOptions.contains(a)) {
      flags.add(a);
    } else if (a.startsWith('--')) {
      throw _Stop('unknown option: $a');
    } else {
      pos.add(a);
    }
  }
  return (pos, opts, flags);
}

void _need(List<String> pos, int n, String form) {
  if (pos.length != n) throw _Stop('usage: $form');
}

String _one(List<String> pos, String form) {
  _need(pos, 1, form);
  return pos.single;
}

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) throw _Stop('no such file: $path');
  return f.readAsStringSync();
}

String? _readIfAny(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : null;
}

int _report(StringSink o, CheckResult r) {
  o.writeln(r.render());
  o.writeln(r.ok ? 'PASSED' : 'FAILED: ${r.failures.length}');
  return r.ok ? 0 : 1;
}

CheckResult _version(String app) {
  final pubspec = _read(p.join(app, 'pubspec.yaml'));
  final dart = <String, String>{};
  final lib = Directory(p.join(app, 'lib'));
  if (lib.existsSync()) {
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart')) {
        dart[p.relative(f.path, from: app)] = f.readAsStringSync();
      }
    }
  }
  Map<String, Set<String>>? fastlane;
  final meta = Directory(p.join(app, 'fastlane', 'metadata', 'android'));
  if (meta.existsSync()) {
    for (final locale in meta.listSync().whereType<Directory>()) {
      final logs = Directory(p.join(locale.path, 'changelogs'));
      if (!logs.existsSync()) continue;
      (fastlane ??= {})[p.basename(locale.path)] = {
        for (final f in logs.listSync().whereType<File>()) p.basename(f.path),
      };
    }
  }
  return checkVersion(
    pubspec: pubspec,
    dartFiles: dart,
    changelog: _readIfAny(p.join(app, 'CHANGELOG.md')),
    fastlaneChangelogs: fastlane,
  );
}

Future<String> _shared(String app) async {
  final appAbs = p.normalize(p.absolute(app));
  final appPubspecText = _read(p.join(appAbs, 'pubspec.yaml'));
  final v = parsePubspecVersion(appPubspecText);
  final lockFile = _findUpwards(appAbs, 'pubspec.lock');
  if (lockFile == null) {
    throw _Stop('no such file: ${p.join(app, 'pubspec.lock')}');
  }
  final lockBase = p.normalize(lockFile.parent.path);
  final isWorkspace = lockBase != appAbs;
  final lockPathPackages = <String, PathPackage>{
    for (final pkg in parsePathPackages(lockFile.readAsStringSync()))
      pkg.name: PathPackage(
        pkg.name,
        pkg.version,
        p.relative(p.normalize(p.join(lockBase, pkg.path)), from: appAbs),
        pkg.dependency,
      ),
  };

  final pkgsByName = <String, PathPackage>{};
  if (!isWorkspace) {
    pkgsByName.addAll(lockPathPackages);
  } else {
    // In a Dart Pub Workspace, root `pubspec.lock` mixes path packages from
    // every workspace member, while omitting workspace members themselves.
    // Walk the app's dependency graph (direct + transitive) against
    // `package_config.json` and root `pubspec.lock` so only path/workspace
    // packages actually used by this app appear in its ledger.
    final configFile =
        _findUpwards(appAbs, p.join('.dart_tool', 'package_config.json'));
    final localPkgDirs = <String, String>{};
    if (configFile != null) {
      final decoded = jsonDecode(configFile.readAsStringSync());
      final pkgList = decoded is Map ? decoded['packages'] : null;
      if (pkgList is List) {
        for (final entry in pkgList) {
          if (entry is! Map) continue;
          final name = entry['name'];
          final rootUri = entry['rootUri'];
          if (name is! String || rootUri is! String) continue;
          final resolved = configFile.absolute.uri.resolve(rootUri);
          if (resolved.scheme != 'file') continue;
          final pkgDir =
              p.normalize(Directory.fromUri(resolved.normalizePath()).path);
          final isLocal = !rootUri.startsWith('file:') ||
              p.isWithin(lockBase, pkgDir);
          if (isLocal) {
            localPkgDirs[name] = pkgDir;
          }
        }
      }
    }

    final visited = <String>{v.name};
    final queue = <(String, String)>[];

    void enqueueFromPubspec(String pubspecYaml, {required bool includeDev}) {
      final doc = loadYaml(pubspecYaml);
      if (doc is! YamlMap) return;
      final sections = includeDev
          ? const ['dependencies', 'dev_dependencies']
          : const ['dependencies'];
      for (final section in sections) {
        final deps = doc[section];
        if (deps is! YamlMap) continue;
        for (final entry in deps.entries) {
          final depName = entry.key.toString();
          if (visited.contains(depName)) continue;
          final depKind = !includeDev
              ? 'transitive'
              : (section == 'dependencies' ? 'direct main' : 'direct dev');
          queue.add((depName, depKind));
        }
      }
    }

    enqueueFromPubspec(appPubspecText, includeDev: true);
    while (queue.isNotEmpty) {
      final (depName, depKind) = queue.removeAt(0);
      if (!visited.add(depName)) continue;

      final lockPkg = lockPathPackages[depName];
      final localDir = localPkgDirs[depName];
      if (lockPkg != null) {
        pkgsByName[depName] = PathPackage(
          lockPkg.name,
          lockPkg.version,
          lockPkg.path,
          depKind,
        );
        final dir = p.normalize(p.join(appAbs, lockPkg.path));
        final depPubspec = _readIfAny(p.join(dir, 'pubspec.yaml'));
        if (depPubspec != null) {
          enqueueFromPubspec(depPubspec, includeDev: false);
        }
      } else if (localDir != null) {
        final depPubspec = _readIfAny(p.join(localDir, 'pubspec.yaml'));
        final depVer = depPubspec == null
            ? '?'
            : parsePubspecVersion(depPubspec).version;
        pkgsByName[depName] = PathPackage(
          depName,
          depVer,
          p.relative(localDir, from: appAbs),
          depKind,
        );
        if (depPubspec != null) {
          enqueueFromPubspec(depPubspec, includeDev: false);
        }
      }
    }
  }

  final pkgs = pkgsByName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final commits = <String, String>{};
  for (final pkg in pkgs) {
    final dir = p.normalize(p.join(appAbs, pkg.path));
    if (!Directory(dir).existsSync()) continue;
    final rev = await Process.run('git', [
      '-C',
      dir,
      'rev-parse',
      '--short',
      'HEAD',
    ]);
    if (rev.exitCode != 0) continue;
    // Uncommitted changes in the package folder mean the commit alone does
    // not say what the app was tested with.
    final st = await Process.run('git', [
      '-C',
      dir,
      'status',
      '--porcelain',
      '--untracked-files=no',
      '--',
      '.',
    ]);
    final dirty = (st.stdout as String).trim().isNotEmpty;
    commits[pkg.name] =
        '${(rev.stdout as String).trim()}${dirty ? ' +uncommitted changes' : ''}';
  }
  return renderSharedVersions(
    app: '${v.name} ${v.version}${v.build == null ? '' : '+${v.build}'}',
    packages: pkgs,
    commits: commits,
  );
}

File? _findUpwards(String startDir, String relativePath) {
  var dir = Directory(startDir).absolute;
  while (true) {
    final candidate = File(p.join(dir.path, relativePath));
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

int _leakscan(StringSink o, String diffPath, String? privatePath, bool all) {
  final diff = _read(diffPath);
  // `git diff a..b > file` leaves an empty file when git fails, and the
  // shell's exit code is lost by the time this runs. Nothing scanned is
  // not clean.
  if (diff.trim().isEmpty) {
    throw _Stop(
      '$diffPath is empty: nothing to scan. '
      'Check that the git diff that wrote it succeeded.',
    );
  }
  final rules = [...publicLeakRules];
  if (privatePath != null) {
    // A named patterns file that cannot be read stops the scan: scanning
    // without it would report clean while the private words go unchecked.
    rules.addAll(parsePrivatePatterns(_read(privatePath)));
  }
  final lines = addedLines(diff, allLines: all);
  final hits = scanLines(lines, rules);
  o.writeln(renderLeakReport(lines, rules, hits));
  if (privatePath == null) {
    o.writeln('note  no --private file: private words not checked');
  }
  return hits.isEmpty ? 0 : 1;
}

const _textExtensions = {
  '.js',
  '.mjs',
  '.html',
  '.json',
  '.css',
  '.webmanifest',
};

CheckResult _webCheck(String app, String web, String? baseHref) {
  final root = Directory(web);
  if (!root.existsSync()) throw _Stop('no such folder: $web');
  final files = <String>{};
  final text = <String, String>{};
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(f.path, from: web);
    files.add(rel);
    if (_textExtensions.contains(p.extension(f.path))) {
      text[rel] = f.readAsStringSync();
    }
  }
  final main = File(p.join(web, 'main.dart.js'));
  return checkWebBuild(
    indexHtml: _readIfAny(p.join(web, 'index.html')),
    manifestJson: _readIfAny(p.join(web, 'manifest.json')),
    bootstrapJs: _readIfAny(p.join(web, 'flutter_bootstrap.js')),
    fontManifestJson: _readIfAny(p.join(web, 'assets', 'FontManifest.json')),
    budgetsJson: _readIfAny(p.join(app, 'budgets.json')),
    mainJsGzipBytes: main.existsSync()
        ? gzipSize(main.readAsBytesSync())
        : null,
    files: files,
    textFiles: text,
    expectedBaseHref: baseHref,
  );
}

/// The build-tools folder: the one named, or the newest under the SDK that
/// ANDROID_HOME (or ANDROID_SDK_ROOT) points at.
String _buildTools(String? given, Map<String, String> env) {
  if (given != null) return given;
  final sdk = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  if (sdk == null) {
    throw _Stop(
      'aapt2 not found: pass --build-tools <dir> or set ANDROID_HOME',
    );
  }
  final bt = Directory(p.join(sdk, 'build-tools'));
  final newest = bt.existsSync()
      ? pickBuildTools(
          bt
              .listSync()
              .whereType<Directory>()
              .map((d) => p.basename(d.path))
              .toList(),
        )
      : null;
  if (newest == null) throw _Stop('aapt2 not found: no build-tools under $sdk');
  return p.join(bt.path, newest);
}

Future<CheckResult> _apkCheck(
  String apk,
  String app,
  String? buildTools,
  Map<String, String> env,
) async {
  if (!File(apk).existsSync()) throw _Stop('no such file: $apk');
  final pubspec = _read(p.join(app, 'pubspec.yaml'));
  final dir = _buildTools(buildTools, env);
  final aapt2 = p.join(dir, 'aapt2');
  if (!File(aapt2).existsSync()) throw _Stop('aapt2 not found at $aapt2');
  final gradle =
      _readIfAny(p.join(app, 'android', 'app', 'build.gradle.kts')) ??
      _readIfAny(p.join(app, 'android', 'app', 'build.gradle'));
  if (gradle == null) throw _Stop('no android/app/build.gradle(.kts) in $app');

  final badging = await Process.run(aapt2, ['dump', 'badging', apk]);
  if (badging.exitCode != 0) {
    throw _Stop('aapt2 dump badging failed: ${badging.stderr}');
  }
  final sum = await Process.run('sha256sum', [apk]);
  if (sum.exitCode != 0) throw _Stop('sha256sum failed: ${sum.stderr}');

  List<ApkSigner>? signers;
  String? signerFailure;
  final apksigner = p.join(dir, 'apksigner');
  if (File(apksigner).existsSync()) {
    final v = await Process.run(apksigner, ['verify', '--print-certs', apk]);
    if (v.exitCode == 0) {
      signers = parseSigners(v.stdout as String);
    } else {
      signers = const [];
      signerFailure =
          'apksigner verify failed: ${'${v.stdout}${v.stderr}'.trim()}';
    }
  }
  final r = checkApk(
    badging: parseBadging(badging.stdout as String),
    pubspec: pubspec,
    gradle: gradle,
    sha256: (sum.stdout as String).split(RegExp(r'\s')).first,
    signers: signers,
    apkBytes: File(apk).lengthSync(),
    budgetsJson: _readIfAny(p.join(app, 'budgets.json')),
  );
  if (signerFailure != null) {
    r.failures
      ..remove('apksigner printed no signer')
      ..add(signerFailure);
  }
  return r;
}
