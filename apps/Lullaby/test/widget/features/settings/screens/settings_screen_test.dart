import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/features/settings/presentation/controllers/theme_controller.dart';
import 'package:lullaby/features/settings/presentation/screens/settings_screen.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

/// The backup section (sanctuary_backup_ui 0.3.0) reads the key store and
/// the reminder store; without in-memory stand-ins it waits on the platform
/// plugin forever and pumpAndSettle times out.
Widget _settings({SecureKeyStore? store}) => ProviderScope(
      overrides: [
        secureKeyStoreProvider
            .overrideWithValue(store ?? InMemorySecureKeyStore()),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'lullaby',
            aadContext: 'ghost-backup/v1',
            appDisplayName: 'Lullaby',
          ),
        ),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
        themeStorageProvider.overrideWithValue(InMemorySecretStorage()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  group('SettingsScreen', () {
    testWidgets('renders theme option', (tester) async {
      await tester.pumpWidget(
        _settings(),
      );

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Follow phone'), findsOneWidget);
    });

    testWidgets('renders about option', (tester) async {
      await tester.pumpWidget(
        _settings(),
      );

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Lullaby v1.0.0'), findsOneWidget);
    });

    testWidgets('renders privacy option', (tester) async {
      await tester.pumpWidget(
        _settings(),
      );

      expect(find.text('Privacy'), findsOneWidget);
      // Honest since two-phone sync: the data leaves only by a parent's choice.
      expect(
          find.text('Stays on this phone unless you turn on sync, export, '
              'or let Android back it up to Google'),
          findsOneWidget);
    });

    testWidgets('says Android may back up to Google, near the encrypted backup',
        (tester) async {
      await tester.pumpWidget(_settings());
      await tester.pumpAndSettle();

      const text = 'Android may also back up this app’s data to Google, if the '
          'phone’s owner allows it in Android settings. The encrypted backup '
          'here is the private choice.';
      await tester.scrollUntilVisible(find.text(text), 200);
      expect(find.text(text), findsOneWidget);
    });

    testWidgets(
        'says Android skips a large app and what the encrypted backup holds',
        (tester) async {
      await tester.pumpWidget(_settings());
      await tester.pumpAndSettle();

      // True to the code: the backup carries every table and, since the
      // owner's ruling (board-0167), the baby's photo itself.
      const text = 'Android skips its own backup of an app whose data is '
          'large, so the baby’s photo may not be in it. The encrypted backup '
          'here holds every log and note, and the baby’s photo.';
      await tester.scrollUntilVisible(find.text(text), 200);
      expect(find.text(text), findsOneWidget);
    });

    testWidgets('has a door to Sync with another phone', (tester) async {
      await tester.pumpWidget(_settings());
      expect(find.text('Sync with another phone'), findsOneWidget);
    });

    testWidgets('tapping theme opens dialog', (tester) async {
      await tester.pumpWidget(
        _settings(),
      );

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('tapping about opens about dialog', (tester) async {
      await tester.pumpWidget(
        _settings(),
      );

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      // The dialog names the licence in the LICENSE file (MIT, the fleet
      // rule). It said AGPL-3.0 before, which the repo never was.
      expect(find.text('MIT License'), findsOneWidget);
      expect(find.textContaining('AGPL'), findsNothing);
    });

    // board-0166, board-0170: the household sees who publishes the app, in
    // the fleet's one shared line (the words live in openhearth_design).
    testWidgets('the about dialog names the publisher', (tester) async {
      await tester.pumpWidget(_settings());

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(find.text('Published by Intergenerational Symbolic Systems'),
          findsOneWidget);
      expect(find.byType(OhPublisherLine), findsOneWidget);
      expect(find.text(ohPublisherLine), findsOneWidget);
    });

    // Ruling 48: unfinished backup setup gets a dismissible "finish setup"
    // line so it is never forgotten. It sits at the top of Settings, not on
    // Home, which is read at a glance at 3 a.m. and should not nag.
    const notSetUp = "Backup isn't set up. Your data is only on this device.";

    testWidgets('no backup yet: the finish-setup line shows and dismisses',
        (tester) async {
      await tester.pumpWidget(_settings());
      await tester.pumpAndSettle();

      expect(find.text(notSetUp), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text(notSetUp), findsNothing);
    });

    testWidgets('setup finished: no finish-setup line', (tester) async {
      await tester.pumpWidget(_settings(
        store: InMemorySecureKeyStore(
          mnemonic: 'abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon abandon about',
          acknowledged: true,
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(BackupSetupReminder, skipOffstage: false),
          findsOneWidget);
      expect(find.text(notSetUp), findsNothing);
    });
  });
}
