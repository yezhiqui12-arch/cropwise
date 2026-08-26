import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:latlong2/latlong.dart' show LatLng;

import 'scouting_route_generator.dart';

class MetricFieldPoint {
  const MetricFieldPoint(this.eastMeters, this.northMeters);

  final double eastMeters;
  final double northMeters;
}

class IllustratedFieldGeometry {
  const IllustratedFieldGeometry({
    required this.boundary,
    required this.metricBoundary,
    required this.rowSegments,
    required this.textureSegments,
    required this.minEast,
    required this.maxEast,
    required this.minNorth,
    required this.maxNorth,
    required this.origin,
  });

  final List<LatLng> boundary;
  final List<MetricFieldPoint> metricBoundary;
  final List<List<LatLng>> rowSegments;
  final List<List<LatLng>> textureSegments;
  final double minEast;
  final double maxEast;
  final double minNorth;
  final double maxNorth;
  final LatLng origin;

  double get widthMeters => maxEast - minEast;
  double get heightMeters => maxNorth - minNorth;
  double get aspectRatio => widthMeters / heightMeters;

  List<Offset> projectBoundaryToViewport(Size size, {double padding = 24}) {
    if (metricBoundary.isEmpty || size.isEmpty) return const [];
    final usableWidth = math.max(1, size.width - padding * 2);
    final usableHeight = math.max(1, size.height - padding * 2);
    final scale = math.min(
      usableWidth / math.max(widthMeters, 1),
      usableHeight / math.max(heightMeters, 1),
    );
    final renderedWidth = widthMeters * scale;
    final renderedHeight = heightMeters * scale;
    final left = (size.width - renderedWidth) / 2;
    final top = (size.height - renderedHeight) / 2;
    return [
      for (final point in metricBoundary)
        Offset(
          left + (point.eastMeters - minEast) * scale,
          top + (maxNorth - point.northMeters) * scale,
        ),
    ];
  }
}

class IllustratedFieldGeometryGenerator {
  static IllustratedFieldGeometry generate({
    required List<LatLng> boundary,
    required double rowBearingDegrees,
  }) {
    if (boundary.length < 3) {
      throw ArgumentError.value(boundary, 'boundary', 'Needs three points');
    }
    final projection = _MetricProjection(boundary);
    final metric = boundary.map(projection.project).toList(growable: false);
    final minEast = metric.map((point) => point.eastMeters).reduce(math.min);
    final maxEast = metric.map((point) => point.eastMeters).reduce(math.max);
    final minNorth = metric.map((point) => point.northMeters).reduce(math.min);
    final maxNorth = metric.map((point) => point.northMeters).reduce(math.max);
    final rowSegments = _parallelLines(
      projection: projection,
      boundary: boundary,
      metricBoundary: metric,
      bearingDegrees: rowBearingDegrees,
      lineCount: 18,
    );
    final textureSegments = _parallelLines(
      projection: projection,
      boundary: boundary,
      metricBoundary: metric,
      bearingDegrees: (rowBearingDegrees + 38) % 360,
      lineCount: 28,
    );
    return IllustratedFieldGeometry(
      boundary: List.unmodifiable(boundary),
      metricBoundary: List.unmodifiable(metric),
      rowSegments: List.unmodifiable(rowSegments),
      textureSegments: List.unmodifiable(textureSegments),
      minEast: minEast,
      maxEast: maxEast,
      minNorth: minNorth,
      maxNorth: maxNorth,
      origin: projection.origin,
    );
  }

  static List<List<LatLng>> _parallelLines({
    required _MetricProjection projection,
    required List<LatLng> boundary,
    required List<MetricFieldPoint> metricBoundary,
    required double bearingDegrees,
    required int lineCount,
  }) {
    final radians = bearingDegrees * math.pi / 180;
    final alongEast = math.sin(radians);
    final alongNorth = math.cos(radians);
    final crossEast = -alongNorth;
    final crossNorth = alongEast;
    final alongValues = metricBoundary
        .map(
          (point) =>
              point.eastMeters * alongEast + point.northMeters * alongNorth,
        )
        .toList(growable: false);
    final crossValues = metricBoundary
        .map(
          (point) =>
              point.eastMeters * crossEast + point.northMeters * crossNorth,
        )
        .toList(growable: false);
    final minAlong = alongValues.reduce(math.min);
    final maxAlong = alongValues.reduce(math.max);
    final minCross = crossValues.reduce(math.min);
    final maxCross = crossValues.reduce(math.max);
    final result = <List<LatLng>>[];
    for (var line = 1; line <= lineCount; line++) {
      final cross = minCross + (maxCross - minCross) * line / (lineCount + 1);
      List<LatLng>? active;
      for (var step = 0; step <= 160; step++) {
        final along = minAlong + (maxAlong - minAlong) * step / 160;
        final point = projection.unproject(
          MetricFieldPoint(
            along * alongEast + cross * crossEast,
            along * alongNorth + cross * crossNorth,
          ),
        );
        final inside = ScoutingRouteGenerator.pointInsidePolygon(
          point,
          boundary,
        );
        if (inside) {
          active ??= <LatLng>[];
          active.add(point);
        } else if (active != null) {
          if (active.length >= 2) result.add(List.unmodifiable(active));
          active = null;
        }
      }
      if (active != null && active.length >= 2) {
        result.add(List.unmodifiable(active));
      }
    }
    return result;
  }
}

class _MetricProjection {
  _MetricProjection(List<LatLng> boundary)
    : origin = ScoutingRouteGenerator.polygonCenter(boundary);

  final LatLng origin;

  MetricFieldPoint project(LatLng point) {
    const earthRadius = 6371000.0;
    final latitudeRadians = origin.latitude * math.pi / 180;
    return MetricFieldPoint(
      (point.longitude - origin.longitude) *
          math.pi /
          180 *
          earthRadius *
          math.cos(latitudeRadians),
      (point.latitude - origin.latitude) * math.pi / 180 * earthRadius,
    );
  }

  LatLng unproject(MetricFieldPoint point) {
    const earthRadius = 6371000.0;
    final latitudeRadians = origin.latitude * math.pi / 180;
    return LatLng(
      origin.latitude + point.northMeters / earthRadius * 180 / math.pi,
      origin.longitude +
          point.eastMeters /
              (earthRadius * math.cos(latitudeRadians)) *
              180 /
              math.pi,
    );
  }
}
