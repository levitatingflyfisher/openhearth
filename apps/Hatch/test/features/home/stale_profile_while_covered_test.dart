import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/router/app_router.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/home/presentation/home_screen.dart';
import 'package:hatch/features/profiles/presentation/profile_picker_screen.dart';
import 'package:hatch/features/settings/presentation/settings_screen.dart';
import 'package:hatch/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A restore from Settings can replace the profiles so the active hatcher no
/// longer exists. Settings is pushed over Home, so Home is hidden at that
/// moment. Today the app goes straight to the picker as soon as the profiles
/// change, even from under Settings. Riverpod 3 pauses what a hidden widget
/// watches; this pins that Hatch still goes to the picker at once.
void main() {
  testWidgets('a hatcher removed while Settings covers Home goes to the picker',
      (tester) async {
    SharedPreferences.setMockInitialValues({'active_profile_id': 1});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('hatch'),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'hatch',
            aadContext: 'hatch-backup/v1',
            appDisplayName: 'Hatch',
          ),
        ),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    expect(await container.read(profilesDaoProvider).createProfile(), 1);

    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // Home is hidden: this is the case riverpod 3 pauses.
    final home = tester.element(find.byType(HomeScreen, skipOffstage: false));
    expect(TickerMode.of(home), isFalse);

    // What onAfterRestore does once a restore has replaced the profiles.
    await container.read(profilesDaoProvider).remove(1);
    container.invalidate(profilesProvider);
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePickerScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(prefs.getInt('active_profile_id'), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
