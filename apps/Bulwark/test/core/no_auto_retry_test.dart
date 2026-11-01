// A failed read of the phone's own database is shown once, with its Try
// again, and is not read again on its own. Riverpod 3 retries a failed
// provider up to 10 times by default; for a disk read that only puts a
// spinner where the error and Try again belong. These tests pin the old
// behaviour: one read, then the error, and nothing more until the household
// taps Try again.
//
// The failures are `Exception`s on purpose. Riverpod 3 never retries an
// `Error`, so the `StateError` in load_failure_test.dart could not catch a
// retry.

import 'package:bulwark/core/providers/core_providers.dart';
import 'package:bulwark/core/storage/app_database.dart' hide UserPrefs;
import 'package:bulwark/features/adoption/presentation/progress_screen.dart';
import 'package:bulwark/features/adoption/presentation/providers.dart';
import 'package:bulwark/features/adoption/presentation/queue_screen.dart';
import 'package:bulwark/features/adoption/presentation/shopping_screen.dart';
import 'package:bulwark/features/checkin/presentation/checkin_screen.dart';
import 'package:bulwark/features/home/presentation/home_screen.dart';
import 'package:bulwark/features/library/data/content_loader.dart';
import 'package:bulwark/features/settings/domain/settings_repository.dart';
import 'package:bulwark/features/settings/domain/user_prefs.dart';
import 'package:bulwark/shared/theme/app_theme.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../support/adoption_harness.dart';

/// Fails every read, as a broken disk would, and counts them.
class _FailReads extends QueryInterceptor {
  int reads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    reads++;
    throw Exception('disk read failed');
  }
}

/// The prefs stream fails when it is listened to, as a broken disk would.
/// A fake rather than [_FailReads], because a closed drift query stream
/// leaves a timer behind that a widget test cannot flush.
class _FailingSettings implements SettingsRepository {
  _FailingSettings(this.reads);
  final _FailReads reads;

  @override
  Stream<UserPrefs> watchUserPrefs() {
    reads.reads++;
    return Stream.error(Exception('disk read failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets the clock run five seconds in small steps: long enough for riverpod
/// 3's default retry (200 ms, doubling) to have read again several times.
Future<void> _wait5s(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  final providers = <String, ProviderListenable<AsyncValue<Object?>>>{
    'profile': profileProvider,
    'activeHabits': activeHabitsProvider,
    'todaysCheckins': todaysCheckinsProvider,
    'pulseDue': pulseDueProvider,
    'queuedHabits': queuedHabitsProvider,
    'pausedHabits': pausedHabitsProvider,
    'graduatedHabits': graduatedHabitsProvider,
    'habitStatesById': habitStatesByIdProvider,
    'shoppingStates': shoppingStatesProvider,
    'allCheckins': allCheckinsProvider,
    'allPulses': allPulsesProvider,
    'graduationEligible': graduationEligibleProvider,
    'weakTriggerIds': weakTriggerIdsProvider,
    'userPrefs': userPrefsProvider,
  };

  for (final p in providers.entries) {
    testWidgets('${p.key}: a failed read stays an error and is read once',
        (tester) async {
      final reads = _FailReads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);

      // A plain ProviderScope: this tests the provider's own policy, not
      // the app's root scope.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          contentLibraryProvider.overrideWith((ref) => testLibrary()),
          settingsRepositoryProvider
              .overrideWithValue(_FailingSettings(reads)),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Consumer(
            builder: (context, ref, _) => Text(ref.watch(p.value).when(
                  data: (_) => 'data',
                  error: (_, _) => 'error',
                  loading: () => 'loading',
                )),
          ),
        ),
      ));
      await _wait5s(tester);

      expect(find.text('error'), findsOneWidget);
      expect(reads.reads, 1);
    });
  }

  // Each screen and whether it shows the fleet's failure state. Progress
  // and Shopping draw what they could read (`value ?? empty`, as
  // `valueOrNull` did on riverpod 2), so for them the pin is only that the spinner a retry
  // would bring back stays away.
  final screens = <String, (Widget, bool)>{
    'Home': (const HomeScreen(), true),
    'Check-in': (const CheckinScreen(), true),
    'Queue': (const QueueScreen(), true),
    'Progress': (const ProgressScreen(), false),
    'Shopping': (const ShoppingScreen(), false),
  };

  for (final s in screens.entries) {
    testWidgets('${s.key}: a failed disk read keeps its Try again and is not '
        'read again on its own', (tester) async {
      final reads = _FailReads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [...adoptionOverrides(db: db), ...backupOverrides()],
        child: MaterialApp(theme: AppTheme.light, home: s.value.$1),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      final first = reads.reads;
      expect(first, greaterThan(0));

      await _wait5s(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      if (s.value.$2) {
        expect(find.byType(OhErrorState), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      }
      expect(reads.reads, first);
    });
  }
}
