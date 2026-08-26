import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/illustrated_field_geometry.dart';
import 'package:wormwise/services/scouting_route_generator.dart';

void main() {
  const boundary = [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0040),
    LatLng(17.0020, 121.0040),
    LatLng(17.0020, 121.0000),
  ];

  test('polygon fits without stretching and preserves north orientation', () {
    final geometry = IllustratedFieldGeometryGenerator.generate(
      boundary: boundary,
      rowBearingDegrees: 0,
    );
    final projected = geometry.projectBoundaryToViewport(
      const Size(500, 300),
      padding: 30,
    );
    final minX = projected
        .map((point) => point.dx)
        .reduce((a, b) => a < b ? a : b);
    final maxX = projected
        .map((point) => point.dx)
        .reduce((a, b) => a > b ? a : b);
    final minY = projected
        .map((point) => point.dy)
        .reduce((a, b) => a < b ? a : b);
    final maxY = projected
        .map((point) => point.dy)
        .reduce((a, b) => a > b ? a : b);

    expect((maxX - minX) / (maxY - minY), closeTo(geometry.aspectRatio, 0.001));
    expect(projected[2].dy, lessThan(projected[1].dy));
    expect(minX, greaterThanOrEqualTo(30));
    expect(maxX, lessThanOrEqualTo(470));
  });

  test('illustrated row lines follow evaluator-confirmed direction', () {
    final geometry = IllustratedFieldGeometryGenerator.generate(
      boundary: boundary,
      rowBearingDegrees: 90,
    );

    expect(geometry.rowSegments, isNotEmpty);
    for (final line in geometry.rowSegments.take(4)) {
      final bearing = ScoutingRouteGenerator.bearingDegrees(
        line.first,
        line.last,
      );
      expect(bearing, closeTo(90, 1));
    }
  });

  test('texture and row geometry remains clipped to exact polygon', () {
    final geometry = IllustratedFieldGeometryGenerator.generate(
      boundary: boundary,
      rowBearingDegrees: 25,
    );

    for (final segment in [
      ...geometry.textureSegments,
      ...geometry.rowSegments,
    ]) {
      expect(
        segment.every(
          (point) => ScoutingRouteGenerator.pointInsidePolygon(point, boundary),
        ),
        isTrue,
      );
    }
  });
}
