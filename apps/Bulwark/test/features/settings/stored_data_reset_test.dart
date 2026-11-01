// Erase and restore change the database under every keepAlive read model.
// These tests hold the line for the whole class: each keepAlive read model is
// in storedDataReadModels, and after either path every one of them shows the
// data now in the database, not a copy from before.
import 'dart:io';

import 'package:bulwark/core/storage/app_database.dart' hide UserPrefs;
import 'package:bulwark/features/adoption/data/checkin_repository.dart';
import 'package:bulwark/features/adoption/data/habit_state_repository.dart';
import 'package:bulwark/features/adoption/data/profile_repository.dart';
import 'package:bulwark/features/adoption/data/pulse_repository.dart';
import 'package:bulwark/features/adoption/data/shopping_repository.dart';
import 'package:bulwark/features/adoption/domain/checkin.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';
import 'package:bulwark/features/adoption/domain/habit_state.dart';
import 'package:bulwark/features/adoption/domain/profile.dart';
import 'package:bulwark/features/adoption/domain/pulse.dart';
import 'package:bulwark/features/adoption/presentation/providers.dart';
import 'package:bulwark/features/settings/presentation/settings_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncProviderListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/adoption_harness.dart';

const _profile = Profile(
  wakeMinutes: 7 * 60,
  bedMinutes: 22 * 60,
  goal: Goal.general,
  pace: Pace.moderate,
  onboarded: true,
);

final _refProvider = Provider<Ref>((ref) => ref);

/// One habit in each status, plus a check-in, a pulse and a purchase, so
/// every read model has something to cache.
Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  final longAgo = now.subtract(const Duration(days: 60));
  await ProfileRepository(db).save(_profile);
  final habits = HabitStateRepository(db);
  await habits.upsert(HabitState(
    interventionId: 'sleep-window',
    status: HabitStatus.active,
    activatedAt: longAgo,
    createdAt: longAgo,
  ));
  await habits.upsert(HabitState(
    interventionId: 'eat-protein',
    status: HabitStatus.paused,
    createdAt: longAgo,
  ));
  await habits.upsert(HabitState(
    interventionId: 'box-breathing',
    status: HabitStatus.queued,
    queuePosition: 0,
    createdAt: longAgo,
  ));
  await CheckinRepository(db).upsert(Checkin(
    interventionId: 'sleep-window',
    date: now,
    result: CheckinResult.did,
  ));
  await PulseRepository(db).upsert(Pulse(
    interventionId: 'sleep-window',
    weekStart: longAgo,
    result: PulseResult.solid,
  ));
  await ShoppingRepository(db).setPurchased('sleep-window', purchased: true);
}

bool _isEmpty(Object? v) =>
    v == null || (v is Iterable && v.isEmpty) || (v is Map && v.isEmpty);

Future<Map<String, Object?>> _readAll(ProviderContainer c) async => {
      for (final p in storedDataReadModels)
        p.name!: await c.read((p as AsyncProviderListenable<Object?>).future),
    };

void main() {
  test('every keepAlive read model in providers.dart is reset by both paths',
      () {
    final source = File('lib/features/adoption/presentation/providers.dart')
        .readAsStringSync();
    final declared = RegExp(
      r'@Riverpod\(keepAlive: true[^)]*\)\s*\n[^\n(]*?\s(\w+)\(Ref ref\)',
    ).allMatches(source).map((m) => '${m[1]}Provider').toSet();

    expect(declared, isNotEmpty, reason: 'the scan must find the providers');
    expect(storedDataReadModels.map((p) => p.name).toSet(), declared);
  });

  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  testWidgets('after an erase every read model is empty', (tester) async {
    await _seed(db);
    await tester.pumpWidget(ProviderScope(
      overrides: adoptionOverrides(db: db),
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          home: TextButton(
            onPressed: () => eraseAllData(ref),
            child: const Text('erase'),
          ),
        ),
      ),
    ));
    final container =
        ProviderScope.containerOf(tester.element(find.text('erase')));

    final before = (await tester.runAsync(() => _readAll(container)))!;
    expect(before['pausedHabitsProvider'], isNotEmpty);
    expect(before['activeHabitsProvider'], isNotEmpty);

    await tester.tap(find.text('erase'));
    await tester.pumpAndSettle();

    final after = (await tester.runAsync(() => _readAll(container)))!;
    for (final e in after.entries) {
      expect(_isEmpty(e.value), isTrue, reason: '${e.key} still holds data');
    }
  });

  test('after a restore every read model shows the restored data', () async {
    await _seed(db);
    final container = ProviderContainer(overrides: adoptionOverrides(db: db));
    addTearDown(container.dispose);

    final before = await _readAll(container);
    expect(before['pausedHabitsProvider'], isNotEmpty);

    // The restored backup was empty: the restore leaves no rows behind.
    await db.eraseUserData();
    await afterBackupRestore(container.read(_refProvider));

    final after = await _readAll(container);
    for (final e in after.entries) {
      expect(_isEmpty(e.value), isTrue, reason: '${e.key} still holds data');
    }
  });
}
