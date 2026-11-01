import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:fpdart/fpdart.dart' show Either, Left, Unit;
import 'package:sundial/core/error/failures.dart';
import 'package:sundial/features/sessions/domain/sessions_repository.dart';
import 'package:sundial/features/sessions/presentation/manual_entry_sheet.dart';

/// A sessions repo whose writes always fail.
class _FailingSessionsRepo implements SessionsRepository {
  @override
  Future<Either<StorageFailure, Unit>> saveSession(Session s) async =>
      const Left(StorageFailure('disk full'));
  @override
  Stream<int> watchSecondsForDay(String dateDay) => Stream.value(0);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Pumps ManualEntrySheet inside a minimal GoRouter so `context.pop()` works.
/// Returns the AppDatabase the test can query after tapping Save.
Future<AppDatabase> _pumpSheet(
  WidgetTester tester, {
  required String activeProfileId,
  List<({String id, String name})> extraProfiles = const [],
  List<Override> extraOverrides = const [],
  Widget sheet = const ManualEntrySheet(),
}) async {
  SharedPreferences.setMockInitialValues({
    'active_profile_id': activeProfileId,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());

  // Seed any extra profiles beyond the 'default' one the migration inserts.
  // Named profiles are required because sessions.profileId is an FK.
  for (final p in extraProfiles) {
    await db.into(db.profiles).insert(
          ProfilesCompanion.insert(
            id: p.id,
            name: p.name,
            colorValue: 0xFF5E9478,
            createdAt: 0,
            sortOrder: const Value(0),
          ),
        );
  }

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/add',
        builder: (_, __) => sheet,
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) => db),
      ...extraOverrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  // Pushed over a home route, so a close on Save shows as 'home' again.
  router.push('/add');
  await tester.pumpAndSettle();
  return db;
}

/// Lets drift's real async work finish between frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('ManualEntrySheet profile attribution', () {
    testWidgets(
        'saves with profileId=null when active profile is Everyone',
        (tester) async {
      final db = await _pumpSheet(tester, activeProfileId: kEveryoneProfileId);

      // Default duration is 0h 30m — above the > 0 guard.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final sessions = await db.select(db.sessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.first.profileId, isNull,
          reason: 'Everyone sessions must store profileId=null so they count '
              'for every profile without double-counting');
    });

    testWidgets(
        'saves with profileId=<active> when a named profile is active',
        (tester) async {
      final db = await _pumpSheet(
        tester,
        activeProfileId: 'dad',
        extraProfiles: const [(id: 'dad', name: 'Dad')],
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final sessions = await db.select(db.sessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.first.profileId, 'dad');
    });

    testWidgets(
        'saves with profileId=default when default profile is active',
        (tester) async {
      final db = await _pumpSheet(tester, activeProfileId: 'default');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final sessions = await db.select(db.sessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.first.profileId, 'default');
    });
  });

  // A failed write used to be dropped: the sheet awarded badges and closed
  // as if the time were saved, and the entry was gone.
  testWidgets('a failed save keeps the sheet open and says so',
      (tester) async {
    await _pumpSheet(
      tester,
      activeProfileId: 'default',
      extraOverrides: [
        sessionsRepositoryProvider.overrideWith((_) => _FailingSessionsRepo()),
      ],
    );

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('Add Time'), findsOneWidget,
        reason: 'the sheet stays open so the entry can be retried');
    expect(find.text('home'), findsNothing);
    expect(find.text('Couldn’t save the session. Please try again.'),
        findsOneWidget);
  });

  testWidgets('a good save closes the sheet', (tester) async {
    await _pumpSheet(tester, activeProfileId: 'default');

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Add Time'), findsNothing);
  });
}
