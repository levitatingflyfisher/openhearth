// Onboarding (§2 module map): age gate (13+) → SILENT keygen → 12-word
// reveal (and the 6 backup words) → optional backup → display name → "My Porch" auto-created.
//
// Honesty requirements carried in the copy, not a policy page:
// - keygen touches no server; there is no account to create;
// - the 12 words have no reset path, BY DESIGN (§1.6);
// - a bare-words restore is identity-only — groups come back from friends
//   (§3.1 step 8), and the flow says so before the user commits.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../domain/domain.dart';
import '../../move/move_page.dart';
import '../backup_saved_dialog.dart';
import '../providers.dart';
import '../error_line.dart';

enum _Step { age, restore, restoreBackup, words, backup, name }

class OnboardingFlow extends ConsumerStatefulWidget {
  /// True when an identity already exists (mid-onboarding relaunch or a
  /// just-restored seed): resume past the age gate and keygen.
  final bool hasIdentity;
  const OnboardingFlow({super.key, required this.hasIdentity});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late _Step _step = widget.hasIdentity ? _Step.words : _Step.age;
  // Cached: FutureBuilder must settle.
  Future<({List<String> words, List<String> backup})>? _wordsFuture;
  bool _busy = false;
  bool _restored = false;
  String? _error;

  /// An unexpected failure (keystore, storage, sodium): shown as a
  /// sentence through OhErrorState, the exception only behind Details.
  /// Errors count too: StateError and StateCorruptError extend Error, and
  /// an uncaught one would leave the person with no sentence at all.
  Object? _failure;
  StackTrace? _failureStack;
  final _restoreCtl = TextEditingController();
  final _backupTextCtl = TextEditingController();
  final _restoreWordsCtl = TextEditingController();
  final _nameCtl = TextEditingController();

