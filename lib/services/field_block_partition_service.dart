import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'assessment_area_policy.dart';

class FieldBlockPartitionException implements Exception {
  const FieldBlockPartitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProposedFieldBlock {
  const ProposedFieldBlock({
    required this.blockNumber,
    required this.geometryGeoJson,
    required this.areaHectares,
  });

  final int blockNumber;
  final String geometryGeoJson;
  final double areaHectares;
}

class FieldBlockPartitionPlan {
  const FieldBlockPartitionPlan({
    required this.blocks,
    required this.algorithmVersion,
    required this.orientationDegrees,
    required this.qualityScore,
  });

  final List<ProposedFieldBlock> blocks;
  final String algorithmVersion;
  final double orientationDegrees;
  final double qualityScore;
}

/// Produces conservative, equal-area block proposals from a simple field
/// polygon. Multiple orientations are evaluated and the best valid layout is
/// selected. Unsupported or suspicious geometry is rejected rather than
/// silently producing misleading assessment blocks.
class FieldBlockPartitionService {
  const FieldBlockPartitionService();

  static const algorithmVersion = 'equal_area_multi_axis_v1';
  static const _earthRadiusMeters = 6371008.8;
  static const _minimumCompactness = 0.025;
  static const _minimumSpanMeters = 8.0;

  FieldBlockPartitionPlan partition({
    required String boundaryGeoJson,
    required double expectedAreaHectares,
    int candidateIndex = 0,
  }) {
    if (!AssessmentAreaPolicy.isWithinAssessmentLimit(expectedAreaHectares)) {
      throw FieldBlockPartitionException(
        'Automatic block preparation supports fields up to '
        '${AssessmentAreaPolicy.maxAssessmentAreaHectares.toStringAsFixed(0)} ha.',
      );
    }
    final ring = _parseSimplePolygon(boundaryGeoJson);
    if (ring.length < 3) {
      throw const FieldBlockPartitionException(
        'The field outline does not contain a usable polygon.',
      );
    }
    if (_hasSelfIntersection(ring)) {
      throw const FieldBlockPartitionException(
        'The field outline crosses itself. Correct the outline before preparing blocks.',
      );
    }

    final origin = _centroid(ring);
    final points = ring.map((point) => _project(point, origin)).toList();
    final sourceArea = _area(points);
    if (sourceArea <= 0) {
      throw const FieldBlockPartitionException(
        'The field outline has no usable calculated area.',
      );
    }
    final blockCount = AssessmentAreaPolicy.requiredBlockCount(
      expectedAreaHectares,
    );
    if (blockCount == 1) {
      return FieldBlockPartitionPlan(
        blocks: [
          ProposedFieldBlock(
            blockNumber: 1,
            geometryGeoJson: _encodePolygon(ring),
            areaHectares: expectedAreaHectares,
          ),
        ],
        algorithmVersion: algorithmVersion,
        orientationDegrees: 0,
        qualityScore: 1,
      );
    }

    final candidates = <FieldBlockPartitionPlan>[];
    for (var degrees = 0; degrees < 180; degrees += 15) {
      final candidate = _candidate(
        points: points,
        origin: origin,
        expectedAreaHectares: expectedAreaHectares,
        blockCount: blockCount,
        degrees: degrees.toDouble(),
      );
      if (candidate == null) continue;
      candidates.add(candidate);
    }
    if (candidates.isEmpty) {
      throw const FieldBlockPartitionException(
        'Cropwise could not make safe connected blocks from this outline. Adjust the field outline or divide the maize area manually.',
      );
    }
    candidates.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    return candidates[candidateIndex.abs() % candidates.length];
  }

