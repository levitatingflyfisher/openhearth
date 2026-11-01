import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/sanctuary_backup/backup_config.dart';
import 'package:peckish/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:peckish/main.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/backup_overrides.dart';

// Drift widget-test rules apply: see groceries_screen_test.dart.
//
// On the web the household's diary lives in the browser, and clearing the
// browser's website data erases it. The family opens the app in a phone
// browser, so the real PeckishApp must say so above every screen on the
// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<int> noticesShown(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
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
    final shown = find.text(ohWebDataNotice).evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    return shown;
  }

  testWidgets('on the web the app shows the data notice once',
      (tester) async {
    debugOhWebDataNoticeOnWeb = true;
    expect(await noticesShown(tester), 1);
  });

  testWidgets('off the web the app shows no data notice', (tester) async {
    debugOhWebDataNoticeOnWeb = false;
    expect(await noticesShown(tester), 0);
  });
}
