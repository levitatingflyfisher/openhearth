import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show secureKeyStoreProvider;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

// The web app moves from the shared old origin to its own address (owner
// ruling, 15 Nov 2026). Two web builds come from this code:
//   the new site:  flutter build web --release --base-href /
//   the move page: flutter build web --release --base-href /move/hatch/ \
//                    --dart-define=OH_MOVE_PAGE=true
// The move page lives at the old origin for good. It counts what is saved
// there and saves the app's own backup file; the new site opens that file.

/// True in the move page build (`--dart-define=OH_MOVE_PAGE=true`).
const ohMovePage = bool.fromEnvironment('OH_MOVE_PAGE');

/// The app's short name in the move page address.
const moveAppSlug = 'hatch';

/// The app's own address.
const moveNewAddress = 'hatch.familyflourishing.org';

/// The records the backup holds: every row of every table the serializer
/// dumps. Reads only.
Future<int> countBackupRecords(BackupSerializer serializer) async {
  final manifest = BackupEnvelope.describe(await serializer.dumpAll());
  return manifest.tableCounts.values.fold<int>(0, (sum, n) => sum + n);
}

/// How many records this browser holds. Watched only on the web.
final storedRecordCountProvider = FutureProvider.autoDispose<int>(
    (ref) => countBackupRecords(ref.watch(backupSerializerProvider)));

/// The app's own export, for the move page: a browser without recovery
/// words sets them up first, because the backup file is locked with them.
Future<void> moveExport(BuildContext context, WidgetRef ref) async {
  const flow = BackupFlow();
  final keys = ref.read(secureKeyStoreProvider);
  if (await keys.readMnemonic() == null) {
    if (!context.mounted) return;
    await flow.runSeedSetup(context, ref);
    if (!context.mounted || await keys.readMnemonic() == null) return;
  }
  if (!context.mounted) return;
  await flow.runExport(context, ref);
}

/// The whole app in the move page build: [OhMoveDataScreen] and nothing
/// else. It never builds the normal app, so nothing that runs at the
/// normal start (the backup freshness snapshot, the audio preload) runs
/// here.
class MovePageApp extends StatelessWidget {
  /// The backup wiring, the same overrides the normal app uses.
  final List<Override> overrides;
  final ThemeData theme;
  final ThemeData darkTheme;

  const MovePageApp({
    super.key,
    required this.overrides,
    required this.theme,
    required this.darkTheme,
  });

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          title: 'Hatch',
          theme: theme,
          darkTheme: darkTheme,
          home: Consumer(
            builder: (context, ref, _) => OhMoveDataScreen(
              appName: 'Hatch',
              newAddress: moveNewAddress,
              countRecords: () =>
                  countBackupRecords(ref.read(backupSerializerProvider)),
              onSaveBackup: (context) => moveExport(context, ref),
            ),
          ),
        ),
      );
}

/// [OhMovedHereOffer] for the first screen: on the web, while this browser
/// holds no records, it offers the way back to the old address and the
/// app's own import.
class MovedHereOfferSlot extends ConsumerWidget {
  /// Null follows the platform, or [debugOhMovedHereOfferOnWeb].
  final bool? onWeb;
  const MovedHereOfferSlot({super.key, this.onWeb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(onWeb ?? debugOhMovedHereOfferOnWeb ?? kIsWeb)) {
      return const SizedBox.shrink();
    }
    final empty = switch (ref.watch(storedRecordCountProvider)) {
      AsyncData(:final value) => value == 0,
      _ => false,
    };
    return OhMovedHereOffer(
      storeIsEmpty: empty,
      appSlug: moveAppSlug,
      onWeb: true,
      onImport: (context) async {
        await const BackupFlow().runRestore(context, ref);
        ref.invalidate(storedRecordCountProvider);
      },
    );
  }
}
