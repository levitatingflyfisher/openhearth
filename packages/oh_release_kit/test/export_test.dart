import 'dart:io';

import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Scratch on real disk inside the package's own ignored build folder: the
// export refuses RAM-backed folders, and so should its tests.
Directory _scratch() {
  final root = Directory(p.join('.dart_tool', 'kit_test_tmp'))
    ..createSync(recursive: true);
  return root.createTempSync('export_');
}

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', [
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test'
        '@example.com',
    '-c',
    'commit.gpgsign=false',
    ...args,
  ], workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

void main() {
  group('exportDestProblem', () {
    test('an existing folder is refused', () {
      final d = _scratch();
      addTearDown(() => d.deleteSync(recursive: true));
      expect(exportDestProblem(d.path), contains('already exists'));
    });

    test('a RAM-backed folder is refused', () {
      for (final dest in ['/tmp/x', '/dev/shm/x', '/run/user/1000/x']) {
        expect(exportDestProblem(dest), contains('RAM'), reason: dest);
      }
    });

    test('a new folder on real disk is fine', () {
      final d = _scratch();
      addTearDown(() => d.deleteSync(recursive: true));
      expect(exportDestProblem(p.join(d.path, 'new')), isNull);
    });
  });

  group('exportCommit', () {
    late Directory scratch;
    late String repo;
    setUp(() async {
      scratch = _scratch();
      repo = p.join(scratch.path, 'repo');
      Directory(repo).createSync();
      await _git(repo, ['init', '-q']);
      File(p.join(repo, 'a.txt')).writeAsStringSync('committed\n');
      await _git(repo, ['add', 'a.txt']);
      await _git(repo, ['commit', '-q', '-m', 'one']);
      // Working-tree changes must not reach the export.
      File(p.join(repo, 'a.txt')).writeAsStringSync('dirty\n');
      File(p.join(repo, 'untracked.txt')).writeAsStringSync('x\n');
    });
    tearDown(() => scratch.deleteSync(recursive: true));

    test('exports the commit, not the working tree', () async {
      final dest = p.join(scratch.path, 'out');
      final sha = await exportCommit(repo, 'HEAD', dest);
      expect(sha, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(File(p.join(dest, 'a.txt')).readAsStringSync(), 'committed\n');
      expect(File(p.join(dest, 'untracked.txt')).existsSync(), isFalse);
    });

    test('an unknown commit fails and leaves no folder', () async {
      final dest = p.join(scratch.path, 'out');
      await expectLater(
        exportCommit(repo, 'no-such-ref', dest),
        throwsA(isA<ExportException>()),
      );
      expect(Directory(dest).existsSync(), isFalse);
    });

    test('an existing destination is refused before git runs', () async {
      final dest = p.join(scratch.path, 'out');
      Directory(dest).createSync();
      await expectLater(
        exportCommit(repo, 'HEAD', dest),
        throwsA(isA<ExportException>()),
      );
    });
  });
}
