import 'dart:convert';
import 'dart:ui' show Offset, Rect, Size;

import 'package:latlong2/latlong.dart';

import '../data/repositories/scouting_workflow_repository.dart';
import '../services/polygon_calculator.dart';
import 'assessment_history_models.dart';
import 'da_assessment_results.dart';

enum AssessmentMapLayer { damage, infestation, expert }

extension AssessmentMapLayerPresentation on AssessmentMapLayer {
  String get label => switch (this) {
    AssessmentMapLayer.damage => 'Damage screening',
    AssessmentMapLayer.infestation => 'Current sampled infestation',
    AssessmentMapLayer.expert => 'Expert findings',
  };
}

class AssessmentMapPoint {
  const AssessmentMapPoint({
    required this.station,
    required this.record,
    required this.planned,
    required this.damage,
  });
  final StationSnapshot station;
  final StationPlantRecord? record;
  final LatLng? planned;
  final bool? damage;
  String get id => '${station.prepared.run.id}:${station.stationNumber}';
  String get label =>
      'Block ${station.prepared.run.blockSequence} · Plant ${station.stationNumber}';
  LatLng? get location => planned;
  String get locationLabel => 'Scouting pin';
}

/// Read-only projection: uses the same unique samples and evidence checks as Results.
class AssessmentMapData {
  AssessmentMapData(AssessmentHistoryDetail detail)
    : sample = DaSampleResults.fromDetail(detail) {
    points = [for (final station in sample.plants) _point(station)];
  }
  final DaSampleResults sample;
  late final List<AssessmentMapPoint> points;
  int get mappedCount => points.where((p) => p.location != null).length;
  int get unlocatedCount => points.length - mappedCount;

  AssessmentMapPoint _point(StationSnapshot station) {
    final record = sample.observation(station);
    return AssessmentMapPoint(
      station: station,
      record: record,
      planned: samplingTarget(
        station.prepared.run.routeGeojson,
        station.stationNumber,
      ),
      damage: sample.isAssessable(station) ? sample.isPositive(station) : null,
    );
  }

  static LatLng? _coordinate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return null;
    final point = LatLng(latitude, longitude);
    return PolygonCalculator.isValidCoordinate(point) ? point : null;
  }

  static LatLng? samplingTarget(String? geojson, int number) {
    if (geojson == null || geojson.isEmpty) return null;
    try {
      final raw = jsonDecode(geojson);
      if (raw is! Map || raw['features'] is! List) return null;
      for (final feature in raw['features'] as List) {
        if (feature is! Map) continue;
        final properties = feature['properties'];
        if (properties is! Map ||
            properties['feature_type'] != 'station_target' ||
            properties['station_number'] != number) {
          continue;
        }
        final geometry = feature['geometry'];
        final coordinates = geometry is Map ? geometry['coordinates'] : null;
        if (coordinates is List &&
            coordinates.length >= 2 &&
            coordinates[0] is num &&
            coordinates[1] is num) {
          return _coordinate(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
          );
        }
      }
    } catch (_) {
      // An absent or invalid target never becomes an invented map coordinate.
    }
    return null;
  }
}

/// Groups overlapping screen targets without altering a sample's saved coordinates.
List<List<AssessmentMapPoint>> groupAssessmentMapPoints(
  List<AssessmentMapPoint> points,
  Offset Function(LatLng) project, {
  double separation = 46,
}) {
  final groups = <List<AssessmentMapPoint>>[];
  for (final point in points.where((p) => p.location != null)) {
    final screen = project(point.location!);
    // Keep clusters compact: a chain of nearby pins must not swallow the whole field.
    final group = groups
        .where(
          (g) => g.every(
            (other) =>
                (project(other.location!) - screen).distance < separation,
          ),
        )
        .firstOrNull;
    if (group == null) {
      groups.add([point]);
    } else {
      group.add(point);
    }
  }
  return groups;
}

/// Separates overview labels in screen space; saved scouting anchors are unchanged.
List<Offset> layoutAssessmentMapPins(
  List<Offset> anchors,
  Rect bounds, {
  Size separation = const Size(34, 38),
}) {
  final placed = <Offset>[];
  for (final anchor in anchors) {
    final origin = Offset(
      anchor.dx.clamp(bounds.left, bounds.right),
      anchor.dy.clamp(bounds.top, bounds.bottom),
    );
    final candidates =
        <Offset>[
          origin,
          for (var ring = 1; ring <= 10; ring++)
            for (var y = -ring; y <= ring; y++)
              for (var x = -ring; x <= ring; x++)
                if (x.abs() == ring || y.abs() == ring)
                  origin + Offset(x * separation.width, y * separation.height),
        ]..sort((a, b) {
          final distance = (a - origin).distanceSquared.compareTo(
            (b - origin).distanceSquared,
          );
          if (distance != 0) return distance;
          final row = a.dy.compareTo(b.dy);
          return row != 0 ? row : a.dx.compareTo(b.dx);
        });
    placed.add(
      candidates
              .where(
                (candidate) =>
                    candidate.dx >= bounds.left &&
                    candidate.dx <= bounds.right &&
                    candidate.dy >= bounds.top &&
                    candidate.dy <= bounds.bottom &&
                    placed.every(
                      (other) =>
                          (candidate.dx - other.dx).abs() >=
                              separation.width - .01 ||
                          (candidate.dy - other.dy).abs() >=
                              separation.height - .01,
                    ),
              )
              .firstOrNull ??
          origin,
    );
  }
  return placed;
}
