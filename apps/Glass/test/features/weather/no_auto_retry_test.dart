import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glass/core/providers/core_providers.dart';
import 'package:glass/core/storage/app_database.dart';
import 'package:glass/features/weather/data/open_meteo_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A forecast that fails is shown as failed, with Try again, and nothing
/// fetches again on its own. Each fetch is a request that carries a place to
/// the network, so the household decides when another one goes out.
/// Riverpod 3 retries a failed provider by default (up to 10 times, from
/// 200 ms apart); this pins that WeatherGlass does not.
void main() {
  test('a failed forecast is fetched once and not retried on its own',
      () async {
    var attempts = 0;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      openMeteoProvider.overrideWithValue(_Offline(() => attempts++)),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    final id = await container
        .read(locationsRepositoryProvider)
        .add(label: 'Berlin', lat: 52.52, lon: 13.41);

    // Home watches the forecast while it is on screen.
    container.listen(forecastProvider(id), (_, __) {}, fireImmediately: true);
    await expectLater(
        container.read(forecastProvider(id).future), throwsA(anything));
    expect(attempts, 1);

    // Long enough for several of riverpod 3's default retries.
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(attempts, 1, reason: 'no fetch goes out without a tap');
    expect(container.read(forecastProvider(id)).hasError, isTrue,
        reason: 'the error stays on screen with its Try again');
  });
}

class _Offline extends OpenMeteo {
  _Offline(this.onAttempt);
  final void Function() onAttempt;
  @override
  Future<String> fetchForecastJson(double lat, double lon) async {
    onAttempt();
    throw http.ClientException('offline');
  }
}
