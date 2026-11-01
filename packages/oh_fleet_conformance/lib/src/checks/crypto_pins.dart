import 'dart:io';

import '../findings.dart';
import '../package_resolution.dart';

const _check = 'C15-cryptoPins';

/// The packages C15 treats as cryptographic: they do the cryptography
/// (ciphers, hashes, key derivation, recovery phrases). Key storage such as
/// `flutter_secure_storage` holds keys but computes nothing, so it is not
/// on the list.
const kCryptoPackages = {
  'bip39',
  'bip39_mnemonic',
  'crypto',
  'cryptography',
  'cryptography_flutter',
  'encrypt',
  'hashlib',
  'pointycastle',
  'sodium',
  'sodium_libs',
  'webcrypto',
};

final _exact = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-+]+)?$');
final _entry = RegExp(r'^  ([A-Za-z0-9_]+):\s*(.*)$');
final _version = RegExp(r'^    version:\s*(.*)$');

/// C15: every cryptographic dependency in `pubspec.yaml` is pinned to an
/// exact version from pub (`2.9.0`, never `^2.9.0` or a range), in
/// `dependencies:` and `dependency_overrides:`. In a Dart Pub Workspace,
/// `dependency_overrides:` at the enclosing workspace root `pubspec.yaml` is
/// checked too, and when a `pubspec.lock` exists at the app root or parent
/// workspace root, every pinned crypto dependency must match its locked
/// hosted version. A new release then cannot reach a backup key or a recovery
/// phrase without a deliberate change and its tests. `dev_dependencies:`
/// never ship and are not checked.
///
/// A crypto package from git or a path is a finding: it has no version to
/// pin. No `pubspec.yaml` is a finding: nothing read is not nothing wrong.
List<ConformanceFinding> checkCryptoPins({required Directory root}) {
  final file = File('${root.path}/pubspec.yaml');
  if (!file.existsSync()) {
    return const [
      ConformanceFinding(_check,
          'no pubspec.yaml at the app root, so no dependency was checked'),
    ];
  }

  final findings = <ConformanceFinding>[];
  final pinned = <String, String>{};
  _scanPubspec(
    file: file,
    label: 'pubspec.yaml',
    sections: const {'dependencies:', 'dependency_overrides:'},
    findings: findings,
    pinnedOut: pinned,
  );

  // In a Dart Pub Workspace, dependency_overrides live in the workspace root
  // pubspec.yaml rather than member pubspecs.
  final workspacePubspec = findWorkspacePubspec(root);
  if (workspacePubspec != null) {
    _scanPubspec(
      file: workspacePubspec,
      label: 'workspace pubspec.yaml',
      sections: const {'dependency_overrides:'},
      findings: findings,
      pinnedOut: pinned,
    );
  }

  // If a pubspec.lock exists (local or walked up to workspace root), verify
  // that every exact-pinned crypto package is locked to that exact hosted
  // version.
  if (pinned.isNotEmpty) {
    final lock = findPubspecLock(root);
    if (lock != null) {
      final locked = _parseLockedPackages(lock.readAsStringSync());
      for (final entry in pinned.entries) {
        final pkgLock = locked[entry.key];
        if (pkgLock == null) continue;
        if (pkgLock.source != null && pkgLock.source != 'hosted') {
          findings.add(ConformanceFinding(
            _check,
            'pubspec.lock resolves ${entry.key} from source '
            '"${pkgLock.source}" instead of hosted pub version ${entry.value}',
          ));
        } else if (pkgLock.version != null && pkgLock.version != entry.value) {
          findings.add(ConformanceFinding(
            _check,
            'pubspec.lock locks ${entry.key} at ${pkgLock.version} instead of '
            'pinned version ${entry.value}',
          ));
        }
      }
    }
  }

  return findings;
}

void _scanPubspec({
  required File file,
  required String label,
  required Set<String> sections,
  required List<ConformanceFinding> findings,
  required Map<String, String> pinnedOut,
}) {
  final lines = file.readAsLinesSync();
  String? section;
  for (var i = 0; i < lines.length; i++) {
    final line = _withoutComment(lines[i]);
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      section = line.trim();
      continue;
    }
    if (!sections.contains(section)) continue;
    final m = _entry.firstMatch(line);
    if (m == null || !kCryptoPackages.contains(m.group(1))) continue;

    final name = m.group(1)!;
    var constraint = _unquoted(m.group(2)!);
    if (constraint.isEmpty) {
      // Map form: read the entry's own deeper lines for `version:`.
      for (var j = i + 1; j < lines.length; j++) {
        final inner = _withoutComment(lines[j]);
        if (inner.trim().isEmpty) continue;
        if (!inner.startsWith('    ')) break;
        final v = _version.firstMatch(inner);
        if (v != null) constraint = _unquoted(v.group(1)!);
      }
    }
    if (_exact.hasMatch(constraint)) {
      pinnedOut[name] = constraint;
      continue;
    }

    final shown = constraint.isEmpty ? 'no version (git, path or sdk)' : constraint;
    findings.add(ConformanceFinding(
      _check,
      '$label:${i + 1} $name is $shown. Cryptographic dependencies '
      'are pinned to one exact version from pub, for example '
      '"$name: 1.2.3"',
    ));
  }
}

class _LockedPackage {
  final String? source;
  final String? version;
  const _LockedPackage({this.source, this.version});
}

Map<String, _LockedPackage> _parseLockedPackages(String lockYaml) {
  final lines = lockYaml.split('\n');
  final out = <String, _LockedPackage>{};
  var inPackages = false;
  String? current;
  int? currentIndent;
  String? source;
  String? version;

  void flush() {
    if (current != null) {
      out[current!] = _LockedPackage(source: source, version: version);
    }
    current = null;
    currentIndent = null;
    source = null;
    version = null;
  }

  for (final raw in lines) {
    final line = _withoutComment(raw);
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      flush();
      inPackages = line.trim() == 'packages:';
      continue;
    }
    if (!inPackages) continue;
    final trimmed = line.trim();
    if (current != null && indent <= currentIndent!) {
      flush();
    }
    if (current == null) {
      final header = RegExp(r'^([A-Za-z0-9_]+):$').firstMatch(trimmed);
      if (header != null) {
        current = header.group(1);
        currentIndent = indent;
      }
      continue;
    }
    final src = RegExp(r'^source:\s*(.+)$').firstMatch(trimmed);
    if (src != null) source = _unquoted(src.group(1)!);
    final ver = RegExp(r'^version:\s*(.+)$').firstMatch(trimmed);
    if (ver != null) version = _unquoted(ver.group(1)!);
  }
  flush();
  return out;
}

String _withoutComment(String line) {
  final hash = line.indexOf(' #');
  final cut = line.trimLeft().startsWith('#')
      ? ''
      : (hash < 0 ? line : line.substring(0, hash));
  return cut.trimRight();
}

String _unquoted(String value) {
  final v = value.trim();
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    return v.substring(1, v.length - 1);
  }
  return v;
}
