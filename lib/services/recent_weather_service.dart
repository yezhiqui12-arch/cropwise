import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'polygon_calculator.dart';

typedef WeatherHttpGet = Future<String> Function(Uri uri);

class CurrentFieldWeather {
  const CurrentFieldWeather({
    required this.temperatureC,
    required this.weatherCode,
    required this.isDay,
    required this.soilMoisture,
    required this.observedAt,
  });

  final double temperatureC;
  final int weatherCode;
  final bool isDay;
  final double? soilMoisture;
  final DateTime observedAt;
}

String weatherLabelForCode(int code) => switch (code) {
  0 => 'Clear sky',
  1 => 'Mostly clear',
  2 => 'Partly cloudy',
  3 => 'Overcast',
  45 || 48 => 'Foggy',
  51 || 53 || 55 || 56 || 57 => 'Drizzle',
  61 || 63 || 65 || 66 || 67 => 'Rain',
  71 || 73 || 75 || 77 => 'Snow',
  80 || 81 || 82 => 'Rain showers',
  85 || 86 => 'Snow showers',
  95 || 96 || 99 => 'Thunderstorm',
  _ => 'Current weather',
};

class OpenMeteoCurrentWeatherService {
  const OpenMeteoCurrentWeatherService();

  Future<CurrentFieldWeather> current({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(6),
      'longitude': longitude.toStringAsFixed(6),
      'current': 'temperature_2m,weather_code,is_day,soil_moisture_0_to_1cm',
      'temperature_unit': 'celsius',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Cropwise/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Weather service returned ${response.statusCode}.');
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid current weather response.');
      }
      final values = decoded['current'];
      if (values is! Map<String, dynamic>) {
        throw const FormatException('Current weather is unavailable.');
      }
      final temperature = values['temperature_2m'];
      final weatherCode = values['weather_code'];
      final isDay = values['is_day'];
      if (temperature is! num || weatherCode is! num || isDay is! num) {
        throw const FormatException('Current weather is incomplete.');
      }
      return CurrentFieldWeather(
        temperatureC: temperature.toDouble(),
        weatherCode: weatherCode.toInt(),
        isDay: isDay.toInt() == 1,
        soilMoisture: (values['soil_moisture_0_to_1cm'] as num?)?.toDouble(),
        observedAt:
            DateTime.tryParse(values['time']?.toString() ?? '') ??
            DateTime.now(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class RecentWeatherCoordinates {
  const RecentWeatherCoordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

RecentWeatherCoordinates? resolveRecentWeatherCoordinates({
  required double? storedLatitude,
  required double? storedLongitude,
  required String boundaryGeoJson,
}) {
  if (storedLatitude != null && storedLongitude != null) {
    return RecentWeatherCoordinates(storedLatitude, storedLongitude);
  }
  final points = PolygonCalculator.fromGeoJson(boundaryGeoJson);
  if (points.isEmpty) return null;
  final center = PolygonCalculator.calculateCenter(points);
  return RecentWeatherCoordinates(center.latitude, center.longitude);
}

class RecentRainSnapshot {
  const RecentRainSnapshot({
    required this.precipitationMm,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.fetchedAtUtc,
  });

  final double precipitationMm;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final DateTime fetchedAtUtc;

  String toJson() => jsonEncode({
    'precipitation_mm': precipitationMm,
    'period_start_utc': periodStartUtc.toIso8601String(),
    'period_end_utc': periodEndUtc.toIso8601String(),
    'fetched_at_utc': fetchedAtUtc.toIso8601String(),
  });

  static RecentRainSnapshot? tryParse(String? value) {
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return RecentRainSnapshot(
        precipitationMm: (json['precipitation_mm'] as num).toDouble(),
        periodStartUtc: DateTime.parse(json['period_start_utc'] as String),
        periodEndUtc: DateTime.parse(json['period_end_utc'] as String),
        fetchedAtUtc: DateTime.parse(json['fetched_at_utc'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

abstract interface class RecentWeatherService {
  Future<RecentRainSnapshot> recentRain({
    required double latitude,
    required double longitude,
    DateTime? nowUtc,
  });
}

class OpenMeteoRecentWeatherService implements RecentWeatherService {
  OpenMeteoRecentWeatherService({WeatherHttpGet? httpGet})
    : _httpGet = httpGet ?? _defaultGet;

  final WeatherHttpGet _httpGet;

  @override
  Future<RecentRainSnapshot> recentRain({
    required double latitude,
    required double longitude,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final start = now.subtract(const Duration(hours: 48));
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(6),
      'longitude': longitude.toStringAsFixed(6),
      'hourly': 'precipitation',
      'past_days': '3',
      'forecast_days': '1',
      'timezone': 'UTC',
    });
    final decoded = jsonDecode(await _httpGet(uri)) as Map<String, dynamic>;
    final hourly = decoded['hourly'] as Map<String, dynamic>?;
    final times = hourly?['time'] as List<dynamic>?;
    final precipitation = hourly?['precipitation'] as List<dynamic>?;
    if (times == null ||
        precipitation == null ||
        times.length != precipitation.length) {
      throw const FormatException(
        'Open-Meteo returned incomplete hourly data.',
      );
    }

    var total = 0.0;
    var samples = 0;
    for (var index = 0; index < times.length; index++) {
      final rawTime = times[index] as String;
      final time = DateTime.parse(
        rawTime.endsWith('Z') ? rawTime : '${rawTime}Z',
      );
      if (time.isBefore(start) || time.isAfter(now)) continue;
      final value = precipitation[index];
      if (value is! num) continue;
      total += value.toDouble();
      samples++;
    }
    if (samples == 0) {
      throw const FormatException('Open-Meteo returned no recent hourly data.');
    }
    return RecentRainSnapshot(
      precipitationMm: total,
      periodStartUtc: start,
      periodEndUtc: now,
      fetchedAtUtc: now,
    );
  }

  static Future<String> _defaultGet(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Cropwise/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Weather service returned ${response.statusCode}.',
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
