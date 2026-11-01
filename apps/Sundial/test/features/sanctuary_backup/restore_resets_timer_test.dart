// A restore replaces every profile and session. The timer and the two Undo
// offers live for the whole app, outside the database, so the restore hook
// must end them: otherwise a timer started for a profile the restore removed
// saves a session for it, and an Undo writes pre-restore data into the
// restored record. These tests run the real hook, after a real restoreAll.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/sanctuary_backup/backup_config.dart';
import 'package:sundial/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:sundial/features/sessions/presentation/session_undo.dart';
import 'package:sundial/features/timer/domain/timer_state.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';
import 'package:sundial/features/timer/presentation/unsaved_session_panel.dart';

/// Hands the container's own Ref to the hook, the way the backup controller
/// calls it, outside any provider's build.
final _refProvider = Provider<Ref>((ref) => ref);

const _timerKeys = [
  'timer_start_ms',
  'timer_paused_accumulated_secs',
  'timer_profile_id',
  'timer_unsaved_draft',
];

late AppDatabase db;
late SharedPreferences prefs;
late ProviderContainer container;
late List<MethodCall> timerChannelCalls;
String? widgetTodayHours;

Future<void> _seedProfile(AppDatabase d, String id, String name) =>
    d.into(d.profiles).insert(ProfilesCompanion.insert(
          id: id,
          name: name,
          colorValue: 0xFF5E9478,
          createdAt: 1700000000000,
        ));

Session _session(String id, String? profileId) => Session(
      id: id,
      startTime: DateTime(2026, 4, 1, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 4, 1, 10).millisecondsSinceEpoch,
      durationSecs: 3600,
      notes: null,
      dateDay: '2026-04-01',
      profileId: profileId,
      locationLabel: null,
      lat: null,
      lng: null,
      createdAt: 0,
      updatedAt: 0,
    );

/// A backup made on another device: one profile, 'grandma', and none of the
/// profiles this device has now.
Future<Uint8List> _backupWithoutKid() async {
  final other = AppDatabase(NativeDatabase.memory());
  addTearDown(other.close);
  await _seedProfile(other, 'grandma', 'Grandma');
  return SundialBackupSerializer(other).dumpAll();
}

