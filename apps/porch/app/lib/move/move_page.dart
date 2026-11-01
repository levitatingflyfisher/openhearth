import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sodium/sodium_sumo.dart' show SodiumSumo;

import '../data/backup_share.dart';
import '../data/backup_sink.dart' show backupStamp;
import '../data/key_store.dart';
import '../data/porch_state.dart';
import '../data/state_store.dart';
import '../domain/domain.dart';

// The web app moves from the shared old origin to its own address (owner
// ruling, 15 Nov 2026). Two web builds come from this code:
//   the new site:  flutter build web --release --base-href /
//   the move page: flutter build web --release --base-href /move/porch/ \
//                    --dart-define=OH_MOVE_PAGE=true
// The move page lives at the old origin for good. It reads the identity
// and the groups there and hands over the app's own sealed backup file;
// the new site restores it from the file's text and the 6 backup words.

/// True in the move page build (`--dart-define=OH_MOVE_PAGE=true`).
const ohMovePage = bool.fromEnvironment('OH_MOVE_PAGE');

/// The app's short name in the move page address.
const moveAppSlug = 'porch';

/// The app's own address.
const moveNewAddress = 'porch.familyflourishing.org';

/// Said when the browser holds no Porch identity.
const moveNothingToSave =
    'There’s no Porch identity in this browser, so there’s nothing to save.';

/// Said after the file is handed over.
const moveSavedNote =
    'Open this file at the new address with your 6 backup words.';

/// Reads what the old address holds and seals it, writing nothing: no
/// state key is made, nothing goes to the backup sink, and no setting
/// changes. That is the difference from the app's own `saveBackup`.
class PorchMoveReader {
  final SodiumSumo sodium;
  final PorchKeyStore keys;

  /// The state store, or null when this browser never made one.
  final Future<StateStore?> Function() openStore;

  /// Argon2id costs; null is the app's default (MODERATE).
  final ({int? ops, int? mem}) limits;

  const PorchMoveReader({
    required this.sodium,
    required this.keys,
    required this.openStore,
    this.limits = (ops: null, mem: null),
  });

  Future<PorchState?> _state() async => (await openStore())?.load();

  /// The identity and each group it holds; 0 with no identity.
  Future<int> countRecords() async {
    if (await keys.readEntropy() == null) return 0;
    return 1 + ((await _state())?.groups.length ?? 0);
  }

  /// The backup file, sealed under the 6 backup words exactly as the app
  /// seals it, or null with no identity.
  Future<Uint8List?> seal() async {
    final entropy = await keys.readEntropy();
    if (entropy == null) return null;
    final state = await _state() ?? PorchState.initial();
    return sealBackup(
      sodium,
      entropy: entropy,
      stateSnapshot: state.toJson(),
      opsLimit: limits.ops,
      memLimit: limits.mem,
    );
  }
}

/// The whole app in the move page build: [OhMoveDataScreen] and nothing
/// else. It never builds the normal app, so nothing that runs at the
/// normal start (the state key, the relay, sync) runs here.
class MovePageApp extends StatelessWidget {
  final PorchMoveReader reader;
  final BackupShare share;

  const MovePageApp({super.key, required this.reader, required this.share});

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final blob = await reader.seal();
    if (blob == null) {
      messenger.showSnackBar(const SnackBar(content: Text(moveNothingToSave)));
      return;
    }
    await share.share(blob,
        fileName: 'porch-${backupStamp(DateTime.now().toUtc())}.porchbackup');
    messenger.showSnackBar(const SnackBar(content: Text(moveSavedNote)));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Porch',
        debugShowCheckedModeBanner: false,
        theme: OhTheme.light(),
        darkTheme: OhTheme.hearthDark(),
        home: OhMoveDataScreen(
          appName: 'Porch',
          newAddress: moveNewAddress,
          countRecords: reader.countRecords,
          onSaveBackup: _save,
        ),
      );
}

/// [OhMovedHereOffer] for the first screen: on the web, while this browser
/// holds no identity, it offers the way back to the old address and the
/// app's own restore from a backup file. Off the web it draws nothing.
class MovedHereOfferSlot extends StatelessWidget {
  final bool storeIsEmpty;

  /// Opens the app's own restore from a backup file.
  final VoidCallback onImport;

  /// Null follows the platform, or [debugOhMovedHereOfferOnWeb].
  final bool? onWeb;

  const MovedHereOfferSlot({
    super.key,
    required this.storeIsEmpty,
    required this.onImport,
    this.onWeb,
  });

  @override
  Widget build(BuildContext context) {
    if (!(onWeb ?? debugOhMovedHereOfferOnWeb ?? kIsWeb)) {
      return const SizedBox.shrink();
    }
    return OhMovedHereOffer(
      storeIsEmpty: storeIsEmpty,
      appSlug: moveAppSlug,
      onWeb: true,
      onImport: (_) async => onImport(),
    );
  }
}
