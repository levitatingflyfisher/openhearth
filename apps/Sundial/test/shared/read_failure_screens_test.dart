import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/flow_mode/presentation/flow_screen.dart';
import 'package:sundial/features/profiles/data/local_profiles_repository.dart';
import 'package:sundial/features/profiles/data/profiles_dao.dart';
import 'package:sundial/features/sessions/data/local_sessions_repository.dart';
import 'package:sundial/features/sessions/data/sessions_dao.dart';
import 'package:sundial/features/sessions/presentation/history_screen.dart';
import 'package:sundial/features/stats/presentation/cumulative_chart.dart';
import 'package:sundial/features/stats/presentation/heatmap_chart.dart';
import 'package:sundial/features/stats/presentation/stats_screen.dart';

// A failed read of the household's own time or people says so, with Try
// again. It is never drawn as "0h this year", as empty days, or as a
// missing row of people: a parent reads those as "our time is gone".
// After Try again, with a read that works, the data is there.

final _disk = Exception('disk read failed');

/// Which reads fail. Each fake reads the real in-memory database once its
/// switch is off.
class _Switch {
  bool year = false;
  bool days = false;
  bool sessions = false;
  bool totals = false;
  bool profiles = false;
}

class _Sessions extends LocalSessionsRepository {
  _Sessions(AppDatabase db, this.sw) : super(SessionsDao(db));
  final _Switch sw;

  @override
  Stream<int> watchSecondsForYear(String year) =>
      sw.year ? Stream.error(_disk) : super.watchSecondsForYear(year);
  @override
  Stream<int> watchSecondsForDay(String dateDay) =>
      sw.days ? Stream.error(_disk) : super.watchSecondsForDay(dateDay);
  @override
  Stream<List<Session>> watchAllSessionsFiltered(String? profileId) =>
      sw.sessions
          ? Stream.error(_disk)
          : super.watchAllSessionsFiltered(profileId);
  @override
  Stream<int> watchSecondsForYearFiltered(String year, String? profileId) =>
      sw.totals
          ? Stream.error(_disk)
          : super.watchSecondsForYearFiltered(year, profileId);
}

class _Profiles extends LocalProfilesRepository {
  _Profiles(AppDatabase db, this.sw) : super(ProfilesDao(db), SessionsDao(db));
  final _Switch sw;
  @override
  Stream<List<Profile>> watchAll() =>
      sw.profiles ? Stream.error(_disk) : super.watchAll();
}

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

void main() {
  late AppDatabase db;
  late _Switch sw;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sw = _Switch();
    for (final (id, name) in [('a', 'Ada'), ('b', 'Ben')]) {
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: id,
            name: name,
            colorValue: 0xFF5E9478,
            createdAt: 0,
            sortOrder: const Value(0),
          ));
    }
    final now = DateTime.now();
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: 's',
          startTime: now.millisecondsSinceEpoch,
          endTime: now.millisecondsSinceEpoch + 7200000,
          durationSecs: 7200,
          dateDay: _today(),
          profileId: const Value('a'),
          createdAt: 0,
          updatedAt: 0,
        ));
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((_) => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionsRepositoryProvider.overrideWithValue(_Sessions(db, sw)),
        profilesRepositoryProvider.overrideWithValue(_Profiles(db, sw)),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  void expectSaid(WidgetTester tester, String title) {
    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  }

  Future<void> tryAgain(WidgetTester tester) async {
    sw
      ..year = false
      ..days = false
      ..sessions = false
      ..totals = false
      ..profiles = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsNothing);
  }

  group('Flow', () {
    testWidgets('a failed year read is said, never "0h this year"',
        (tester) async {
      sw.year = true;
      await pump(tester, const FlowScreen());

      expectSaid(tester, 'Couldn’t read this year’s time');
      expect(find.textContaining('this year ·'), findsNothing);

      await tryAgain(tester);
      expect(find.textContaining('this year ·'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a failed read of the last seven days is said',
        (tester) async {
      sw.days = true;
      await pump(tester, const FlowScreen());

      expectSaid(tester, 'Couldn’t read the last seven days');

      await tryAgain(tester);
      await unmount(tester);
    });

    testWidgets('a failed read of the people is said, never no chips',
        (tester) async {
      sw.profiles = true;
      await pump(tester, const FlowScreen());

      expectSaid(tester, 'Couldn’t read your people');

      await tryAgain(tester);
      expect(find.text('Ada'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('History', () {
    testWidgets('a failed read of the people is said', (tester) async {
      sw.profiles = true;
      await pump(tester, const HistoryScreen());

      expectSaid(tester, 'Couldn’t read your people');

      await tryAgain(tester);
      expect(find.text('Ada'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('a failed read of the sessions is said, never a spinner',
        (tester) async {
      sw.sessions = true;
      await pump(tester, const HistoryScreen());

      expectSaid(tester, 'Couldn’t read your sessions');

      await tryAgain(tester);
      await unmount(tester);
    });
  });

  group('Stats', () {
    testWidgets('a failed read of the people is said', (tester) async {
      sw.profiles = true;
      await pump(tester, const StatsScreen());

      expectSaid(tester, 'Couldn’t read your people');

      await tryAgain(tester);
      expect(find.text('Ada'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a failed total is said, never 0h', (tester) async {
      sw.totals = true;
      await pump(tester, const StatsScreen());

      expectSaid(tester, 'Couldn’t read this total');

      await tryAgain(tester);
      await unmount(tester);
    });

    testWidgets(
        'a failed read of the sessions is said in each part, never empty '
        'months, an empty year or "0m total"', (tester) async {
      sw.sessions = true;
      await pump(tester, const StatsScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('Couldn’t read this year by month'), findsOneWidget);
      expect(find.text('Couldn’t read your hours outside'), findsOneWidget);
      expect(find.text('Couldn’t read the last 12 months'), findsOneWidget);
      expect(find.text('0m total'), findsNothing);

      // Each part's Try again reads that part again.
      sw.sessions = false;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Try again').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Try again'), findsNothing);
      expect(find.text('2h total'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('Stats charts, alone', () {
    testWidgets('a failed read of all time is said, never "0m total"',
        (tester) async {
      sw.sessions = true;
      await pump(tester, const Scaffold(body: CumulativeChart()));

      expectSaid(tester, 'Couldn’t read your hours outside');
      // The card's frame stays above the error.
      expect(find.text('Hours outside, all time'), findsOneWidget);
      expect(find.text('0m total'), findsNothing);

      await tryAgain(tester);
      expect(find.text('2h total'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a failed read of the last 12 months is said, never empty days',
        (tester) async {
      sw.sessions = true;
      await pump(tester, const Scaffold(body: HeatmapChart()));

      expectSaid(tester, 'Couldn’t read the last 12 months');
      expect(find.text('Last 12 months'), findsOneWidget);
      final grid = find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_HeatmapPainter');
      expect(grid, findsNothing, reason: 'no grid of empty days');

      await tryAgain(tester);
      expect(grid, findsOneWidget);
      await unmount(tester);
    });
  });
}
