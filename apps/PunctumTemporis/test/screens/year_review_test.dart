import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/screens/year_review_screen.dart';

void main() {
  late StorageService storageService;

  setUp(() async {
    AppTheme.visualStyle = 'modern';
    SharedPreferences.setMockInitialValues({
      'crt_effects': false,
    });
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
  });

  Widget buildApp() {
    return MaterialApp(
      theme: AppTheme.buildTheme(Brightness.dark, Colors.green),
      home: YearReviewScreen(storageService: storageService),
    );
  }

  testWidgets('renders without overflow on empty data', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(YearReviewScreen), findsOneWidget);
    expect(find.text('YEAR IN REVIEW'), findsOneWidget);
  });

  testWidgets('shows empty state when no clips', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // Scroll down to find the empty state message
    await tester.scrollUntilVisible(
      find.textContaining('NO CLIPS FOR'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final year = DateTime.now().year;
    expect(find.textContaining('NO CLIPS FOR $year'), findsOneWidget);
  });

  testWidgets('shows year selector with current year', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final year = DateTime.now().year;
    expect(find.text(year.toString()), findsOneWidget);
  });

  testWidgets('section headers render correctly', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('ACTIVITY'), findsOneWidget);
    expect(find.text('MONTHLY'), findsOneWidget);
    expect(find.text('STATISTICS'), findsOneWidget);
  });

  // 1 November 2026 is a Sunday, so its label starts a heatmap column, and
  // it still falls in daylight time. From local midnight on 1 January that is
  // 304 days less one hour, which a 24-hour count truncates to 303 and draws
  // the label a whole week early. Needs a daylight-saving zone to bite (the
  // suite runs with TZ=America/New_York); elsewhere it passes either way.
  testWidgets('a month label sits on its own week after a clock change',
      (tester) async {
    storageService.setClipsForTest({
      '2026-06-15': [
        Clip(
          id: 'c1',
          date: '2026-06-15',
          filePath: '/clips/c1.mp4',
          type: ClipType.video,
          createdAt: DateTime(2026, 6, 15),
        ),
      ],
    });
    await tester.pumpWidget(buildApp());
    await tester.pump();

    double left(String label) => tester
        .widget<Positioned>(find
            .ancestor(of: find.text(label), matching: find.byType(Positioned))
            .first)
        .left!;

    // December's column (48) needs no daylight correction, so the ratio
    // holds at any cell size.
    expect(left('N') / left('D'), closeTo(44 / 48, 1e-6));
  });

  // The heatmap asked for each day by adding 24 hours to local midnight on
  // 1 January. Where the clocks go back while the year's first day is in
  // daylight time (Sydney, Auckland), every later midnight lands at 23:00 on
  // the day before, so a clip showed on the wrong cell. Run it under
  // TZ=Australia/Sydney to see it; New York passes either way, because
  // there the offsets cancel out over the year.
  testWidgets('the heatmap asks for every day of the year once, in order',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final recording = _RecordingStorage(prefs);
    final year = DateTime.now().year;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.dark, Colors.green),
      home: YearReviewScreen(storageService: recording),
    ));
    await tester.pump();

    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final days = DateTime(year, 3, 0).day == 29 ? 366 : 365;
    final expected = [
      for (var i = 0; i < days; i++) key(DateTime(year, 1, 1 + i)),
    ];
    expect(recording.asked.length, greaterThanOrEqualTo(days));
    expect(recording.asked.take(days).toList(), expected);
  });

  group('StorageService range-stats', () {
    test('uniqueDatesInRange returns correct set', () {
      final result =
          storageService.uniqueDatesInRange('2026-01-01', '2026-12-31');
      expect(result, isEmpty);
    });

    test('getStreakInRange returns 0 for empty', () {
      final result =
          storageService.getStreakInRange('2026-01-01', '2026-12-31');
      expect(result, 0);
    });

    test('getLocationCountsInRange returns empty for no clips', () {
      final result =
          storageService.getLocationCountsInRange('2026-01-01', '2026-12-31');
      expect(result, isEmpty);
    });

    test('getTagCountsInRange returns empty for no clips', () {
      final result =
          storageService.getTagCountsInRange('2026-01-01', '2026-12-31');
      expect(result, isEmpty);
    });

    test('getFaceCountsInRange returns empty for no clips', () {
      final result =
          storageService.getFaceCountsInRange('2026-01-01', '2026-12-31');
      expect(result, isEmpty);
    });
  });

  group('Reminder preferences', () {
    test('default reminder is disabled', () {
      expect(storageService.getReminderEnabled(), false);
    });

    test('default reminder time is 20:00', () {
      final time = storageService.getReminderTime();
      expect(time.hour, 20);
      expect(time.minute, 0);
    });

    test('setReminderEnabled persists', () async {
      await storageService.setReminderEnabled(true);
      expect(storageService.getReminderEnabled(), true);
    });

    test('setReminderTime persists', () async {
      await storageService
          .setReminderTime(const TimeOfDay(hour: 9, minute: 30));
      final time = storageService.getReminderTime();
      expect(time.hour, 9);
      expect(time.minute, 30);
    });
  });
}

/// Records every day the heatmap asks about, in the order it asks.
class _RecordingStorage extends StorageService {
  _RecordingStorage(super.prefs);

  final asked = <String>[];

  @override
  int clipCountForDate(String date) {
    asked.add(date);
    return super.clipCountForDate(date);
  }
}
