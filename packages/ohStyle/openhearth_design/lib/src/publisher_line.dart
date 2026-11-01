import 'package:flutter/material.dart';

/// The one line every fleet app shows to name its publisher (board-0166,
/// spelled as ruled in board-0170). A household should see who publishes
/// the app it trusts with its data, the same words in every app. Kept here
/// once so no app spells it its own way.
const ohPublisherLine = 'Published by Intergenerational Symbolic Systems';

/// [ohPublisherLine] in the quiet small style (`bodySmall`, the secondary
/// colour), centred. Put it at the foot of an app's About or Settings.
class OhPublisherLine extends StatelessWidget {
  const OhPublisherLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      ohPublisherLine,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
