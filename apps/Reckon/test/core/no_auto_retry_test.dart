// A failed read of the phone's own data is shown once and is not read again
// on its own. Riverpod 3 retries a failed provider up to 10 times by default
// (from 200 ms, doubling). For a disk or keychain read that only puts a
// spinner where the error belongs; for the model it would load the model
// again and again. These tests pin the old behaviour: one read, then the
// error, and nothing more until the person asks again.
//
// Each provider fails through its real dependency (the database, the
// keychain channel, a repository), so the provider's own policy is what is
// tested. The failures are `Exception`s on purpose: riverpod 3 never retries
// an `Error`, so a `StateError` could not catch a retry.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:reckon/app/root_overrides.dart';
import 'package:reckon/core/auth/auth_providers.dart';
import 'package:reckon/core/database/app_database.dart';
import 'package:reckon/core/database/database_providers.dart';
import 'package:reckon/core/llm/anthropic_key_store.dart';
import 'package:reckon/core/llm/llm_providers.dart';
import 'package:reckon/core/llm/stove_secret_store.dart';
import 'package:reckon/core/notifications/local_notification_service.dart';
import 'package:reckon/core/notifications/notification_providers.dart';
import 'package:reckon/core/theme/theme_preference.dart';
import 'package:reckon/features/case/data/case_providers.dart';
import 'package:reckon/features/case/data/case_repository_impl.dart';
import 'package:reckon/features/case/domain/entities/case.dart';
import 'package:reckon/features/case/presentation/home_screen.dart';
import 'package:reckon/features/forecasters/data/forecaster_providers.dart';
import 'package:reckon/features/glossary/data/glossary_providers.dart';
import 'package:reckon/features/glossary/domain/entities/glossary_entry.dart';
import 'package:reckon/features/glossary/domain/repositories/glossary_repository.dart';
import 'package:reckon/features/glossary/presentation/glossary_screen.dart';
import 'package:reckon/features/outside_view/data/outside_view_providers.dart';
import 'package:reckon/features/party/data/group_providers.dart';
import 'package:reckon/features/party/data/party_providers.dart';
import 'package:reckon/features/party/presentation/groups_screen.dart';
import 'package:reckon/features/party/sync/party_sync_providers.dart';
import 'package:reckon/features/predictions/data/prediction_providers.dart';
import 'package:reckon/features/record/data/record_providers.dart';
import 'package:reckon/features/record/presentation/record_screen.dart';
import 'package:reckon/features/reveal/data/reveal_providers.dart';
import 'package:reckon/shared/theme/reckon_theme.dart';

/// Counts every read that reaches storage, of any kind.
class _Reads {
  int count = 0;
}

/// Fails every database read, as a broken disk would, and counts them.
class _FailDbReads extends QueryInterceptor {
  _FailDbReads(this.reads);
  final _Reads reads;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    reads.count++;
    throw Exception('disk read failed');
  }
}

/// The open-decisions stream fails when it is listened to. A fake rather
/// than [_FailDbReads], because a failed drift query stream leaves a timer
/// that a widget test cannot flush.
class _FailingCaseStream extends CaseRepositoryImpl {
  _FailingCaseStream(super.db, this.reads);
  final _Reads reads;

  @override
  Stream<List<Case>> watchActive() {
    reads.count++;
    return Stream.error(Exception('disk read failed'));
  }
}

class _FailingGlossary implements GlossaryRepository {
  _FailingGlossary(this.reads);
  final _Reads reads;

  @override
  Future<List<GlossaryEntry>> all() async {
    reads.count++;
    throw Exception('asset read failed');
  }

  @override
  Future<GlossaryEntry?> byId(String id) async {
    reads.count++;
    throw Exception('asset read failed');
  }
}

class _FailingNotifications implements LocalNotificationService {
  _FailingNotifications(this.reads);
  final _Reads reads;

