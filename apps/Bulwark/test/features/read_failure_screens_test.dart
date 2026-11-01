import 'package:bulwark/core/storage/app_database.dart';
import 'package:bulwark/features/adoption/data/checkin_repository.dart';
import 'package:bulwark/features/adoption/data/habit_state_repository.dart';
import 'package:bulwark/features/adoption/data/pulse_repository.dart';
import 'package:bulwark/features/adoption/data/shopping_repository.dart';
import 'package:bulwark/features/adoption/domain/checkin.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';
import 'package:bulwark/features/adoption/domain/habit_state.dart';
import 'package:bulwark/features/adoption/domain/pulse.dart';
import 'package:bulwark/features/adoption/domain/shopping_state.dart';
import 'package:bulwark/features/adoption/presentation/progress_screen.dart';
import 'package:bulwark/features/adoption/presentation/providers.dart';
import 'package:bulwark/features/adoption/presentation/queue_screen.dart';
import 'package:bulwark/features/adoption/presentation/shopping_screen.dart';
import 'package:bulwark/features/checkin/presentation/checkin_screen.dart';
import 'package:bulwark/features/library/domain/enums.dart';
import 'package:bulwark/features/library/domain/intervention.dart';
import 'package:bulwark/features/library/presentation/intervention_detail_screen.dart';
import 'package:bulwark/shared/extensions/datetime_ext.dart';
import 'package:bulwark/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../support/adoption_harness.dart';
import '../support/content_builders.dart';

/// A failed read of the household's own data is never drawn as an empty
/// list: the screen says it couldn't read, offers Try again, and once the
/// read works again the data is there. An empty list on a failed read tells
/// a parent their habits are gone, and they may start over on top of them.
///
/// Each fake reads the real in-memory database until [failing] is set, then
/// throws, so the real providers and the real screens run.
class _Switch {
  bool failing = true;
  void check() {
    if (failing) throw StateError('disk I/O error');
  }
}

class _HabitStates extends HabitStateRepository {
  _HabitStates(super.db, this.sw, {this.only});
  final _Switch sw;

  /// Fail only reads of this status (and getAll when null).
  final HabitStatus? only;

  @override
  Future<List<HabitState>> byStatus(HabitStatus status) {
    if (only == null || only == status) sw.check();
    return super.byStatus(status);
  }

  @override
  Future<List<HabitState>> getAll() {
    if (only == null) sw.check();
    return super.getAll();
  }
}

class _Checkins extends CheckinRepository {
  _Checkins(super.db, this.sw);
  final _Switch sw;

  @override
  Future<List<Checkin>> since(DateTime date) {
    sw.check();
    return super.since(date);
  }

  @override
  Future<List<Checkin>> getAll() {
    sw.check();
    return super.getAll();
  }
}

class _Pulses extends PulseRepository {
  _Pulses(super.db, this.sw);
  final _Switch sw;

  @override
  Future<List<Pulse>> getAll() {
    sw.check();
    return super.getAll();
  }
}

class _Shopping extends ShoppingRepository {
  _Shopping(super.db, this.sw);
  final _Switch sw;

  @override
  Future<List<ShoppingState>> getAll() {
    sw.check();
    return super.getAll();
  }
}

