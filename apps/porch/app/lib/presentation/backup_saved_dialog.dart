// After every backup: say plainly where the file is and why that is not
// enough, and offer the share sheet so a copy can live somewhere that
// survives uninstall. Shared by onboarding and Settings. Also the 6 backup
// words, shown wherever the 12 recovery words are.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Said beside the app's own backup: Android's backup to Google is the phone
/// owner's option and is separate from this encrypted file.
const androidBackupNote =
    'Android may also back up this app’s data to Google, if the phone’s '
    'owner allows it in Android settings. The encrypted backup here is '
    'the private choice.';

/// Said with the 6 backup words, wherever they are shown.
const backupWordsNote =
    'These 6 words unlock a backup file, if you make one. Porch picked '
    'them for you. Write them down with your 12 words. Alone they open '
    'nothing, but with any backup file they bring back your identity and '
    'every group. They can’t be changed, so keep them apart from your '
    'backup files.';

/// The 6 backup words as numbered chips under their heading and note.
/// Shown beside the 12 recovery words, in onboarding and in Settings.
class BackupWordsBlock extends StatelessWidget {
  final List<String> words;
  const BackupWordsBlock(this.words, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Your 6 backup words',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(backupWordsNote),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                Chip(label: Text('${i + 1}. ${words[i]}')),
            ],
          ),
        ],
      );
}

/// The backup dialog → saveBackup → Backup saved dialog. Used by Settings
/// and by Home's fresh-backup offer, so both behave identically. There is
/// nothing to type: the 6 backup words lock the file.
Future<void> runBackupFlow(BuildContext context, WidgetRef ref) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Encrypted backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Restores your identity AND groups on a new '
              'phone. The file is ciphertext, locked by your 6 backup '
              'words.'),
          const SizedBox(height: 8),
          Text(androidBackupNote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Create backup'),
        ),
      ],
    ),
  );
  if (go != true) return;
  final saved = await ref.read(actionsProvider).saveBackup();
  if (!context.mounted) return;
  await showBackupSavedDialog(context, ref, saved);
}

Future<void> showBackupSavedDialog(
    BuildContext context, WidgetRef ref, SavedBackup saved) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Backup saved'),
      content: const SingleChildScrollView(
        child: Text(
          'Porch saved your backup in its own storage on this device. That '
          'copy is deleted if you uninstall Porch or lose the phone, so '
          'share or save a copy '
          'somewhere that lasts: your files, a drive you trust, another '
          'device. It is ciphertext; only your 6 backup words open it.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: () => ref.read(actionsProvider).shareBackup(saved.blob),
          child: const Text('Share / save backup file'),
        ),
      ],
    ),
  );
}
