import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glass/core/providers/core_providers.dart';
import 'package:glass/core/router/app_router.dart';
import 'package:glass/core/storage/app_database.dart';
import 'package:glass/features/weather/data/models.dart';
import 'package:glass/features/weather/presentation/forecast_view.dart';
import 'package:glass/features/weather/presentation/home_screen.dart';
import 'package:glass/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedLocation _place(String id, String label, int order) => SavedLocation(
      id: id,
      label: label,
      sublabel: null,
      lat: 52.52,
      lon: 13.41,
      isCurrent: false,
      sortOrder: order,
      createdAt: 0,
    );

final _places = [
  _place('berlin', 'Berlin', 0),
  _place('paris', 'Paris', 1),
  _place('oslo', 'Oslo', 2),
];

Forecast _forecast() {
  final base = DateTime(2026, 6, 25);
  return Forecast(
    current: CurrentConditions(
        time: DateTime(2026, 6, 25, 14),
        temperatureC: 23.6,
        apparentC: 24.8,
        weatherCode: 0,
        isDay: true,
        windKmh: 12,
        humidity: 47,
        precipMm: 0),
    hourly: [
      for (var i = 0; i < 48; i++)
        HourlyPoint(
            time: base.add(Duration(hours: i)),
            temperatureC: 18,
            precipProbability: 0,
            weatherCode: 0),
    ],
    daily: [
      for (var i = 0; i < 7; i++)
        DailyPoint(
            date: base.add(Duration(days: i)),
            weatherCode: 0,
            highC: 25,
            lowC: 14,
            precipProbabilityMax: 0),
    ],
    utcOffsetSeconds: 7200,
  );
}

String _shownPlace(WidgetTester tester) {
  final views = tester
      .widgetList<ForecastView>(find.byType(ForecastView).hitTestable())
      .toList();
  expect(views, hasLength(1));
  return views.single.location.id;
}

/// The Places list doubles as a switcher: tapping a place pops back to Home,
/// which turns to that place. Home hears the request through a provider
/// listener while Places covers it. Riverpod 3 pauses listeners of widgets
/// that are not visible, so this pins that the request still lands once
/// Home is shown again.
void main() {
  testWidgets('tapping a place in Places turns Home to it', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider
            .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
        savedLocationsProvider.overrideWith((ref) => Stream.value(_places)),
        for (final p in _places)
          forecastProvider(p.id).overrideWith((ref) => _forecast()),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('weatherglass'),
        sanctuaryBackupConfigProvider.overrideWithValue(
            const SanctuaryBackupConfig(
                appId: 'weatherglass',
                aadContext: 'weatherglass-backup/v1',
                appDisplayName: 'WeatherGlass')),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(_shownPlace(tester), 'berlin');

    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();
    // Home is covered and its tickers are off: the condition under which
    // riverpod 3 pauses its listener.
    expect(
        TickerMode.of(
            tester.element(find.byType(HomeScreen, skipOffstage: false))),
        isFalse);
    await tester.tap(find.widgetWithText(ListTile, 'Oslo'));
    await tester.pumpAndSettle();

    expect(_shownPlace(tester), 'oslo');
  });
}
