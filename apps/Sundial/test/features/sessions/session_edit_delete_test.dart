import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:fpdart/fpdart.dart' show Either, Left, Unit;
import 'package:sundial/core/error/failures.dart';
import 'package:sundial/features/sessions/data/local_sessions_repository.dart';
import 'package:sundial/features/sessions/data/sessions_dao.dart';
import 'package:sundial/features/sessions/presentation/session_edit_sheet.dart';
import 'package:sundial/features/sessions/presentation/session_undo.dart';

/// The real repository, except that every save fails.
class _SaveFailsRepo extends LocalSessionsRepository {
  _SaveFailsRepo(super.dao);
  @override
  Future<Either<StorageFailure, Unit>> saveSession(Session s) async =>
      const Left(StorageFailure('disk full'));
}

/// doet-07 / about-face-01: the only way to delete a session was an
/// unadvertised swipe. Edit Session now has a visible Delete. It is a
/// deliberate act, so it does not ask (fleet delete ruling); it offers an
/// Undo that never times out, on History.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  final session = Session(
    id: 's1',
    startTime: DateTime(2026, 3, 28, 9).millisecondsSinceEpoch,
    endTime: DateTime(2026, 3, 28, 10).millisecondsSinceEpoch,
    durationSecs: 3600,
    notes: 'creek walk',
    dateDay: '2026-03-28',
    createdAt: 0,
    updatedAt: 0,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.sessions).insert(session.toCompanion(true));
  });

  Future<void> openEditor(WidgetTester tester,
      {List<Override> overrides = const []}) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        // Stands in for History, which shows the session Undo bar.
        builder: (context, _) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('open'),
            ),
            bottomNavigationBar:
                OhUndoBar(controller: ref.watch(sessionUndoControllerProvider)),
          ),
        ),
      ),
      GoRoute(
        path: '/edit',
        builder: (_, __) =>
            SessionEditSheet(sessionId: session.id, initialSession: session),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((_) => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
  }

  Future<List<Session>> stored() => db.select(db.sessions).get();

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  }

  testWidgets('Delete is visible, does not ask, and Undo brings it back',
      (tester) async {
    await openEditor(tester);
    final delete = find.text('Delete session');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing, reason: 'deliberate: no ask');
    expect(find.text('open'), findsOneWidget, reason: 'the editor closed');
    expect(await tester.runAsync(stored), isEmpty);

    // Undo never times out.
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);

    final back = (await tester.runAsync(stored))!;
    expect(back.single.id, 's1');
    expect(back.single.notes, 'creek walk');
    expect(back.single.durationSecs, 3600);
    await drain(tester);
  });

  // The Undo dropped its save result: a failed restore cleared the offer
  // and said nothing, so the session was gone for good.
  testWidgets('a failed Undo says so and keeps the Undo offered',
      (tester) async {
    await openEditor(tester, overrides: [
      sessionsRepositoryProvider
          .overrideWith((_) => _SaveFailsRepo(SessionsDao(db))),
    ]);
    final delete = find.text('Delete session');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await settle(tester);
    expect(await tester.runAsync(stored), isEmpty);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('Couldn’t restore the session. Please try again.'),
        findsOneWidget);
    expect(find.text('Undo'), findsOneWidget,
        reason: 'the offer stays so the restore can be tried again');
    await drain(tester);
  });
}