/// What the backup controller does on a confirmed restore: replace the
/// database, then run the app's hook.
Future<void> _restore() async {
  await SundialBackupSerializer(db).restoreAll(await _backupWithoutKid());
  afterSundialRestore(container.read(_refProvider));
  // The hook starts the timer's prefs writes and the widget refresh without
  // waiting; let them land.
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void _mockChannels() {
  timerChannelCalls = [];
  widgetTodayHours = null;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const timerChannel = MethodChannel('com.openhearth.sundial/media_session');
  const widgetChannel = MethodChannel('home_widget');
  messenger.setMockMethodCallHandler(timerChannel, (call) async {
    timerChannelCalls.add(call);
    return null;
  });
  messenger.setMockMethodCallHandler(widgetChannel, (call) async {
    if (call.method == 'saveWidgetData') {
      final args = call.arguments as Map;
      if (args['id'] == 'today_hours') {
        widgetTodayHours = args['data'] as String?;
      }
      return true;
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(timerChannel, null);
    messenger.setMockMethodCallHandler(widgetChannel, null);
  });
}

Future<void> _setUp(Map<String, Object> prefsValues) async {
  _mockChannels();
  SharedPreferences.setMockInitialValues(prefsValues);
  prefs = await SharedPreferences.getInstance();
  db = AppDatabase(NativeDatabase.memory());
  container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appDatabaseProvider.overrideWith((_) => db),
  ]);
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await _seedProfile(db, 'kid', 'Kid');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('a restore ends the timer, so it cannot save for a removed profile',
      () {
    test(
        'a running timer for a profile the restore removed is ended, its '
        'stored keys go, and its notification is dismissed', () async {
      await _setUp({});
      container.read(activeProfileIdProvider.notifier).select('kid');
      await container.read(timerProvider.notifier).start();
      expect(container.read(timerProvider), isA<TimerRunning>());

      await _restore();

      expect(container.read(timerProvider), isA<TimerIdle>(),
          reason: 'a running timer would save a session for "kid", whom '
              'the restore removed');
      for (final key in _timerKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(
        timerChannelCalls.where((c) => c.method == 'dismiss'),
        isNotEmpty,
        reason: 'the notification would still offer STOP for "kid"',
      );
    });

    test('a paused timer is ended too', () async {
      await _setUp({
        'timer_paused_accumulated_secs': 1800,
        'timer_profile_id': 'kid',
      });
      expect(container.read(timerProvider), isA<TimerPaused>());

      await _restore();

      expect(container.read(timerProvider), isA<TimerIdle>());
      for (final key in _timerKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    });

    test(
        'a timer running when the app was last closed does not come back '
        'after a restart', () async {
      await _setUp({
        'timer_start_ms': DateTime.now()
            .subtract(const Duration(minutes: 20))
            .millisecondsSinceEpoch,
        'timer_profile_id': 'kid',
      });
      expect(container.read(timerProvider), isA<TimerRunning>());

      await _restore();

      // A fresh start of the app rebuilds the timer from the stored keys.
      final restarted = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) => db),
      ]);
      addTearDown(restarted.dispose);
      expect(restarted.read(timerProvider), isA<TimerIdle>());
    });

    test(
        'an unsaved draft for a removed profile is dropped, in memory and '
        'on disk', () async {
      await _setUp({});
      container.read(activeProfileIdProvider.notifier).select('kid');
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      await notifier.buildDraftSession();
      expect(container.read(timerProvider), isA<TimerStopped>());

      await _restore();

      expect(container.read(timerProvider), isA<TimerIdle>());
      expect(prefs.containsKey('timer_unsaved_draft'), isFalse);
    });

    test(
        'the home-screen widget is refreshed without the ended timer\'s '
        'time', () async {
      await _setUp({
        'timer_start_ms': DateTime.now()
            .subtract(const Duration(hours: 1, minutes: 30))
            .millisecondsSinceEpoch,
        'timer_profile_id': 'kid',
      });
      expect(container.read(timerProvider), isA<TimerRunning>());

      await _restore();

      expect(widgetTodayHours, '0m',
          reason: 'the restored record has no time today, and the timer '
              'that held 1h 30m is gone');
    });
  });

  group('a restore ends both app-wide Undo offers', () {
    test(
        'a pending "session deleted" Undo is dropped, so it cannot put the '
        'old session into the restored record', () async {
      await _setUp({});
      final repo = container.read(sessionsRepositoryProvider);
      final old = _session('old-session', 'kid');
      await repo.saveSession(old);
      await repo.deleteSession(old.id);
      final undo = container.read(sessionUndoControllerProvider);
      var committed = false;
      undo.show(
        message: 'Deleted 1h on Wed, Apr 1',
        onUndo: () async => repo.saveSession(old),
        onCommit: () async => committed = true,
      );

      await _restore();

      expect(undo.pending, isNull);
      expect(committed, isFalse, reason: 'a restore never commits the offer');
      await undo.undo();
      final ids = (await db.select(db.sessions).get()).map((s) => s.id);
      expect(ids, isNot(contains('old-session')));
    });

    test(
        'a pending "draft discarded" Undo is dropped, so it cannot bring an '
        'old draft back', () async {
      await _setUp({});
      container.read(activeProfileIdProvider.notifier).select('kid');
      final notifier = container.read(timerProvider.notifier);
      await notifier.start();
      final draft = await notifier.buildDraftSession();
      notifier.discard();
      final undo = container.read(timerUndoControllerProvider);
      var committed = false;
      undo.show(
        message: 'Discarded 0m · today',
        onUndo: () async => notifier.restoreDiscarded(draft),
        onCommit: () async => committed = true,
      );

      await _restore();

      expect(undo.pending, isNull);
      expect(committed, isFalse, reason: 'a restore never commits the offer');
      await undo.undo();
      expect(container.read(timerProvider), isA<TimerIdle>());
      expect(prefs.containsKey('timer_unsaved_draft'), isFalse);
    });
  });
}