  @override
  void dispose() {
    _restoreCtl.dispose();
    _backupTextCtl.dispose();
    _restoreWordsCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
      _failure = null;
    });
    try {
      await body();
    } on Object catch (e, st) {
      debugPrint('porch onboarding: $e');
      if (!mounted) return;
      setState(() {
        _failure = e;
        _failureStack = st;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createIdentity() => _run(() async {
        await ref.read(sessionProvider.notifier).createIdentity();
        setState(() => _step = _Step.words);
      });

  Future<void> _restore() => _run(() async {
        final words = _restoreCtl.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        try {
          final entropy = mnemonicToEntropy(words);
          await ref
              .read(sessionProvider.notifier)
              .createIdentity(entropy: entropy);
          setState(() {
            _restored = true;
            _step = _Step.name;
          });
        } on MnemonicException catch (e) {
          setState(() => _error = e.message);
        }
      });

  Future<void> _restoreBackup() => _run(() async {
        try {
          await ref.read(actionsProvider).restoreFromBackup(
              passphrase: _restoreWordsCtl.text,
              backupText: _backupTextCtl.text);
          // A backup taken before the name step has no name yet: finish
          // there. Otherwise the root gate flips straight to Home.
          if (mounted) setState(() => _step = _Step.name);
        } on BackupException catch (e) {
          setState(() => _error = _backupMessage(e));
        }
      });

  static String _backupMessage(BackupException e) => switch (e.message) {
        'not 6 backup words' =>
          'That is not 6 backup words. Type the 6 backup words you wrote '
              'down with your 12 words.',
        'wrong words or corrupted backup' =>
          'Those words do not open this backup: wrong words or corrupted '
              'backup. Check the 6 backup words and that you pasted the '
              'whole file.',
        'not a Porch backup blob' =>
          'This is not a Porch backup. Paste the whole contents of the '
              '.porchbackup file.',
        _ => 'This backup could not be read. Paste the whole file again.',
      };

  Future<void> _saveBackup() async {
    SavedBackup? saved;
    await _run(() async {
      saved = await ref.read(actionsProvider).saveBackup();
    });
    // Outside _run: the busy spinner must not keep animating behind the
    // dialog while the person decides whether to share.
    final s = saved;
    if (s == null || !mounted) return;
    await showBackupSavedDialog(context, ref, s);
    if (!mounted) return;
    setState(() => _step = _Step.name);
  }

  Future<({List<String> words, List<String> backup})> _readWords() async {
    final actions = ref.read(actionsProvider);
    return (
      words: await actions.recoveryWords(),
      backup: await actions.backupWords(),
    );
  }

  Future<void> _finish() => _run(() async {
        final name = _nameCtl.text.trim();
        if (name.isEmpty) {
          setState(() => _error = 'Pick a name your friends know.');
          return;
        }
        await ref
            .read(actionsProvider)
            .completeOnboarding(displayName: name);
        // RootGate flips to Home when the state carries the name.
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OhPage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              children: [
                ..._content(context),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ErrorLine(_error!),
                  ),
                if (_failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OhErrorState.fromError(_failure!,
                        stackTrace: _failureStack),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) => switch (_step) {
        _Step.age => _ageGate(context),
        _Step.restore => _restoreStep(context),
        _Step.restoreBackup => _restoreBackupStep(context),
        _Step.words => _wordsStep(context),
        _Step.backup => _backupStep(context),
        _Step.name => _nameStep(context),
      };

  List<Widget> _ageGate(BuildContext context) => [
        // On the web, an empty browser at the new address offers the way
        // back to the old one, and this app's restore from a backup file.
        MovedHereOfferSlot(
          storeIsEmpty: !widget.hasIdentity,
          onImport: () => setState(() {
            _error = null;
            _step = _Step.restoreBackup;
          }),
        ),
        const Icon(Icons.light_mode_outlined, size: 56),
        const SizedBox(height: 16),
        Text('Welcome to the porch',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'Porch is one button: tell your closest people you are around, '
          'and see when they are. No accounts, no feed, no tracking: '
          'your name and your groups live on this phone, end-to-end '
          'encrypted.',
        ),
        const SizedBox(height: 12),
        const Text('Porch is for ages thirteen and up.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _createIdentity,
          child: const Text("I’m 13 or older"),
        ),
        TextButton(
          onPressed:
              _busy ? null : () => setState(() => _step = _Step.restore),
          child: const Text('Restore an existing identity'),
        ),
      ];

  List<Widget> _restoreStep(BuildContext context) => [
        Text('Restore from your 12 words',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'Your 12 words rebuild your identity only. Groups are not stored '
          'on any server: friends will need to invite you again, or restore '
          'from a backup file to get groups back too.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _restoreCtl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Your 12 recovery words',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _restore,
          child: const Text('Restore'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _error = null;
                    _step = _Step.restoreBackup;
                  }),
          child: const Text('Restore from a backup file instead'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.age),
          child: const Text('Back'),
        ),
      ];

  List<Widget> _restoreBackupStep(BuildContext context) => [
        Text('Restore from a backup file',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'A backup file brings back your identity and the groups it held. '
          'Open the .porchbackup file in any text editor, copy everything '
          'in it, and paste it below. It is ciphertext; only your 6 backup '
          'words open it, here on this phone.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _backupTextCtl,
          minLines: 3,
          maxLines: 6,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Backup file contents',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _restoreWordsCtl,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Your 6 backup words',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: Listenable.merge([_backupTextCtl, _restoreWordsCtl]),
          builder: (context, _) => FilledButton(
            onPressed: _busy ||
                    _backupTextCtl.text.trim().isEmpty ||
                    _restoreWordsCtl.text.trim().isEmpty
                ? null
                : _restoreBackup,
            child: const Text('Restore from backup'),
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _error = null;
                    _step = _Step.restore;
                  }),
          child: const Text('Back'),
        ),
      ];

  List<Widget> _wordsStep(BuildContext context) => [
        Text('Your 12 recovery words',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'These words ARE your identity. No server holds a copy and no one '
          'can reset them, by design. Write them down, keep them offline. '
          'You can see them again in Settings.',
        ),
        const SizedBox(height: 16),
        FutureBuilder<({List<String> words, List<String> backup})>(
          future: _wordsFuture ??= _readWords(),
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final words = data.words;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                BackupWordsBlock(data.backup),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed:
              _busy ? null : () => setState(() => _step = _Step.backup),
          child: const Text('I wrote them down'),
        ),
      ];

  List<Widget> _backupStep(BuildContext context) => [
        Text('Optional: an encrypted backup',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'A backup file of your identity, for if this phone disappears. '
          'Your 6 backup words unlock it. You have no groups yet, so this '
          'one holds none; once you have a group, Porch offers a fresh '
          'backup that includes it. The file is ciphertext, safe to keep '
          'anywhere.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _saveBackup,
          child: const Text('Create encrypted backup'),
        ),
        TextButton(
          onPressed:
              _busy ? null : () => setState(() => _step = _Step.name),
          child: const Text('Skip for now'),
        ),
      ];

  List<Widget> _nameStep(BuildContext context) => [
        Text('How friends see you',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'Only people you invite ever see this. It travels end-to-end '
          'encrypted and never touches a server in plaintext.',
        ),
        if (_restored) ...[
          const SizedBox(height: 12),
          const Text(
            'Identity restored. Groups are not stored on any server, so '
            'ask friends to invite you again. Your porch fills back up from '
            'their side.',
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtl,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: const Text('Finish setup'),
        ),
      ];
}
