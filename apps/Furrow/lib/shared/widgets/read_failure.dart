import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// A failed read of a small part of a screen (one list in Settings, the award shelf,
/// a day’s marks), said in one line with Try again. The rest of the
/// screen stays. It is never drawn as zero, empty or missing: a household reads
/// an unmarked day as "our marks are gone". For a whole screen use
/// [OhReadError].
class InlineReadError extends StatelessWidget {
  const InlineReadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  /// Names the part: "Couldn’t read your awards".
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
          alignment: WrapAlignment.center,
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

