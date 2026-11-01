import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fleet's rule: cryptographic dependencies are pinned to exact
/// versions (`3.0.8`, never `^3.0.8`). Fleet conformance C15 checks the
/// same once the shared packages carry it; this holds it in the meantime.
void main() {
  test('crypto is pinned to an exact version', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => RegExp('^  crypto:').hasMatch(l));
    final constraint = line.split(':').last.split('#').first.trim();
    expect(constraint, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'crypto must be an exact pin, found "$constraint"');
  });
}
