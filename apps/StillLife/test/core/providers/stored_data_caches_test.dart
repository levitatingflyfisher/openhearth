import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/core/providers/stored_data_caches.dart';

/// The guard for the restore reset (see lib/core/providers/stored_data_caches.dart).
///
/// Every restore merges into the live database, and the tabs stay alive
/// under Settings. So every provider declared in lib/ must be one of:
/// - a StreamProvider (each one here returns a Drift watch query, which
///   follows the database by itself);
/// - a provider that calls `rereadOnDatabaseWrites(ref)`;
/// - an entry in `storedDataResets`, which every restore resets;
/// - named below with the reason it holds no stored data.
/// A new provider fails this test until someone rules on it.

const _wiring =
    'Wires a service, repository, client or store; holds no copy of stored '
    'data.';
const _action =
    'Holds only the state of the action in progress, never the rows.';
const _deviceSetting =
    'A device setting kept in secure storage or preferences; the backup does '
    'not carry it.';
const _uiChoice = 'A choice on screen, kept on purpose.';

const _ruled = <String, String>{
  // Wiring.
  'appraisalRepositoryProvider': _wiring,
  'appraiserCountryCodeProvider': _wiring,
  '_appraiserDioProvider': _wiring,
  'hostedMessagesClientProvider': _wiring,
  'messagesTransportProvider': _wiring,
  'appraiserServiceProvider': _wiring,
  'billingServiceProvider': _wiring,
  'itemChatServiceProvider': _wiring,
  'secureStorageProvider': _wiring,
  'databaseProvider': _wiring,
  'notificationServiceProvider': _wiring,
  'profileRepositoryProvider': _wiring,
  '_photoStorageServiceProvider': _wiring,
  '_mlDioProvider': _wiring,
  '_productLookupDioProvider': _wiring,
  'itemRepositoryProvider': _wiring,
  'categoryRepositoryProvider': _wiring,
  'tagRepositoryProvider': _wiring,
  'photoRepositoryProvider': _wiring,
  'propertyRepositoryProvider': _wiring,
  'roomRepositoryProvider': _wiring,
  'containerRepositoryProvider': _wiring,
  'policyRepositoryProvider': _wiring,
  'maintenanceRepositoryProvider': _wiring,
  'loanRepositoryProvider': _wiring,
  'exportServiceProvider': _wiring,
  'importServiceProvider': _wiring,
  'csvExportServiceProvider': _wiring,
  'productLookupServiceProvider': _wiring,
  'onDeviceSupportProvider': _wiring,
  'providerManagerProvider': _wiring,
  'itemPhotoAnalysisServiceProvider': _wiring,
  'voiceInputServiceProvider': _wiring,
  'savedSearchServiceProvider': _wiring,
  'consumableSeederProvider': _wiring,
  'importFallbackSeederProvider': _wiring,
  'amazonImportServiceProvider': _wiring,
  'receiptOcrServiceProvider': _wiring,
  '_secureStorageProvider': _wiring,
  'lanDiscoveryProvider': _wiring,
  'lanSyncClientProvider': _wiring,
  'syncStampProvider': _wiring,
  'photoBackupContainerProvider': _wiring,
  'photoVaultStoreProvider': _wiring,
  'photoBackupVaultProvider': _wiring,
  'photoRestoreGuardProvider': _wiring,
  '_insuranceGapServiceProvider': _wiring,
  'photoStorageServiceProvider': _wiring,
  'quantityControllerProvider': _wiring,
  'recentlyDeletedRepositoryProvider': _wiring,
  'llmConnectionTesterProvider': _wiring,
  'themePreferenceStoreProvider': _wiring,
  'webDavServiceProvider': _wiring,
  'videoSessionLogProvider': _wiring,
  'analysisOrchestratorProvider': _wiring,
  'itemDraftStoreProvider':
      'Wires the draft store. Drafts are for a new item only (key "new"), '
      'and no restore writes the drafts table, so a draft cannot overwrite '
      'a restored row.',
  'crdtManagerProvider':
      'The sync clock and this device\'s identity, kept on the device. A '
      'restore keeps each row\'s own stamp, and the clock only moves forward.',
  'lanSyncServerProvider':
      'Serves only while the Sync screen is open; the screen stops it when '
      'it closes. Every restore starts from Settings, Reports or WebDAV, '
      'which cannot be in front while the Sync screen is open. Its merge is '
      'last-writer-wins, and the one-shot reads follow its writes.',
  // Actions in progress.
  'categoryControllerProvider': _action,
  'itemControllerProvider': _action,
  'photoControllerProvider': _action,
  'tagControllerProvider': _action,
  'loanControllerProvider': _action,
  'propertyControllerProvider': _action,
  'roomControllerProvider': _action,
  'containerControllerProvider': _action,
  'maintenanceControllerProvider': _action,
  'exportControllerProvider': _action,
  'policyControllerProvider': _action,
  'syncControllerProvider':
      'The peers found on the network and the last sync time; no stored rows.',
  'videoAnalysisControllerProvider':
      'A walkthrough in progress. Its suggestions become new items only when '
      'confirmed; it never writes an existing row.',
  // Device settings.
  'accountProvider': _deviceSetting,
  'cloudApiConfigProvider': _deviceSetting,
  'productLookupEnabledProvider': _deviceSetting,
  'syncSecretProvider': _deviceSetting,
  'savedSearchesProvider': _deviceSetting,
  'onDeviceModelsControllerProvider':
      'The on-device model files; not household data.',
  'nanoStatusProvider':
      'The phone\'s on-device model status; not household data.',
  'initialThemePreferenceProvider': _deviceSetting,
  'themePreferenceProvider': _deviceSetting,
  'themeModeProvider': _deviceSetting,
  'llmTierPriorityProvider': _deviceSetting,
  'llmTierEnabledProvider': _deviceSetting,
  'ollamaHostProvider': _deviceSetting,
  'ollamaPortProvider': _deviceSetting,
  'ollamaModelProvider': _deviceSetting,
  'cloudApiTypeSettingProvider': _deviceSetting,
  'claudeApiKeySettingProvider': _deviceSetting,
  'appraiserModelSettingProvider': _deviceSetting,
  'openAiCompatBaseUrlProvider': _deviceSetting,
  'openAiCompatApiKeyProvider': _deviceSetting,
  'openAiCompatModelProvider': _deviceSetting,
  // Choices on screen.
  'routerProvider': _uiChoice,
  'inventoryQueryProvider': _uiChoice,
  'selectedPropertyIdProvider': _uiChoice,
  // Built once, or from streams.
  'bootstrapProvider':
      'Runs once at start to seed an empty database; holds nothing.',
  'appVersionProvider': 'The app\'s own version; not household data.',
  'activeProfileProvider':
      'Watches profilesProvider, a Drift stream, so it follows a restore.',
  'nlQueryParserProvider':
      'Built from the rooms, categories and containers streams, so it '
      'follows a restore.',
};

