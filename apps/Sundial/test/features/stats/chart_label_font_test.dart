// Regression test: the two stats charts painted their axis and month labels
// with a bare TextStyle (no font family), so the labels fell back to the
// platform font instead of the app's Nunito, and drew as blocks in goldens.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/stats/presentation/cumulative_chart.dart';
import 'package:sundial/features/stats/presentation/heatmap_chart.dart';
import 'package:sundial/shared/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget chart) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider
          .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: chart)),
    ),
  ));
  await tester.pump();
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

/// The label style the chart's painter draws with. The painters are private,
/// so the field is read dynamically.
TextStyle _labelStyle(WidgetTester tester, Type chart) {
  // Material widgets inside the chart's Card add CustomPaints of their own
  // with no painter; the chart's is the one with a painter.
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(chart),
      matching:
          find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null)));
  return (paint.painter! as dynamic).labelStyle as TextStyle;
}

void main() {
  final themeFamily = AppTheme.light.textTheme.labelSmall!.fontFamily;

  test('the theme names a font family to compare against', () {
    expect(themeFamily, contains('Nunito'));
  });

  testWidgets('cumulative chart labels use the theme font family',
      (tester) async {
    await _pump(tester, const CumulativeChart());
    expect(_labelStyle(tester, CumulativeChart).fontFamily, themeFamily);
    await _tearDown(tester);
  });

  testWidgets('heatmap month labels use the theme font family',
      (tester) async {
    await _pump(tester, const HeatmapChart());
    expect(_labelStyle(tester, HeatmapChart).fontFamily, themeFamily);
    await _tearDown(tester);
  });
}
