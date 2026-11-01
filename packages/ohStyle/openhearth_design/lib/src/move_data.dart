import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'move_link_stub.dart' if (dart.library.js_interop) 'move_link_web.dart';
import 'spacing.dart';

// Each web app that keeps private data moves from the shared old origin
// (levitatingflyfisher.github.io/<App>/) to its own address,
// <app>.familyflourishing.org (owner ruling, 15 Nov 2026). A browser keeps
// saved data per origin, so the new address starts empty. The move page
// stays at the old origin for good, in the landing site at /move/<app>/,
// and saves the app's own backup file; the new address opens that file.

/// The old origin. Every move page lives here, in the landing site.
const ohMovePageOrigin = 'https://levitatingflyfisher.github.io';

/// The move page for the app whose short name is [appSlug].
String ohMovePageUrl(String appSlug) => '$ohMovePageOrigin/move/$appSlug/';

/// The app's new home page, for a host such as
/// `stilllife.familyflourishing.org`.
String ohNewAddressUrl(String host) => 'https://$host/';

// ── The words (plain, curly apostrophes, no em dashes) ──────────────────────

String ohMoveTitle(String appName) => '$appName has moved';
String ohMoveLivesAt(String appName, String host) =>
    '$appName now lives at $host.';
String ohMoveFound(int records) => switch (records) {
      0 => 'We found no records saved in this browser.',
      1 => 'We found 1 record saved in this browser.',
      _ => 'We found $records records saved in this browser.',
    };
const ohMoveCounting = 'Counting your records…';
const ohMoveCountFailed =
    'We couldn’t count your records, but nothing was removed. You can still '
    'save a backup file.';
const ohMoveHow = '1. Save a backup file here. Your browser keeps it with '
    'your other downloads.\n'
    '2. Go to the new address.\n'
    '3. Open the backup file there.';
const ohMoveSaveLabel = 'Save a backup file';
const ohMoveNothingDeleted =
    'Nothing here is deleted. Your records stay here until you remove them.';
String ohMoveGoTo(String host) => 'Go to $host';

const ohMovedHereTitle = 'Used this app before at the old address?';
const ohMovedHereBody = '1. Go to the old address and save a backup file '
    'there.\n'
    '2. Come back here and open it.';
const ohMovedHereOldAddressLabel = 'Go to the old address';
const ohMovedHereImportLabel = 'Open a backup file';
const ohMovedHereDismissLabel = 'Not now';

// ── The move page ───────────────────────────────────────────────────────────

/// The whole move page: an app built with `OH_MOVE_PAGE=true` opens straight
/// to this and never to its normal home.
///
/// It reads and exports, and nothing else: its only calls are
/// [countRecords] (once), [onSaveBackup] (the app's own export, when the
/// button is pressed) and the link to the new address. It has no way to
/// write, so it deletes nothing.
class OhMoveDataScreen extends StatefulWidget {
  /// The name the family knows, such as "Still Life".
  final String appName;

  /// The new host, such as `stilllife.familyflourishing.org`.
  final String newAddress;

  /// How many records this browser holds for the app. Called once.
  final Future<int> Function() countRecords;

  /// The app's own export: it saves the backup file.
  final Future<void> Function(BuildContext context) onSaveBackup;

  /// Opens a link. Null opens a new browser tab; tests pass their own.
  final void Function(Uri uri)? onOpenLink;

  const OhMoveDataScreen({
    super.key,
    required this.appName,
    required this.newAddress,
    required this.countRecords,
    required this.onSaveBackup,
    this.onOpenLink,
  });

  @override
  State<OhMoveDataScreen> createState() => _OhMoveDataScreenState();
}

