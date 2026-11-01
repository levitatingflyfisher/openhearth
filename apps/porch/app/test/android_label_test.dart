// The name under the launcher icon is the product's name, not the Dart
// package id the Flutter template put there.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the Android launcher label is "Porch"', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final label =
        RegExp(r'<application[^>]*android:label="([^"]*)"').firstMatch(manifest);
    expect(label?.group(1), 'Porch');
  });
}