  FieldBlockPartitionPlan? _candidate({
    required List<_Point> points,
    required LatLng origin,
    required double expectedAreaHectares,
    required int blockCount,
    required double degrees,
  }) {
    final radians = degrees * math.pi / 180;
    final axis = _Point(math.cos(radians), math.sin(radians));
    final projections = points.map((p) => p.dot(axis)).toList();
    final minimum = projections.reduce(math.min);
    final maximum = projections.reduce(math.max);
    if (maximum - minimum < _minimumSpanMeters * blockCount) return null;

    final totalArea = _area(points);
    final cuts = <double>[minimum];
    for (var index = 1; index < blockCount; index++) {
      final target = totalArea * index / blockCount;
      var low = cuts.last;
      var high = maximum;
      for (var iteration = 0; iteration < 48; iteration++) {
        final middle = (low + high) / 2;
        final clipped = _clipMaximum(points, axis, middle);
        if (_area(clipped) < target) {
          low = middle;
        } else {
          high = middle;
        }
      }
      final cut = (low + high) / 2;
      // More than two boundary crossings means the cut can create separated
      // islands in a concave field. Reject that orientation instead of joining
      // those islands with an artificial edge.
      if (_crossingCount(points, axis, cut) > 2) return null;
      cuts.add(cut);
    }
    cuts.add(maximum);

    final polygons = <List<_Point>>[];
    for (var index = 0; index < blockCount; index++) {
      var polygon = _clipMinimum(points, axis, cuts[index]);
      polygon = _clipMaximum(polygon, axis, cuts[index + 1]);
      polygon = _removeDuplicateVertices(polygon);
      if (polygon.length < 3 || _hasSelfIntersectionProjected(polygon)) {
        return null;
      }
      final area = _area(polygon);
      final perimeter = _perimeter(polygon);
      final compactness = 4 * math.pi * area / (perimeter * perimeter);
      final spanAlong = cuts[index + 1] - cuts[index];
      final perpendicular = _Point(-axis.y, axis.x);
      final crossValues = polygon.map((p) => p.dot(perpendicular)).toList();
      final spanAcross =
          crossValues.reduce(math.max) - crossValues.reduce(math.min);
      if (compactness < _minimumCompactness ||
          math.min(spanAlong, spanAcross) < _minimumSpanMeters) {
        return null;
      }
      polygons.add(polygon);
    }

    final polygonAreas = polygons.map(_area).toList();
    final areaSum = polygonAreas.fold<double>(0, (sum, area) => sum + area);
    if ((areaSum - totalArea).abs() / totalArea > 0.005) return null;
    final hectareScale = expectedAreaHectares / areaSum;
    final blockAreas = polygonAreas.map((area) => area * hectareScale).toList();
    if (blockAreas.any(
      (area) => !AssessmentAreaPolicy.isValidBlockArea(area),
    )) {
      return null;
    }

    final mean = expectedAreaHectares / blockCount;
    final imbalance = blockAreas
        .map((area) => (area - mean).abs() / mean)
        .fold<double>(0, math.max);
    final totalPerimeter = polygons
        .map(_perimeter)
        .fold<double>(0, (sum, value) => sum + value);
    final compactnessPenalty = totalPerimeter / math.sqrt(totalArea);
    final score = 1 / (1 + imbalance * 8 + compactnessPenalty * 0.02);

    return FieldBlockPartitionPlan(
      blocks: [
        for (var index = 0; index < polygons.length; index++)
          ProposedFieldBlock(
            blockNumber: index + 1,
            geometryGeoJson: _encodePolygon(
              polygons[index].map((p) => _unproject(p, origin)).toList(),
            ),
            areaHectares: blockAreas[index],
          ),
      ],
      algorithmVersion: algorithmVersion,
      orientationDegrees: degrees,
      qualityScore: score,
    );
  }

