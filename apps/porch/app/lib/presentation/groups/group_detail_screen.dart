// Group detail: roster (tap a friend → contact note), invite lifecycle
// incl. "void — regenerate" (§3.5 step 7 / PRD gate 4), admin ops
// (remove → rotation, transfer), and the sacred SILENT leave (§3.6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../data/invite_repo.dart';
import '../../domain/domain.dart';
import '../format.dart';
import '../providers.dart';

const _statusLabels = {
  InviteStatus.open: 'open',
  InviteStatus.joined: 'joined',
  InviteStatus.granted: 'granted',
  InviteStatus.voided: 'void',
};

class GroupDetailScreen extends ConsumerWidget {
  final String groupUuid;
  const GroupDetailScreen({super.key, required this.groupUuid});

  Future<void> _mint(BuildContext context, WidgetRef ref) async {
    final InviteHandle handle;
    try {
      handle = await ref.read(actionsProvider).mintInvite(groupUuid);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn’t reach the relay. Try again when "
              'connected.')));
      return;
    }
    if (!context.mounted) return;
    await _showInvite(context, handle);
  }

  Future<void> _regenerate(
      BuildContext context, WidgetRef ref, String inviteId) async {
    final handle =
        await ref.read(actionsProvider).regenerateInvite(groupUuid, inviteId);
    if (!context.mounted) return;
    await _showInvite(context, handle);
  }

  Future<void> _showInvite(BuildContext context, InviteHandle handle) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          // Scrollable: a long invite link at textScale 3 on a 320 dp
          // screen is taller than the dialog's max height.
          scrollable: true,
          title: const Text('Share this invite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(handle.link),
              const SizedBox(height: 12),
              const Text('Or the code by itself:'),
              const SizedBox(height: 4),
              SelectableText(handle.code),
              const SizedBox(height: 12),
              const Text('One person can use it, within 72 hours. The '
                  'link itself is the key, so share it privately.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

  // Delete policy (fleet ruling): a deliberate delete skips the question
  // and offers a lasting Undo. These three keep a confirm on purpose,
  // because none of them can be undone from this phone: Remove rotates
  // the group key at once (delaying it would leave the removed person
  // holding the live key), and Remove, Leave and Transfer are each sent
  // to the other members' phones the moment they commit. The confirm
  // names the act and the person; the two that cut someone off carry
  // the urgency colour, icon and word.

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, RosterEntry member) async {
    final name =
        member.displayName.isEmpty ? 'this member' : member.displayName;
    final ok = await showOhConfirm(
      context,
      title: 'Remove $name?',
      message: 'The group key changes at once: they lose both the key and '
          'the channel. They are not notified.',
      confirmLabel: 'Remove $name',
      destructive: true,
    );
    if (ok) {
      await ref
          .read(actionsProvider)
          .removeMember(groupUuid, member.signPk);
    }
  }

  Future<void> _confirmTransfer(
      BuildContext context, WidgetRef ref, RosterEntry member) async {
    final name =
        member.displayName.isEmpty ? 'this member' : member.displayName;
    final ok = await showOhConfirm(
      context,
      title: 'Make $name admin?',
      message: 'They take over removing members and rescuing invites, and '
          'you stop being admin. No keys change.',
      confirmLabel: 'Make $name admin',
    );
    if (ok) {
      await ref
          .read(actionsProvider)
          .transferAdmin(groupUuid, member.signPk);
    }
  }

  Future<void> _confirmLeave(
      BuildContext context, WidgetRef ref, String groupName) async {
    final nav = Navigator.of(context);
    final ok = await showOhConfirm(
      context,
      title: 'Leave $groupName?',
      message: 'You slip out quietly. No one is notified: your light just '
          'never comes on there again. This phone forgets the group keys.',
      confirmLabel: 'Leave $groupName',
      destructive: true,
    );
    if (ok) {
      await ref.read(actionsProvider).leaveGroup(groupUuid);
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(porchStateProvider).value;
    final session = ref.watch(sessionProvider).value;
    final g = state?.groupByUuid(groupUuid);
    if (g == null || session == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final myPk = session.identity.sign.publicKey;
    final imAdmin = g.roster.isAdminPk(myPk);
    final now = ref.read(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text(g.name)),
      body: OhPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Text('Members', style: Theme.of(context).textTheme.labelLarge),
            for (final m in g.roster.members)
              _memberTile(context, ref, m,
                  isMe: bytesEqual(m.signPk, myPk), imAdmin: imAdmin),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _mint(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invite a friend'),
            ),
            if (g.pendingInvites.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Invites', style: Theme.of(context).textTheme.labelLarge),
              for (final (i, invite) in g.pendingInvites.indexed)
                _inviteTile(context, ref, invite, now, ordinal: i + 1),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Include in my default broadcast'),
              subtitle: const Text(
                  'Pre-selected when you turn your porch light on'),
              value: g.defaultBroadcast,
              onChanged: (on) =>
                  ref.read(actionsProvider).setGroupBroadcast(groupUuid, on),
            ),
            const Divider(height: 32),
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _confirmLeave(context, ref, g.name),
              icon: const Icon(Icons.logout),
              label: const Text('Leave group'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(BuildContext context, WidgetRef ref, RosterEntry m,
      {required bool isMe, required bool imAdmin}) {
    final name = m.displayName.isEmpty ? 'Friend' : m.displayName;
    // The Admin badge lives in the (wrapping) title, not in `trailing`:
    // a chip at textScale 3 on a 320 dp screen would otherwise consume
    // the whole tile width (house accessibility sweep).
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(name[0].toUpperCase())),
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(isMe ? '$name (you)' : name),
          if (m.isAdmin) const Chip(label: Text('Admin')),
        ],
      ),
      subtitle: m.contactNote.isEmpty
          ? null
          : Text(m.contactNote,
              overflow: TextOverflow.ellipsis, maxLines: 2),
      trailing: (imAdmin && !isMe)
          ? PopupMenuButton<String>(
              tooltip: 'Member actions: $name',
              onSelected: (v) => switch (v) {
                'remove' => _confirmRemove(context, ref, m),
                _ => _confirmTransfer(context, ref, m),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'remove', child: Text('Remove from group')),
                PopupMenuItem(value: 'admin', child: Text('Make admin')),
              ],
            )
          : null,
    );
  }

  /// Column-based, everything wraps: chips and buttons at textScale 3 on a
  /// 320 dp screen must never fight a ListTile's leading/trailing slots.
  /// Labeled by ordinal, not by inviteId — the random id means nothing to
  /// a human (and would make goldens nondeterministic).
  Widget _inviteTile(
      BuildContext context, WidgetRef ref, PendingInvite invite, int now,
      {required int ordinal}) {
    final label = _statusLabels[invite.status]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(label)),
              Text('Invite #$ordinal',
                  style: Theme.of(context).textTheme.titleSmall),
              switch (invite.status) {
                InviteStatus.granted =>
                  const Icon(Icons.check_circle_outline, size: 18),
                InviteStatus.joined =>
                  const Icon(Icons.hourglass_top, size: 18),
                _ => const SizedBox.shrink(),
              },
            ],
          ),
          Text(
            switch (invite.status) {
              InviteStatus.open => invite.isExpired(now)
                  ? 'expired: void it and make a new one'
                  : 'expires: ${formatRemaining(invite.expiresAt - now)}',
              InviteStatus.joined =>
                'someone joined: letting them in on the next refresh',
              InviteStatus.granted => 'used: they are in',
              InviteStatus.voided => 'dead: regenerate to invite again',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
          switch (invite.status) {
            InviteStatus.open => TextButton(
                onPressed: () => ref
                    .read(actionsProvider)
                    .voidInvite(groupUuid, invite.inviteId),
                child: const Text('Void'),
              ),
            InviteStatus.voided => TextButton(
                onPressed: () => _regenerate(context, ref, invite.inviteId),
                child: const Text('Regenerate'),
              ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}
