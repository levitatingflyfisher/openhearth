// Groups list: client-side facts (§3.2 step 1) — creating one calls no
// server, ever. Join-with-a-code lives here too (the primary tested path).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../join/join_screen.dart';
import '../providers.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctl,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(ctl.text.trim()),
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(actionsProvider).createGroup(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(porchStateProvider).value;
    final groups = state?.groups ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
      // The rows carry their own 16 dp inset, so the page adds none.
      body: OhPage(
        padding: EdgeInsets.zero,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Join with a code'),
              subtitle: const Text('Paste a porch:// link or invite code'),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const JoinScreen())),
            ),
            const Divider(),
            for (final g in groups)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group_outlined)),
                title: Text(g.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(g.roster.members.length == 1
                    ? 'Just you'
                    : '${g.roster.members.length} people'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        GroupDetailScreen(groupUuid: g.groupUuid))),
              ),
          ],
        ),
      ),
    );
  }
}
