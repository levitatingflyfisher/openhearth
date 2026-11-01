import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/onboarding/presentation/onboarding_screen.dart';

/// Android's own backup is the phone owner's choice again (owner ruling,
/// 3 July 2026), so onboarding must not say the data never leaves the phone.
void main() {
  testWidgets('onboarding does not claim data never leaves the phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((_) => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('never leaves your phone'), findsNothing);
    expect(
      find.text('Free forever. Sundial sends your data nowhere. '
          'Android’s own backup is your choice.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
