// Every screen has a way in (fleet roadmap item 22). The fleet's C9 check
// reads go_router's GoRoute table; porch has no router (Navigator.push of
// MaterialPageRoute from three screens deep at most), so C9 cannot see it
// and stays off in fleet_conformance_test.dart. This is porch's own
// version: every *Screen / *Flow widget declared under lib/presentation
// must be constructed somewhere in lib/ outside its own file.
import 'dart:io';

import 'package:test/test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final declared = <String, String>{}; // class name -> declaring file
  final decl = RegExp(r'class\s+(\w+(?:Screen|Flow))\s+extends\s+'
      r'(?:Stateless|Stateful|ConsumerStateful|Consumer)Widget');
  for (final f in libFiles.where((f) => f.path.contains('presentation'))) {
    for (final m in decl.allMatches(_stripComments(f.readAsStringSync()))) {
      declared[m.group(1)!] = f.path;
    }
  }

  test('finds the screens (cannot pass by finding nothing)', () {
    expect(declared.keys, containsAll(['HomeScreen', 'OnboardingFlow']));
    expect(declared.length, greaterThanOrEqualTo(7),
        reason: 'found only ${declared.keys}');
  });

  test('every screen is constructed from somewhere else in lib/', () {
    final orphans = <String>[];
    for (final MapEntry(key: name, value: home) in declared.entries) {
      final door = RegExp('\\b$name\\(');
      final reached = libFiles.any((f) =>
          f.path != home && door.hasMatch(_stripComments(f.readAsStringSync())));
      if (!reached) orphans.add('$name ($home)');
    }
    expect(orphans, isEmpty, reason: 'screens with no way in: $orphans');
  });
}
