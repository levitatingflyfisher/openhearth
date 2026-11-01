// Home (§2 module map): the big Available button and the feed.
//
// Honesty is structural here: everything presence-shaped renders through
// FeedModel, which is built from PresenceSnapshots — the type that cannot
// exist without fetchedAt — and the staleness banner is not optional
// decoration but the §1.4 rule (>15 min → "as of N min ago").
//
// The 25 s foreground poll + fetch-on-open run only when
// tickerEnabledProvider says so (bootstrap: yes; tests drive refreshes
// explicitly). No read receipts exist anywhere — the protocol cannot even
// express them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../backup_saved_dialog.dart';
import '../feed_model.dart';
import '../format.dart';
import '../groups/groups_screen.dart';
import '../providers.dart';
import '../settings/settings_screen.dart';
import '../web_preview.dart';
import 'available_sheet.dart';

/// Home's porch light control; tests find it by this key.
const porchLightKey = ValueKey('porch-light');

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (ref.read(tickerEnabledProvider)) {
      // Fetch on open + 25 s foreground poll (§1.3).
      scheduleMicrotask(_refresh);
      _ticker = Timer.periodic(
          const Duration(seconds: 25), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(actionsProvider).refresh();

  Future<void> _openAvailableSheet() async {
    final state = ref.read(porchStateProvider).value;
    if (state == null || state.groups.isEmpty) return;
    final choice = await showModalBottomSheet<AvailableChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AvailableSheet(
        groups: [
          for (final g in state.groups)
            SheetGroup(
                uuid: g.groupUuid,
                name: g.name,
                preselected: g.defaultBroadcast),
        ],
        defaultDurationSeconds: state.settings.defaultExpiry,
      ),
    );
    if (choice == null || choice.groupUuids.isEmpty) return;
    await ref.read(actionsProvider).tapAvailable(
          groupUuids: choice.groupUuids,
          tag: choice.tag,
          durationSeconds: choice.durationSeconds,
        );
  }

  void _showFriend(FeedFriend f) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(f.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.contactNote.isEmpty
                ? 'No contact note yet. Ask them how they like to be '
                    'reached.'
                : f.contactNote),
            const SizedBox(height: 12),
            Text('Together in: ${f.groupNames.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(porchStateProvider).value;
    final session = ref.watch(sessionProvider).value;
    if (state == null || session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = ref.read(clockProvider)();
    final model = buildFeedModel(state,
        myPk: session.identity.sign.publicKey, now: now);
    final promptDue =
        ref.read(metricsServiceProvider).promptDue(state, now);
    final relayOk = ref.read(actionsProvider).relayConfigured();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Porch', overflow: TextOverflow.ellipsis),
        // The fleet bar: words stay while they fit beside a whole title and
        // fold into their tooltips, rightmost first, when they don't (the
        // title was squeezed to "Po…" at 320 dp x 3.0).
        actions: [
          OhBarActions(children: [
            OhBarAction(
              icon: Icons.group_outlined,
              label: 'Groups',
              onPressed: _openGroups,
            ),
            // Settings is a rare visit, so it lives in the worded More menu
            // (fleet top-bar ruling); three worded commands beside the
            // title folded two of them at 360 dp x 1.3.
            _moreMenu(context),
          ]),
        ],
      ),
      body: OhPage(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              const WebPreviewBanner(),
              if (!relayOk) _noRelayNotice(context),
              if (promptDue) _feedbackCard(context),
              if (model.isStale(now)) _staleBanner(context, model, now),
              _availabilityCard(
                  context, model, now, state.groups.isNotEmpty, relayOk),
              // Below the light, so the task comes first (ruling 48), and
              // one backup card at a time: unfinished setup first.
              if (!state.settings.hasBackup &&
                  !state.settings.finishSetupDismissed)
                _finishSetupCard(context)
              else if (state.settings.offerFreshBackup &&
                  state.groups.isNotEmpty)
                _freshBackupCard(context),
              const SizedBox(height: 16),
              ..._feed(context, model, now, relayOk),
            ],
          ),
        ),
      ),
    );
  }

  /// The shipped default relay is a placeholder that can never resolve.
  /// Until a real one is set, say so where the decision to tap is made.
  Widget _noRelayNotice(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('No relay set up',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Porch needs a relay to carry your light between '
                  'phones, and none is set. Until you add one, everything '
                  'stays only on this phone: friends will not see your '
                  'light, and theirs will not reach you.'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _openSettings,
                  child: const Text('Set up a relay'),
                ),
              ),
            ],
          ),
        ),
      );

  /// Fleet ruling 48: setup skipped at first run stays visible until done
  /// or dismissed. porch's is the backup onboarding lets you skip.
  Widget _finishSetupCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Finish setup: back up this phone',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text('Your 12 words bring back only you. A backup '
                  'file, locked by your 6 backup words, also brings back '
                  'your groups if this phone is lost.'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => runBackupFlow(context, ref),
                    child: const Text('Back up now'),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(actionsProvider).dismissFinishSetup(),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  /// The onboarding backup predates every group; offer one that holds them.
  Widget _freshBackupCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Back up your groups',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text('Your backup was made before you had any groups, '
                  'so it cannot bring them back. A fresh one can.'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => runBackupFlow(context, ref),
                    child: const Text('Back up now'),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(actionsProvider).dismissFreshBackupOffer(),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _feedbackCard(BuildContext context) => Card(
        child: ListTile(
          title: const Text("How’s Porch working for you?"),
          subtitle: const Text(
              'Porch keeps no telemetry, so your voice is the only '
              'signal. Tell a friend, or tell us on the repo.'),
          trailing: IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(actionsProvider).dismissFeedbackPrompt(),
          ),
        ),
      );

  Widget _staleBanner(BuildContext context, FeedModel model, int now) {
    final age = now - model.oldestFetchedAt!;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.history, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Showing the last known, ${formatAsOf(age)}. Pull to refresh.'),
            ),
          ],
        ),
      ),
    );
  }

  /// Rare actions, in words (fleet ruling): refresh (the 25 s poll and
  /// pull-to-refresh cover most of it, but a mouse cannot pull) and the
  /// theme, which stays two taps from Home.
  Widget _moreMenu(BuildContext context) {
    final theme = ref.watch(themeModeProvider);
    // A word, not only a tooltip: this is Home's route to the theme.
    return OhBarOverflow<Object>(
      onSelected: (choice) {
        if (choice is OhThemeModePreference) {
          ref.read(themeModeProvider.notifier).set(choice);
        } else if (choice == 'settings') {
          _openSettings();
        } else {
          _refresh();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<Object>(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
          ),
        ),
        const PopupMenuItem<Object>(
          value: 'refresh',
          child: ListTile(
            leading: Icon(Icons.refresh),
            title: Text('Refresh now'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Theme'),
        ),
        for (final p in OhThemeModePreference.values)
          CheckedPopupMenuItem<Object>(
            value: p,
            checked: p == theme,
            child: Text(p.label),
          ),
      ],
    );
  }

  /// Settings is where the relay URL lives; the endpoint holder is not
  /// reactive, so rebuild on return to re-read whether a relay is set.
  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  void _openGroups() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const GroupsScreen()));

  Widget _availabilityCard(BuildContext context, FeedModel model, int now,
      bool hasGroups, bool relayOk) {
    final mine = model.myStatus;
    final on = mine != null;
    final theme = Theme.of(context);
    // One control, one place, one size, in both states, and it shows which
    // state the light is in (audit humane-interface-07; the floor both
    // sides of the verbs-or-adjectives question share). Its words say the
    // state; picking the other one is the act.
    final control = SegmentedButton<bool>(
      key: porchLightKey,
      segments: const [
        ButtonSegment(
            value: true, label: Text('On'), icon: Icon(Icons.light_mode)),
        ButtonSegment(
            value: false,
            label: Text('Off'),
            icon: Icon(Icons.nightlight_outlined)),
      ],
      selected: {on},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        textStyle: theme.textTheme.titleMedium,
        // Lit is the warm accent; off is the plain selected surface.
        selectedBackgroundColor: on ? theme.colorScheme.primary : null,
        selectedForegroundColor: on ? theme.colorScheme.onPrimary : null,
      ),
      // With no group there is nobody to tell: shown, off and disabled,
      // not a control whose handler returns in silence. A light that is
      // already on can always be turned off.
      onSelectionChanged: hasGroups || on
          ? (choice) => choice.first
              ? _openAvailableSheet()
              : ref.read(actionsProvider).tapOff()
          : null,
    );
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your porch light', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            control,
            if (mine != null) ...[
              const SizedBox(height: 12),
              Text(
                  relayOk
                      ? "You’re on the porch"
                      : 'Your light is on, on this phone only',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text([
                if (mine.tag.isNotEmpty) mine.tag,
                formatRemaining(mine.expiresAt - now),
              ].join(' · ')),
            ],
          ],
        ),
      ),
    );
    if (hasGroups || on) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: 8),
        const Text("You’re not in any group, so there is nobody to tell "
            'yet. Make a group or join one with a code.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _openGroups,
            child: const Text('Open Groups'),
          ),
        ),
      ],
    );
  }

  List<Widget> _feed(
      BuildContext context, FeedModel model, int now, bool relayOk) {
    if (model.friends.isEmpty && !relayOk) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text("Friends can’t show up here yet.",
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'With no relay, nothing from your groups reaches this phone.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }
    if (model.friends.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              const Icon(Icons.nightlight_outlined, size: 40),
              const SizedBox(height: 12),
              Text("Nobody’s on the porch right now.",
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'When someone in your groups turns their light on, '
                'they show up here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Text('On the porch', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      for (final f in model.friends)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(f.tag.isNotEmpty
                  ? f.tag
                  : (f.name.isEmpty ? '?' : f.name[0].toUpperCase())),
            ),
            title: Text(f.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (f.tag.isNotEmpty) f.tag,
                formatRemaining(f.expiresAt - now),
                f.groupNames.join(', '),
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            onTap: () => _showFriend(f),
          ),
        ),
    ];
  }
}
