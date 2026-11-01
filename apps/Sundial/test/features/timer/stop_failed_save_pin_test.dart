import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/error/failures.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/flow_mode/presentation/flow_screen.dart';
import 'package:sundial/features/sessions/data/local_sessions_repository.dart';
import 'package:sundial/features/sessions/data/sessions_dao.dart';
import 'package:sundial/features/timer/data/timer_notification_service.dart';
import 'package:sundial/features/timer/domain/timer_state.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';
import 'package:sundial/features/timer/presentation/timer_screen.dart';

/// The real repository, except that while [failing] is set every save
/// fails as a full disk would.
class _FlakyRepo extends LocalSessionsRepository {
  _FlakyRepo(super.dao);
  bool failing = true;
  int attempts = 0;

  @override
  Future<Either<StorageFailure, Unit>> saveSession(Session s) async {
    attempts++;
    if (failing) return const Left(StorageFailure('disk full'));
    return super.saveSession(s);
  }
}

const _draftKey = 'timer_unsaved_draft';

/// The owner's ruling (board-0167): on a failed save, keep the session as
/// an unsaved draft in the existing panel and say "Couldn’t save the
/// session". Before the ruling, a failed STOP went to Idle, kept nothing,
/// and the screen still said "Session saved".
void main() {
  late AppDatabase db;
  late _FlakyRepo repo;
  late SharedPreferences prefs;

  Future<ProviderContainer> makeContainer(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    repo = _FlakyRepo(SessionsDao(db));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) => db),
      sessionsRepositoryProvider.overrideWith((_) => repo),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('a STOP whose save fails', () {
    test('keeps the session as an unsaved draft with its start, end, profile',
        () async {
      final container =
          await makeContainer({'active_profile_id': 'kid'});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      final started = container.read(timerProvider) as TimerRunning;
      final before = DateTime.now().millisecondsSinceEpoch;

      final result = await notifier.stopAndSave();
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(result.isLeft(), isTrue, reason: 'the failure reaches the screen');
      expect(repo.attempts, 1, reason: 'one attempt, no retry');
      final state = container.read(timerProvider);
      expect(state, isA<TimerStopped>());
      final draft = (state as TimerStopped).session;
      expect(draft.startTime, started.startTime.millisecondsSinceEpoch);
      expect(draft.endTime, inInclusiveRange(before, after));
      expect(draft.profileId, 'kid');
      expect(prefs.getString(_draftKey), isNotNull,
          reason: 'the draft survives the app being closed');
      expect(prefs.getInt('timer_start_ms'), isNull,
          reason: 'the timer itself is over');

      // Nothing saves on its own later.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.attempts, 1);
      expect(await db.select(db.sessions).get(), isEmpty);
    });

    test('from Paused keeps the draft too', () async {
      final container = await makeContainer({});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      await notifier.pause();

      final result = await notifier.stopAndSave();

      expect(result.isLeft(), isTrue);
      expect(container.read(timerProvider), isA<TimerStopped>());
      expect(prefs.getString(_draftKey), isNotNull);
    });

    test('the draft is still there after a restart', () async {
      final container =
          await makeContainer({'active_profile_id': 'kid'});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      await notifier.stopAndSave();
      final draft =
          (container.read(timerProvider) as TimerStopped).session;

      final restarted = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) => db),
        sessionsRepositoryProvider.overrideWith((_) => repo),
      ]);
      addTearDown(restarted.dispose);
      final back = restarted.read(timerProvider);
      expect(back, isA<TimerStopped>());
      expect((back as TimerStopped).session.id, draft.id);
      expect(back.session.profileId, 'kid');
    });

    test('saving the draft later works and clears it', () async {
      final container =
          await makeContainer({'active_profile_id': 'kid'});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      await notifier.stopAndSave();
      final draft =
          (container.read(timerProvider) as TimerStopped).session;

      repo.failing = false;
      final saved = await notifier.confirmSession(draft);

      expect(saved.isRight(), isTrue);
      expect(container.read(timerProvider), isA<TimerIdle>());
      expect(prefs.getString(_draftKey), isNull);
      final rows = await db.select(db.sessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.startTime, draft.startTime);
      expect(rows.single.endTime, draft.endTime);
      expect(rows.single.profileId, 'kid');
    });

    test('for Everyone saves later as Everyone (no profile)', () async {
      final container = await makeContainer({});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      await notifier.stopAndSave();
      final draft =
          (container.read(timerProvider) as TimerStopped).session;
      expect(draft.profileId, kEveryoneProfileId);

      repo.failing = false;
      await notifier.confirmSession(draft);
      final rows = await db.select(db.sessions).get();
      expect(rows.single.profileId, isNull);
    });

    test('from the notification keeps the draft too', () async {
      final container = await makeContainer({});
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();

      final result = await notifier.stopAndSave(fromNative: true);

      expect(result.isLeft(), isTrue);
      expect(container.read(timerProvider), isA<TimerStopped>());
      expect(prefs.getString(_draftKey), isNotNull);
    });

    test('from a notification STOP tapped while the app was closed keeps '
        'the draft', () async {
      final startMs = DateTime.now()
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch;
      final container = await makeContainer({
        'timer_start_ms': startMs,
        'timer_profile_id': 'default',
        notifPendingStop: true,
      });

      container.read(timerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(repo.attempts, 1);
      final state = container.read(timerProvider);
      expect(state, isA<TimerStopped>());
      expect((state as TimerStopped).session.startTime, startMs);
      expect(prefs.getString(_draftKey), isNotNull);
    });
  });

  test('a STOP whose save works is unchanged: saved, Idle, no draft',
      () async {
    final container = await makeContainer({});
    repo.failing = false;
    final notifier = container.read(timerProvider.notifier);
    await notifier.start();

    final result = await notifier.stopAndSave();

    final session = result.getOrElse((f) => fail('save failed: $f'));
    expect(container.read(timerProvider), isA<TimerIdle>());
    expect(prefs.getString(_draftKey), isNull);
    final rows = await db.select(db.sessions).get();
    expect(rows.single.id, session.id);
  });

  for (final entry in <String, Widget Function()>{
    'Timer': () => const TimerScreen(),
    'Flow': () => const FlowScreen(),
  }.entries) {
    for (final paused in [false, true]) {
      final from = paused ? 'Paused' : 'Running';
      for (final fails in [true, false]) {
        final what = fails ? 'a failed save' : 'a save that works';
        testWidgets('${entry.key}, STOP from $from, $what', (tester) async {
          final screen = entry.value();
          SharedPreferences.setMockInitialValues({});
          final p = await SharedPreferences.getInstance();
          final d = AppDatabase(NativeDatabase.memory());
          final r = _FlakyRepo(SessionsDao(d))
            ..failing = fails;
          await tester.binding.setSurfaceSize(const Size(600, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWith((_) => d),
              sharedPreferencesProvider.overrideWithValue(p),
              sessionsRepositoryProvider.overrideWith((_) => r),
            ],
            child: MaterialApp(home: screen),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          final container =
              ProviderScope.containerOf(tester.element(find.byWidget(screen)));
          final notifier = container.read(timerProvider.notifier);
          await tester.runAsync(() async {
            await notifier.start();
            if (paused) await notifier.pause();
          });
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.text('STOP'));
          // The save runs on the database, partly on real time and partly
          // on the test's clock, so step both until the line shows.
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)));
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(SnackBar).evaluate().isNotEmpty) break;
          }
          await tester.pump(const Duration(milliseconds: 500));

          if (fails) {
            expect(find.text('Couldn’t save the session'), findsOneWidget);
            expect(find.text('Session saved'), findsNothing);
            expect(find.text('This session isn’t saved yet'), findsOneWidget,
                reason: 'the draft waits in the unsaved-session panel');
            expect(find.text('Save session'), findsOneWidget);
            expect(container.read(timerProvider), isA<TimerStopped>());
          } else {
            expect(find.text('Session saved'), findsOneWidget);
            expect(find.text('Add notes'), findsOneWidget);
            expect(find.text('Couldn’t save the session'), findsNothing);
            expect(find.text('This session isn’t saved yet'), findsNothing);
            expect(container.read(timerProvider), isA<TimerIdle>());
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
        });
      }
    }
  }
}
