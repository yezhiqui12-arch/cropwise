import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Checks Esri's tile-presence metadata; it does not download an offline tile pack.
class EsriImageryCoverage {
  EsriImageryCoverage({Future<Map<String, dynamic>> Function(Uri)? fetch})
    : _fetch = fetch ?? _download;
  static final instance = EsriImageryCoverage();
  static const service =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer';
  static const tileUrl = '$service/tile/{z}/{y}/{x}?blankTile=false';
  final Future<Map<String, dynamic>> Function(Uri) _fetch;
  final _cached = <String, Future<int?>>{};

  static ({int x, int y}) tileAt(LatLng point, int zoom) {
    final n = 1 << zoom;
    final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
    final longitude = point.longitude.clamp(-180.0, 180.0);
    final radians = latitude * math.pi / 180;
    return (
      x: (((longitude + 180) / 360) * n).floor().clamp(0, n - 1),
      y:
          ((1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
                  2 *
                  n)
              .floor()
              .clamp(0, n - 1),
    );
  }

  static String cellKey(LatLng point) {
    final tile = tileAt(point, 20);
    return '${tile.x}:${tile.y}';
  }

  Future<int?> nativeZoomFor(LatLng point) {
    if (!point.latitude.isFinite || !point.longitude.isFinite) {
      return Future.value(null);
    }
    final key = cellKey(point);
    if (_cached.length > 128) _cached.clear();
    return _cached.putIfAbsent(key, () async {
      final result = await _resolve(point);
      if (result == null) _cached.remove(key);
      return result;
    });
  }

  Future<int?> _resolve(LatLng point) async {
    try {
      for (var z = 20; z >= 12; z--) {
        final tile = tileAt(point, z);
        final n = 1 << z;
        final left = (tile.x - 1).clamp(0, n - 1),
            top = (tile.y - 1).clamp(0, n - 1);
        // Esri may clip requests at its 128-tile bundle boundaries. Split there
        // so every neighboring tile is actually checked, including bundle edges.
        final right = (tile.x + 1).clamp(0, n - 1),
            bottom = (tile.y + 1).clamp(0, n - 1);
        var available = true;
        for (var row = top; row <= bottom && available;) {
          final height = math.min(bottom - row + 1, 128 - row % 128);
          for (var col = left; col <= right && available;) {
            final width = math.min(right - col + 1, 128 - col % 128);
            final reply = await _fetch(
              Uri.parse('$service/tilemap/$z/$row/$col/$width/$height?f=json'),
            );
            final error = reply['error'];
            if (error is Map && error['code'] == 422) {
              available = false;
              break;
            }
            final data = reply['data'], location = reply['location'];
            if (data is! List ||
                location is! Map ||
                location['left'] != col ||
                location['top'] != row ||
                location['width'] != width ||
                location['height'] != height ||
                data.length != width * height ||
                data.any((v) => v != 0 && v != 1)) {
              return null;
            }
            available = data.every((v) => v == 1);
            col += width;
          }
          row += height;
        }
        if (available) return z;
      }
    } catch (_) {
      // Offline or service failure is not evidence that imagery is absent.
    }
    return null;
  }

  static Future<Map<String, dynamic>> _download(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode == 422) {
        return {
          'error': {'code': 422},
        };
      }
      if (response.statusCode != 200) {
        throw const HttpException('Imagery coverage unavailable');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid coverage');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
