import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fleet's rule: cryptographic dependencies are pinned to exact
/// versions (`2.9.0`, never `^2.9.0`), so a new release cannot slip into a
/// backup or a recovery key without a deliberate change and its tests.
void main() {
  const cryptoDeps = ['cryptography', 'bip39_mnemonic'];

  test('every cryptographic dependency is pinned to an exact version', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    for (final dep in cryptoDeps) {
      final line = pubspec.firstWhere(
        (l) => RegExp('^  $dep:').hasMatch(l),
        orElse: () => fail('$dep is missing from pubspec.yaml'),
      );
      final constraint = line.split(':').last.split('#').first.trim();
      expect(constraint, matches(RegExp(r'^\d+\.\d+\.\d+$')),
          reason: '$dep must be an exact pin, found "$constraint"');
    }
  });
}
