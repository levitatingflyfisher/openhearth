// A restore replaces the whole record under every long-lived provider. These
// tests run a real restore into a real (in-memory) database, then the real
// restore hook, and check what the household sees afterwards: the home-screen
// widget and the growth screen's "Latest Measurement" card.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/core/providers/database_provider.dart';
import 'package:lullaby/core/providers/sync_providers.dart';
import 'package:lullaby/features/growth/presentation/controllers/growth_controller.dart';
import 'package:lullaby/features/home_widget/presentation/controllers/home_widget_controller.dart';
import 'package:lullaby/features/sanctuary_backup/after_restore.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/timer_controller.dart';
import 'package:lullaby/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:lullaby/features/sync/data/record_projection.dart';
import 'package:lullaby/features/sync/data/record_writer.dart';
import 'package:lullaby/services/database/database.dart';

import '../../../test_setup.dart';

/// What the widget was last told, key by key (`lullaby.last_sleep_time`...).
final _widget = <String, Object?>{};

/// One baby's record, all at [at]: a feed, a sleep, a diaper, a measurement.
Future<void> _seed(AppDatabase db,
    {required String name, required DateTime at, required double kg}) async {
  await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: name,
        dateOfBirth: DateTime(2026, 1, 1),
        isActive: const Value(true),
        createdAt: at,
        modifiedAt: at,
      ));
  await db.into(db.feedingLogs).insert(FeedingLogsCompanion.insert(
        id: 'f-$name',
        babyId: 'b1',
        type: 'bottle',
        startTime: at,
        createdAt: at,
        modifiedAt: at,
      ));
  await db.into(db.sleepLogs).insert(SleepLogsCompanion.insert(
        id: 's-$name',
        babyId: 'b1',
        startTime: at,
        endTime: Value(at.add(const Duration(minutes: 40))),
        type: 'nap',
        createdAt: at,
        modifiedAt: at,
      ));
  await db.into(db.diaperLogs).insert(DiaperLogsCompanion.insert(
        id: 'd-$name',
        babyId: 'b1',
        time: at,
        type: 'wet',
        createdAt: at,
        modifiedAt: at,
      ));
  await db.into(db.growthRecords).insert(GrowthRecordsCompanion.insert(
        id: 'g-$name',
        babyId: 'b1',
        measuredAt: at,
        weightKg: Value(kg),
        createdAt: at,
        modifiedAt: at,
      ));
}

String _utc(DateTime t) => t.toUtc().toIso8601String();

