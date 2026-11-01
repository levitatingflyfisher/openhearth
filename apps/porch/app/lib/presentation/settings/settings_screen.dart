// Settings: profile (fans out E2EE), seed re-reveal, encrypted backup,
// notification opt-ins (ALL off by default, computed on-device),
// availability default, on-device stats, "What leaves your device", and
// "Start over with a new identity".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../data/relay_config.dart';
import '../../domain/domain.dart';
import '../backup_saved_dialog.dart';
import '../providers.dart';
import '../web_preview.dart';
import 'start_over_screen.dart';
import 'what_leaves_screen.dart';

/// Said when a relay address is refused: Porch talks to relays over https
/// only, so nothing on the way can read or change the traffic.
const httpsOnlyRelayNote = 'Not saved. Porch talks to a relay over https '
    'only. Check that the address starts with https://.';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _noteCtl;
  final TextEditingController _relayCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(porchStateProvider).value;
    _nameCtl = TextEditingController(text: state?.profile.displayName ?? '');
    _noteCtl = TextEditingController(text: state?.profile.contactNote ?? '');
    // The saved relay override lives behind an async store; load it once the
    // first frame is up and reflect it in the field.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await ref.read(actionsProvider).relayUrlSetting();
      if (mounted && saved != null) _relayCtl.text = saved;
    });
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _noteCtl.dispose();
    _relayCtl.dispose();
    super.dispose();
  }

  Future<void> _saveRelay() async {
    final saved = await ref.read(actionsProvider).setRelayUrl(_relayCtl.text);
    if (!mounted) return;
    setState(() {}); // refresh the "In effect" line
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved
            ? 'Relay saved. New syncs use it immediately.'
            : httpsOnlyRelayNote)));
  }

  Future<void> _saveProfile() async {
    final name = _nameCtl.text.trim();
    await ref.read(actionsProvider).updateProfile(
          displayName: name.isEmpty ? null : name,
          contactNote: _noteCtl.text.trim(),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved. It reaches your groups end-to-end '
            'encrypted on the next sync.')));
  }

  Future<void> _showWords() async {
    final actions = ref.read(actionsProvider);
    final words = await actions.recoveryWords();
    final backupWords = await actions.backupWords();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your 12 recovery words'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Chip(label: Text('${i + 1}. ${words[i]}')),
                ],
              ),
              const SizedBox(height: 24),
              BackupWordsBlock(backupWords),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _backup() => runBackupFlow(context, ref);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(porchStateProvider).value;
    final session = ref.watch(sessionProvider).value;
    if (state == null || session == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final stats =
        ref.read(metricsServiceProvider).compute(state.metrics);
    final myPk = session.identity.sign.publicKey;

    // Every friend across groups, deduped by key.
    final friends = <String, RosterEntry>{};
    for (final g in state.groups) {
      for (final m in g.roster.members) {
        if (!bytesEqual(m.signPk, myPk)) friends[b64(m.signPk)] = m;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', overflow: TextOverflow.ellipsis),
        actions: [
          OhThemeToggle(
            value: ref.watch(themeModeProvider),
            onChanged: (p) => ref.read(themeModeProvider.notifier).set(p),
          ),
        ],
      ),
      body: OhPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            const WebPreviewBanner(),
            Text('Profile', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtl,
              decoration: const InputDecoration(
                labelText: 'Contact note',
                helperText: 'How friends reach you, for example “Signal: @you”. '
                    'Travels end-to-end encrypted.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _saveProfile,
              child: const Text('Save profile'),
            ),
            const Divider(height: 32),
            Text('Relay server', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text('Porch needs a relay to carry presence between phones. '
                'Until you point it at one, it runs on this device only. Paste '
                'the URL of a relay you trust: yours, or one a friend runs.'),
            const SizedBox(height: 8),
            TextField(
              controller: _relayCtl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Relay URL',
                hintText: 'https://relay.example',
                helperText: isPlaceholderRelay(Uri.parse(defaultRelayUrl))
                    ? 'Leave blank and Porch stays on this phone only.'
                    : 'Leave blank to use the built-in relay.',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _saveRelay,
              child: const Text('Save relay URL'),
            ),
            const SizedBox(height: 8),
            Text(
                ref.read(actionsProvider).relayConfigured()
                    ? 'In effect: ${ref.read(actionsProvider).effectiveRelayUrlString()}'
                    : 'In effect: none, this phone only',
                style: theme.textTheme.bodySmall),
            const Divider(height: 32),
            Text('Recovery', style: theme.textTheme.labelLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Show recovery words'),
              subtitle: const Text('The 12 words that ARE your identity'),
              onTap: _showWords,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.save_outlined),
              title: const Text('Save encrypted backup'),
              subtitle: Text(state.settings.hasBackup
                  ? 'Locked file: identity + groups'
                  : 'Not backed up on this phone yet'),
              onTap: _backup,
            ),
            Text(androidBackupNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            // Restoring replaces an identity, so it lives on a new phone's
            // first screen, not here (no in-place identity swap is built).
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restore_outlined),
              title: Text('Restoring on a new phone'),
              subtitle: Text('On its first screen, choose “Restore an existing '
                  'identity”, then use your 12 words or paste this backup '
                  'file with your 6 backup words.'),
            ),
            const Divider(height: 32),
            Text('Notifications', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text('Off by default. Alerts are computed on this phone: '
                'the server never learns who you watch.'),
            for (final g in state.groups)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${g.name} (group)',
                    overflow: TextOverflow.ellipsis),
                value: state.notifyPrefs.perGroup[g.groupUuid] ?? false,
                onChanged: (on) => ref
                    .read(actionsProvider)
                    .setNotifyGroup(g.groupUuid, on),
              ),
            for (final e in friends.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    e.value.displayName.isEmpty
                        ? 'Friend'
                        : e.value.displayName,
                    overflow: TextOverflow.ellipsis),
                value: state.notifyPrefs.perFriend[e.key] ?? false,
                onChanged: (on) =>
                    ref.read(actionsProvider).setNotifyFriend(e.key, on),
              ),
            const Divider(height: 32),
            Text('Availability default', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (secs, label) in const [
                  (1800, '30 m'),
                  (3600, '1 h'),
                  (7200, '2 h'),
                  (14400, '4 h'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: state.settings.defaultExpiry == secs,
                    onSelected: (_) =>
                        ref.read(actionsProvider).setDefaultExpiry(secs),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Your Porch stats', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text('${stats.totalPublishes} taps total'),
            Text('Active on ${stats.daysActive} days'),
            Text('Back the same day on ${stats.sameDayReturnDays} of them'),
            const SizedBox(height: 4),
            Text('Computed on this phone. Never uploaded.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shield_outlined),
              title: const Text('What leaves your device'),
              subtitle: const Text('The honest inventory'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WhatLeavesScreen())),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restart_alt),
              title: const Text(startOverTitle),
              subtitle: const Text('Leave every group and forget this '
                  'identity on this phone'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const StartOverScreen())),
            ),
            const Divider(height: 32),
            Text('About', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            const Text('Porch is free software and never phones home.'),
            const SizedBox(height: 16),
            // The fleet's one line naming who publishes the app.
            const OhPublisherLine(),
          ],
        ),
      ),
    );
  }
}
