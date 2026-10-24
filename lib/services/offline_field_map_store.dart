import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

class OfflineMapArea {
  const OfflineMapArea(this.south, this.west, this.north, this.east);
  final double south, west, north, east;

  factory OfflineMapArea.around(List<LatLng> points) {
    if (points.isEmpty ||
        points.any(
          (p) =>
              !p.latitude.isFinite ||
              !p.longitude.isFinite ||
              p.latitude.abs() > 85 ||
              p.longitude.abs() > 180,
        )) {
      throw const FormatException('Save a valid field location first.');
    }
    final south = points.map((p) => p.latitude).reduce(math.min) - .005;
    final north = points.map((p) => p.latitude).reduce(math.max) + .005;
    final west = points.map((p) => p.longitude).reduce(math.min) - .005;
    final east = points.map((p) => p.longitude).reduce(math.max) + .005;
    if (north - south > .1 || east - west > .1 || west < -180 || east > 180) {
      throw const FormatException(
        'The field area is too large for a small offline download.',
      );
    }
    return OfflineMapArea(south, west, north, east);
  }

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;
  List<double> get values => [south, west, north, east];
  String get queryBounds => values.map((v) => v.toStringAsFixed(6)).join(',');
}

class OfflineMapFeature {
  const OfflineMapFeature(this.kind, this.points, {this.roadClass, this.name});
  final String kind;
  final List<LatLng> points;
  final String? roadClass;
  final String? name;
  bool get isArea => kind == 'building' || kind == 'landuse' || kind == 'water';
}

class OfflineFieldMap {
  const OfflineFieldMap(this.area, this.savedAt, this.features, this.bytes);
  final OfflineMapArea area;
  final DateTime savedAt;
  final List<OfflineMapFeature> features;
  final int bytes;
}

/// Stores ODbL map features, never prefetches OSM/Esri raster tiles.
class OfflineFieldMapStore {
  OfflineFieldMapStore({
    this.rootDirectory = getApplicationDocumentsDirectory,
    Future<String> Function(String)? fetch,
  }) : _fetch = fetch ?? _download;
  static final instance = OfflineFieldMapStore();
  final Future<Directory> Function() rootDirectory;
  final Future<String> Function(String) _fetch;
  final Set<String> _busy = {};
  static const maxBytes = 8 * 1024 * 1024;

  Future<File> _file(String boundaryId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(boundaryId)) {
      throw const FormatException('Invalid map identifier.');
    }
    final root = await rootDirectory();
    return File('${root.path}/offline_field_maps/$boundaryId.json');
  }

  Future<OfflineFieldMap?> load(String boundaryId, List<LatLng> points) async {
    final file = await _file(boundaryId);
    if (!await file.exists()) return null;
    try {
      if (await file.length() > maxBytes) return null;
      final map = _decode(await file.readAsString());
      return points.every(map.area.contains) ? map : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<OfflineFieldMap> save(String boundaryId, List<LatLng> points) async {
    if (!_busy.add(boundaryId)) {
      throw StateError('This map is already downloading.');
    }
    try {
      final file = await _file(boundaryId);
      final area = OfflineMapArea.around(points);
      final bbox = area.queryBounds;
      final query =
          '[out:json][timeout:25];(way[highway]($bbox);way[waterway]($bbox);way[building]($bbox);way[landuse]($bbox);way[natural=water]($bbox););out geom;';
      final body = await _fetch(query).timeout(const Duration(seconds: 45));
      if (utf8.encode(body).length > maxBytes) {
        throw const FormatException('Map download exceeds the size limit.');
      }
      final response = jsonDecode(body);
      if (response is! Map ||
          response['elements'] is! List ||
          response['remark'] != null) {
        throw const FormatException(
          'Map service returned an incomplete response. Try again later.',
        );
      }
      final stored = jsonEncode({
        'version': 1,
        'bounds': area.values,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'elements': response['elements'],
        'attribution': '© OpenStreetMap contributors',
        'license': 'https://www.openstreetmap.org/copyright',
      });
      final map = _decode(stored);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(stored, flush: true);
      await temporary.rename(file.path);
      return map;
    } finally {
      _busy.remove(boundaryId);
    }
  }

  Future<void> remove(String boundaryId) async {
    if (_busy.contains(boundaryId)) {
      throw StateError('Wait for the download to finish.');
    }
    final file = await _file(boundaryId);
    if (await file.exists()) await file.delete();
  }

  static OfflineFieldMap _decode(String text) {
    final bytes = utf8.encode(text).length;
    if (bytes > maxBytes) throw const FormatException('Map is too large.');
    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['bounds'] is! List ||
        decoded['elements'] is! List) {
      throw const FormatException('Invalid offline map.');
    }
    final bounds = decoded['bounds'] as List;
    if (bounds.length != 4 || bounds.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Invalid bounds.');
    }
    final area = OfflineMapArea(
      (bounds[0] as num).toDouble(),
      (bounds[1] as num).toDouble(),
      (bounds[2] as num).toDouble(),
      (bounds[3] as num).toDouble(),
    );
    if (area.south >= area.north ||
        area.west >= area.east ||
        area.south < -90 ||
        area.north > 90 ||
        area.west < -180 ||
        area.east > 180) {
      throw const FormatException('Invalid bounds.');
    }
    final date = DateTime.tryParse(decoded['saved_at']?.toString() ?? '');
    if (date == null) throw const FormatException('Invalid download date.');
    final features = <OfflineMapFeature>[];
    for (final element in decoded['elements'] as List) {
      if (element is! Map ||
          element['geometry'] is! List ||
          element['tags'] is! Map) {
        continue;
      }
      final tags = element['tags'] as Map;
      final points = <LatLng>[];
      for (final coordinate in element['geometry'] as List) {
        if (coordinate is! Map ||
            coordinate['lat'] is! num ||
            coordinate['lon'] is! num) {
          throw const FormatException('Invalid map geometry.');
        }
        final lat = (coordinate['lat'] as num).toDouble(),
            lon = (coordinate['lon'] as num).toDouble();
        if (!lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          throw const FormatException('Invalid map geometry.');
        }
        points.add(LatLng(lat, lon));
      }
      if (points.length < 2) continue;
      final kind = tags.containsKey('highway')
          ? 'road'
          : tags.containsKey('waterway')
          ? 'waterway'
          : tags.containsKey('building')
          ? 'building'
          : tags['natural'] == 'water'
          ? 'water'
          : 'landuse';
      if ((kind == 'building' || kind == 'water' || kind == 'landuse') &&
          (points.length < 4 || points.first != points.last)) {
        continue;
      }
      features.add(
        OfflineMapFeature(
          kind,
          points,
          roadClass: tags['highway']?.toString(),
          name: tags['name']?.toString(),
        ),
      );
    }
    return OfflineFieldMap(area, date, features, bytes);
  }

  static Future<String> _download(String query) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(
        Uri.parse('https://overpass-api.de/api/interpreter'),
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'WormWise/1.0 (field offline maps)',
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'Map service unavailable (${response.statusCode}). Try again later.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw const FormatException('Map download exceeds the size limit.');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}
