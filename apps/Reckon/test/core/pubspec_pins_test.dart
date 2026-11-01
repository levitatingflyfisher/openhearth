import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fleet's rule: cryptographic dependencies are pinned to exact
/// versions (`2.9.0`, never `^2.9.0`). Reckon uses `cryptography` directly
/// for ReckonParty's end-to-end encryption.
void main() {
  test('cryptography is pinned to an exact version', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => RegExp('^  cryptography:').hasMatch(l));
    final constraint = line.split(':').last.split('#').first.trim();
    expect(constraint, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'cryptography must be an exact pin, found "$constraint"');
  });
}