  @override
  Future<void> init() async {
    reads.count++;
    throw Exception('notification plugin failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _keychain = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Every keychain call fails, as a locked keychain would, and is counted.
void _failKeychain(WidgetTester tester, _Reads reads) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_keychain, (call) async {
    reads.count++;
    throw PlatformException(code: 'locked', message: 'keychain is locked');
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_keychain, null));
}

/// Lets the clock run five seconds in small steps: long enough for riverpod
/// 3's default retry (200 ms, doubling) to have run several times.
Future<void> _wait5s(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Builds the overrides that fail every storage dependency through [reads].
/// The model is never loaded: [llmServiceProvider] is replaced by a load
/// that fails at once, so the test pins that provider's own policy without
/// touching flutter_gemma.
List<dynamic> _failingDeps(AppDatabase db, _Reads reads) => [
      appDatabaseProvider.overrideWithValue(db),
      caseRepositoryProvider
          .overrideWith((ref) => _FailingCaseStream(db, reads)),
      glossaryRepositoryProvider
          .overrideWithValue(_FailingGlossary(reads)),
      localNotificationServiceProvider
          .overrideWithValue(_FailingNotifications(reads)),
      llmServiceProvider.overrideWith((ref) async {
        reads.count++;
        throw Exception('the model failed to load');
      }),
    ];

/// Listens to one provider on [c] and reports each state change. The
/// subscription closes with the container.
typedef _Listen = void Function(
    ProviderContainer c, void Function(AsyncValue<Object?>) onChange);

void main() {
  // One entry per async provider in lib/. Each listens on a container and
  // reports every state change.
  final providers = <String, _Listen>{
    'onboardingComplete': (c, f) =>
        c.listen(onboardingCompleteProvider, (_, n) => f(n)),
    'seedReferenceClasses': (c, f) =>
        c.listen(seedReferenceClassesProvider, (_, n) => f(n)),
    'hasAnthropicKey': (c, f) =>
        c.listen(hasAnthropicKeyProvider, (_, n) => f(n)),
    'hasStovePhrase': (c, f) =>
        c.listen(hasStovePhraseProvider, (_, n) => f(n)),
    'selectedModelId': (c, f) =>
        c.listen(selectedModelIdProvider, (_, n) => f(n)),
    'llmService': (c, f) => c.listen(llmServiceProvider, (_, n) => f(n)),
    'onDeviceModelReady': (c, f) =>
        c.listen(onDeviceModelReadyProvider, (_, n) => f(n)),
    'initNotifications': (c, f) =>
        c.listen(initNotificationsProvider, (_, n) => f(n)),
    'themePreference': (c, f) =>
        c.listen(themePreferenceProvider, (_, n) => f(n)),
    'openCasesStream': (c, f) =>
        c.listen(openCasesStreamProvider, (_, n) => f(n)),
    'caseById': (c, f) => c.listen(caseByIdProvider('c1'), (_, n) => f(n)),
    'pollsForCase': (c, f) =>
        c.listen(pollsForCaseProvider('c1'), (_, n) => f(n)),
    'forecasters': (c, f) => c.listen(forecastersProvider, (_, n) => f(n)),
    'enabledForecasters': (c, f) =>
        c.listen(enabledForecastersProvider, (_, n) => f(n)),
    'runnableForecasters': (c, f) =>
        c.listen(runnableForecastersProvider, (_, n) => f(n)),
    'glossaryEntries': (c, f) =>
        c.listen(glossaryEntriesProvider, (_, n) => f(n)),
    'glossaryEntry': (c, f) =>
        c.listen(glossaryEntryProvider('g1'), (_, n) => f(n)),
    'getOutsideView': (c, f) =>
        c.listen(getOutsideViewProvider, (_, n) => f(n)),
    'outsideViewForCase': (c, f) =>
        c.listen(outsideViewForCaseProvider('c1'), (_, n) => f(n)),
    'party': (c, f) => c.listen(partyProvider('p1'), (_, n) => f(n)),
    'partyResult': (c, f) =>
        c.listen(partyResultProvider('p1'), (_, n) => f(n)),
    'groups': (c, f) => c.listen(groupsProvider, (_, n) => f(n)),
    'group': (c, f) => c.listen(groupProvider('g1'), (_, n) => f(n)),
    'groupMembers': (c, f) =>
        c.listen(groupMembersProvider('g1'), (_, n) => f(n)),
    'groupParties': (c, f) =>
        c.listen(groupPartiesProvider('g1'), (_, n) => f(n)),
    'partyIsSynced': (c, f) =>
        c.listen(partyIsSyncedProvider('p1'), (_, n) => f(n)),
    'forecasterWeights': (c, f) =>
        c.listen(forecasterWeightsProvider, (_, n) => f(n)),
    'duelForecastsForCase': (c, f) =>
        c.listen(duelForecastsForCaseProvider('c1'), (_, n) => f(n)),
    'closedCaseRecords': (c, f) =>
        c.listen(closedCaseRecordsProvider, (_, n) => f(n)),
    'clarityScore': (c, f) => c.listen(clarityScoreProvider, (_, n) => f(n)),
    'insightCards': (c, f) => c.listen(insightCardsProvider, (_, n) => f(n)),
    'closedCases': (c, f) => c.listen(closedCasesProvider, (_, n) => f(n)),
    'calibrationReport': (c, f) =>
        c.listen(calibrationReportProvider, (_, n) => f(n)),
    'personalBaseRates': (c, f) =>
        c.listen(personalBaseRatesProvider, (_, n) => f(n)),
    'updateQuality': (c, f) =>
        c.listen(updateQualityProvider, (_, n) => f(n)),
    'generateReveal': (c, f) =>
        c.listen(generateRevealProvider, (_, n) => f(n)),
  };

  for (final p in providers.entries) {
    testWidgets('${p.key}: a failed read stays an error and is not read again',
        (tester) async {
      final reads = _Reads();
      _failKeychain(tester, reads);
      final db = AppDatabase(
          NativeDatabase.memory().interceptWith(_FailDbReads(reads)));
      addTearDown(db.close);

      // A plain container: this tests the provider's own policy, not the
      // app's root scope.
      final container =
          ProviderContainer(overrides: _failingDeps(db, reads).cast());
      addTearDown(container.dispose);

      final states = <AsyncValue<Object?>>[];
      p.value(container, states.add);

      await tester.pump(const Duration(milliseconds: 100));
      final firstError = states.indexWhere((s) => s is AsyncError);
      expect(firstError, isNot(-1), reason: 'the read must fail at once');
      final readsAtError = reads.count;
      expect(readsAtError, greaterThan(0),
          reason: 'the failure must come through a real dependency');

      await _wait5s(tester);

      expect(states.skip(firstError + 1), isEmpty,
          reason: 'no reload after the error: ${states.skip(firstError)}');
      expect(states.last.hasError, isTrue);
      expect(states.last.isLoading, isFalse);
      expect(reads.count, readsAtError);
    });
  }

  // Screens that draw the fleet's failure state. After a failed read they
  // keep it, with no spinner coming back, and read nothing more. They run
  // under the app's own root scope, as in the app: Home also shows the
  // shared backup reminder, whose keychain providers cannot name a policy
  // and rely on the root's.
  final screens = <String, Widget>{
    'Home': const HomeScreen(),
    'Record': const RecordScreen(),
    'Glossary': const GlossaryScreen(),
    'Groups': const GroupsScreen(),
  };

  for (final s in screens.entries) {
    testWidgets('${s.key}: a failed read keeps its error and is not read '
        'again on its own', (tester) async {
      final reads = _Reads();
      _failKeychain(tester, reads);
      final db = AppDatabase(
          NativeDatabase.memory().interceptWith(_FailDbReads(reads)));
      addTearDown(db.close);

      await tester.pumpWidget(reckonProviderScope(
        overrides: _failingDeps(db, reads).cast(),
        child: MaterialApp(theme: ReckonTheme.light(), home: s.value),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      final first = reads.count;
      expect(first, greaterThan(0));
      expect(find.byType(OhErrorState), findsWidgets);

      await _wait5s(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(OhErrorState), findsWidgets);
      expect(reads.count, first);
    });
  }
}
