// test/app/stored_data_caches_test.dart
//
// The guard for lib/app/stored_data_caches.dart. Clear all data and a
// restore reset only what storedDataCaches names, so a provider that can
// hold stored data past its screen and is not named would show data that is
// gone. These tests make every such provider a ruling someone wrote down.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/app/root_overrides.dart';
import 'package:mantle/app/stored_data_caches.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

/// Providers ruled to hold stored data where it can outlive its screen.
/// Must match storedDataCaches exactly.
const _cachesByName = {
  'roundResumeOfferProvider': 'Home watches it, and Home stays alive under '
      'Settings, where Clear all data and restore happen.',
};

/// Long-lived providers that hold no copy of stored data, each with why.
const _holdNoStoredData = {
  'databaseProvider': 'the database itself; every read goes through it',
  'membersDaoProvider': 'a DAO; it caches no rows',
  'roundsDaoProvider': 'a DAO; it caches no rows',
  'sessionsDaoProvider': 'a DAO; it caches no rows',
  'matchesDaoProvider': 'a DAO; it caches no rows',
  'chartersDaoProvider': 'a DAO; it caches no rows',
  'readProgressDaoProvider': 'a DAO; it caches no rows',
  'spotProgressDaoProvider': 'a DAO; it caches no rows',
  'discoveredThroughlinesDaoProvider': 'a DAO; it caches no rows',
  'contentRepositoryProvider': 'the bundled deck and canon, not user data',
  'menswearRepositoryProvider': 'the bundled tutor content, not user data',
  'themePreferenceProvider': 'the theme, a device setting kept by Clear all '
      'data and not held in a backup',
};

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList();

/// Every top-level `final x = <constructor>` whose constructor is a riverpod
/// provider (or another scanned provider, such as a family instance), with
/// whether it is autoDispose.
Map<String, bool> _scanProviders() {
  final decl = RegExp(r'^final (\w+)\s*=\s*([A-Za-z_][\w.]*)', multiLine: true);
  final raw = <String, String>{};
  for (final f in _libFiles()) {
    for (final m in decl.allMatches(f.readAsStringSync())) {
      raw[m.group(1)!] = m.group(2)!;
    }
  }
  final out = <String, bool>{};
  bool? autoDispose(String name, [int depth = 0]) {
    final ctor = raw[name];
    if (ctor == null || depth > 5) return null;
    if (ctor.contains('Provider')) return ctor.contains('autoDispose');
    return autoDispose(ctor, depth + 1);
  }

  for (final name in raw.keys) {
    final a = autoDispose(name);
    if (a != null) out[name] = a;
  }
  return out;
}

void main() {
  test('every long-lived provider is ruled on: a stored-data cache or not',
      () {
    final scanned = _scanProviders();
    final longLived = {
      for (final e in scanned.entries)
        if (!e.value) e.key
    };
    // A scan that breaks and finds nothing must fail, not pass.
    expect(longLived, contains('databaseProvider'));
    expect(scanned['roundResumeOfferProvider'], isTrue);
    expect(scanned['clearAllDataUndoProvider'], isTrue);

    final unruled = longLived
        .where((n) =>
            !_cachesByName.containsKey(n) && !_holdNoStoredData.containsKey(n))
        .toList();
    expect(unruled, isEmpty,
        reason: 'A provider that is not autoDispose lives as long as the '
            'app. If it holds stored data, add it to storedDataCaches in '
            'lib/app/stored_data_caches.dart and to _cachesByName here; if '
            'not, add it to _holdNoStoredData with the reason.');
    final gone = _holdNoStoredData.keys.where((n) => !longLived.contains(n));
    expect(gone, isEmpty,
        reason: 'a ruled provider is gone or now autoDispose; update the '
            'table');
  });

  test('every provider the screen under Settings watches is ruled on', () {
    // Settings is pushed only from Home, so Home is what stays alive under
    // it. If Settings is ever opened from elsewhere, what lies under it
    // there needs the same check.
    final settingsOpeners = [
      for (final f in _libFiles())
        if (f.readAsStringSync().contains('SettingsScreen()')) f.path
    ];
    expect(settingsOpeners, [
      'lib/features/home/presentation/home_screen.dart'.replaceAll(
          '/', Platform.pathSeparator)
    ]);

    // Home's own file, plus the app's widgets it builds (the theme toggle
    // and the cards).
    final homeFiles = [
      File('lib/features/home/presentation/home_screen.dart'),
      File('lib/core/theme/theme_preference.dart'),
      ...Directory('lib/widgets').listSync().whereType<File>(),
    ];
    final watch = RegExp(r'ref\.(?:watch|listen)\((\w+)');
    final watched = {
      for (final f in homeFiles)
        for (final m in watch.allMatches(f.readAsStringSync())) m.group(1)!
    };
    expect(watched, contains('roundResumeOfferProvider'),
        reason: 'the scan must see what Home watches');
    final unruled = watched
        .where((n) =>
            !_cachesByName.containsKey(n) && !_holdNoStoredData.containsKey(n))
        .toList();
    expect(unruled, isEmpty,
        reason: 'Home stays alive under Settings, so whatever it watches '
            'outlives Clear all data and a restore. Rule on it above.');
  });

  test('storedDataCaches is exactly the providers ruled to hold stored data',
      () {
    expect(storedDataCaches.map((p) => p.name).toSet(),
        _cachesByName.keys.toSet());
    expect(storedDataCaches, hasLength(_cachesByName.length));
  });

  test('the Clear all data Undo lives only as long as Settings', () {
    // Riverpod 3 has no AutoDisposeProvider type; the flag says it.
    expect(clearAllDataUndoProvider, isA<Provider<OhUndoController>>());
    expect(clearAllDataUndoProvider.isAutoDispose, isTrue);
  });

  test('the shipped backup config runs afterMantleRestore', () {
    expect(mantleBackupConfig.onAfterRestore, afterMantleRestore);
    final c = ProviderContainer(overrides: mantleRootOverrides(web: false));
    addTearDown(c.dispose);
    expect(c.read(sanctuaryBackupConfigProvider), same(mantleBackupConfig));
  });

  test('the reset ends a pending Undo without running its onCommit', () {
    final undo = OhUndoController();
    addTearDown(undo.dispose);
    var committed = false;
    var undone = false;
    undo.show(
      message: 'Cleared all data',
      onUndo: () async => undone = true,
      onCommit: () async => committed = true,
    );

    forgetCachedData((_) {}, undo: undo);

    expect(undo.pending, isNull);
    expect(committed, isFalse, reason: 'a reset never commits the old offer');
    expect(undone, isFalse);
  });

  test('no Undo carries an onCommit', () {
    // forgetCachedData cancels, so it does not need this. An ordinary
    // dismissal (the close button, leaving Settings) runs onCommit, and no
    // Undo in Mantle needs one.
    final hits = [
      for (final f in _libFiles())
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('//') && line.contains('onCommit:'))
            '${f.path}:${i + 1}'
    ];
    expect(hits, isEmpty);
  });

  test('Mantle does not use riverpod codegen, which this scan cannot read',
      () {
    final hits = [
      for (final f in _libFiles())
        if (RegExp(r'@[Rr]iverpod').hasMatch(f.readAsStringSync())) f.path
    ];
    expect(hits, isEmpty,
        reason: 'teach _scanProviders to read @Riverpod(keepAlive: true)');
  });
}
