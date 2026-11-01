import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either, Left, Unit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/error/failures.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/sessions/data/local_sessions_repository.dart';
import 'package:sundial/features/sessions/data/sessions_dao.dart';
import 'package:sundial/features/sessions/presentation/history_screen.dart';

/// The real repository, except that every delete fails.
class _DeleteFailsRepo extends LocalSessionsRepository {
  _DeleteFailsRepo(super.dao);
  @override
  Future<Either<StorageFailure, Unit>> deleteSession(String id) async =>
      const Left(StorageFailure('disk full'));
}

/// History's swipe delete dropped the delete result: the card was already
/// gone when the write failed, and nothing said so.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  final dateDay =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final session = Session(
    id: 's1',
    startTime: today.millisecondsSinceEpoch,
    endTime: today.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    durationSecs: 3600,
    notes: 'creek walk',
    dateDay: dateDay,
    createdAt: 0,
    updatedAt: 0,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.sessions).insert(session.toCompanion(true));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  }

  for (final view in ['List', 'Calendar']) {
    testWidgets('$view view: a failed swipe delete keeps the card and says so',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) => db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionsRepositoryProvider
              .overrideWith((_) => _DeleteFailsRepo(SessionsDao(db))),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await settle(tester);
      await tester.tap(find.text(view));
      await settle(tester);
      if (view == 'Calendar') {
        // The day's list under the grid holds the card.
        await tester.tap(find.text('${today.day}').first);
        await settle(tester);
      }

      final card = find.text('creek walk');
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.drag(card, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete session'));
      await settle(tester);

      expect(find.text('creek walk'), findsOneWidget,
          reason: 'the session is still stored, so its card stays');
      expect(find.text('Couldn’t delete the session. Please try again.'),
          findsOneWidget);
      await drain(tester);
    });
  }
}
