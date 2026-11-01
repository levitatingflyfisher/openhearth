import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/about/presentation/about_screen.dart';
import 'package:peckish/features/settings/presentation/privacy_screen.dart';
import 'package:peckish/features/settings/presentation/settings_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

// Android's own backup can copy this app's data to Google when the phone's
// owner allows it. The app says so beside its encrypted backup, and no
// screen may claim that nothing is ever uploaded.
const sentence = 'Android may also back up this app’s data to Google, if the '
    'phone’s owner allows it in Android settings. The encrypted backup here '
    'is the private choice.';

void main() {
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider
            .overrideWithValue(AppDatabase(NativeDatabase.memory())),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Settings says it beside the encrypted backup', (tester) async {
    await show(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text(sentence), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(sentence), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the privacy map names the Android backup', (tester) async {
    await show(tester, const PrivacyScreen());
    await tester.scrollUntilVisible(find.text(sentence), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(sentence), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('About does not claim nothing is ever uploaded', (tester) async {
    await show(tester, const AboutScreen());
    expect(find.textContaining('nothing is ever uploaded'), findsNothing);
    expect(find.textContaining('Android may also back up'), findsOneWidget);
    await unmount(tester);
  });
}
