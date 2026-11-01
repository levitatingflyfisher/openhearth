import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// A failed read of a small part of a screen (a row of people, one total,
/// the last seven days), said in one line with Try again. The rest of the
/// screen stays. It is never drawn as zero, empty or missing: a parent reads
/// "0h this year" as "our time is gone". For a whole screen use
/// [OhReadError].
class InlineReadError extends StatelessWidget {
  const InlineReadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  /// Names the part: "Couldn’t read your people".
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

/// The household's people, read failed: the chip row says so in its place.
const peopleReadFailed = 'Couldn’t read your people';
