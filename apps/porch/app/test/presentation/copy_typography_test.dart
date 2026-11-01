// House style for words on screen: no spaced em dashes, and typographic
// apostrophes and quotes (’ “ ”) rather than typewriter ones (' ").
// A source scan over string literals in lib/presentation, where every
// on-screen word lives. lib/domain and lib/data are left alone on purpose:
// their strings are wire format, protocol labels and exception messages
// that code matches on (see onboarding's _backupMessage).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final literal = RegExp(r'"([^"\\]|\\.)*"' "|" r"'([^'\\]|\\.)*'");

  Iterable<(String, int, String)> literals() sync* {
    final files = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final t = line.trimLeft();
        if (t.startsWith('//') || line.contains('debugPrint(')) continue;
        if (t.startsWith('import ') || t.startsWith('export ')) continue;
        for (final m in literal.allMatches(line)) {
          yield (f.path, i + 1, m.group(0)!);
        }
      }
    }
  }

  test('the scan sees the copy (cannot pass by finding nothing)', () {
    expect(literals().length, greaterThan(200));
  });

  test('no spaced em dash in on-screen copy', () {
    final hits = [
      for (final (path, line, lit) in literals())
        if (lit.contains(' — ') || lit.endsWith(" —'") || lit.endsWith(' —"'))
          '$path:$line $lit',
    ];
    expect(hits, isEmpty);
  });

  test('no typewriter apostrophe or quote inside on-screen copy', () {
    final apostrophe = RegExp(r"[A-Za-z](?:'|\\')[A-Za-z]");
    final hits = [
      for (final (path, line, lit) in literals())
        if ((lit.startsWith('"') &&
                apostrophe.hasMatch(lit.substring(1, lit.length - 1))) ||
            (lit.startsWith("'") &&
                (lit.substring(1, lit.length - 1).contains('"') ||
                    apostrophe.hasMatch(lit.substring(1, lit.length - 1)))))
          '$path:$line $lit',
    ];
    expect(hits, isEmpty);
  });
}
