import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:lullaby/core/errors/failures.dart';
import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/core/providers/repository_providers.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/babies/domain/repositories/baby_repository.dart';
import 'package:lullaby/features/calendar/presentation/controllers/calendar_controller.dart';
import 'package:lullaby/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/tracking/domain/entities/diaper_log.dart';
import 'package:lullaby/features/tracking/domain/entities/feeding_log.dart';
import 'package:lullaby/features/tracking/domain/entities/sleep_log.dart';
import 'package:lullaby/features/tracking/domain/repositories/diaper_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/feeding_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/sleep_repository.dart';

// A failed read of the baby's log says so, with Try again. It is never drawn
// as a month (or a day) with nothing logged: a tired parent reads that as
// "the log is gone".

class _Babies extends Mock implements BabyRepository {}

class _Feedings extends Mock implements FeedingRepository {}

class _Sleeps extends Mock implements SleepRepository {}

class _Diapers extends Mock implements DiaperRepository {}

final _baby = BabyEntity(
  id: 'baby1',
  name: 'Alice',
  dateOfBirth: DateTime(2024, 12, 1),
  isActive: true,
  createdAt: DateTime(2025, 1, 1),
  modifiedAt: DateTime(2025, 1, 1),
);

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2025)));

  group('the providers', () {
    late ProviderContainer container;

    setUp(() {
      final babies = _Babies();
      final feedings = _Feedings();
      final sleeps = _Sleeps();
      final diapers = _Diapers();
      when(babies.watchActiveBaby).thenAnswer((_) => Stream.value(_baby));
      when(() => feedings.getInRange(any(), any(), any())).thenAnswer(
          (_) async => Err<List<FeedingLogEntity>>(DatabaseFailure.from(
              Exception('disk read failed'), StackTrace.current)));
      when(() => sleeps.getInRange(any(), any(), any()))
          .thenAnswer((_) async => const Success(<SleepLogEntity>[]));
      when(() => diapers.getInRange(any(), any(), any()))
          .thenAnswer((_) async => const Success(<DiaperLogEntity>[]));
      container = ProviderContainer(overrides: [
        babyRepositoryProvider.overrideWithValue(babies),
        feedingRepositoryProvider.overrideWithValue(feedings),
        sleepRepositoryProvider.overrideWithValue(sleeps),
        diaperRepositoryProvider.overrideWithValue(diapers),
      ]);
      addTearDown(container.dispose);
    });

    test('a failed month read is an error, never an empty month', () async {
      final range = (start: DateTime(2025, 1), end: DateTime(2025, 2));
      container.listen(calendarEventsProvider(range), (_, _) {});
      // Let the active baby arrive, which reads the month again.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(calendarEventsProvider(range)).hasError, isTrue);
    });

    test('a failed day read is an error, never an empty day', () async {
      final day = (babyId: 'baby1', day: DateTime(2025, 1, 3));
      container.listen(dayDetailProvider(day), (_, _) {});
      await expectLater(
          container.read(dayDetailProvider(day).future), throwsException);
    });
  });

  testWidgets('the calendar says a failed read, with Try again',
      (tester) async {
    var failing = true;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeBabyProvider.overrideWith((ref) => Stream.value(_baby)),
        calendarEventsProvider.overrideWith((ref, range) async {
          if (failing) throw Exception('disk read failed');
          return <DateTime, DayEventCounts>{};
        }),
      ],
      child: const MaterialApp(home: CalendarScreen()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(OhReadError), findsOneWidget);
    expect(find.text('Couldn’t read this month’s events'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(OhReadError), findsNothing);
  });
}
