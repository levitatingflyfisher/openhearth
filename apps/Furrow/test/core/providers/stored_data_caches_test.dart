// A restore changes the database under every long-lived provider. This
// guard holds the line for the whole class: each long-lived provider in lib/
// is either in storedDataResets, which the restore hook resets, or named as
// holding no stored data. A new long-lived cache or Undo cannot slip past
// both lists unseen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/stored_data_caches.dart';
import 'package:furrow/features/sanctuary_backup/backup_config.dart';

/// `@Riverpod(keepAlive: true)` (any other arguments allowed), then the
/// class or function it annotates. The generated provider is that name in
/// lower camel case plus `Provider`.
final _generatedKeepAlive = RegExp(
  r'@Riverpod\([^)]*keepAlive:\s*true[^)]*\)\s*'
  r'(?:class\s+(\w+)|[\w<>?, ]+?\s+(\w+)\s*\()',
);

/// A hand-written top-level provider: `final xProvider = SomeProvider...`.
/// Riverpod keeps it alive unless its type says `autoDispose`.
final _handWritten = RegExp(
  r'^final\s+(\w+Provider)\s*=\s*([\w.]+)',
  multiLine: true,
);

String _providerName(String declared) =>
    '${declared[0].toLowerCase()}${declared.substring(1)}Provider';

Set<String> _longLivedProvidersInLib() => _longLivedProvidersIn([
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') && !f.path.endsWith('.g.dart')))
        f.readAsStringSync(),
    ]);

Set<String> _longLivedProvidersIn(Iterable<String> sources) {
  final found = <String>{};
  for (final text in sources) {
    for (final m in _generatedKeepAlive.allMatches(text)) {
      found.add(_providerName(m.group(1) ?? m.group(2)!));
    }
    for (final m in _handWritten.allMatches(text)) {
      final type = m.group(2)!;
      if (type.contains('Provider') && !type.contains('autoDispose')) {
        found.add(m.group(1)!);
      }
    }
  }
  return found;
}

void main() {
  test(
      'every long-lived provider in lib/ is reset by a restore, or is '
      'named as holding no stored data', () {
    final found = _longLivedProvidersInLib();
    // An empty scan means a pattern broke, not that all is well. Furrow's
    // long-lived providers are all hand-written today; the generated
    // pattern is checked on its own by the next test.
    expect(
        found,
        containsAll(
            ['habitUndoProvider', 'newlyEarnedAwardsProvider']));

    final reset = [for (final e in storedDataResets) e.provider.name];
    final kept = [for (final p in keepAliveWithoutStoredData) p.name];
    // A hand-written provider has no name unless it is given one; without
    // names the comparison below would match nothing.
    expect([...reset, ...kept], everyElement(isNotNull),
        reason: 'give each listed provider a name: matching its variable');
    final listed = {...reset, ...kept};
    expect(
      found.difference(listed),
      isEmpty,
      reason: 'add each to storedDataResets if it holds stored data or a '
          'pending write, else to keepAliveWithoutStoredData',
    );
    expect(
      listed.difference(found),
      isEmpty,
      reason: 'a listed provider is no longer long-lived in lib/',
    );
  });

  test('the scan finds a generated keepAlive provider and skips the rest',
      () {
    const sample = '''
@Riverpod(keepAlive: true)
Stream<List<Habit>> pinnedHabits(Ref ref) => const Stream.empty();

@Riverpod(keepAlive: true, dependencies: [])
class FieldCache extends _\$FieldCache {}

@riverpod
Stream<List<Habit>> shortLived(Ref ref) => const Stream.empty();

final screenOnlyProvider = FutureProvider.autoDispose<int>((ref) => 1);
''';
    expect(_longLivedProvidersIn([sample]),
        {'pinnedHabitsProvider', 'fieldCacheProvider'});
  });

  test('the backup config runs the restore hook that resets the list', () {
    expect(furrowBackupConfig.onAfterRestore, same(afterFurrowRestore));
  });
}
