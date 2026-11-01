import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../../app/stored_data_caches.dart';
import '../../../core/providers.dart';
import '../../../core/theme/theme_preference.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

/// Settings — theme picker, About Mantle blurb, data-reset affordance.
///
/// Theme: follow the phone (the default), Light, Dark, or Night. The first
/// three are also in every primary screen's app bar; Night, the neutral
/// low-light theme, is the extra choice that lives only here.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// The Undo for Clear all data. It has no timer: it lasts until the
  /// person taps Undo or Dismiss, leaves Settings, or a restore replaces the
  /// data, and after that the safety copy is still in Previous backups.
  OhUndoController get _undo => ref.read(clearAllDataUndoProvider);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefAsync = ref.watch(themePreferenceProvider);
    final currentPref = prefAsync.value ?? ThemePreference.system;
    // Watched so the Undo lives exactly as long as Settings.
    final undo = ref.watch(clearAllDataUndoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      bottomNavigationBar: OhUndoBar(controller: undo),
      body: OhPage(
        padding: EdgeInsets.zero,
        child: ListView(
          padding: OhSpacing.insetPage,
          children: [
            const SizedBox(height: OhSpacing.md),

            // ── Theme section ─────────────────────────────────────────────────
            Text(
              'Appearance',
              key: const Key('settings-appearance-heading'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.sm),

            for (final pref in ThemePreference.values)
              _ThemeOption(
                key: Key('settings-theme-${pref.name}'),
                pref: pref,
                selected: currentPref == pref,
                onTap: () async {
                  await setThemePreference(pref);
                  ref.invalidate(themePreferenceProvider);
                },
              ),

            const SizedBox(height: OhSpacing.xl),
            const Divider(),
            const SizedBox(height: OhSpacing.lg),

            // ── About section ─────────────────────────────────────────────────
            Text(
              'About Mantle',
              key: const Key('settings-about-heading'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.sm),
            Text(
              'Mantle helps households discover the aesthetic thread that runs through their home, not by expertise but by noticing what they’re already drawn to.\n\n'
              'No account required. Mantle itself sends nothing anywhere. Your data stays on this phone unless you export it or Android backs it up for you; see Backup below.\n\n'
              'Part of the OpenHearth family of tools for domestic life.',
              key: const Key('settings-about-body'),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'v1.0 · MIT license',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.md),
            // The fleet's one line naming who publishes the app.
            const OhPublisherLine(),

            const SizedBox(height: OhSpacing.xl),
            const Divider(),
            const SizedBox(height: OhSpacing.lg),

            // ── Data reset section ────────────────────────────────────────────
            Text(
              'Data',
              key: const Key('settings-data-heading'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.sm),
            // Names exactly what goes and what stays; _wipe is the truth.
            Text(
              'Deletes the household members, rounds, charters, and solo and '
              'tutor progress on this device. Keeps only the theme and the '
              'backup set-up (recovery words and Previous backups). If backup '
              'is set up, a safety copy goes into Previous backups first, so '
              'you can bring it back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.md),
            OutlinedButton(
              key: const Key('settings-reset-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              onPressed: _clearAll,
              child: const Text('Clear all data'),
            ),

            const SizedBox(height: OhSpacing.lg),

            // ── Encrypted backup ──────────────────────────────────────────────
            // The shared sanctuary section: seed-phrase setup, verified export,
            // preview-before-restore, the snapshot vault, and plain-JSON export.
            // Brings its own divider + header; copy comes from
            // sanctuaryBackupConfigProvider (wired in main.dart).
            Text(
              'Android may also back up this app’s data to Google, if the '
              'phone’s owner allows it in Android settings. The encrypted '
              'backup here is the private choice.',
              key: const Key('settings-google-backup-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: OhSpacing.md),
            const BackupSettingsSection(),

            const SizedBox(height: OhSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// Clear all data, per the fleet delete ruling: pressing the button is
  /// already deliberate, so when a safety copy can be taken it clears at
  /// once and offers an Undo that never expires. Without backup there is no
  /// way back, so it asks first and says so. If the copy fails, nothing is
  /// cleared.
  Future<void> _clearAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final backup = ref.read(backupControllerProvider.notifier);
    final snap = await backup.snapshotBeforeWipe();
    if (!mounted) return;

    switch (snap.outcome) {
      case PreWipeOutcome.failed:
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Couldn’t make a safety copy, so nothing was cleared.'),
        ));
      case PreWipeOutcome.noKey:
        final go = await showOhConfirm(
          context,
          title: 'Clear all data for good?',
          message: 'Backup isn’t set up, so there is no copy to bring '
              'it back. The household members, rounds, charters, and solo and '
              'tutor progress will be gone. The theme stays. You can set up '
              'backup or export first, below.',
          confirmLabel: 'Clear all data',
          destructive: true,
        );
        if (!go || !mounted) return;
        await _wipe();
        messenger.showSnackBar(
            const SnackBar(
                content: Text('Your data is cleared. The theme is kept.')));
      case PreWipeOutcome.taken:
        await _wipe();
        final entry = snap.entry!;
        _undo.show(
          message: 'Your data is cleared. A safety copy is in Previous '
              'backups.',
          onUndo: () => _restoreSafetyCopy(entry.id, messenger),
        );
    }
  }

  Future<void> _restoreSafetyCopy(
      String entryId, ScaffoldMessengerState messenger) async {
    final blob = await ref.read(backupVaultProvider).read(entryId);
    final outcome = blob == null
        ? RestoreOutcome.failed
        : await ref
            .read(backupControllerProvider.notifier)
            .restoreFromBlob(blob);
    messenger.showSnackBar(SnackBar(
      content: Text(outcome == RestoreOutcome.success
          ? 'Your data is back.'
          : 'Couldn’t bring it back here. The safety copy is still in '
              'Previous backups.'),
    ));
  }

  /// Delete rows from every table, then run the same reset as a restore, so
  /// Home (alive under Settings) shows nothing that is gone and any earlier
  /// Undo ends. The schema, the backup vault and the recovery words stay, so
  /// the safety copy can still be opened.
  Future<void> _wipe() async {
    final db = ref.read(databaseProvider);
    // Taken before the await: Home needs the reset even if Settings has
    // closed by the time the delete is done.
    final container = ProviderScope.containerOf(context, listen: false);
    await db.transaction(() async {
      await db.delete(db.members).go();
      await db.delete(db.rounds).go();
      await db.delete(db.rankingSessions).go();
      await db.delete(db.rankingMatches).go();
      await db.delete(db.charters).go();
      await db.delete(db.readProgress).go();
      await db.delete(db.spotProgress).go();
      await db.delete(db.discoveredThroughlines).go();
    });
    forgetCachedData(container.invalidate, undo: mounted ? _undo : null);
  }
}

// ── _ThemeOption ──────────────────────────────────────────────────────────────

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    super.key,
    required this.pref,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference pref;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OhSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OhSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              key: Key('settings-theme-radio-${pref.name}'),
              width: 24,
              height: 24,
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: OhSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pref.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    pref.hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
