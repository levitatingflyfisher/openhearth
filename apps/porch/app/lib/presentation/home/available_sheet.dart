// The Available sheet (§3.4 step 1): group multi-select, expiry
// (30 m / 1 h / 2 h / 4 h / custom), tag presets + short custom tag.
import 'package:flutter/material.dart';

/// What the user picked; the home screen turns it into a tap.
class AvailableChoice {
  final List<String> groupUuids;
  final String tag;
  final int durationSeconds;
  const AvailableChoice({
    required this.groupUuids,
    required this.tag,
    required this.durationSeconds,
  });
}

class SheetGroup {
  final String uuid;
  final String name;
  final bool preselected;
  const SheetGroup(
      {required this.uuid, required this.name, required this.preselected});
}

// Words, not emoji: the self-hosted web build has no colour-emoji font, so
// an emoji preset drew as a box there (and on any friend's PWA feed).
const presetTags = ['walking', 'chores', 'driving', 'at my desk', 'reading'];
const durationChoices = [(1800, '30 m'), (3600, '1 h'), (7200, '2 h'), (14400, '4 h')];

class AvailableSheet extends StatefulWidget {
  final List<SheetGroup> groups;
  final int defaultDurationSeconds;
  const AvailableSheet({
    super.key,
    required this.groups,
    required this.defaultDurationSeconds,
  });

  @override
  State<AvailableSheet> createState() => _AvailableSheetState();
}

class _AvailableSheetState extends State<AvailableSheet> {
  late final Set<String> _selected = {
    for (final g in widget.groups)
      if (g.preselected) g.uuid,
  };
  late int _duration = widget.defaultDurationSeconds;
  bool _customDuration = false;
  String _presetTag = '';
  final _customMinutesCtl = TextEditingController();
  final _customTagCtl = TextEditingController();

  @override
  void dispose() {
    _customMinutesCtl.dispose();
    _customTagCtl.dispose();
    super.dispose();
  }

  int? get _customMinutes {
    final mins = int.tryParse(_customMinutesCtl.text.trim());
    return (mins == null || mins <= 0) ? null : mins;
  }

  bool get _canConfirm =>
      _selected.isNotEmpty && (!_customDuration || _customMinutes != null);

  void _confirm() {
    var duration = _duration;
    if (_customDuration) {
      final mins = _customMinutes;
      if (mins == null) return;
      duration = mins * 60;
    }
    final custom = _customTagCtl.text.trim();
    Navigator.of(context).pop(AvailableChoice(
      groupUuids: _selected.toList(),
      tag: custom.isNotEmpty ? custom : _presetTag,
      durationSeconds: duration.clamp(60, 14400),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Turn on your porch light',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Who sees it', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in widget.groups)
                  FilterChip(
                    label: Text(g.name),
                    selected: _selected.contains(g.uuid),
                    onSelected: (on) => setState(() {
                      on ? _selected.add(g.uuid) : _selected.remove(g.uuid);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('For how long', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (secs, label) in durationChoices)
                  ChoiceChip(
                    label: Text(label),
                    selected: !_customDuration && _duration == secs,
                    onSelected: (_) => setState(() {
                      _duration = secs;
                      _customDuration = false;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _customDuration,
                  onSelected: (_) => setState(() => _customDuration = true),
                ),
              ],
            ),
            if (_customDuration)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _customMinutesCtl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    helperText: 'How many minutes, e.g. 45',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text("What you’re up to (optional)",
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in presetTags)
                  ChoiceChip(
                    label: Text(tag),
                    selected: _presetTag == tag,
                    onSelected: (on) =>
                        setState(() => _presetTag = on ? tag : ''),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customTagCtl,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: 'Custom tag',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _canConfirm ? _confirm : null,
              child: const Text('Turn on the porch light'),
            ),
          ],
        ),
      ),
    );
  }
}
