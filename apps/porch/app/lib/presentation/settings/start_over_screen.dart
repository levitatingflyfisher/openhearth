// "Start over with a new identity": for when the 12 words, the 6 backup
// words or a backup file may have reached someone else. Porch leaves every
// group first, while this identity still exists, so the old identity is in
// no group; only then does this phone forget it (PorchActions.startOver).
// Nothing can bring the identity back from this phone afterwards, so the
// step asks for typed words, not a tap.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../providers.dart';

const startOverTitle = 'Start over with a new identity';
const startOverWhen = 'Use this if your recovery words, your backup words or '
    'a backup file may have reached someone else.';
const startOverLeavesEveryGroup = 'Porch takes you out of every group you '
    'are in. Once a friend’s phone sees you leave, it locks that group '
    'again, so your old words and files can’t get back in.';
const startOverPhoneForgets = 'This phone forgets your identity: your 12 '
    'recovery words, your 6 backup words, your groups and the backup files '
    'saved on this phone.';
const startOverCopiesElsewhere = 'Backup files you already shared or saved '
    'somewhere else are not deleted, but they no longer get anyone into your '
    'groups.';
const startOverThen = 'Then Porch starts fresh, as on a new phone. To be '
    'back in a group, ask someone in it to invite you again.';
const startOverTypeToConfirm = 'To go on, type start over.';
const startOverButton = 'Start over';
const startOverUnreachedTitle = 'Some groups didn’t hear you leave';
const startOverGoOn = 'Go on anyway';
const startOverFailed = 'Porch couldn’t finish starting over. Try again.';

/// The words the person types, compared without case or outer spaces.
const _confirmWords = 'start over';

/// The groups a LEAVE did not reach, named, and what going on means.
String startOverUnreachedMessage(List<String> names) =>
    'Porch couldn’t reach the relay to leave: ${names.join(', ')}. If you go '
    'on, this phone forgets them anyway, and your old identity stays in '
    'them until a member there removes it. Or cancel, and try again later.';

class StartOverScreen extends ConsumerStatefulWidget {
  const StartOverScreen({super.key});

  @override
  ConsumerState<StartOverScreen> createState() => _StartOverScreenState();
}

class _StartOverScreenState extends ConsumerState<StartOverScreen> {
  final _typed = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _confirmed => _typed.text.trim().toLowerCase() == _confirmWords;

  Future<void> _startOver() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final actions = ref.read(actionsProvider);
      final result = await actions.startOver();
      if (!result.forgotten) {
        if (!mounted) return;
        final goOn = await showOhConfirm(
          context,
          title: startOverUnreachedTitle,
          message: startOverUnreachedMessage(result.unreached),
          confirmLabel: startOverGoOn,
          destructive: true,
        );
        if (!goOn) return;
        await actions.startOver(goOnWithoutUnreached: true);
      }
      // Onboarding now owns the root; nothing above it may stay open.
      nav.popUntil((route) => route.isFirst);
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text(startOverFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: const Text(startOverTitle, overflow: TextOverflow.ellipsis)),
      body: OhPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            const Text(startOverWhen),
            const SizedBox(height: 16),
            for (final line in const [
              startOverLeavesEveryGroup,
              startOverPhoneForgets,
              startOverCopiesElsewhere,
            ]) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(line)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            const Text(startOverThen),
            const SizedBox(height: 24),
            Text(startOverTypeToConfirm, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _typed,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            // Urgency is hue, icon and word, as in the fleet's confirm.
            FilledButton(
              onPressed: _confirmed && !_busy ? _startOver : null,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                minimumSize: const Size(48, 48),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.report_outlined),
                  SizedBox(width: 8),
                  Text(startOverButton),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