  List<LatLng> _parseSimplePolygon(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map || decoded['type'] != 'Polygon') {
      throw const FieldBlockPartitionException(
        'Automatic division currently requires one connected field polygon.',
      );
    }
    final coordinates = decoded['coordinates'];
    if (coordinates is! List || coordinates.length != 1) {
      throw const FieldBlockPartitionException(
        'Fields containing holes or disconnected areas require manual block preparation.',
      );
    }
    final rawRing = coordinates.first;
    if (rawRing is! List) return const [];
    final result = <LatLng>[];
    for (final coordinate in rawRing) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final longitude = coordinate[0];
      final latitude = coordinate[1];
      if (longitude is num && latitude is num) {
        result.add(LatLng(latitude.toDouble(), longitude.toDouble()));
      }
    }
    if (result.length > 1 && result.first == result.last) result.removeLast();
    return result;
  }

  LatLng _centroid(List<LatLng> points) => LatLng(
    points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
    points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
  );

  _Point _project(LatLng point, LatLng origin) {
    final latitudeRadians = origin.latitude * math.pi / 180;
    return _Point(
      (point.longitude - origin.longitude) *
          math.pi /
          180 *
          _earthRadiusMeters *
          math.cos(latitudeRadians),
      (point.latitude - origin.latitude) * math.pi / 180 * _earthRadiusMeters,
    );
  }

  LatLng _unproject(_Point point, LatLng origin) {
    final latitudeRadians = origin.latitude * math.pi / 180;
    return LatLng(
      origin.latitude + point.y / _earthRadiusMeters * 180 / math.pi,
      origin.longitude +
          point.x /
              (_earthRadiusMeters * math.cos(latitudeRadians)) *
              180 /
              math.pi,
    );
  }

  List<_Point> _clipMaximum(List<_Point> polygon, _Point axis, double limit) =>
      _clip(polygon, (p) => p.dot(axis) <= limit, (a, b) {
        final delta = b - a;
        final denominator = delta.dot(axis);
        if (denominator.abs() < 1e-12) return a;
        return a + delta * ((limit - a.dot(axis)) / denominator);
      });

  List<_Point> _clipMinimum(List<_Point> polygon, _Point axis, double limit) =>
      _clip(polygon, (p) => p.dot(axis) >= limit, (a, b) {
        final delta = b - a;
        final denominator = delta.dot(axis);
        if (denominator.abs() < 1e-12) return a;
        return a + delta * ((limit - a.dot(axis)) / denominator);
      });

  List<_Point> _clip(
    List<_Point> polygon,
    bool Function(_Point) inside,
    _Point Function(_Point, _Point) intersection,
  ) {
    if (polygon.isEmpty) return const [];
    final output = <_Point>[];
    var previous = polygon.last;
    var previousInside = inside(previous);
    for (final current in polygon) {
      final currentInside = inside(current);
      if (currentInside != previousInside) {
        output.add(intersection(previous, current));
      }
      if (currentInside) output.add(current);
      previous = current;
      previousInside = currentInside;
    }
    return output;
  }

  List<_Point> _removeDuplicateVertices(List<_Point> points) {
    final result = <_Point>[];
    for (final point in points) {
      if (result.isEmpty || (point - result.last).length > 0.01) {
        result.add(point);
      }
    }
    if (result.length > 1 && (result.first - result.last).length <= 0.01) {
      result.removeLast();
    }
    return result;
  }

  double _area(List<_Point> points) {
    if (points.length < 3) return 0;
    var twice = 0.0;
    for (var i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      twice += points[i].x * next.y - next.x * points[i].y;
    }
    return twice.abs() / 2;
  }

  double _perimeter(List<_Point> points) {
    var result = 0.0;
    for (var i = 0; i < points.length; i++) {
      result += (points[(i + 1) % points.length] - points[i]).length;
    }
    return result;
  }

  bool _hasSelfIntersection(List<LatLng> points) {
    final origin = _centroid(points);
    return _hasSelfIntersectionProjected(
      points.map((point) => _project(point, origin)).toList(),
    );
  }

  bool _hasSelfIntersectionProjected(List<_Point> points) {
    for (var i = 0; i < points.length; i++) {
      final a1 = points[i];
      final a2 = points[(i + 1) % points.length];
      for (var j = i + 1; j < points.length; j++) {
        if (j == i ||
            j == (i + 1) % points.length ||
            (i == 0 && j == points.length - 1)) {
          continue;
        }
        final b1 = points[j];
        final b2 = points[(j + 1) % points.length];
        if (_segmentsIntersect(a1, a2, b1, b2)) return true;
      }
    }
    return false;
  }

  bool _segmentsIntersect(_Point a, _Point b, _Point c, _Point d) {
    final abC = _cross(b - a, c - a);
    final abD = _cross(b - a, d - a);
    final cdA = _cross(d - c, a - c);
    final cdB = _cross(d - c, b - c);
    return abC * abD < -1e-8 && cdA * cdB < -1e-8;
  }

  int _crossingCount(List<_Point> polygon, _Point axis, double limit) {
    var crossings = 0;
    for (var index = 0; index < polygon.length; index++) {
      final first = polygon[index].dot(axis) - limit;
      final second = polygon[(index + 1) % polygon.length].dot(axis) - limit;
      if ((first < -1e-8 && second > 1e-8) ||
          (first > 1e-8 && second < -1e-8)) {
        crossings++;
      }
    }
    return crossings;
  }

  double _cross(_Point a, _Point b) => a.x * b.y - a.y * b.x;

  String _encodePolygon(List<LatLng> points) => jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        for (final point in [...points, points.first])
          [point.longitude, point.latitude],
      ],
    ],
  });
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;

  double dot(_Point other) => x * other.x + y * other.y;
  double get length => math.sqrt(x * x + y * y);
  _Point operator +(_Point other) => _Point(x + other.x, y + other.y);
  _Point operator -(_Point other) => _Point(x - other.x, y - other.y);
  _Point operator *(double scale) => _Point(x * scale, y * scale);
}
