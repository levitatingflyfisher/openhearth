import 'package:flutter/material.dart';

import '../../domain/entities/tag.dart';

class TagChip extends StatelessWidget {
  final Tag tag;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  const TagChip({super.key, required this.tag, this.onTap, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final chipColor = tag.color != null ? Color(tag.color!) : null;

    if (onDeleted != null) {
      return InputChip(
        label: _WrappingLabel(tag.name),
        backgroundColor: chipColor?.withAlpha(40),
        side: chipColor != null
            ? BorderSide(color: chipColor.withAlpha(100))
            : null,
        onDeleted: onDeleted,
        // By default the delete icon's box is a square as tall as the label,
        // so a label wrapped onto three lines got a delete box three lines
        // wide that left too little width for a whole word. A fixed width
        // keeps the room for the name; the height follows the icon.
        deleteIconBoxConstraints: const BoxConstraints.tightFor(width: 32),
        onPressed: onTap,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    }

    return ActionChip(
      label: _WrappingLabel(tag.name),
      backgroundColor: chipColor?.withAlpha(40),
      side: chipColor != null
          ? BorderSide(color: chipColor.withAlpha(100))
          : null,
      onPressed: onTap ?? () {},
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A chip's label is one line that fades at the chip's edge, so at large
/// text a long tag name ("Long Tag Name That Could Wrap") lost its end on a
/// narrow phone. This label wraps onto more lines instead; the chip still
/// never grows wider than the space it is given.
class _WrappingLabel extends StatelessWidget {
  const _WrappingLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    // Replaces (not merges) the chip's DefaultTextStyle: merge cannot set
    // maxLines back to unlimited.
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style,
      overflow: TextOverflow.visible,
      child: Text(text),
    );
  }
}
