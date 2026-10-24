import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' show Distance, LatLng, LengthUnit;

class PolygonValidationResult {
  const PolygonValidationResult(this.issues);

  final List<String> issues;

  bool get isValid => issues.isEmpty;
}

class PolygonCalculator {
  /// Web Mercator cannot project the poles, even though latitude is finite.
  static bool isValidCoordinate(LatLng point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 85.05112878 &&
      point.longitude.abs() <= 180;

  static double calculateSquareMeters(List<LatLng> points) {
    if (points.length < 3 || points.any((p) => !isValidCoordinate(p))) return 0;

    const earthRadius = 6378137.0;
    final meanLatitude =
        points.map((point) => point.latitude).reduce((a, b) => a + b) /
        points.length;
    final cosine = math.cos(meanLatitude * math.pi / 180);
    double twiceArea = 0;

    for (var index = 0; index < points.length; index++) {
      final currentPoint = points[index];
      final nextPoint = points[(index + 1) % points.length];
      final xCurrent =
          currentPoint.longitude * math.pi / 180 * earthRadius * cosine;
      final yCurrent = currentPoint.latitude * math.pi / 180 * earthRadius;
      final xNext = nextPoint.longitude * math.pi / 180 * earthRadius * cosine;
      final yNext = nextPoint.latitude * math.pi / 180 * earthRadius;
      twiceArea += (xCurrent * yNext) - (xNext * yCurrent);
    }

    return twiceArea.abs() / 2;
  }

  static double calculateHectares(List<LatLng> points) {
    return calculateSquareMeters(points) / 10000;
  }

  static double calculatePerimeterMeters(List<LatLng> points) {
    if (points.length < 2 || points.any((p) => !isValidCoordinate(p))) return 0;

    const distance = Distance();
    var perimeter = 0.0;
    for (var index = 0; index < points.length; index++) {
      perimeter += distance.as(
        LengthUnit.Meter,
        points[index],
        points[(index + 1) % points.length],
      );
    }
    return perimeter;
  }

  static LatLng calculateCenter(List<LatLng> points) {
    points = points.where(isValidCoordinate).toList(growable: false);
    if (points.isEmpty) return const LatLng(17.7905, 121.4781);
    return LatLng(
      points.map((point) => point.latitude).reduce((a, b) => a + b) /
          points.length,
      points.map((point) => point.longitude).reduce((a, b) => a + b) /
          points.length,
    );
  }

  static PolygonValidationResult validate(List<LatLng> points) {
    final issues = <String>[];
    if (points.any((point) => !isValidCoordinate(point))) {
      return const PolygonValidationResult([
        'Boundary points must have valid map coordinates. Clear and redraw the outline.',
      ]);
    }
    if (points.length < 3) {
      issues.add('Add at least three boundary points.');
      return PolygonValidationResult(List.unmodifiable(issues));
    }

    if (_hasDuplicatePoints(points)) {
      issues.add('Two or more boundary points are in the same location.');
    }
    if (_hasSelfIntersection(points)) {
      issues.add('The boundary crosses itself. Move or remove a point.');
    }
    if (calculateSquareMeters(points) < 1) {
      issues.add('The drawn boundary is too small to represent a field.');
    }

    return PolygonValidationResult(List.unmodifiable(issues));
  }

  /// Returns the original point indices in an order that removes crossing
  /// polygon edges. A simple (including concave) polygon is left unchanged.
  ///
  /// Each correction is a standard 2-opt reversal between two crossing edges,
  /// so this does not sort every point around a centroid or force the field to
  /// be convex.
  static List<int> untangledOrder(List<LatLng> points) {
    final order = List<int>.generate(points.length, (index) => index);
    if (points.length < 4) return order;

    final maximumCorrections = points.length * points.length;
    for (var correction = 0; correction < maximumCorrections; correction++) {
      final crossing = _firstSelfIntersection(points, order);
      if (crossing == null) break;

      final reversedMiddle = order
          .sublist(crossing.firstEdge + 1, crossing.secondEdge + 1)
          .reversed
          .toList(growable: false);
      order.setRange(
        crossing.firstEdge + 1,
        crossing.secondEdge + 1,
        reversedMiddle,
      );
    }
    return order;
  }

  static String toGeoJson(List<LatLng> points) {
    if (points.any((point) => !isValidCoordinate(point))) {
      throw ArgumentError('Boundary points must have valid map coordinates.');
    }
    if (points.isEmpty) {
      return '{"type":"Polygon","coordinates":[]}';
    }

    final closedPoints = [...points, points.first];
    return jsonEncode({
      'type': 'Polygon',
      'coordinates': [
        closedPoints
            .map((point) => [point.longitude, point.latitude])
            .toList(growable: false),
      ],
    });
  }

  static List<LatLng> fromGeoJson(String geometryGeoJson) {
    try {
      final decoded = jsonDecode(geometryGeoJson);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'Polygon') {
        return const [];
      }
      final coordinates = decoded['coordinates'];
      if (coordinates is! List || coordinates.isEmpty) return const [];
      final firstRing = coordinates.first;
      if (firstRing is! List) return const [];

      final points = <LatLng>[];
      for (final coordinate in firstRing) {
        if (coordinate is! List || coordinate.length < 2) continue;
        final longitude = coordinate[0];
        final latitude = coordinate[1];
        if (longitude is! num || latitude is! num) continue;
        final point = LatLng(latitude.toDouble(), longitude.toDouble());
        if (!isValidCoordinate(point)) return const [];
        points.add(point);
      }

      if (points.length > 1 && _samePoint(points.first, points.last)) {
        points.removeLast();
      }
      return List.unmodifiable(points);
    } on FormatException {
      return const [];
    }
  }

