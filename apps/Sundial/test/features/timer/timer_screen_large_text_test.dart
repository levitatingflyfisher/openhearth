// Regression test: at 3x accessibility text the idle clock wrapped to "00:"
// over "00" and the taller clock pushed START below the scroll viewport, so a
// user with large text saw no way to start the timer without scrolling.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/timer/presentation/timer_screen.dart';
import 'package:sundial/shared/theme/app_theme.dart';

Future<Widget> _app(double scale) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      appDatabaseProvider
          .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      // The scale goes in below MaterialApp, which rebuilds its own
      // MediaQuery from the view.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const TimerScreen(),
    ),
  );
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

/// The button of [type] that holds [label]. FilledButton.icon builds a
/// subclass, so the match is by `is`, not by exact type.
Finder _button(Type type, String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) =>
        type == FilledButton ? w is FilledButton : w is OutlinedButton));

/// The whole button lies inside the window and inside the scroll view's
/// visible area, and a tap at its centre reaches it.
void _expectFullyShown(WidgetTester tester, Finder button, double width) {
  expect(button, findsOneWidget);
  final rect = tester.getRect(button);
  final screen = Offset.zero & Size(width, 800);
  final scrollables =
      find.ancestor(of: button, matching: find.byType(Scrollable));
  final window = scrollables.evaluate().isEmpty
      ? screen
      : screen.intersect(tester.getRect(scrollables.first));
  bool inside(Rect outer) =>
      rect.left >= outer.left - 0.5 &&
      rect.top >= outer.top - 0.5 &&
      rect.right <= outer.right + 0.5 &&
      rect.bottom <= outer.bottom + 0.5;
  expect(inside(window), isTrue,
      reason: 'button at $rect is not wholly inside the visible $window');
  final hit = tester.hitTestOnBinding(rect.center);
  final box = tester.renderObject(button);
  expect(hit.path.any((e) => e.target == box), isTrue,
      reason: 'a tap at ${rect.center} does not reach the button');
}

void main() {
  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 2.0, 3.0]) {
      testWidgets(
          'at ${width.toInt()} wide and ${scale}x text the clock is one line '
          'and the controls show in full', (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);

        await tester.pumpWidget(await _app(scale));
        await tester.pump(const Duration(milliseconds: 100));

        final start = _button(FilledButton, 'START');
        _expectFullyShown(tester, start, width);

        // One line: every glyph of "00:00" sits on the same baseline row.
        final clock = tester.renderObject<RenderParagraph>(find.text('00:00'));
        final boxes = clock.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 5));
        final tops = boxes.map((b) => b.top.round()).toSet();
        expect(tops, hasLength(1),
            reason: 'the clock wrapped onto ${tops.length} lines');

        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 100));
        // The running and paused buttons must show in full too (an overflow
        // fails the test as a layout exception).
        _expectFullyShown(tester, _button(OutlinedButton, 'PAUSE'), width);
        _expectFullyShown(tester, _button(FilledButton, 'STOP'), width);
        await tester.tap(find.text('PAUSE'));
        await tester.pump(const Duration(milliseconds: 100));
        _expectFullyShown(tester, _button(FilledButton, 'RESUME'), width);
        _expectFullyShown(tester, _button(OutlinedButton, 'STOP'), width);

        await _drain(tester);
      });
    }
  }
}
