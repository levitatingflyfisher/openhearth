// Structural purity: the domain layer is PURE DART (BUILD-SPEC module map:
// core logic has "NO Flutter imports anywhere"; house style: claims must be
// checkable in the architecture). This test greps the source so the claim
// can never silently rot.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final domainDir = Directory('lib/domain');

  List<File> dartFiles() => domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/domain exists and is non-trivial', () {
    expect(domainDir.existsSync(), isTrue);
    expect(dartFiles().length, greaterThanOrEqualTo(8));
  });

  test('no Flutter (or UI, or IO, or network) imports anywhere in domain',
      () {
    final banned = [
      RegExp("import\\s+'package:flutter"),
      RegExp("import\\s+'dart:ui"),
      RegExp("import\\s+'dart:io"),
      RegExp("import\\s+'dart:html"),
      RegExp("import\\s+'package:http"),
    ];
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      for (final pattern in banned) {
        expect(pattern.hasMatch(src), isFalse,
            reason: '${f.path} matches $pattern — domain must stay pure');
      }
    }
  });

  test('the only key-bearing crypto dependency is libsodium; package:crypto '
      'appears solely in the mnemonic checksum', () {
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      final usesPureDartCrypto =
          src.contains("import 'package:crypto/crypto.dart'");
      if (usesPureDartCrypto) {
        expect(f.path.replaceAll('\\', '/'), 'lib/domain/mnemonic.dart',
            reason: 'package:crypto is for the BIP39 checksum ONLY — '
                'all secret-bearing crypto must be libsodium');
      }
      expect(src.contains('package:pointycastle'), isFalse,
          reason: '${f.path}: no ad-hoc crypto libraries');
    }
  });
}
