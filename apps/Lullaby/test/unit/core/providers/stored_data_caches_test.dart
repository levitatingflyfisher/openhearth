// A restore changes the database under every long-lived provider. This
// guard holds the line for the whole class: each long-lived provider in lib/
// is either in storedDataResets, which the restore hook resets, or ruled
// below as holding no stored data, with the reason. A new long-lived cache or
// Undo cannot slip past both lists unseen.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/app/undo_host.dart';
import 'package:lullaby/core/providers/stored_data_caches.dart';

/// A top-level provider: `final xProvider = SomeProvider...`. Lullaby writes
/// every provider by hand. Riverpod keeps one alive unless its type says
/// `autoDispose`.
final _declared = RegExp(
  r'^final\s+(\w+Provider)\s*=\s*([\w.]+)',
  multiLine: true,
);

const _driftWatch = 'a Drift watch stream: it follows the database itself';
const _repository = 'wraps the database and caches nothing';
const _lastAction = 'holds only how its last action went (AsyncValue<void>)';
const _uiChoice = 'a choice on screen, not stored data';
const _theme = 'the theme, a setting on this phone that no backup holds';

/// Long-lived providers that hold no stored data, each with its reason.
const _holdNoStoredData = <String, String>{
  'databaseProvider': 'the database itself',
  'babyRepositoryProvider': _repository,
  'feedingRepositoryProvider': _repository,
  'sleepRepositoryProvider': _repository,
  'diaperRepositoryProvider': _repository,
  'growthRepositoryProvider': _repository,
  'medicineRepositoryProvider': _repository,
  'vaccineRepositoryProvider': _repository,
  'handoffRepositoryProvider': _repository,
  'recordWriterProvider': 'picks the write path per write; holds no records',
  'syncSettingsStorageProvider':
      'the store for this phone\'s sync choices, which no backup holds',
  'householdSyncProvider':
      'sync. A restore is refused while this phone holds a household log '
          '(ADR-0007); without one there is no loop, no listener and no '
          'queued write to replay',
  'babyListProvider': _driftWatch,
  'activeBabyProvider': _driftWatch,
  '_activeBabyForCalendarProvider': _driftWatch,
  '_calendarBabyIdProvider': 'the id from a Drift watch stream',
  'growthRecordsProvider': _driftWatch,
  'latestGrowthProvider': _driftWatch,
  'medicineLogsProvider': _driftWatch,
  'vaccineRecordsProvider': _driftWatch,
  'timelineProvider': _driftWatch,
  'allEventsProvider': _driftWatch,
  'activeSleepProvider': _driftWatch,
  'recentFeedingsProvider': _driftWatch,
  'lastFeedingProvider': _driftWatch,
  'recentDiapersProvider': _driftWatch,
  'babyControllerProvider': _lastAction,
  'growthControllerProvider': _lastAction,
  'medicineControllerProvider': _lastAction,
  'vaccineControllerProvider': _lastAction,
  'sleepControllerProvider': _lastAction,
  'feedingControllerProvider': _lastAction,
  'diaperControllerProvider': _lastAction,
  'selectedDayProvider': _uiChoice,
  'doctorDateRangeProvider': _uiChoice,
  'statsPeriodProvider': _uiChoice,
  'timelineFilterProvider': _uiChoice,
  'statsAggregatorProvider': 'computes from the repositories; caches nothing',
  'exportFileShareProvider': 'the platform\'s share function',
  'homeWidgetControllerProvider':
      'reads the database on every redraw, never a cached value',
  'themeStorageProvider': _theme,
  'initialThemePreferenceProvider': _theme,
  'themeModeProvider': _theme,
};

/// Every long-lived provider in lib/, by name, with its declared type.
Map<String, String> _longLivedProvidersInLib() {
  final found = <String, String>{};
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
  for (final file in sources) {
    for (final m in _declared.allMatches(file.readAsStringSync())) {
      final type = m.group(2)!;
      if (type.contains('Provider') && !type.contains('autoDispose')) {
        found[m.group(1)!] = type;
      }
    }
  }
  return found;
}

void main() {
  final found = _longLivedProvidersInLib();
  final reset = [for (final e in storedDataResets) e.provider.name];

  test(
      'every long-lived provider in lib/ is reset by a restore, or is ruled '
      'to hold no stored data', () {
    // An empty scan means the pattern broke, not that all is well.
    expect(found.keys,
        containsAll(['databaseProvider', 'undoControllerProvider']));
    // A provider has no name unless it is given one; without names the
    // comparison below would match nothing.
    expect(reset, everyElement(isNotNull),
        reason: 'give each listed provider name: matching its variable');

    final listed = {...reset.cast<String>(), ..._holdNoStoredData.keys};
    expect(found.keys.toSet().difference(listed), isEmpty,
        reason: 'add each to storedDataResets if it holds stored data or a '
            'pending write, else to _holdNoStoredData with the reason');
    expect(listed.difference(found.keys.toSet()), isEmpty,
        reason: 'a listed provider is no longer long-lived in lib/');
    expect(reset.toSet().intersection(_holdNoStoredData.keys.toSet()), isEmpty,
        reason: 'a provider is either reset or ruled to hold nothing');
  });

  // The class the audit found: a one-shot read of stored data, kept for the
  // app's lifetime. It can never be ruled harmless; it must be reset, or be
  // a watch stream, or be autoDispose.
  test('no long-lived one-shot FutureProvider escapes the reset', () {
    final oneShot = {
      for (final e in found.entries)
        if (e.value.startsWith('FutureProvider')) e.key,
    };
    expect(oneShot, contains('rawExportProvider'));
    expect(oneShot.difference(reset.toSet()), isEmpty);
  });

  test('the Undo is ended first, so it cannot fire into the restored record',
      () {
    expect(reset.first, 'undoControllerProvider');
  });

  test('a restore ends a pending Undo without running its onCommit', () {
    final refProvider = Provider<Ref>((ref) => ref);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var commits = 0;
    var undos = 0;
    final undo = c.read(undoControllerProvider);
    undo.show(
      message: 'Feed deleted',
      onUndo: () async => undos++,
      onCommit: () async => commits++,
    );
    expect(undo.pending, isNotNull);

    // Only the Undo entry: the others rebuild providers that need a database.
    final entry = storedDataResets
        .firstWhere((e) => e.provider.name == 'undoControllerProvider');
    entry.reset(c.read(refProvider));

    expect(undo.pending, isNull, reason: 'the old offer must be gone');
    expect(commits, 0, reason: 'a commit is written against the old record');
    expect(undos, 0);
  });

  test('the shipped backup config runs the restore hook', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('onAfterRestore: lullabyAfterRestore'));
    final hook = File('lib/features/sanctuary_backup/after_restore.dart')
        .readAsStringSync();
    expect(hook, contains('forgetCachedData(ref)'));
  });
}