void main() {
  late AppDatabase db;
  late _Switch sw;

  setUp(() {
    db = memoryDatabase();
    sw = _Switch();
  });
  tearDown(() => db.close());

  Future<void> put(String id, HabitStatus status) =>
      HabitStateRepository(db).upsert(HabitState(
        interventionId: id,
        status: status,
        activatedAt: DateTime(2026, 1, 1),
        graduatedAt:
            status == HabitStatus.graduated ? DateTime(2026, 2, 1) : null,
        createdAt: DateTime(2026, 1, 1),
      ));

  final library = libraryOf([
    intervention(id: 'sleep-window'),
    intervention(
      id: 'acv',
      shopping: const Shopping(
        item: 'Apple cider vinegar',
        criteria: 'any ACV; always dilute',
        recurring: true,
        where: ShopWhere.grocery,
      ),
    ),
  ]);

  Future<void> pump(
      WidgetTester tester, Widget screen, List<Override> fakes) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [...adoptionOverrides(db: db, library: library), ...fakes],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ));
    await tester.pumpAndSettle();
  }

  /// The read-failure state is up, with Try again, and none of [emptyTexts].
  void expectReadError(String title, List<String> emptyTexts) {
    expect(find.byType(OhReadError), findsOneWidget);
    expect(find.text(title), findsOneWidget);
    expect(find.text(OhErrorMessages.readFailed), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    for (final t in emptyTexts) {
      expect(find.textContaining(t), findsNothing, reason: 'drawn as empty');
    }
  }

  Future<void> tryAgainWorking(WidgetTester tester) async {
    sw.failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(OhReadError), findsNothing);
  }

  group('Progress', () {
    const empty = ['No stones yet', 'Nothing here yet'];

    testWidgets('a failed read of the habits is not an empty wall',
        (tester) async {
      await put('sleep-window', HabitStatus.graduated);
      await pump(tester, const ProgressScreen(), [
        habitStateRepositoryProvider.overrideWithValue(_HabitStates(db, sw))
      ]);

      expectReadError('Couldn’t read your progress', empty);

      await tryAgainWorking(tester);
      expect(find.text('sleep-window'), findsOneWidget);
    });

    testWidgets('a failed read of the check-ins is not an empty trend',
        (tester) async {
      await put('sleep-window', HabitStatus.active);
      await CheckinRepository(db).upsert(Checkin(
        interventionId: 'sleep-window',
        date: DateTime.now().dateOnly,
        result: CheckinResult.did,
      ));
      await pump(tester, const ProgressScreen(),
          [checkinRepositoryProvider.overrideWithValue(_Checkins(db, sw))]);

      expectReadError('Couldn’t read your progress',
          [...empty, 'Check in through the week']);

      await tryAgainWorking(tester);
      expect(find.textContaining('1 of 1 check-ins done'), findsOneWidget);
    });

    testWidgets('a failed read of the pulses is not drawn as no pulses',
        (tester) async {
      await put('sleep-window', HabitStatus.graduated);
      await pump(tester, const ProgressScreen(),
          [pulseRepositoryProvider.overrideWithValue(_Pulses(db, sw))]);

      expectReadError('Couldn’t read your progress', empty);

      await tryAgainWorking(tester);
      expect(find.text('sleep-window'), findsOneWidget);
    });
  });

  group('Shopping', () {
    const empty = ['Nothing to buy'];

    testWidgets('a failed read of the habits is not an empty list',
        (tester) async {
      await put('acv', HabitStatus.active);
      await pump(tester, const ShoppingScreen(), [
        habitStateRepositoryProvider.overrideWithValue(_HabitStates(db, sw))
      ]);

      expectReadError('Couldn’t read your shopping list', empty);

      await tryAgainWorking(tester);
      expect(find.text('Apple cider vinegar'), findsOneWidget);
    });

    testWidgets('a failed read of what was bought is not all unticked',
        (tester) async {
      await put('acv', HabitStatus.active);
      await ShoppingRepository(db).setPurchased('acv',
          purchased: true, purchasedAt: DateTime(2026, 1, 2));
      await pump(tester, const ShoppingScreen(),
          [shoppingRepositoryProvider.overrideWithValue(_Shopping(db, sw))]);

      expectReadError('Couldn’t read your shopping list', empty);
      expect(find.byType(Checkbox), findsNothing);

      await tryAgainWorking(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });
  });

  testWidgets(
      'Queue: a failed read of the set-aside habits is not an empty '
      'queue', (tester) async {
    await put('sleep-window', HabitStatus.paused);
    await pump(tester, const QueueScreen(), [
      habitStateRepositoryProvider
          .overrideWithValue(_HabitStates(db, sw, only: HabitStatus.paused)),
    ]);

    expectReadError('Couldn’t read your queue', ['Your queue is empty']);

    await tryAgainWorking(tester);
    expect(find.text('Set aside'), findsOneWidget);
    expect(find.text('sleep-window'), findsOneWidget);
  });

  group('Check-in', () {
    testWidgets(
        'a failed read of today’s answers does not show them unanswered',
        (tester) async {
      await put('sleep-window', HabitStatus.active);
      await CheckinRepository(db).upsert(Checkin(
        interventionId: 'sleep-window',
        date: DateTime.now().dateOnly,
        result: CheckinResult.did,
      ));
      await pump(tester, const CheckinScreen(),
          [checkinRepositoryProvider.overrideWithValue(_Checkins(db, sw))]);

      expectReadError('Couldn’t read today’s habits', ['Nothing to log yet']);
      expect(find.text('sleep-window'), findsNothing);

      await tryAgainWorking(tester);
      expect(find.text('sleep-window'), findsOneWidget);
    });

    testWidgets('a failed read of the weekly pulse is not "nothing to log"',
        (tester) async {
      await put('sleep-window', HabitStatus.graduated);
      await pump(tester, const CheckinScreen(),
          [pulseRepositoryProvider.overrideWithValue(_Pulses(db, sw))]);

      expectReadError('Couldn’t read today’s habits', ['Nothing to log yet']);

      await tryAgainWorking(tester);
      expect(find.text('Weekly pulse'), findsOneWidget);
    });
  });

  testWidgets(
      'Detail: a failed read of the habit’s state does not offer to '
      'start it again', (tester) async {
    await put('sleep-window', HabitStatus.active);
    await pump(tester, const InterventionDetailScreen(id: 'sleep-window'),
        [habitStateRepositoryProvider.overrideWithValue(_HabitStates(db, sw))]);

    expectReadError('Couldn’t read this habit', ['Activate', 'Add to queue']);

    await tryAgainWorking(tester);
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('Activate'), findsNothing);
  });
}
