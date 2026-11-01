// lib/features/stats/presentation/chart_label_style.dart
import 'package:flutter/material.dart';

/// The text style the stats charts paint their labels with.
///
/// A CustomPainter's TextPainter gets no DefaultTextStyle, so a bare
/// TextStyle there has no font family and falls back to the platform font.
/// The family comes from the app theme (the shared Nunito) so chart labels
/// match the rest of the app. Each label sets its own size.
TextStyle chartLabelStyle(BuildContext context, {required Color color}) {
  final base = Theme.of(context).textTheme.labelSmall;
  return TextStyle(
    fontFamily: base?.fontFamily,
    fontFamilyFallback: base?.fontFamilyFallback,
    color: color,
    fontWeight: FontWeight.w500,
  );
}
