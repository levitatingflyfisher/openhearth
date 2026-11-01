// The CI workflow runs third-party actions with the repo's token. A tag
// can be moved to other code at any time; a full commit hash cannot. So
// every action is pinned by its commit, with the tag it was taken from in
// a comment, and the token may only read the repo.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final ci = File('../.github/workflows/ci.yml').readAsStringSync();

  test('every action is pinned by a full commit hash, its tag in a comment',
      () {
    final uses = RegExp(r'uses:\s*(\S+)(.*)').allMatches(ci).toList();
    expect(uses, isNotEmpty);
    for (final m in uses) {
      final ref = m.group(1)!;
      expect(ref, matches(RegExp(r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$')),
          reason: ref);
      expect(m.group(2), matches(RegExp(r'^\s*#\s*v\d')), reason: m.group(0));
    }
  });

  test('the workflow token may only read the repo', () {
    expect(ci, matches(RegExp(r'^permissions:\s*\n\s+contents:\s*read\s*$',
        multiLine: true)));
  });
}
