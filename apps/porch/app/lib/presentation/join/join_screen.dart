// Join (§3.5 steps 3 & 5): paste the code (or the porch:// link — both
// parse identically), wait honestly, complete when the grant lands.
//
// The waiting state is real: joining is a two-sided handshake, and this
// screen says so instead of spinning forever. Every failure has a typed,
// human answer — including "already used", which is the invite-link trust
// model working as designed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../data/invite_repo.dart';
import '../../data/relay_api.dart';
import '../providers.dart';
import '../error_line.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeCtl = TextEditingController();
  JoinedInvite? _joined;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined =
          await ref.read(actionsProvider).redeemInvite(_codeCtl.text.trim());
      setState(() => _joined = joined);
    } on ArgumentError {
      setState(
          () => _error = "That doesn’t look like a Porch invite. Check the "
              'code and try again.');
    } on RelayGone {
      setState(() => _error = 'This invite has already been used or '
          'expired. Ask your friend for a fresh one.');
    } on RelayNotFound {
      setState(() => _error = 'That invite is expired or unknown. Ask your '
          'friend for a fresh one.');
    } on RelayError {
      setState(() => _error = "You’re offline. Try again when you’re "
          'connected.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await ref.read(actionsProvider).completeJoin(_joined!);
      if (!mounted) return;
      if (group == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Not yet: still waiting to be let in.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Welcome to ${group.name}!')));
        Navigator.of(context).pop();
      }
    } on RelayError {
      setState(() => _error = "You’re offline. Try again when you’re "
          'connected.');
    } on StateError {
      setState(() => _error = 'That grant failed verification, so Porch is refusing '
          'to join. Ask your friend to regenerate the invite.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: OhPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          children: [
            if (_joined == null) ..._inputPhase() else ..._waitingPhase(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ErrorLine(_error!),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _inputPhase() => [
        const Text('Paste the invite your friend sent you. The link itself '
            'is the key, and the server never sees it.'),
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtl,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Invite code or porch:// link',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: const Text('Join'),
        ),
      ];

  List<Widget> _waitingPhase() => [
        const Icon(Icons.hourglass_top, size: 40),
        const SizedBox(height: 12),
        Text('Waiting to be let in…',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Your friend needs to open Porch to let you in. This usually '
          'takes under a minute once they do.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _check,
          child: const Text('Check now'),
        ),
      ];
}
