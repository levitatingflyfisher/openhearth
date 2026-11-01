// The iOS widget was dead code (nothing built or wrote to it), and its
// app group, group.com.porch.app, named a domain the publisher does not
// hold. Both are gone; this keeps that name from coming back on any
// Apple target.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no Apple target names the group.com.porch app group', () {
    final hits = <String>[];
    for (final dir in ['ios', 'macos']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File) continue;
        final String text;
        try {
          text = f.readAsStringSync();
        } on FileSystemException {
          continue; // binary
        }
        if (text.contains('group.com.porch')) hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });

  test('the dead iOS widget is gone', () {
    expect(Directory('ios/PorchWidget').existsSync(), isFalse);
  });
}
