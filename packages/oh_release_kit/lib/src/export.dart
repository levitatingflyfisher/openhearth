import 'dart:io';

import 'package:path/path.dart' as p;

class ExportException implements Exception {
  final String message;
  const ExportException(this.message);
  @override
  String toString() => message;
}

// Folders that live in memory on common Linux setups. A release tree there
// competes with the build for RAM and is gone after a reboot.
const _ramRoots = ['/tmp', '/dev/shm', '/run'];

/// Why [dest] cannot take a clean export, or null when it can. The export
/// only ever fills a folder it made itself, so nothing old can mix in.
String? exportDestProblem(String dest) {
  final abs = p.normalize(p.absolute(dest));
  for (final root in _ramRoots) {
    if (abs == root || p.isWithin(root, abs)) {
      return '$abs is under $root, which is RAM on this kind of system; '
          'export to real disk';
    }
  }
  if (FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound) {
    return '$abs already exists; the export only fills a new folder';
  }
  return null;
}

/// Writes the tree of [commit] in [repo] into the new folder [dest] with
/// `git archive`, and returns the full commit id. The working tree, its
/// untracked files and its build output never reach the export (release
/// rule 2). On any failure the half-made folder is removed.
Future<String> exportCommit(String repo, String commit, String dest) async {
  final problem = exportDestProblem(dest);
  if (problem != null) throw ExportException(problem);

  final rev = await Process.run('git', [
    '-C',
    repo,
    'rev-parse',
    '--verify',
    '--quiet',
    '$commit^{commit}',
  ]);
  if (rev.exitCode != 0) {
    throw ExportException('$commit is not a commit in $repo');
  }
  final sha = (rev.stdout as String).trim();

  final out = Directory(dest)..createSync(recursive: true);
  try {
    final archive = await Process.start('git', [
      '-C',
      repo,
      'archive',
      '--format=tar',
      sha,
    ]);
    final tar = await Process.start('tar', ['-x', '-C', out.path]);
    final archiveErr = archive.stderr.drain<void>();
    final tarErr = tar.stderr.transform(const SystemEncoding().decoder).join();
    await archive.stdout.pipe(tar.stdin);
    final codes = await Future.wait([archive.exitCode, tar.exitCode]);
    await archiveErr;
    final err = await tarErr;
    if (codes[0] != 0 || codes[1] != 0) {
      throw ExportException(
        'git archive exited ${codes[0]}, '
        'tar exited ${codes[1]} $err',
      );
    }
  } catch (_) {
    out.deleteSync(recursive: true);
    rethrow;
  }
  return sha;
}