class _Declared {
  _Declared(this.name, this.type, this.body, this.file);
  final String name;
  final String type;
  final String body;
  final String file;
}

final _declaration = RegExp(
  r'^(?:final|late final)\s+(_?\w+Provider)\s*=\s*([\w.\s]+?)\s*[<(]',
  multiLine: true,
);

// A top-level declaration ends where the next line starts at column 0 with
// anything but a closing bracket.
final _nextTopLevel = RegExp(r'\n(?=[^\s})\]])');

List<_Declared> _scan(String path, String source) {
  final found = <_Declared>[];
  for (final m in _declaration.allMatches(source)) {
    final end = _nextTopLevel.firstMatch(source.substring(m.end));
    found.add(
      _Declared(
        m.group(1)!,
        m.group(2)!.replaceAll(RegExp(r'\s+'), ''),
        source.substring(
          m.start,
          end == null ? source.length : m.end + end.start,
        ),
        path,
      ),
    );
  }
  return found;
}

List<File> _libFiles() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Source without `//` comments, so a comment naming a pattern is not a hit.
String _code(String source) => source
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  final declared = [
    for (final f in _libFiles()) ..._scan(f.path, f.readAsStringSync()),
  ];
  final resetNames = {for (final e in storedDataResets) e.provider.name};

  test('the scan finds the providers it must', () {
    final names = declared.map((d) => d.name).toSet();
    // If these vanish, the pattern broke, and the guard would pass by
    // finding nothing.
    expect(
      names,
      containsAll([
        'shellUndoControllerProvider',
        'screenUndoControllerProvider',
        'warrantyExpiringSoonProvider',
        '_recentActivityProvider',
        'itemTagsProvider',
        'inventoryItemsProvider',
      ]),
    );
    expect(declared.length, greaterThan(100));
  });

  test('every provider follows the database, is reset, or is ruled on', () {
    final unruled = <String>[];
    for (final d in declared) {
      if (d.type.startsWith('StreamProvider')) continue;
      if (d.body.contains('rereadOnDatabaseWrites(ref)')) continue;
      if (resetNames.contains(d.name)) continue;
      if (_ruled.containsKey(d.name)) continue;
      unruled.add('${d.name} (${d.type}, ${d.file})');
    }
    expect(
      unruled,
      isEmpty,
      reason:
          'A restore merges into the live database. Each of these must call '
          'rereadOnDatabaseWrites(ref), go into storedDataResets, or be '
          'ruled on in this test with the reason it holds no stored data.',
    );
  });

  test('a one-shot read never hides behind a ruling', () {
    // A FutureProvider is a one-shot read. Only those that read no stored
    // data may be ruled on; the rest must follow the database.
    const notStoredData = {
      'bootstrapProvider',
      'appVersionProvider',
      'nanoStatusProvider',
      'cloudApiConfigProvider',
      'syncSecretProvider',
      'savedSearchesProvider',
    };
    final ruledFutures = [
      for (final d in declared)
        if (d.type.startsWith('FutureProvider') && _ruled.containsKey(d.name))
          d.name,
    ];
    expect(ruledFutures.toSet(), notStoredData);
  });

  test('every entry in the list and the rulings is still declared', () {
    final names = declared.map((d) => d.name).toSet();
    expect(resetNames.difference(names), isEmpty);
    expect(_ruled.keys.toSet().difference(names), isEmpty);
    expect(resetNames.contains(null), isFalse);
  });

  test('the reset ends every screen Undo the screens use', () {
    final used = <String>{};
    for (final f in _libFiles()) {
      for (final m in RegExp(
        r"screenUndoControllerProvider\('(\w+)'\)",
      ).allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used, isNotEmpty);
    expect(undoScreens.toSet(), used);
  });

  test('no Undo has an onCommit, so ending one writes nothing', () {
    // forgetCachedData ends each offer with dismiss(), which runs the
    // offer's onCommit. One that wrote would then write during a restore.
    final hits = <String>[];
    for (final f in _libFiles()) {
      final lines = _code(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('onCommit:')) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });

  test('every screen that starts a restore or an import resets after it', () {
    // Each file that calls an import entry point, and what it does after.
    const resetsItself = {
      'lib/features/backup/presentation/photo_restore_flow.dart',
      'lib/features/reports/presentation/screens/reports_screen.dart',
      'lib/features/settings/presentation/screens/settings_screen.dart',
    };
    const ruled = {
      // The encrypted backup: its restore hook resets (backup_wiring.dart).
      // The WebDAV restore goes through it too (webdav_backup_flow.dart).
      'lib/services/backup/still_life_backup_serializer.dart',
      // Does the import for reports_screen.dart, which resets.
      'lib/features/reports/presentation/controllers/export_controller.dart',
      // LAN sync: last-writer-wins, and the one-shot reads follow it. An
      // Undo after a sync is the household's own later choice, so it stays.
      'lib/services/sync/merge_engine.dart',
    };
    final callers = <String>{};
    final entry = RegExp(r'\.(importFromJson|guardedImport|importJson)\(');
    for (final f in _libFiles()) {
      if (entry.hasMatch(_code(f.readAsStringSync()))) {
        callers.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(callers, {...resetsItself, ...ruled});
    for (final path in resetsItself) {
      expect(
        _code(File(path).readAsStringSync()),
        contains('forgetCachedData(container.invalidate, container.read)'),
        reason: '$path must reset after its import',
      );
    }
    expect(
      _code(File('lib/features/backup/backup_wiring.dart').readAsStringSync()),
      contains('forgetCachedData(ref.invalidate, ref.read)'),
    );
  });
}
