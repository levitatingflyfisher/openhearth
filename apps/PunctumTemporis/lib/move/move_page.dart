import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../screens/backup_restore_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

// The web app moves from the shared old origin to its own address (owner
// ruling, 15 Nov 2026). Two web builds come from this code:
//   the new site:  flutter build web --release --base-href /
//   the move page: flutter build web --release --base-href /move/punctum/ \
//                    --dart-define=OH_MOVE_PAGE=true
// The move page lives at the old origin for good. It counts the clips saved
// there and opens the app's own backup; the new site restores that file.

/// True in the move page build (`--dart-define=OH_MOVE_PAGE=true`).
const ohMovePage = bool.fromEnvironment('OH_MOVE_PAGE');

/// The app's short name in the move page address.
const moveAppSlug = 'punctum';

/// The app's own address.
const moveNewAddress = 'punctum.familyflourishing.org';

/// The clips the journal holds: the family's records.
int storedClipCount(StorageService storage) =>
    storage.clips.values.fold<int>(0, (sum, day) => sum + day.length);

/// The whole app in the move page build: [OhMoveDataScreen] and nothing
/// else. main() opens [storage] read-only and never builds the normal app,
/// so nothing that runs at the normal start (folders, migration,
/// notifications, the freshness snapshot) runs here.
class MovePageApp extends StatelessWidget {
  final StorageService storage;
  const MovePageApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Punctum Temporis',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.buildTheme(
            Brightness.light, Color(storage.getAccentColor())),
        darkTheme:
            AppTheme.buildTheme(Brightness.dark, Color(storage.getAccentColor())),
        home: OhMoveDataScreen(
          appName: 'Punctum Temporis',
          newAddress: moveNewAddress,
          countRecords: () async => storedClipCount(storage),
          // The app's own backup, with nothing that restores: the backup
          // file is made and downloaded there.
          onSaveBackup: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  BackupRestoreScreen(storageService: storage, exportOnly: true),
            ),
          ),
        ),
      );
}

/// [OhMovedHereOffer] for the first screen: on the web, while this browser
/// holds no clips, it offers the way back to the old address and the app's
/// own restore. Off the web it draws nothing.
class MovedHereOfferSlot extends StatefulWidget {
  final StorageService storage;

  /// Null follows the platform, or [debugOhMovedHereOfferOnWeb].
  final bool? onWeb;

  const MovedHereOfferSlot({super.key, required this.storage, this.onWeb});

  @override
  State<MovedHereOfferSlot> createState() => _MovedHereOfferSlotState();
}

class _MovedHereOfferSlotState extends State<MovedHereOfferSlot> {
  // A restore or a first clip changes the count: build again.
  void _recount() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.storage.changes.addListener(_recount);
  }

  @override
  void dispose() {
    widget.storage.changes.removeListener(_recount);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.onWeb ?? debugOhMovedHereOfferOnWeb ?? kIsWeb)) {
      return const SizedBox.shrink();
    }
    return OhMovedHereOffer(
      storeIsEmpty: storedClipCount(widget.storage) == 0,
      appSlug: moveAppSlug,
      onWeb: true,
      onImport: (context) async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BackupRestoreScreen(storageService: widget.storage),
        ));
      },
    );
  }
}
