import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/settings/presentation/settings_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

// The erase dialog must tell the truth about the way back, read from the
// key store at the moment it opens (not from whatever another screen left
// cached): with recovery words a verified safety copy is taken first; with
// none, there is no copy, and it says so.
void main() {
  const phrase = 'abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon about';

  Future<void> openErase(WidgetTester tester, SecureKeyStore store) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider
            .overrideWithValue(AppDatabase(NativeDatabase.memory())),
        secureKeyStoreProvider.overrideWithValue(store),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Erase all data'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('Erase all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase all data'));
    // The dialog waits on a fresh read of the key store (and, with words,
    // the key derivation behind it), which runs on real time.
    for (var i = 0;
        i < 40 && find.byType(AlertDialog).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('without recovery words it says there is no copy',
      (tester) async {
    await openErase(tester, InMemorySecureKeyStore());
    expect(find.textContaining('there is no copy to restore'), findsOneWidget);
    expect(find.textContaining('safety copy'), findsNothing);
    await unmount(tester);
  });

  testWidgets('with recovery words it promises the safety copy',
      (tester) async {
    await openErase(
        tester, InMemorySecureKeyStore(mnemonic: phrase, acknowledged: true));
    expect(find.textContaining('safety copy is saved to Previous backups'),
        findsOneWidget);
    expect(find.textContaining('no copy'), findsNothing);
    await unmount(tester);
  });

  // The words are the promise (Irori's ruling, 12 November 2026). Erase
  // keeps the theme, the built-in food database and the two downloads (the
  // offline barcode database and the AI model), so neither the button nor
  // the dialog may say "everything". The safety copy holds only the
  // household's records, so the dialog says exactly what restoring brings
  // back. Pinned word for word: a change here is a change to the promise.
  const subtitle = 'Deletes your data on this device. Keeps the theme, the '
      'food databases and the downloaded AI model.';
  const deletes = 'This deletes your Peckish data on this device, including '
      'the AI key and the household sync code. It keeps only the theme, the '
      'built-in food database, the offline barcode database and the '
      'downloaded AI model.';
  const withCopy = '$deletes A safety copy is saved to Previous backups '
      'first. Restoring it brings back your diary, foods, meals, recipes, '
      'plan, groceries and targets.';
  const withoutCopy =
      '$deletes Backup is not set up, so there is no copy to restore.';

  testWidgets(
      'with recovery words the button and dialog say exactly what '
      'stays and what a restore brings back', (tester) async {
    await openErase(
        tester, InMemorySecureKeyStore(mnemonic: phrase, acknowledged: true));
    expect(find.text(subtitle), findsOneWidget);
    expect(find.text(withCopy), findsOneWidget);
    expect(find.textContaining('everything'), findsNothing);
    await unmount(tester);
  });

  testWidgets('without recovery words the dialog says exactly what stays',
      (tester) async {
    await openErase(tester, InMemorySecureKeyStore());
    expect(find.text(subtitle), findsOneWidget);
    expect(find.text(withoutCopy), findsOneWidget);
    expect(find.textContaining('everything'), findsNothing);
    await unmount(tester);
  });
}
