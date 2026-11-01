import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openhearth_design/openhearth_design.dart' show OhPage;

import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crt_effects.dart';
import '../widgets/thumbnail_image.dart';
import '../widgets/undo_host.dart' show confirmDeleteForGood, removalName;

/// Everything deleted and still kept (owner ruling, board-0138): clips by
/// their day, montages by name, and the files an older version set aside.
/// A clip or montage can be restored. An old set-aside file's day is not
/// known for certain, so it cannot go back on one; it can be kept. Every
/// "Delete for good" asks first and names the item (owner ruling,
/// board-0124). Nothing here is destroyed on a timer.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key, required this.storageService});

  final StorageService storageService;

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  StorageService get _storage => widget.storageService;

  @override
  void initState() {
    super.initState();
    _storage.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    _storage.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _keep(SetAsideFiles item) async {
    await _storage.keepForNow([item]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Kept. The app asks again in '
          '${StorageService.deletedKeepDays} days.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clips = [..._storage.pendingClipRemovals]
      ..sort((a, b) => a.clip.date.compareTo(b.clip.date));
    final montages = [..._storage.pendingCompilationRemovals]
      ..sort((a, b) => a.compilation.title.compareTo(b.compilation.title));
    final old = _storage.setAsideFiles;
    final empty = clips.isEmpty && montages.isEmpty && old.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'RECENTLY DELETED',
          style: AppTheme.pixelFont(fontSize: 12),
        ),
      ),
      body: OhPage(
        padding: EdgeInsets.zero,
        safeArea: false,
        child: CrtOverlay(
          enabled: _storage.getCrtEffects(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                empty
                    ? 'Nothing deleted is waiting.'
                    : 'Deleted clips and montages wait here until you '
                        'choose. After ${StorageService.deletedKeepDays} '
                        'days the app asks once.',
                style: AppTheme.monoFont(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (clips.isNotEmpty) ...[
                const SizedBox(height: 24),
                _header('CLIPS'),
                for (final r in clips)
                  _DeletedRow(
                    key: ValueKey('deleted-${r.id}'),
                    removal: r,
                    thumbnailPath: r.clip.thumbnailPath,
                    onRestore: () => _storage.restoreClip(r),
                    onDeleteForGood: () =>
                        confirmDeleteForGood(context, _storage, r),
                  ),
              ],
              if (montages.isNotEmpty) ...[
                const SizedBox(height: 24),
                _header('MONTAGES'),
                for (final r in montages)
                  _DeletedRow(
                    key: ValueKey('deleted-${r.id}'),
                    removal: r,
                    onRestore: () => _storage.restoreCompilation(r),
                    onDeleteForGood: () =>
                        confirmDeleteForGood(context, _storage, r),
                  ),
              ],
              if (old.isNotEmpty) ...[
                const SizedBox(height: 24),
                _header('FROM AN OLDER VERSION'),
                for (final r in old)
                  _DeletedRow(
                    key: ValueKey('deleted-${r.id}'),
                    removal: r,
                    thumbnailPath: r.thumbnailPath,
                    note: 'Its day is not known, so it cannot go back.',
                    onKeep: () => _keep(r),
                    onDeleteForGood: () =>
                        confirmDeleteForGood(context, _storage, r),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: AppTheme.pixelFont(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

/// One deleted item: its picture when it has one, its name, when it was
/// deleted, and its choices.
class _DeletedRow extends StatelessWidget {
  const _DeletedRow({
    super.key,
    required this.removal,
    required this.onDeleteForGood,
    this.onRestore,
    this.onKeep,
    this.thumbnailPath,
    this.note,
  });

  final Removal removal;
  final VoidCallback? onRestore;
  final VoidCallback? onKeep;
  final VoidCallback onDeleteForGood;
  final String? thumbnailPath;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = removalName(removal);
    final label = '${name[0].toUpperCase()}${name.substring(1)}';
    final when = DateFormat('MMM d, yyyy').format(removal.deletedAt.toLocal());
    final dim = AppTheme.monoFont(fontSize: 12, color: AppTheme.dimInk(theme));
    final button = TextButton.styleFrom(minimumSize: const Size(48, 48));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.05), // contrast-exempt: a fill, not text
          borderRadius: AppTheme.isHearth ? BorderRadius.circular(12) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thumbnailPath != null) ...[
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ThumbnailImage(
                      path: thumbnailPath!,
                      placeholder: Icon(Icons.videocam,
                          color: theme.colorScheme.primary, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTheme.monoFont(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        removal is SetAsideFiles
                            ? 'Here since $when'
                            : 'Deleted $when',
                        style: dim,
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 4),
                        Text(note!, style: dim),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (onRestore != null)
                  TextButton(
                    onPressed: onRestore,
                    style: button,
                    child: const Text('Restore'),
                  ),
                if (onKeep != null)
                  TextButton(
                    onPressed: onKeep,
                    style: button,
                    child: const Text('Keep'),
                  ),
                TextButton(
                  onPressed: onDeleteForGood,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Delete for good'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
