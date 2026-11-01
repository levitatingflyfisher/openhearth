// Regression test: on a narrow phone the "Last 12 months" heatmap opened
// scrolled to the start, so today's column (the right-hand end) was off
// screen. It must open showing the newest end at every width.
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/stats/presentation/heatmap_chart.dart';
import 'package:sundial/shared/theme/app_theme.dart';

Future<void> _open(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: HeatmapChart(),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  // The heatmap used to jump to its end once, after the first layout. A
  // later width change (rotation, split screen, the golden sweep that reuses
  // one screen at several sizes) left the old offset, so a narrower viewport
  // showed the middle of the year and today was off screen.
  testWidgets('heatmap keeps today in view when the width shrinks',
      (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 5, 20, 12)), () async {
      await _open(tester, 360);
      tester.view.physicalSize = const Size(320, 800);
      await tester.pumpAndSettle();
      final view = find.byType(SingleChildScrollView);
      final viewport = tester.getRect(view);
      final content = tester.getRect(find.descendant(
          of: view,
          matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter != null)));
      expect(content.right, lessThanOrEqualTo(viewport.right + 0.5));
      await _tearDown(tester);
    });
  });

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('heatmap opens showing today at ${width.toInt()} wide',
        (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 5, 20, 12)), () async {
        await _open(tester, width);
        final view = find.byType(SingleChildScrollView);
        final viewport = tester.getRect(view);
        final content = tester.getRect(find.descendant(
            of: view,
            matching: find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter != null)));
        // The painted content's right end (today's column) must sit inside
        // the viewport, not beyond it.
        expect(content.right, lessThanOrEqualTo(viewport.right + 0.5));
        expect(content.right, greaterThan(viewport.left));
        await _tearDown(tester);
      });
    });
  }
}
