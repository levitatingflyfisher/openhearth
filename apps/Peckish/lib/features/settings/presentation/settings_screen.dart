import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/core/providers/shown_value.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/presentation/ai_settings_dialog.dart';
import 'package:peckish/features/barcode/data/barcode_db_download_service.dart';
import 'package:peckish/features/diary/presentation/targets_dialog.dart';
import 'package:peckish/features/settings/data/export_serializer.dart';
import 'package:peckish/features/settings/data/export_share.dart';
import 'package:peckish/features/settings/data/plain_export.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/theme_toggle_action.dart';

/// What "Erase all data" deletes and keeps, said once for both dialogs.
const _eraseDeletes = 'This deletes your Peckish data on this device, '
    'including the AI key and the household sync code. It keeps only the '
    'theme, the built-in food database, the offline barcode database and the '
    'downloaded AI model.';

/// Settings: appearance, encrypted backup, plaintext export, erase, About.
/// Calm and reversible throughout — every destructive action confirms first
/// and says exactly what it will do.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Appearance',
                  style: Theme.of(context).textTheme.titleMedium),
              // The same three choices as every tab's top bar.
              ListTile(
                leading: const Icon(Icons.contrast),
                title: const Text('Theme'),
                subtitle: Text((prefs.shownValue?.themeMode ??
                        OhThemeModePreference.defaultValue)
                    .label),
                trailing: const ThemeToggleAction(),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('Your day', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Daily targets'),
                subtitle: const Text(
                    'Optional numbers to aim for: a floor for protein, '
                    'a budget for the day.'),
                onTap: () => showTargetsDialog(context, ref),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.tips_and_updates_outlined),
                title: const Text('Round out your day'),
                subtitle: const Text(
                    'Ideas from your regulars to finish the day’s targets. '
                    'All math stays on this phone.'),
                value: prefs.shownValue?.suggestionsEnabled ?? true,
                onChanged: (on) => ref
                    .read(settingsRepositoryProvider)
                    .setSuggestionsEnabled(on),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('Your data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              // Encrypted .ohbk backup + restore (sanctuary_backup_ui).
              const BackupSettingsSection(),
              // Android's own backup is the phone owner's choice, and this
              // app cannot see it. Said here, beside the private option.
              const ListTile(
                leading: Icon(Icons.cloud_outlined),
                title: Text('Android backup to Google'),
                subtitle: Text(
                    'Android may also back up this app’s data to Google, if '
                    'the phone’s owner allows it in Android settings. The '
                    'encrypted backup here is the private choice.'),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Export data (plain JSON)'),
                subtitle:
                    const Text('A readable copy you own. Keep it anywhere.'),
                onTap: () async {
                  // Gathered through the same snapshot the encrypted backup
                  // uses (v0.1 exported an empty shell here).
                  final json =
                      await buildPlainExport(ref.read(appDatabaseProvider));
                  await shareExport(
                    fileName: exportFileName(DateTime.now()),
                    content: json,
                  );
                },
              ),
              // Web has no local slices (ADR-0010): the tile would promise a
              // phone-side answer the platform can't keep. The capability seam
              // answers for the platform; this screen never asks kIsWeb itself.
              if (localSlicesSupported)
                ListTile(
                  leading: const Icon(Icons.qr_code_2_outlined),
                  title: const Text('Offline barcode lookup'),
                  subtitle: const Text(
                      'Answer scans from this phone. Nothing leaves.'),
                  onTap: () => context.push('/barcode-db'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Erase all data'),
                // Names what stays: the words are the promise.
                subtitle: const Text('Deletes your data on this device. '
                    'Keeps the theme, the food databases and the '
                    'downloaded AI model.'),
                onTap: () async {
                  // With recovery words a verified safety copy goes into
                  // Previous backups first, so the dialog must not claim
                  // there is no way back; without them, it must say so.
                  // Read at the moment the dialog opens, not from whatever
                  // another screen left cached: a deep link to Settings
                  // has nothing else keeping this loaded.
                  bool hasWords;
                  try {
                    hasWords =
                        (await ref.read(backupSetupStatusProvider.future))
                            .hasWords;
                  } on Object {
                    hasWords = false;
                  }
                  if (!context.mounted) return;
                  // The one truly destructive act: urgency is colour, icon and
                  // word together (ohStyle colour language).
                  final confirmed = await showOhConfirm(
                    context,
                    title: 'Erase all data?',
                    // Says exactly what stays and what a restore brings
                    // back: the safety copy holds the household's records,
                    // not the AI key or the sync code.
                    message: hasWords
                        ? '$_eraseDeletes A safety copy is saved to Previous '
                            'backups first. Restoring it brings back your '
                            'diary, foods, meals, recipes, plan, groceries '
                            'and targets.'
                        : '$_eraseDeletes Backup is not set up, so there is '
                            'no copy to restore.',
                    confirmLabel: 'Erase all data',
                    destructive: true,
                  );
                  if (!confirmed || !context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final outcome = await eraseAfterSnapshot(
                    snapshot: () => ref
                        .read(backupControllerProvider.notifier)
                        .snapshotBeforeWipe(),
                    wipe: () => eraseAllData(ref),
                    promisedCopy: hasWords,
                  );
                  if (outcome == EraseOutcome.keptBecauseSnapshotFailed) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Couldn’t save a safety copy first, so '
                            'nothing was erased. Try again, or export your '
                            'data first.')));
                    return;
                  }
                  if (context.mounted) context.go('/');
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('Household', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('Household sync'),
                subtitle: const Text(
                    'One plan, one list, every device, encrypted, on your own '
                    'Wi-Fi. Diaries stay personal.'),
                onTap: () => context.push('/sync'),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('Intelligence',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('AI guesstimate'),
                subtitle: const Text(
                    'Off by default. Your own key or your own local server.'),
                onTap: () => showAiSettingsDialog(context, ref),
              ),
              const SizedBox(height: AppSpacing.lg),

              ListTile(
                leading: const Icon(Icons.wifi_off_outlined),
                title: const Text('What leaves your device'),
                subtitle: const Text(
                    'The whole network map on one screen. Most rows say '
                    '“nothing”.'),
                onTap: () => context.push('/privacy'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About Peckish'),
                onTap: () => context.push('/about'),
              ),
            ],
          )),
    );
  }
}