void main() {
  ensureSqlite3();
  TestWidgetsFlutterBinding.ensureInitialized();

  final before = DateTime(2026, 11, 1, 8);
  final restored = DateTime(2026, 10, 20, 15, 30);

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    _widget.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        _widget[args['id'] as String] = args['data'];
      }
      return true;
    });

    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      // Sync off: every write goes straight to Drift.
      recordWriterProvider
          .overrideWithValue(DirectRecordWriter(RecordProjection(db))),
    ]);
    // The app always listens to the active baby (LullabyApp, above every
    // screen). On riverpod 3 a stream nobody listens to is paused, and a
    // read of its future would wait for ever.
    container.listen(activeBabyProvider, (_, _) {});
    await _seed(db, name: 'Before', at: before, kg: 6.1);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  });

  /// A backup holding the restored record, made the way the app makes one.
  Future<Uint8List> backup({bool openSleep = false}) async {
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    await _seed(other, name: 'Restored', at: restored, kg: 5.4);
    if (openSleep) {
      final now = DateTime.now().subtract(const Duration(minutes: 20));
      await other.into(other.sleepLogs).insert(SleepLogsCompanion.insert(
            id: 's-open',
            babyId: 'b1',
            startTime: now,
            type: 'nap',
            createdAt: now,
            modifiedAt: now,
          ));
    }
    final bytes = await LullabyBackupSerializer(other).dumpAll();
    await other.close();
    return bytes;
  }

  /// The restore as the package runs it: the destructive apply, then the
  /// app's hook.
  Future<void> restore({bool openSleep = false}) async {
    final bytes = await backup(openSleep: openSleep);
    await LullabyBackupSerializer(db).restoreAll(bytes);
    container.read(Provider<void>((ref) => lullabyAfterRestore(ref)));
    // Let the hook's widget redraw finish, and the timers' reload with the
    // redraw it makes.
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> widgetUpdate() =>
      container.read(homeWidgetControllerProvider).triggerUpdate();

  /// The widget as the app draws it once the active baby has loaded: on
  /// launch and after every log.
  Future<void> drawWidget() async {
    await container.read(activeBabyProvider.future);
    await widgetUpdate();
    expect(_widget['lullaby.baby_name'], isNot('–'));
  }

  group('after a restore the home-screen widget shows the restored record',
      () {
    setUp(() async {
      // The widget was drawn before the restore, as it is on every launch,
      // so anything it caches holds the old record.
      await drawWidget();
      expect(_widget['lullaby.last_sleep_time'], _utc(before));
      await restore();
    });

    test('last sleep', () {
      expect(_widget['lullaby.last_sleep_time'], _utc(restored));
    });

    test('last diaper', () {
      expect(_widget['lullaby.last_diaper_time'], _utc(restored));
    });

    test('last feed', () {
      expect(_widget['lullaby.last_feed_time'], _utc(restored));
    });

    test('baby name', () {
      expect(_widget['lullaby.baby_name'], 'Restored');
    });
  });

  test('after a restore the widget shows the restored record\'s running sleep',
      () async {
    await drawWidget();
    expect(_widget['lullaby.active_timer_type'], isNull);
    await restore(openSleep: true);
    expect(_widget['lullaby.active_timer_type'], 'sleep');
    // The app's own timer row too, not only the widget.
    expect([for (final t in container.read(activeTimersProvider)) t.logId],
        ['s-open']);
  });

  test('after a restore the growth card shows the restored measurement',
      () async {
    final card = container.listen(latestGrowthProvider('b1'), (_, _) {});
    addTearDown(card.close);
    await container.read(latestGrowthProvider('b1').future);
    expect(card.read().value?.weightKg, 6.1);

    await restore();
    await container.read(latestGrowthProvider('b1').future);
    expect(card.read().value?.weightKg, 5.4);
  });

  // The same cache, outside a restore: the audit missed that these were
  // never refreshed at all, so a new sleep or measurement went unseen too.
  test('a sleep logged after the widget was drawn reaches the widget',
      () async {
    await drawWidget();
    final later = before.add(const Duration(hours: 3));
    await db.into(db.sleepLogs).insert(SleepLogsCompanion.insert(
          id: 's-later',
          babyId: 'b1',
          startTime: later,
          type: 'nap',
          createdAt: later,
          modifiedAt: later,
        ));
    await widgetUpdate();
    expect(_widget['lullaby.last_sleep_time'], _utc(later));
  });

  test('a diaper logged after the widget was drawn reaches the widget',
      () async {
    await drawWidget();
    final later = before.add(const Duration(hours: 3));
    await db.into(db.diaperLogs).insert(DiaperLogsCompanion.insert(
          id: 'd-later',
          babyId: 'b1',
          time: later,
          type: 'dirty',
          createdAt: later,
          modifiedAt: later,
        ));
    await widgetUpdate();
    expect(_widget['lullaby.last_diaper_time'], _utc(later));
  });

  test('a new measurement reaches the growth card', () async {
    final card = container.listen(latestGrowthProvider('b1'), (_, _) {});
    addTearDown(card.close);
    await container.read(latestGrowthProvider('b1').future);
    final later = before.add(const Duration(days: 7));
    await db.into(db.growthRecords).insert(GrowthRecordsCompanion.insert(
          id: 'g-later',
          babyId: 'b1',
          measuredAt: later,
          weightKg: const Value(6.6),
          createdAt: later,
          modifiedAt: later,
        ));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(card.read().value?.weightKg, 6.6);
  });
}
