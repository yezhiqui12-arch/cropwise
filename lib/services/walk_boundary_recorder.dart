import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

enum WalkSampleDecision {
  accepted,
  acceptedCorner,
  replacedWithCorner,
  poorAccuracy,
  tooClose,
  implausibleJump,
  invalid,
}

class WalkBoundarySample {
  const WalkBoundarySample({
    required this.position,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final LatLng position;
  final double accuracyMeters;
  final DateTime capturedAt;
}

class WalkBoundaryPoint {
  const WalkBoundaryPoint({
    required this.position,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.isMarkedCorner,
  });

  final LatLng position;
  final double accuracyMeters;
  final DateTime capturedAt;
  final bool isMarkedCorner;
}

class WalkBoundaryRecorder {
  WalkBoundaryRecorder({
    this.minimumPointDistanceMeters = 5,
    this.maximumAccuracyMeters = 25,
    this.maximumWalkingSpeedMetersPerSecond = 4.5,
  });

  final double minimumPointDistanceMeters;
  final double maximumAccuracyMeters;
  final double maximumWalkingSpeedMetersPerSecond;

  final List<WalkBoundaryPoint> _points = [];
  final List<WalkBoundaryPoint> _corners = [];
  WalkBoundarySample? _latestSample;
  int _rejectedAccuracyCount = 0;
  int _rejectedMovementCount = 0;

  List<WalkBoundaryPoint> get points => List.unmodifiable(_points);
  List<WalkBoundaryPoint> get corners => List.unmodifiable(_corners);

  /// Confirmed averaged corners define straight edges independently of GPS trace noise.
  WalkSampleDecision markCorner(WalkBoundarySample sample) {
    if (!_isValid(sample)) return WalkSampleDecision.invalid;
    if (sample.accuracyMeters > maximumAccuracyMeters) {
      return WalkSampleDecision.poorAccuracy;
    }
    final corner = WalkBoundaryPoint(
      position: sample.position,
      accuracyMeters: sample.accuracyMeters,
      capturedAt: sample.capturedAt,
      isMarkedCorner: true,
    );
    if (_corners.length >= 3 &&
        const Distance().as(
              LengthUnit.Meter,
              _corners.first.position,
              sample.position,
            ) <
            minimumPointDistanceMeters) {
      return WalkSampleDecision.tooClose;
    }
    if (_corners.isNotEmpty &&
        const Distance().as(
              LengthUnit.Meter,
              _corners.last.position,
              sample.position,
            ) <
            minimumPointDistanceMeters) {
      return WalkSampleDecision.tooClose;
    }
    _corners.add(corner);
    return WalkSampleDecision.acceptedCorner;
  }

  WalkBoundarySample? get latestSample => _latestSample;
  int get rejectedAccuracyCount => _rejectedAccuracyCount;
  int get rejectedMovementCount => _rejectedMovementCount;

  double? get latestAccuracyMeters => _latestSample?.accuracyMeters;

  double? get distanceToStartMeters {
    final latest = _latestSample;
    if (latest == null || (_corners.isEmpty && _points.isEmpty)) return null;
    return const Distance().as(
      LengthUnit.Meter,
      _corners.isNotEmpty ? _corners.first.position : _points.first.position,
      latest.position,
    );
  }

  double get acceptedPathMeters {
    if (_points.length < 2) return 0;
    const distance = Distance();
    var total = 0.0;
    for (var index = 1; index < _points.length; index++) {
      total += distance.as(
        LengthUnit.Meter,
        _points[index - 1].position,
        _points[index].position,
      );
    }
    return total;
  }

  double? get averageAccuracyMeters {
    if (_points.isEmpty) return null;
    return _points
            .map((point) => point.accuracyMeters)
            .reduce((first, second) => first + second) /
        _points.length;
  }

  WalkSampleDecision addSample(
    WalkBoundarySample sample, {
    bool markedCorner = false,
  }) {
    _latestSample = sample;
    if (!_isValid(sample)) return WalkSampleDecision.invalid;
    if (sample.accuracyMeters > maximumAccuracyMeters) {
      _rejectedAccuracyCount++;
      return WalkSampleDecision.poorAccuracy;
    }

    final candidate = WalkBoundaryPoint(
      position: sample.position,
      accuracyMeters: sample.accuracyMeters,
      capturedAt: sample.capturedAt,
      isMarkedCorner: markedCorner,
    );
    if (_points.isEmpty) {
      _points.add(candidate);
      return markedCorner
          ? WalkSampleDecision.acceptedCorner
          : WalkSampleDecision.accepted;
    }

    final previous = _points.last;
    final distanceMeters = const Distance().as(
      LengthUnit.Meter,
      previous.position,
      sample.position,
    );

    if (markedCorner && distanceMeters < minimumPointDistanceMeters / 2) {
      _points[_points.length - 1] = candidate;
      return WalkSampleDecision.replacedWithCorner;
    }
    if (distanceMeters < minimumPointDistanceMeters) {
      _rejectedMovementCount++;
      return WalkSampleDecision.tooClose;
    }

    final elapsedSeconds =
        sample.capturedAt.difference(previous.capturedAt).inMilliseconds / 1000;
    if (!markedCorner &&
        elapsedSeconds >= 0.5 &&
        elapsedSeconds <= 30 &&
        distanceMeters / elapsedSeconds > maximumWalkingSpeedMetersPerSecond) {
      _rejectedMovementCount++;
      return WalkSampleDecision.implausibleJump;
    }

    _points.add(candidate);
    return markedCorner
        ? WalkSampleDecision.acceptedCorner
        : WalkSampleDecision.accepted;
  }

  void reset() {
    _points.clear();
    _corners.clear();
    _latestSample = null;
    _rejectedAccuracyCount = 0;
    _rejectedMovementCount = 0;
  }

  List<WalkBoundaryPoint> simplified({double toleranceMeters = 2}) {
    if (_points.length <= 2 || toleranceMeters <= 0) {
      return List.unmodifiable(_points);
    }

    final anchorIndices = <int>[0];
    for (var index = 1; index < _points.length - 1; index++) {
      if (_points[index].isMarkedCorner) anchorIndices.add(index);
    }
    anchorIndices.add(_points.length - 1);

    final result = <WalkBoundaryPoint>[];
    for (var anchor = 1; anchor < anchorIndices.length; anchor++) {
      final start = anchorIndices[anchor - 1];
      final end = anchorIndices[anchor];
      final simplifiedSegment = _douglasPeucker(
        _points.sublist(start, end + 1),
        toleranceMeters,
      );
      if (result.isNotEmpty) simplifiedSegment.removeAt(0);
      result.addAll(simplifiedSegment);
    }
    return List.unmodifiable(result);
  }

  bool _isValid(WalkBoundarySample sample) {
    return sample.position.latitude.isFinite &&
        sample.position.longitude.isFinite &&
        sample.position.latitude >= -85.05112878 &&
        sample.position.latitude <= 85.05112878 &&
        sample.position.longitude >= -180 &&
        sample.position.longitude <= 180 &&
        sample.accuracyMeters.isFinite &&
        sample.accuracyMeters >= 0;
  }

  List<WalkBoundaryPoint> _douglasPeucker(
    List<WalkBoundaryPoint> input,
    double toleranceMeters,
  ) {
    if (input.length <= 2) return List.of(input);

    var furthestDistance = 0.0;
    var furthestIndex = 0;
    for (var index = 1; index < input.length - 1; index++) {
      final distance = _perpendicularDistanceMeters(
        input[index].position,
        input.first.position,
        input.last.position,
      );
      if (distance > furthestDistance) {
        furthestDistance = distance;
        furthestIndex = index;
      }
    }

    if (furthestDistance <= toleranceMeters) {
      return [input.first, input.last];
    }
    final first = _douglasPeucker(
      input.sublist(0, furthestIndex + 1),
      toleranceMeters,
    );
    final second = _douglasPeucker(
      input.sublist(furthestIndex),
      toleranceMeters,
    );
    return [...first.take(first.length - 1), ...second];
  }

  double _perpendicularDistanceMeters(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    const earthRadius = 6378137.0;
    final latitudeRadians =
        ((lineStart.latitude + lineEnd.latitude + point.latitude) / 3) *
        math.pi /
        180;
    final longitudeScale = math.cos(latitudeRadians);

    ({double x, double y}) project(LatLng value) => (
      x: value.longitude * math.pi / 180 * earthRadius * longitudeScale,
      y: value.latitude * math.pi / 180 * earthRadius,
    );

    final projectedPoint = project(point);
    final projectedStart = project(lineStart);
    final projectedEnd = project(lineEnd);
    final dx = projectedEnd.x - projectedStart.x;
    final dy = projectedEnd.y - projectedStart.y;
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        math.pow(projectedPoint.x - projectedStart.x, 2) +
            math.pow(projectedPoint.y - projectedStart.y, 2),
      );
    }

    final fraction =
        (((projectedPoint.x - projectedStart.x) * dx) +
            ((projectedPoint.y - projectedStart.y) * dy)) /
        ((dx * dx) + (dy * dy));
    final clamped = fraction.clamp(0.0, 1.0);
    final nearestX = projectedStart.x + (clamped * dx);
    final nearestY = projectedStart.y + (clamped * dy);
    return math.sqrt(
      math.pow(projectedPoint.x - nearestX, 2) +
          math.pow(projectedPoint.y - nearestY, 2),
    );
  }
}