  static bool _hasDuplicatePoints(List<LatLng> points) {
    for (var first = 0; first < points.length; first++) {
      for (var second = first + 1; second < points.length; second++) {
        if (_samePoint(points[first], points[second])) return true;
      }
    }
    return false;
  }

  static bool _samePoint(LatLng first, LatLng second) {
    const tolerance = 0.00000001;
    return (first.latitude - second.latitude).abs() < tolerance &&
        (first.longitude - second.longitude).abs() < tolerance;
  }

  static bool _hasSelfIntersection(List<LatLng> points) {
    final order = List<int>.generate(points.length, (index) => index);
    return _firstSelfIntersection(points, order) != null;
  }

  static ({int firstEdge, int secondEdge})? _firstSelfIntersection(
    List<LatLng> points,
    List<int> order,
  ) {
    for (var firstEdge = 0; firstEdge < order.length; firstEdge++) {
      final firstStart = points[order[firstEdge]];
      final firstEnd = points[order[(firstEdge + 1) % order.length]];

      for (
        var secondEdge = firstEdge + 1;
        secondEdge < order.length;
        secondEdge++
      ) {
        final edgesAreAdjacent =
            secondEdge == firstEdge + 1 ||
            (firstEdge == 0 && secondEdge == order.length - 1);
        if (edgesAreAdjacent) continue;

        final secondStart = points[order[secondEdge]];
        final secondEnd = points[order[(secondEdge + 1) % order.length]];
        if (_segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd)) {
          return (firstEdge: firstEdge, secondEdge: secondEdge);
        }
      }
    }
    return null;
  }

  static bool _segmentsIntersect(
    LatLng firstStart,
    LatLng firstEnd,
    LatLng secondStart,
    LatLng secondEnd,
  ) {
    final firstOrientation = _orientation(firstStart, firstEnd, secondStart);
    final secondOrientation = _orientation(firstStart, firstEnd, secondEnd);
    final thirdOrientation = _orientation(secondStart, secondEnd, firstStart);
    final fourthOrientation = _orientation(secondStart, secondEnd, firstEnd);

    return firstOrientation * secondOrientation < 0 &&
        thirdOrientation * fourthOrientation < 0;
  }

  static double _orientation(LatLng first, LatLng second, LatLng third) {
    return (second.longitude - first.longitude) *
            (third.latitude - first.latitude) -
        (second.latitude - first.latitude) *
            (third.longitude - first.longitude);
  }
}
