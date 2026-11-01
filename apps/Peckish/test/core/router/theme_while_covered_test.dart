import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/sanctuary_backup/backup_config.dart';
import 'package:peckish/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:peckish/main.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/backup_overrides.dart';

// Drift widget-test rules apply: see groceries_screen_test.dart.
//
// Riverpod 3 pauses a hidden widget's ref.watch. Settings is pushed over
// the tab shell, so Today sits covered while the theme changes. The app's
// theme is watched by PeckishApp, above the navigator, so it must turn at
// once; Today's own toggle must show the new mode when it comes back.
void main() {
  testWidgets('a theme picked in Settings applies while Today is covered',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs =
        (await tester.runAsync(SharedPreferences.getInstance))!;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
        sanctuary.sanctuaryAppDomainProvider.overrideWithValue('peckish'),
        sanctuaryBackupConfigProvider.overrideWithValue(peckishBackupConfig),
        backupSerializerProvider.overrideWith(
          (ref) => PeckishBackupSerializer(ref.watch(appDatabaseProvider)),
        ),
        ...backupTestOverrides(),
      ],
      child: const PeckishApp(),
    ));
    await tester.pumpAndSettle();

    ThemeMode appMode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    expect(appMode(), ThemeMode.system);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    // Settings' own toggle: open the menu, pick Dark.
    await tester.tap(find.text('Auto').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    // Today is still underneath and covered: its tickers are off, so this
    // runs the paused case on riverpod 3.
    final today =
        tester.element(find.byType(TodayScreen, skipOffstage: false));
    expect(TickerMode.of(today), isFalse);
    expect(appMode(), ThemeMode.dark,
        reason: 'the app theme turns while Settings is open');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Logged today'), findsOneWidget);
    expect(appMode(), ThemeMode.dark);
    expect(find.text('Dark'), findsOneWidget,
        reason: "Today's own toggle shows the new mode on return");

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
