import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Since openhearth_design 0.7.1 the shared package ships Lora and Nunito.
// A second copy in the app is dead weight, and a bare family name in code
// would only resolve while that copy exists. These tests pin both.
void main() {
  test('pubspec declares no font families of its own', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('family: Lora')));
    expect(pubspec, isNot(contains('family: Nunito')));
    expect(pubspec, isNot(contains('assets/fonts')));
  });

  test('assets/fonts holds no Lora or Nunito files', () {
    final dir = Directory('assets/fonts');
    final names = dir.existsSync()
        ? dir.listSync().map((e) => e.uri.pathSegments.last).toList()
        : <String>[];
    expect(
      names.where((n) => n.contains('Lora') || n.contains('Nunito')),
      isEmpty,
    );
  });

  test('no code names Lora or Nunito without the shared package', () {
    final bare = RegExp(
      r"fontFamily:\s*'(Lora|Nunito)',(?!\s*package:)",
    );
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (bare.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
