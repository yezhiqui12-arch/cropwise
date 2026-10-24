import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'offline_field_map_store.dart';

/// Street vectors bundled with the app; available without a network request.
class LocalPiatMapStore {
  static const assetPath = 'assets/maps/piat_streets.json';
  static Future<OfflineFieldMap>? _cached;

  static Future<OfflineFieldMap> load() => _cached ??= _load();

  static Future<OfflineFieldMap> _load() async {
    final text = await rootBundle.loadString(assetPath);
    final data = jsonDecode(text);
    if (data is! Map ||
        data['version'] != 1 ||
        data['bounds'] is! List ||
        data['features'] is! List) {
      throw const FormatException('Invalid Piat map asset.');
    }
    final bounds = data['bounds'] as List;
    if (bounds.length != 4 || bounds.any((value) => value is! num)) {
      throw const FormatException('Invalid Piat map bounds.');
    }
    final west = (bounds[0] as num).toDouble();
    final south = (bounds[1] as num).toDouble();
    final east = (bounds[2] as num).toDouble();
    final north = (bounds[3] as num).toDouble();
    final area = OfflineMapArea(south, west, north, east);
    if (south >= north ||
        west >= east ||
        south < -90 ||
        north > 90 ||
        west < -180 ||
        east > 180) {
      throw const FormatException('Invalid Piat map bounds.');
    }
    final features = <OfflineMapFeature>[];
    for (final raw in data['features'] as List) {
      if (raw is! Map || raw['k'] is! String || raw['c'] is! List) continue;
      final points = <LatLng>[];
      for (final coordinate in raw['c'] as List) {
        if (coordinate is! List ||
            coordinate.length != 2 ||
            coordinate[0] is! num ||
            coordinate[1] is! num) {
          throw const FormatException('Invalid Piat map geometry.');
        }
        final lat = (coordinate[0] as num).toDouble();
        final lon = (coordinate[1] as num).toDouble();
        if (!lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          throw const FormatException('Invalid Piat map geometry.');
        }
        points.add(LatLng(lat, lon));
      }
      if (points.length < 2) continue;
      features.add(
        OfflineMapFeature(
          raw['k'] as String,
          points,
          roadClass: raw['r']?.toString(),
          name: raw['n']?.toString(),
        ),
      );
    }
    final savedAt = DateTime.tryParse(data['downloaded_at']?.toString() ?? '');
    return OfflineFieldMap(
      area,
      savedAt ?? DateTime.utc(2026),
      features,
      utf8.encode(text).length,
    );
  }
}
