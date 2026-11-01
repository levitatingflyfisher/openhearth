import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/core/providers/database_provider.dart';
import 'package:lilt/core/providers/repository_providers.dart';
import 'package:lilt/core/providers/settings_providers.dart';
import 'package:lilt/domain/models/ranking.dart';
import 'package:lilt/domain/repositories/names_repository.dart';
import 'package:lilt/domain/repositories/session_repository.dart';
import 'package:lilt/domain/repositories/shortlist_repository.dart';
import 'package:lilt/features/home/home_screen.dart';
import 'package:lilt/features/matchup/matchup_screen.dart';
import 'package:lilt/features/name_detail/name_detail_screen.dart';
import 'package:lilt/features/results/couple_results_screen.dart';
import 'package:lilt/features/results/solo_results_screen.dart';
import 'package:lilt/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:lilt/features/settings/settings_screen.dart';
import 'package:lilt/features/shortlist/shortlist_screen.dart';
import 'package:lilt/services/database/database.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/navigation/nav_harness.dart';

/// A repository whose every read fails the way a broken disk does: with an
/// Exception. Riverpod 3 retries an Exception (never an Error) up to 10
/// times on its own; these count how often the app asks.
class _BrokenSessions implements SessionRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

class _BrokenNames implements NamesRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

class _BrokenShortlist implements ShortlistRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

/// The real repository, except the ensemble comparison fails.
class _NoMethodology extends SessionRepository {
  _NoMethodology(AppDatabase db, NamesRepository names)
      : super(db.sessionDao, db.eloMatchesDao, names);
  int calls = 0;
  @override
  Future<Methodology> methodology(String sessionId) async {
    calls++;
    throw Exception('disk read failed');
  }
}

/// Lilt keeps riverpod 2's behaviour: a provider that fails is not retried
/// on its own. Every failure here is a read of the phone's own database. A
/// loop against a broken disk helps nobody, and while it runs a spinner sits
/// where the plain error and its Try again belong. The household sees the
/// error and decides when to try again.
///
/// Each screen is pumped in a plain ProviderScope, without the root scope's
/// policy, so this pins the policy each provider carries itself.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late _BrokenSessions sessions;
  late _BrokenNames names;
  late _BrokenShortlist shortlist;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sessions = _BrokenSessions();
    names = _BrokenNames();
    shortlist = _BrokenShortlist();
  });
  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionRepositoryProvider.overrideWithValue(sessions),
        namesRepositoryProvider.overrideWithValue(names),
        shortlistRepositoryProvider.overrideWithValue(shortlist),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('lilt'),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
              appId: 'lilt',
              aadContext: 'lilt-backup/v1',
              appDisplayName: 'Lilt'),
        ),
        backupSerializerProvider
            .overrideWith((ref) => LiltBackupSerializer(db)),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
      child: MaterialApp(home: screen),
    ));
    await tester.pump();
    await tester.pump();
  }

  int allCalls() => sessions.calls + names.calls + shortlist.calls;

  /// Waits long enough for several of riverpod 3's default retries
  /// (200 ms apart, doubling) and checks nobody asked the disk again.
  Future<void> expectNoRetry(WidgetTester tester,
      {required bool showsTryAgain, String retryLabel = 'Try again'}) async {
    final before = allCalls();
    expect(before, greaterThan(0), reason: 'the screen read the disk once');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(allCalls(), before, reason: 'a failed read is not retried');
    if (showsTryAgain) {
      expect(find.text(retryLabel), findsOneWidget,
          reason: 'the error stays on screen, not a spinner');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Home: a failed session list is read once', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    expect(find.text('Couldn’t load your sessions'), findsOneWidget);
    await expectNoRetry(tester, showsTryAgain: true);
  });

  testWidgets('Shortlist: a failed shortlist is read once', (tester) async {
    await pumpScreen(tester, const ShortlistScreen());
    await expectNoRetry(tester, showsTryAgain: true);
  });

  testWidgets('Settings: a failed Recently cleared list is read once',
      (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    // Settings shows an empty Recently cleared on failure, so a retry loop
    // would run unseen. Only the count can show it.
    await expectNoRetry(tester, showsTryAgain: false);
  });

  testWidgets('Matchup: a failed session is read once', (tester) async {
    await pumpScreen(tester, const MatchupScreen(sessionId: 's'));
    await expectNoRetry(tester, showsTryAgain: true);
  });

  testWidgets('Solo results: a failed ranking is read once', (tester) async {
    await pumpScreen(tester, const SoloResultsScreen(sessionId: 's'));
    await expectNoRetry(tester, showsTryAgain: true);
  });

  testWidgets('Couple results: a failed ranking is read once',
      (tester) async {
    await pumpScreen(tester,
        const CoupleResultsScreen(sessionAId: 'a', sessionBId: 'b'));
    await expectNoRetry(tester, showsTryAgain: true);
  });

  testWidgets('Name detail: a failed name is read once', (tester) async {
    await pumpScreen(tester, const NameDetailScreen(nameId: 'n'));
    await expectNoRetry(tester,
        showsTryAgain: true, retryLabel: 'Back to your sessions');
  });

  testWidgets('Show methodology: a failed comparison is read once',
      (tester) async {
    late _NoMethodology repo;
    final h = await NavHarness.create(extraOverrides: [
      sessionRepositoryProvider.overrideWith((ref) => repo = _NoMethodology(
          ref.watch(databaseProvider), ref.watch(namesRepositoryProvider))),
    ]);
    addTearDown(h.dispose);
    await tester.runAsync(() => h.rankedSession());
    await h.pumpApp(tester);
    await tester.tap(find.text('Solo'));
    await NavHarness.settle(tester);

    final toggle = find.byType(Switch);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await NavHarness.settle(tester);
    expect(repo.calls, 1);

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await NavHarness.settle(tester);
    expect(repo.calls, 1, reason: 'a failed comparison is not retried');
    final tryAgain = find.text('Try again');
    await tester.ensureVisible(tryAgain);
    expect(tryAgain, findsOneWidget);
  });
}
