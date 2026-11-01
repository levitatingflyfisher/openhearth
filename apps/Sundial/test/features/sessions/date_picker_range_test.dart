import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/sessions/presentation/manual_entry_sheet.dart';
import 'package:sundial/features/sessions/presentation/session_edit_sheet.dart';

/// Both date pickers began 90 days back. For an older date the initial date
/// fell before the first date, Flutter's assertion failed, and the picker
/// never opened.
void main() {
  late SharedPreferences prefs;
  final now = DateTime.now();
  final old = DateTime(now.year, now.month, now.day, 9)
      .subtract(const Duration(days: 200));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, Widget sheet) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider
            .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: sheet),
    ));
    await tester.pump();
  }

  testWidgets('Edit Session opens the picker for a session 200 days old',
      (tester) async {
    final session = Session(
      id: 'old',
      startTime: old.millisecondsSinceEpoch,
      endTime: old.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      durationSecs: 3600,
      dateDay: '',
      createdAt: 0,
      updatedAt: 0,
    );
    await pump(
        tester, SessionEditSheet(sessionId: 'old', initialSession: session));

    await tester.tap(find.byIcon(LucideIcons.calendarDays));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('Add Time opens the picker for a day 200 days old',
      (tester) async {
    await pump(tester, ManualEntrySheet(initialDate: old));

    await tester.tap(find.byIcon(LucideIcons.calendarCheck));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
