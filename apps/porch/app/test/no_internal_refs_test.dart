// The source is published. Internal ruling numbers and ruling notes from
// the publisher's own process mean nothing to a reader and do
// not belong in it: say "the publisher's rule" instead. This scans every
// text file in the repo, both codebases and the docs.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

final _internalRef =
    RegExp(r'\bboard[- ]?(\d{3,}|ruling)', caseSensitive: false);

const _skipDirs = {
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  'Pods',
  '.gradle',
  'ephemeral',
};

void main() {
  test('no internal ruling numbers or ruling notes in the tree', () {
    final hits = <String>[];
    void walk(Directory dir) {
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory) {
          if (!_skipDirs.contains(name)) walk(e);
        } else if (e is File) {
          final String text;
          try {
            text = utf8.decode(e.readAsBytesSync());
          } on FormatException {
            continue; // binary: images, icons
          }
          final lines = const LineSplitter().convert(text);
          for (var i = 0; i < lines.length; i++) {
            if (_internalRef.hasMatch(lines[i])) {
              hits.add('${e.path}:${i + 1}');
            }
          }
        }
      }
    }

    walk(Directory('..'));
    expect(hits, isEmpty);
  });
}
