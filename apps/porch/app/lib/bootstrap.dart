// bootstrap — the production wiring (§2 module map: DI of ports →
// providers). This is the ONE place where platform adapters meet the
// Riverpod seams; tests override the exact same providers with fakes, so
// what the suite exercises is what ships. This file is platform glue and
// cannot run on the host VM — everything with logic lives behind the
// providers and IS host-tested.
//
// It builds on both device and web: the state store, backup sink, and relay
// transport are chosen by conditional imports inside the data layer, and the
// one web-only guard (path_provider has no web implementation) lives here
// behind [kIsWeb]. On web the persistent stores use browser storage — a real
// downgrade the web-preview notice owns.
//
// No keystore read here can stop the app from starting. The state key and
// the saved relay URL are read under the root gate (launchReadsProvider,
// wired by launchWiring), so a keystore that refuses at launch is shown with
// Try again. The theme is read here for the first frame, and a refusal opens
// in the default theme (readLaunchTheme). Everything here runs under
// LaunchGuard (main.dart), so a failure in libsodium or the documents folder
// is shown with Try again, never a blank screen.
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import 'backup_folder_adapter.dart';
import 'backup_share_adapter.dart';
import 'data/api_client.dart';
import 'data/backup_sink.dart';
import 'data/key_store.dart';
import 'data/relay_config.dart';
import 'data/secure_storage_adapter.dart';
import 'data/state_store.dart';
import 'data/theme_store.dart';
import 'move/move_page.dart';
import 'presentation/app.dart';
import 'presentation/providers.dart';

Future<Widget> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sodium = await SodiumSumoInit.init();
  final secretStore = FlutterSecureStorageSecretStore();
  final keyStore = PorchKeyStore(secretStore);
  final relayConfig = RelayConfigStore(secretStore);
  // Read before runApp so the first frame is already in the chosen theme.
  final themeStore = ThemePreferenceStore(secretStore);
  final theme = await readLaunchTheme(themeStore);

  // path_provider has no web implementation; the web state store + backup sink
  // ignore the directory (they use browser storage), so the call is skipped on
  // web and the sentinel path is never touched there.
  final docsPath =
      kIsWeb ? '' : (await getApplicationDocumentsDirectory()).path;
  // Backup files go where no automatic backup takes them (backupFolderFor):
  // they leave the phone only when the person shares one.
  final backupFolder = kIsWeb
      ? (path: '', exclude: null)
      : backupFolderFor(defaultTargetPlatform.name.toLowerCase(),
          applicationSupport: (await getApplicationSupportDirectory()).path);
  // The share sheet's copies of backup files land here (share_plus writes
  // each one under the temporary folder); Start over deletes them too.
  final sharedCopiesRoot =
      kIsWeb ? null : (await getTemporaryDirectory()).path;

  final overrides = <Override>[
    sodiumProvider.overrideWithValue(sodium),
    // The effective relay URL comes from the launch reads (launchWiring).
    // The client reads the endpoint holder live, so a settings change takes
    // effect without rebuilding the client (see relay_config.dart).
    relayProvider.overrideWith((ref) {
      final endpoint = ref.watch(relayEndpointProvider);
      return HttpRelayApi(
        baseUrl: endpoint.url,
        liveBaseUrl: () => endpoint.url,
      );
    }),
    relayConfigStoreProvider.overrideWithValue(relayConfig),
    themeStoreProvider.overrideWithValue(themeStore),
    initialThemeProvider.overrideWithValue(theme),
    keyStoreProvider.overrideWithValue(keyStore),
    ...launchWiring(
      openStateStore: (stateKey) => createPersistentStateStore(
        sodium,
        directory: docsPath,
        stateKey: stateKey,
      ),
    ),
    backupSinkProvider.overrideWithValue(createBackupSink(
        directory: backupFolder.path,
        excludeFromBackup: backupFolder.exclude,
        sharedCopiesRoot: sharedCopiesRoot)),
    backupShareProvider.overrideWithValue(const SharePlusBackupShare()),
    // widgetMirror stays Noop until W5 wires home_widget (§5.3(e));
    // localNotifier stays Noop until its platform adapter lands (the
    // notification DIFF logic is real and tested);
    // pushPort stays NoopPush by design for all of v1 (§1.3).
  ];
  return porchProviderScope(overrides: overrides, child: const PorchApp());
}

/// The move page build (OH_MOVE_PAGE=true, lib/move/move_page.dart): the
/// old web address's identity and groups, read and never written. The state
/// key is read, never made, so a browser with no Porch makes nothing.
Future<Widget> bootstrapMovePage() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sodium = await SodiumSumoInit.init();
  final keyStore = PorchKeyStore(FlutterSecureStorageSecretStore());
  return MovePageApp(
    reader: PorchMoveReader(
      sodium: sodium,
      keys: keyStore,
      openStore: () async {
        final stateKey = await keyStore.readStateKey();
        if (stateKey == null) return null;
        return createPersistentStateStore(sodium,
            directory: '', stateKey: stateKey);
      },
    ),
    share: const SharePlusBackupShare(),
  );
}
