import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/recent_weather_service.dart';

void main() {
  test('sums only precipitation from the previous 48 hours', () async {
    late Uri requestedUri;
    final service = OpenMeteoRecentWeatherService(
      httpGet: (uri) async {
        requestedUri = uri;
        return jsonEncode({
          'hourly': {
            'time': [
              '2026-08-23T11:00',
              '2026-08-24T12:00',
              '2026-08-25T12:00',
              '2026-08-26T12:00',
              '2026-08-26T13:00',
            ],
            'precipitation': [99, 1.2, 0.3, 2.5, 88],
          },
        });
      },
    );

    final result = await service.recentRain(
      latitude: 17.759,
      longitude: 121.561,
      nowUtc: DateTime.utc(2026, 8, 26, 12),
    );

    expect(result.precipitationMm, closeTo(4.0, 0.001));
    expect(requestedUri.host, 'api.open-meteo.com');
    expect(requestedUri.queryParameters['timezone'], 'UTC');
    expect(RecentRainSnapshot.tryParse(result.toJson())?.precipitationMm, 4.0);
  });

  test('rejects incomplete hourly weather data', () async {
    final service = OpenMeteoRecentWeatherService(
      httpGet: (_) async => jsonEncode({
        'hourly': {
          'time': ['2026-08-26T12:00'],
          'precipitation': <double>[],
        },
      }),
    );

    expect(
      () => service.recentRain(
        latitude: 17,
        longitude: 121,
        nowUtc: DateTime.utc(2026, 8, 26, 12),
      ),
      throwsFormatException,
    );
  });

  test('derives weather coordinates from a legacy saved outline', () {
    final location = resolveRecentWeatherCoordinates(
      storedLatitude: null,
      storedLongitude: null,
      boundaryGeoJson:
          '{"type":"Polygon","coordinates":[[[121.56,17.75],[121.57,17.75],[121.57,17.76],[121.56,17.75]]]}',
    );

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(17.753, 0.01));
    expect(location.longitude, closeTo(121.565, 0.01));
  });
}
