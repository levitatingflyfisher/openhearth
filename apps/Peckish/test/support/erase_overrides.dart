import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/sync/data/lan_sync_server.dart';
import 'package:peckish/features/sync/data/sync_secret_store.dart';
import 'package:peckish/features/sync/presentation/sync_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An API key store in memory. Tests put made-up values in it, never a real
/// key.
class MemoryKeyStore implements KeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? v) async => value = v;
}

/// Stands in for the LAN server: says whether it is serving, binds nothing.
class FakeLanSyncServer implements LanSyncServer {
  @override
  bool isRunning = false;

  @override
  int get port => kSyncPort;

  @override
  Future<void> start() async => isRunning = true;

  @override
  Future<void> stop() async => isRunning = false;
}

/// Everything "Erase all data" and the restore hook touch, in memory, so
/// neither waits on a platform channel. The stores are fields so a test can
/// fill them first and look at them after.
class EraseHarness {
  EraseHarness(this.db, this.prefs, {RecipeDraftStore? drafts})
      : drafts = drafts ?? MemoryRecipeDraftStore();

  final AppDatabase db;
  final SharedPreferences prefs;
  final keys = MemoryKeyStore();
  final stove = InMemoryStoveSecretStore();
  final sync = InMemorySyncSecretStore();
  final server = FakeLanSyncServer();
  final RecipeDraftStore drafts;

  List<Override> get overrides => [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiKeyStoreProvider.overrideWithValue(keys),
        stoveSecretStoreProvider.overrideWithValue(stove),
        syncSecretStoreProvider.overrideWithValue(sync),
        lanSyncServerProvider.overrideWithValue(server),
        recipeDraftStoreProvider.overrideWithValue(drafts),
      ];
}
