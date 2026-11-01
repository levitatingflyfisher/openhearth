import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../features/inventory/presentation/controllers/quantity_controller.dart';
import '../../features/loans/presentation/controllers/loan_controller.dart';

/// A failed read of a small part of a screen (an item's loans, photos or
/// tags, one dashboard section, the saved searches), said in one line with
/// Try again. The rest of the screen stays. It is never drawn as empty or
/// missing: a household reads "no loans" as "it’s here", and a missing
/// photo as "it’s gone". For a whole screen use [OhReadError].
class InlineReadError extends StatelessWidget {
  const InlineReadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  /// Names the part: "Couldn’t read this item’s loans".
  final String title;

  /// Reads again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.folder_off_outlined,
                  size: 18, color: cs.onSurfaceVariant),
            ),
            Text(title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Above an item list: says when the read of which items are on loan, or
/// running low, failed. Without it a loaned item looks not loaned. Draws
/// nothing while both reads are fine.
class ItemMarksReadError extends ConsumerWidget {
  const ItemMarksReadError({super.key});

  static bool _failed(AsyncValue<Object?> v) => v.hasError && !v.hasValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_failed(ref.watch(activeLoanedItemIdsProvider))) {
      return InlineReadError(
        title: 'Couldn’t read which items are on loan',
        onRetry: () => ref.invalidate(activeLoanedItemIdsProvider),
      );
    }
    if (_failed(ref.watch(lowStockItemsProvider))) {
      return InlineReadError(
        title: 'Couldn’t read which items are running low',
        onRetry: () => ref.invalidate(lowStockItemsProvider),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Builds [builder] again when its `reread` is called. A screen that makes
/// a read's stream in build hands `reread` to Try again: the rebuild makes
/// the stream, and so the read, again.
class Rereadable extends StatefulWidget {
  const Rereadable({super.key, required this.builder});

  final Widget Function(BuildContext context, VoidCallback reread) builder;

  @override
  State<Rereadable> createState() => _RereadableState();
}

class _RereadableState extends State<Rereadable> {
  void _reread() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.builder(context, _reread);
}
