import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lilt/app/read_failure.dart';
import 'package:lilt/app/stored_data_caches.dart';
import 'package:lilt/core/providers/repository_providers.dart';
import 'package:lilt/core/providers/retry_policy.dart';
import 'package:lilt/core/providers/settings_providers.dart';
import 'package:lilt/domain/models/name_session.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:lilt/app/theme_toggle.dart';

/// Sessions in Recently cleared (soft-deleted by Clear all sessions).
final clearedSessionsProvider = FutureProvider<List<NameSession>>(
  (ref) => ref.watch(sessionRepositoryProvider).clearedSessions(),
  retry: noAutoRetry,
);

/// The Undo offered after Clear all sessions. A provider, not a field of
/// the screen, so a restore can reach a pending offer. It is autoDispose,
/// so it still lives only as long as the Settings screen.
final clearSessionsUndoProvider =
    Provider.autoDispose<OhUndoController>((ref) {
  final undo = OhUndoController();
  ref.onDispose(undo.dispose);
  return undo;
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  OhUndoController get _undo => ref.read(clearSessionsUndoProvider);

  @override
  Widget build(BuildContext context) {
    final undo = ref.watch(clearSessionsUndoProvider);
    final clearedAsync = ref.watch(clearedSessionsProvider);
    final cleared = clearedAsync.value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [OhBarActions(children: [LiltThemeToggle()])],
      ),
      bottomSheet: OhUndoBar(controller: undo),
      body: OhPage(
        padding: EdgeInsets.zero,
        child: ListView(
          children: [
            // A statement, not a setting: the couple guard needs every session
            // locked, so there is nothing to switch off (ADR-0004).
            const ListTile(
              title: Text('Peeking prevention'),
              subtitle: Text(
                'Always on. Once you pass the phone to your partner, neither '
                'of you can open results until you’ve both finished.',
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Ranking Confidence'),
              subtitle: Text(
                'Higher = more comparisons but more stable results. '
                'Current: ${(ref.watch(convergenceTauProvider) * 100).toStringAsFixed(0)}%',
              ),
            ),
            Slider(
              value: ref.watch(convergenceTauProvider),
              min: 0.80,
              max: 0.99,
              divisions: 19,
              label:
                  '${(ref.watch(convergenceTauProvider) * 100).toStringAsFixed(0)}%',
              onChanged: (val) {
                final prefs = ref.read(sharedPreferencesProvider);
                prefs.setDouble('convergence_tau', val);
                ref.invalidate(convergenceTauProvider);
              },
            ),
            const Divider(),
            // Deliberate, so it does not ask (fleet delete ruling): it clears
            // at once, softly, and the Undo below never times out. What
            // survives is said before the tap, as the old dialog did.
            ListTile(
              title: const Text('Clear all sessions'),
              subtitle: const Text(
                'Removes every session, finished or not. Your shortlist is '
                'kept, and cleared sessions can be restored below.',
              ),
              trailing: const Icon(Icons.delete_outline),
              onTap: _clearSessions,
            ),
            // A failed read is said, never drawn as nothing cleared: this
            // list is the way to restore them.
            if (clearedAsync.hasError && !clearedAsync.hasValue)
              InlineReadError(
                title: 'Couldn’t read your cleared sessions',
                onRetry: () => ref.invalidate(clearedSessionsProvider),
              )
            else if (cleared.isNotEmpty)
              _RecentlyCleared(
                sessions: cleared,
                onRestore: _restore,
                onDeleteForever: () => _deleteForever(cleared.length),
              ),
            const BackupSettingsSection(),
            // Android's own backup to Google is the phone owner's option, so
            // say so beside our backup.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Android may also back up this app’s data to Google, if the '
                'phone’s owner allows it in Android settings. The encrypted '
                'backup here is the private choice.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(),
            const ListTile(title: Text('Version'), trailing: Text('1.0.0')),
            // The fleet's one line naming who publishes the app. Lilt has no
            // About screen, so it sits at the foot of Settings.
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OhPublisherLine(),
            ),
            // Room for the Undo bar so it never covers the last row.
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }

  /// After cleared rows come back (Restore on a row, or the Undo): reload
  /// every cached read. A pending Undo stays, as its rows still exist.
  void _refresh() => refreshStoredDataCaches(ref.invalidate);

  /// After an erase: the same reset a restore runs, so no cached copy of
  /// the cleared or deleted sessions stays, and an older Undo ends.
  void _forget() => forgetCachedData(ref.invalidate, undo: _undo);

  Future<void> _clearSessions() async {
    final repo = ref.read(sessionRepositoryProvider);
    final ids = await repo.clearAllSessions();
    if (!mounted) return;
    _forget();
    if (ids.isEmpty) return;
    _undo.show(
      message: ids.length == 1
          ? 'Cleared 1 session'
          : 'Cleared ${ids.length} sessions',
      onUndo: () async {
        await repo.restoreSessions(ids);
        if (mounted) _refresh();
      },
    );
  }

  Future<void> _restore(NameSession s) async {
    await ref.read(sessionRepositoryProvider).restoreSessions([s.id]);
    if (mounted) _refresh();
  }

  Future<void> _deleteForever(int count) async {
    final label = count == 1 ? 'Delete 1 session' : 'Delete $count sessions';
    final ok = await showOhConfirm(
      context,
      title: 'Delete cleared sessions for good?',
      message:
          'Their comparisons go too, and there is no way back. Your '
          'shortlist is kept.',
      confirmLabel: label,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(sessionRepositoryProvider).deleteClearedForever();
    if (mounted) _forget();
  }
}

/// The lasting way back from Clear all sessions: one row per cleared
/// session with Restore, then a confirmed Delete forever.
class _RecentlyCleared extends StatelessWidget {
  final List<NameSession> sessions;
  final ValueChanged<NameSession> onRestore;
  final VoidCallback onDeleteForever;

  const _RecentlyCleared({
    required this.sessions,
    required this.onRestore,
    required this.onDeleteForever,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Recently cleared',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final s in sessions)
          ListTile(
            title: Text(s.participantLabel ?? 'Solo'),
            subtitle: Text(
              '${s.poolSize} names · '
              '${s.isComplete ? 'Complete' : 'In progress'}',
            ),
            trailing: TextButton(
              onPressed: () => onRestore(s),
              child: const Text('Restore'),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Delete forever'),
              onPressed: onDeleteForever,
            ),
          ),
        ),
      ],
    );
  }
}
