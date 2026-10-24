import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/esri_imagery_coverage.dart';

Map<String, dynamic> reply(Uri uri, {bool available = true}) {
  final parts = uri.pathSegments;
  final row = int.parse(parts[parts.length - 4]);
  final col = int.parse(parts[parts.length - 3]);
  final width = int.parse(parts[parts.length - 2]);
  final height = int.parse(parts.last);
  return {
    'location': {'left': col, 'top': row, 'width': width, 'height': height},
    'data': List.filled(width * height, available ? 1 : 0),
  };
}

int zoom(Uri uri) => int.parse(uri.pathSegments[uri.pathSegments.length - 5]);

void main() {
  const field = LatLng(17.830542, 121.502989);
  test('uses the highest available imagery and caches the location', () async {
    final requests = <Uri>[];
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        requests.add(uri);
        return reply(uri);
      },
    );
    expect(await coverage.nativeZoomFor(field), 20);
    final count = requests.length;
    expect(await coverage.nativeZoomFor(field), 20);
    expect(requests.length, count);
  });

  test('missing levels 19 and 20 fall back to level 18', () async {
    final requests = <Uri>[];
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        requests.add(uri);
        return reply(uri, available: zoom(uri) <= 18);
      },
    );
    expect(await coverage.nativeZoomFor(field), 18);
    expect(requests.map(zoom), containsAllInOrder([20, 19, 18]));
  });

  test('a missing neighbor also lowers the imagery level', () async {
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        final result = reply(uri);
        if (zoom(uri) == 20) (result['data'] as List)[0] = 0;
        return result;
      },
    );
    expect(await coverage.nativeZoomFor(field), 19);
  });

  test('missing bundles are treated as missing coverage', () async {
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        return zoom(uri) > 18
            ? {
                'error': {'code': 422},
              }
            : reply(uri);
      },
    );
    expect(await coverage.nativeZoomFor(field), 18);
  });

  test('offline failure is not cached as absent imagery', () async {
    var offline = true;
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        if (offline) throw const SocketException('Offline');
        return reply(uri);
      },
    );
    expect(await coverage.nativeZoomFor(field), isNull);
    offline = false;
    expect(await coverage.nativeZoomFor(field), 20);
  });

  test(
    'rejects clipped or malformed coverage instead of inventing it',
    () async {
      final coverage = EsriImageryCoverage(
        fetch: (uri) async {
          final result = reply(uri);
          (result['location'] as Map)['width'] = 0;
          return result;
        },
      );
      expect(await coverage.nativeZoomFor(field), isNull);
      final invalid = EsriImageryCoverage(
        fetch: (uri) async {
          final result = reply(uri);
          (result['data'] as List)[0] = 2;
          return result;
        },
      );
      expect(await invalid.nativeZoomFor(field), isNull);
    },
  );

  test('splits tilemap requests across 128-tile bundle boundaries', () async {
    final requests = <Uri>[];
    final coverage = EsriImageryCoverage(
      fetch: (uri) async {
        requests.add(uri);
        final location = reply(uri)['location'] as Map;
        final col = location['left'] as int, row = location['top'] as int;
        final width = location['width'] as int,
            height = location['height'] as int;
        expect(col ~/ 128, (col + width - 1) ~/ 128);
        expect(row ~/ 128, (row + height - 1) ~/ 128);
        return reply(uri);
      },
    );
    expect(await coverage.nativeZoomFor(const LatLng(0, 0)), 20);
    expect(requests, hasLength(4));
  });

  test('invalid coordinates do not request coverage', () async {
    final coverage = EsriImageryCoverage(
      fetch: (_) async => fail('Unexpected request'),
    );
    expect(await coverage.nativeZoomFor(LatLng(double.nan, 121)), isNull);
  });
}