class _OhMoveDataScreenState extends State<OhMoveDataScreen> {
  late final Future<int> _count = widget.countRecords();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSaveBackup(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openNewAddress() => (widget.onOpenLink ?? ohOpenMoveLink)(
      Uri.parse(ohNewAddressUrl(widget.newAddress)));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: OhSpacing.md);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: OhSpacing.insetPage,
              children: [
                const SizedBox(height: OhSpacing.lg),
                Text(ohMoveTitle(widget.appName), style: text.headlineSmall),
                gap,
                SelectableText(
                    ohMoveLivesAt(widget.appName, widget.newAddress),
                    style: text.bodyLarge),
                gap,
                FutureBuilder<int>(
                  future: _count,
                  builder: (context, snap) => Text(
                    snap.hasError
                        ? ohMoveCountFailed
                        : snap.hasData
                            ? ohMoveFound(snap.data!)
                            : ohMoveCounting,
                    style: text.bodyLarge,
                  ),
                ),
                gap,
                Text(ohMoveHow, style: text.bodyLarge),
                const SizedBox(height: OhSpacing.lg),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.download),
                  label: const Text(ohMoveSaveLabel),
                ),
                gap,
                Text(ohMoveNothingDeleted, style: text.bodyMedium),
                const SizedBox(height: OhSpacing.lg),
                OutlinedButton.icon(
                  onPressed: _openNewAddress,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(ohMoveGoTo(widget.newAddress)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── The offer at the new address ────────────────────────────────────────────

/// Tests only: when set, the offer acts as on the web (true) or off it
/// (false) wherever `onWeb` is not passed. Reset it with
/// [debugResetOhMovedHereOffer] in tearDown.
bool? debugOhMovedHereOfferOnWeb;

// "Not now" lasts for this page load: one flag for the whole app, so the
// offer does not come back when its screen is built again. Nothing is
// stored, and the offer goes for good once the store holds data.
bool _dismissed = false;

/// Tests only: forgets "Not now" and clears [debugOhMovedHereOfferOnWeb].
void debugResetOhMovedHereOffer() {
  _dismissed = false;
  debugOhMovedHereOfferOnWeb = null;
}

/// A card for the app's first screen at its new address. It shows only on
/// the web and only while [storeIsEmpty] is true: a family that used the
/// app at the old address is sent to the move page there, and then opens
/// its backup file here with the app's own import.
class OhMovedHereOffer extends StatefulWidget {
  /// True while the app has no records in this browser.
  final bool storeIsEmpty;

  /// The app's short name in the move page address, such as `stilllife`.
  final String appSlug;

  /// The app's own import: it opens the backup file.
  final Future<void> Function(BuildContext context) onImport;

  /// Null follows the platform ([kIsWeb]), or [debugOhMovedHereOfferOnWeb]
  /// when a test sets it.
  final bool? onWeb;

  /// Opens a link. Null opens a new browser tab; tests pass their own.
  final void Function(Uri uri)? onOpenLink;

  const OhMovedHereOffer({
    super.key,
    required this.storeIsEmpty,
    required this.appSlug,
    required this.onImport,
    this.onWeb,
    this.onOpenLink,
  });

  @override
  State<OhMovedHereOffer> createState() => _OhMovedHereOfferState();
}

class _OhMovedHereOfferState extends State<OhMovedHereOffer> {
  @override
  Widget build(BuildContext context) {
    final web = widget.onWeb ?? debugOhMovedHereOfferOnWeb ?? kIsWeb;
    if (!web || !widget.storeIsEmpty || _dismissed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.all(OhSpacing.md),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: OhSpacing.insetMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ohMovedHereTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onSecondaryContainer)),
            const SizedBox(height: OhSpacing.sm),
            Text(ohMovedHereBody,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSecondaryContainer)),
            const SizedBox(height: OhSpacing.sm),
            Wrap(
              spacing: OhSpacing.sm,
              runSpacing: OhSpacing.xs,
              children: [
                FilledButton(
                  onPressed: () => widget.onImport(context),
                  child: const Text(ohMovedHereImportLabel),
                ),
                OutlinedButton(
                  onPressed: () => (widget.onOpenLink ?? ohOpenMoveLink)(
                      Uri.parse(ohMovePageUrl(widget.appSlug))),
                  child: const Text(ohMovedHereOldAddressLabel),
                ),
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Text(ohMovedHereDismissLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
