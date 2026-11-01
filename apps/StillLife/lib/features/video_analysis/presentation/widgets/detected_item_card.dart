import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../domain/entities/detected_object.dart';

/// Card displaying a single detected object with review action buttons.
class DetectedItemCard extends StatelessWidget {
  final DetectedObject object;
  final bool isConfirmed;
  final bool isDeleted;
  final VoidCallback? onConfirm;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const DetectedItemCard({
    super.key,
    required this.object,
    this.isConfirmed = false,
    this.isDeleted = false,
    this.onConfirm,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedOpacity(
      duration: OhMotion.standard,
      opacity: isDeleted ? 0.45 : 1.0,
      child: Card(
        elevation: isConfirmed ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: OhRadii.lg,
          side: isConfirmed
              ? BorderSide(color: colorScheme.primary, width: 2)
              : isDeleted
              ? BorderSide(color: colorScheme.error.withAlpha(100))
              : BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // The words get the card's width. A fixed right column for price
          // and actions once squeezed the title to "Sony A7III Ca..." on a
          // 320 wide phone and the tag chip to nothing at 3x text. So price,
          // confidence and actions sit in their own row at the bottom, and
          // every text wraps instead of being cut off.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: OhRadii.md,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Image.memory(
                        object.frameImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name and brand/model beside the thumbnail. This column
                  // is the narrowest place on the card, so its words are
                  // kept whole: a long word lowers the text size just enough
                  // to fit rather than splitting across two lines.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OhWholeWordsText(
                          object.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: isDeleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (object.brand != null || object.model != null) ...[
                          const SizedBox(height: OhSpacing.xs),
                          OhWholeWordsText(
                            [
                              object.brand,
                              object.model,
                            ].whereType<String>().join(' '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Category chip: as wide as its words, and wraps them when
              // they need more than one line.
              if (object.category != null) ...[
                const SizedBox(height: OhSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: OhRadii.sm,
                  ),
                  child: Text(
                    object.category!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],

              if (object.description != null) ...[
                const SizedBox(height: OhSpacing.xs),
                Text(
                  object.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: OhSpacing.sm),

              // Price and confidence, then the review actions.
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: OhSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (object.estimatedPrice != null)
                          Text(
                            '\$${object.estimatedPrice!.toStringAsFixed(0)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        Text(
                          '${(object.confidence * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onConfirm != null)
                        _ActionIcon(
                          icon: isConfirmed
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: isConfirmed
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          onTap: onConfirm!,
                          tooltip: 'Confirm',
                        ),
                      if (onEdit != null)
                        _ActionIcon(
                          icon: Icons.edit_outlined,
                          color: colorScheme.onSurfaceVariant,
                          onTap: onEdit!,
                          tooltip: 'Edit',
                        ),
                      if (onDelete != null)
                        _ActionIcon(
                          icon: isDeleted
                              ? Icons.restore_from_trash
                              : Icons.close_rounded,
                          color: isDeleted
                              ? colorScheme.tertiary
                              : colorScheme.error,
                          onTap: onDelete!,
                          tooltip: isDeleted ? 'Restore' : 'Delete',
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
