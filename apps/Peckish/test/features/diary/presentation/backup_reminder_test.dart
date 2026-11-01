import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

import '../../../support/backup_overrides.dart';

// Fleet ruling on first run: open straight into the task, and never let
// unfinished setup be forgotten. A fresh install lands on Today with a
// dismissible line saying backup isn't set up.
void main() {
  testWidgets('Today carries a dismissible finish-setup line', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...backupTestOverrides(),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining("Backup isn't set up"), findsOneWidget);
    // A plain tap, on the fake clock. The dismissal used to be tapped
    // inside runAsync; on riverpod 3 the refreshed status is built on the
    // next frame, and the write had finished on the real clock after the
    // last pump, so the line stayed up in the test (not in the app).
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Backup isn't set up"), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
