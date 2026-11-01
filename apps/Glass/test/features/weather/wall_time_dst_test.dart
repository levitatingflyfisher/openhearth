import 'package:flutter_test/flutter_test.dart';
import 'package:glass/features/weather/data/models.dart';

// Open-Meteo sends the place's wall clock with no offset. Parsed as a device
// local time, a wall time that falls in the device zone's spring-forward gap
// (02:00 on 2026-03-08 in New York) is moved to 03:00, so the hourly strip
// shows 3 AM twice and the sunrise is an hour out. The device zone and the
// place's zone are unrelated, so the parse must not depend on either.
// Run under TZ=America/New_York to see it fail; under UTC it cannot.
Map<String, dynamic> _json() => {
      'utc_offset_seconds': 0,
      'current': {
        'time': '2026-03-08T02:00',
        'temperature_2m': 1.0,
        'apparent_temperature': 0.0,
        'weather_code': 0,
        'is_day': 0,
        'wind_speed_10m': 1.0,
        'relative_humidity_2m': 50,
        'precipitation': 0.0,
      },
      'hourly': {
        'time': [
          '2026-03-08T01:00',
          '2026-03-08T02:00',
          '2026-03-08T03:00',
        ],
        'temperature_2m': [1.0, 1.0, 1.0],
        'precipitation_probability': [0, 0, 0],
        'weather_code': [0, 0, 0],
      },
      'daily': {
        'time': ['2026-03-08'],
        'weather_code': [0],
        'temperature_2m_max': [5.0],
        'temperature_2m_min': [0.0],
        'precipitation_probability_max': [0],
        'sunrise': ['2026-03-08T02:30'],
        'sunset': ['2026-03-08T17:30'],
      },
    };

void main() {
  test('wall times keep their hour whatever zone the device is in', () {
    final f = Forecast.fromJson(_json());
    expect(f.hourly.map((h) => h.time.hour), [1, 2, 3]);
    expect(f.current.time.hour, 2);
    expect(f.daily.first.sunrise!.hour, 2);
    expect(f.daily.first.sunrise!.minute, 30);
    expect(f.hourly[1].time.isBefore(f.hourly[2].time), isTrue);
  });
}
