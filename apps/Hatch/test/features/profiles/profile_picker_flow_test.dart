import 'package:hatch/core/engine/engine_providers.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/router/app_router.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/home/presentation/home_screen.dart';
import 'package:hatch/features/profiles/domain/active_profile.dart';
import 'package:hatch/features/profiles/presentation/egg_avatar.dart';
import 'package:hatch/features/profiles/presentation/profile_picker_screen.dart';
import 'package:hatch/shared/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery_core/mastery_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end picker flow over the real router + in-memory database:
/// redirect-when-no-profile, no-typing profile creation, tap-to-select
/// landing on Home, and the long-press manage dialog.
Future<ProviderContainer> makeContainer({
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return container;
}

Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: container.read(appRouterProvider),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('navigating to /home with no active profile redirects to the '
      'picker', (tester) async {
    final container = await makeContainer();
    await pumpApp(tester, container);

    container.read(appRouterProvider).go('/home');
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePickerScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text("Who's hatching today?"), findsOneWidget);
  });

  testWidgets('tapping the add egg creates "Hatcher 1" with no typing', (
    tester,
  ) async {
    final container = await makeContainer();
    await pumpApp(tester, container);

    expect(find.text('New hatcher'), findsOneWidget);
    await tester.tap(find.text('New hatcher'));
    await tester.pumpAndSettle();

    expect(find.text('Hatcher 1'), findsOneWidget);
    expect(find.byType(EggAvatar), findsOneWidget);
  });

  testWidgets('tapping an egg selects the profile and lands on Home', (
    tester,
  ) async {
    final container = await makeContainer();
    final id = await container.read(profilesDaoProvider).createProfile();
    await pumpApp(tester, container);

    await tester.tap(find.text('Hatcher 1'));
    await tester.pumpAndSettle();

    expect(container.read(activeProfileProvider), id);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hatch'), findsOneWidget);
  });

  testWidgets('long-press opens the manage dialog; remove asks for '
      'confirmation before deleting', (tester) async {
    final container = await makeContainer();
    await container.read(profilesDaoProvider).createProfile();
    await pumpApp(tester, container);

    await tester.longPress(find.text('Hatcher 1'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Hatcher 1?'), findsOneWidget);

    // Backing out keeps the profile.
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Hatcher 1'), findsOneWidget);
  });

  testWidgets('removing a hatcher also retires her engine in memory, so '
      'nothing can save her old progress again', (tester) async {
    final container = await makeContainer();
    final id = await container.read(profilesDaoProvider).createProfile();
    final engine = await container.read(engineServiceProvider(id).future);
    await pumpApp(tester, container);

    await tester.longPress(find.text('Hatcher 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Hatcher 1'), findsNothing);

    final spec = engine.assembleRound(RoundIntent.piecing).events.first;
    Object? error;
    await tester.runAsync(() async {
      try {
        await engine.record(
          AnswerEvent(
            fact: spec.fact,
            direction: spec.direction,
            kind: spec.kind,
            rung: spec.rung,
            correct: true,
            latencyMs: 900,
            production: true,
            at: DateTime(2026, 8, 7, 9),
          ),
        );
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<StateError>());
  });

  testWidgets('rename flows through the dialog to the grid label', (
    tester,
  ) async {
    final container = await makeContainer();
    await container.read(profilesDaoProvider).createProfile();
    await pumpApp(tester, container);

    await tester.longPress(find.text('Hatcher 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Hatcher 1'), findsNothing);
  });

  testWidgets('the add egg disappears at four hatchers', (tester) async {
    final container = await makeContainer();
    final dao = container.read(profilesDaoProvider);
    for (var i = 0; i < 4; i++) {
      await dao.createProfile();
    }
    await pumpApp(tester, container);

    expect(find.byType(EggAvatar), findsNWidgets(4));
    expect(find.text('New hatcher'), findsNothing);
  });
}
