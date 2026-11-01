import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/app/stored_data_caches.dart';
import 'package:lilt/features/home/home_screen.dart';
import 'package:lilt/features/matchup/matchup_notifier.dart';
import 'package:lilt/features/name_detail/name_detail_screen.dart';
import 'package:lilt/features/results/couple_results_screen.dart';
import 'package:lilt/features/results/solo_results_screen.dart';
import 'package:lilt/features/settings/settings_screen.dart';
import 'package:lilt/features/shortlist/shortlist_screen.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// The long-lived providers that keep a copy of stored data. Each must be
/// in [storedDataCaches], so a restore and an erase reset it.
final Map<String, ProviderOrFamily> _cachesByName = {
  'allSessionsProvider': allSessionsProvider,
  'clearedSessionsProvider': clearedSessionsProvider,
  'shortlistEntriesProvider': shortlistEntriesProvider,
  'soloResultsProvider': soloResultsProvider,
  'methodologyProvider': methodologyProvider,
  'coupleResultsProvider': coupleResultsProvider,
  'nameDetailProvider': nameDetailProvider,
  'matchupProvider': matchupProvider,
};

/// The long-lived providers that hold no copy of what a restore or an
/// erase replaces, each with the reason.
const Map<String, String> _holdNoStoredData = {
  'databaseProvider': 'the database itself; a restore writes through it',
  'namesRepositoryProvider': 'wraps the DAO and reads it on every call',
  'sessionRepositoryProvider': 'wraps the DAOs; rebuilds rankings per call',
  'shortlistRepositoryProvider': 'wraps the DAO and reads it on every call',
  'bootstrapProvider': 'loads the bundled catalog, which a restore keeps',
  'routerProvider': 'navigation only; its guards read the database per call',
  'sharedPreferencesProvider': 'device settings; no backup holds them',
  'convergenceTauProvider': 'a device setting, kept on purpose',
  'themePreferenceProvider': 'a device setting, kept on purpose',
};

/// Top-level provider declarations in lib/, as name to constructor, such as
/// `FutureProvider.family` or `Provider.autoDispose`.
Map<String, String> _declaredProviders() {
  final decl = RegExp(r'^final\s+(\w+)\s*=\s*(\w*Provider\w*(?:\.\w+)*)',
      multiLine: true);
  final anyProviderName = RegExp(r'^final\s+(?:[\w<>, ?]+\s+)?(\w+Provider)\b',
      multiLine: true);
  final found = <String, String>{};
  final missed = <String>[];
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) {
      continue;
    }
    final src = f.readAsStringSync();
    expect(src.contains(RegExp(r'@[Rr]iverpod\b')), isFalse,
        reason: '${f.path} uses riverpod codegen; widen this scan for it');
    final here = {
      for (final m in decl.allMatches(src)) m.group(1)!: m.group(2)!,
    };
    found.addAll(here);
    for (final m in anyProviderName.allMatches(src)) {
      if (!here.containsKey(m.group(1))) missed.add('${f.path}: ${m.group(1)}');
    }
  }
  expect(missed, isEmpty,
      reason: 'declared in a shape the scan does not read; widen the scan');
  return found;
}

bool _autoDispose(String constructor) =>
    constructor.toLowerCase().contains('autodispose');

void main() {
  test('every long-lived provider is ruled on: a stored-data cache or not',
      () {
    final longLived = {
      for (final e in _declaredProviders().entries)
        if (!_autoDispose(e.value)) e.key,
    };
    final ruled = {..._cachesByName.keys, ..._holdNoStoredData.keys};
    expect(longLived.difference(ruled), isEmpty,
        reason: 'a new long-lived provider: if it keeps stored data, add it '
            'to storedDataCaches (lib/app/stored_data_caches.dart) and to '
            '_cachesByName here; if not, add it to _holdNoStoredData');
    expect(ruled.difference(longLived), isEmpty,
        reason: 'ruled on, but gone or now autoDispose: update the tables');
  });

  test('storedDataCaches is exactly the providers ruled to keep stored data',
      () {
    expect(storedDataCaches.toSet(), _cachesByName.values.toSet());
    expect(storedDataCaches, hasLength(_cachesByName.length));
  });

  test('the Clear Undo is autoDispose, so it dies with Settings', () {
    expect(_autoDispose(_declaredProviders()['clearSessionsUndoProvider']!),
        isTrue);
  });

  test('the reset ends a pending Undo without running its onCommit', () {
    final undo = OhUndoController();
    addTearDown(undo.dispose);
    var committed = false;
    var undone = false;
    undo.show(
      message: 'Cleared 2 sessions',
      onUndo: () async => undone = true,
      onCommit: () async => committed = true,
    );

    forgetCachedData((_) {}, undo: undo);

    expect(undo.pending, isNull);
    expect(committed, isFalse, reason: 'a reset never commits the old offer');
    expect(undone, isFalse);
  });

  test('no Undo in lib/ carries an onCommit', () {
    // An ordinary dismissal (the bar's close button, a newer delete, leaving
    // the screen) runs the offer's onCommit. None of Lilt's needs one, so
    // none has one.
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (code.contains('onCommit:')) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty,
        reason: 'no Undo in Lilt needs an onCommit');
  });
}
