import 'dart:convert';
import 'scouting_sampling_protocol.dart';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' show LatLng;

const scoutingRouteDocumentVersion = 'scan_route_guidance_v1';
const scoutingRouteAlgorithmVersion = 'automatic_field_geometry_v3';
const retiredRouteAlgorithmVersion = 'retired_sampling_route';

const routeStartSourcePhoneLocation = 'phone_location';
const routeStartSourceFieldOutlineFallback = 'field_outline_fallback';
const routeStartSourceLegacySaved = 'legacy_saved_start';
const routeOrientationSourceFieldShape = 'field_shape_major_axis';

enum ScoutingRouteStatus { draft, ready }

enum RouteDraftGeometry {
  none,
  entrance,
  rowDirection,
  accessiblePath,
  obstacle,
}

class RoutePreparationData {
  const RoutePreparationData({
    this.entrance,
    this.startSource,
    this.startAccuracyMeters,
    this.rowBearingDegrees,
    this.orientationSource,
    this.accessiblePaths = const [],
    this.obstacles = const [],
    this.obstaclesReviewed = false,
    this.wCrossingConfirmed = false,
    this.draftGeometry = RouteDraftGeometry.none,
    this.draftPoints = const [],
  });

  final LatLng? entrance;
  final String? startSource;
  final double? startAccuracyMeters;
  final double? rowBearingDegrees;
  final String? orientationSource;
  final List<List<LatLng>> accessiblePaths;
  final List<List<LatLng>> obstacles;
  final bool obstaclesReviewed;
  final bool wCrossingConfirmed;
  final RouteDraftGeometry draftGeometry;
  final List<LatLng> draftPoints;

  RoutePreparationData copyWith({
    Object? entrance = _absent,
    Object? startSource = _absent,
    Object? startAccuracyMeters = _absent,
    Object? rowBearingDegrees = _absent,
    Object? orientationSource = _absent,
    List<List<LatLng>>? accessiblePaths,
    List<List<LatLng>>? obstacles,
    bool? obstaclesReviewed,
    bool? wCrossingConfirmed,
    RouteDraftGeometry? draftGeometry,
    List<LatLng>? draftPoints,
  }) {
    return RoutePreparationData(
      entrance: identical(entrance, _absent)
          ? this.entrance
          : entrance as LatLng?,
      startSource: identical(startSource, _absent)
          ? this.startSource
          : startSource as String?,
      startAccuracyMeters: identical(startAccuracyMeters, _absent)
          ? this.startAccuracyMeters
          : startAccuracyMeters as double?,
      rowBearingDegrees: identical(rowBearingDegrees, _absent)
          ? this.rowBearingDegrees
          : rowBearingDegrees as double?,
      orientationSource: identical(orientationSource, _absent)
          ? this.orientationSource
          : orientationSource as String?,
      accessiblePaths: accessiblePaths ?? this.accessiblePaths,
      obstacles: obstacles ?? this.obstacles,
      obstaclesReviewed: obstaclesReviewed ?? this.obstaclesReviewed,
      wCrossingConfirmed: wCrossingConfirmed ?? this.wCrossingConfirmed,
      draftGeometry: draftGeometry ?? this.draftGeometry,
      draftPoints: draftPoints ?? this.draftPoints,
    );
  }

  Map<String, Object?> toJson() => {
    'entrance': entrance == null ? null : _pointJson(entrance!),
    'start_source': startSource,
    'start_accuracy_meters': startAccuracyMeters,
    'row_bearing_degrees': rowBearingDegrees,
    'orientation_source': orientationSource,
    'accessible_paths': accessiblePaths.map(_lineJson).toList(),
    'obstacles': obstacles.map(_lineJson).toList(),
    'obstacles_reviewed': obstaclesReviewed,
    'w_crossing_confirmed': wCrossingConfirmed,
    'draft_geometry': draftGeometry.name,
    'draft_points': _lineJson(draftPoints),
  };

  factory RoutePreparationData.fromJson(Map<String, Object?> json) {
    return RoutePreparationData(
      entrance: _pointFromJson(json['entrance']),
      startSource: json['start_source'] as String?,
      startAccuracyMeters: (json['start_accuracy_meters'] as num?)?.toDouble(),
      rowBearingDegrees: (json['row_bearing_degrees'] as num?)?.toDouble(),
      orientationSource: json['orientation_source'] as String?,
      accessiblePaths: _linesFromJson(json['accessible_paths']),
      obstacles: _linesFromJson(json['obstacles']),
      obstaclesReviewed: json['obstacles_reviewed'] == true,
      wCrossingConfirmed: json['w_crossing_confirmed'] == true,
      draftGeometry: RouteDraftGeometry.values.firstWhere(
        (value) => value.name == json['draft_geometry'],
        orElse: () => RouteDraftGeometry.none,
      ),
      draftPoints: _lineFromJson(json['draft_points']),
    );
  }
}

class ScoutingStationTarget {
  const ScoutingStationTarget({
    required this.stationNumber,
    required this.location,
    this.source = 'generated_approximate',
    this.adjusted = false,
    this.adjustmentReason,
    this.lockedCompleted = false,
    this.sideHint,
  });

  final int stationNumber;
  final LatLng location;
  final String source;
  final bool adjusted;
  final String? adjustmentReason;
  final bool lockedCompleted;
  final String? sideHint;

  ScoutingStationTarget copyWith({
    int? stationNumber,
    LatLng? location,
    String? source,
    bool? adjusted,
    Object? adjustmentReason = _absent,
    bool? lockedCompleted,
    Object? sideHint = _absent,
  }) {
    return ScoutingStationTarget(
      stationNumber: stationNumber ?? this.stationNumber,
      location: location ?? this.location,
      source: source ?? this.source,
      adjusted: adjusted ?? this.adjusted,
      adjustmentReason: identical(adjustmentReason, _absent)
          ? this.adjustmentReason
          : adjustmentReason as String?,
      lockedCompleted: lockedCompleted ?? this.lockedCompleted,
      sideHint: identical(sideHint, _absent)
          ? this.sideHint
          : sideHint as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'station_number': stationNumber,
    'location': _pointJson(location),
    'source': source,
    'adjusted': adjusted,
    'adjustment_reason': adjustmentReason,
    'locked_completed': lockedCompleted,
    'side_hint': sideHint,
  };

  factory ScoutingStationTarget.fromJson(Map<String, Object?> json) {
    return ScoutingStationTarget(
      stationNumber: (json['station_number'] as num).toInt(),
      location: _pointFromJson(json['location'])!,
      source: json['source'] as String? ?? 'generated_approximate',
      adjusted: json['adjusted'] == true,
      adjustmentReason: json['adjustment_reason'] as String?,
      lockedCompleted: json['locked_completed'] == true,
      sideHint: json['side_hint'] as String?,
    );
  }
}

class ScoutingRouteSegment {
  const ScoutingRouteSegment({
    required this.points,
    required this.kind,
    required this.drawable,
    this.stationNumber,
    this.warning,
  });

  final List<LatLng> points;
  final String kind;
  final bool drawable;
  final int? stationNumber;
  final String? warning;

  Map<String, Object?> toJson() => {
    'points': _lineJson(points),
    'kind': kind,
    'drawable': drawable,
    'station_number': stationNumber,
    'warning': warning,
  };

  factory ScoutingRouteSegment.fromJson(Map<String, Object?> json) {
    return ScoutingRouteSegment(
      points: _lineFromJson(json['points']),
      kind: json['kind'] as String,
      drawable: json['drawable'] == true,
      stationNumber: (json['station_number'] as num?)?.toInt(),
      warning: json['warning'] as String?,
    );
  }
}

class PendingTargetAdjustment {
  const PendingTargetAdjustment({
    required this.stationNumber,
    this.candidate,
    this.reason = '',
  });

  final int stationNumber;
  final LatLng? candidate;
  final String reason;

  Map<String, Object?> toJson() => {
    'station_number': stationNumber,
    'candidate': candidate == null ? null : _pointJson(candidate!),
    'reason': reason,
  };

  factory PendingTargetAdjustment.fromJson(Map<String, Object?> json) {
    return PendingTargetAdjustment(
      stationNumber: (json['station_number'] as num).toInt(),
      candidate: _pointFromJson(json['candidate']),
      reason: json['reason'] as String? ?? '',
    );
  }
}

class ScoutingRoutePlan {
  const ScoutingRoutePlan({
    required this.assessmentId,
    required this.blockRunId,
    required this.blockId,
    required this.boundaryVersionId,
    required this.pattern,
    required this.status,
    required this.preparation,
    this.algorithmVersion = scoutingRouteAlgorithmVersion,
    this.targets = const [],
    this.segments = const [],
    this.warnings = const [],
    this.pendingAdjustment,
    this.arrivalConfirmedStation,
    required this.updatedAt,
  });

  final String assessmentId;
  final String blockRunId;
  final String blockId;
  final String boundaryVersionId;
  final String pattern;
  final ScoutingRouteStatus status;
  final RoutePreparationData preparation;
  final String algorithmVersion;
  final List<ScoutingStationTarget> targets;
  final List<ScoutingRouteSegment> segments;
  final List<String> warnings;
  final PendingTargetAdjustment? pendingAdjustment;
  final int? arrivalConfirmedStation;
  final DateTime updatedAt;

  bool get isReady =>
      status == ScoutingRouteStatus.ready &&
      pattern == ScoutingSamplingProtocol.daPattern &&
      targets.length == ScoutingSamplingProtocol.plantsPerBlock;

  ScoutingStationTarget targetFor(int stationNumber) =>
      targets.singleWhere((target) => target.stationNumber == stationNumber);

  ScoutingRoutePlan copyWith({
    String? pattern,
    ScoutingRouteStatus? status,
    RoutePreparationData? preparation,
    String? algorithmVersion,
    List<ScoutingStationTarget>? targets,
    List<ScoutingRouteSegment>? segments,
    List<String>? warnings,
    Object? pendingAdjustment = _absent,
    Object? arrivalConfirmedStation = _absent,
    DateTime? updatedAt,
  }) {
    return ScoutingRoutePlan(
      assessmentId: assessmentId,
      blockRunId: blockRunId,
      blockId: blockId,
      boundaryVersionId: boundaryVersionId,
      pattern: pattern ?? this.pattern,
      status: status ?? this.status,
      preparation: preparation ?? this.preparation,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      targets: targets ?? this.targets,
      segments: segments ?? this.segments,
      warnings: warnings ?? this.warnings,
      pendingAdjustment: identical(pendingAdjustment, _absent)
          ? this.pendingAdjustment
          : pendingAdjustment as PendingTargetAdjustment?,
      arrivalConfirmedStation: identical(arrivalConfirmedStation, _absent)
          ? this.arrivalConfirmedStation
          : arrivalConfirmedStation as int?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String toGeoJson() {
    final features = <Map<String, Object?>>[
      for (final target in targets)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': _pointJson(target.location),
          },
          'properties': {
            'feature_type': 'station_target',
            ...target.toJson()..remove('location'),
          },
        },
      for (var index = 0; index < preparation.accessiblePaths.length; index++)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': _lineJson(preparation.accessiblePaths[index]),
          },
          'properties': {
            'feature_type': 'evaluator_confirmed_accessible_path',
            'path_index': index,
          },
        },
      for (var index = 0; index < preparation.obstacles.length; index++)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [_closedLineJson(preparation.obstacles[index])],
          },
          'properties': {
            'feature_type': 'evaluator_marked_obstacle',
            'obstacle_index': index,
          },
        },
      for (var index = 0; index < segments.length; index++)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': _lineJson(segments[index].points),
          },
          'properties': {
            'feature_type': 'route_segment',
            'segment_index': index,
            'kind': segments[index].kind,
            'drawable': segments[index].drawable,
            'warning': segments[index].warning,
          },
        },
    ];
    return jsonEncode({
      'type': 'FeatureCollection',
      'wormwise': {
        'document_version': scoutingRouteDocumentVersion,
        'assessment_id': assessmentId,
        'block_run_id': blockRunId,
        'block_id': blockId,
        'boundary_version_id': boundaryVersionId,
        'pattern': pattern,
        'status': status.name,
        'algorithm_version': algorithmVersion,
        'preparation': preparation.toJson(),
        'targets': targets.map((target) => target.toJson()).toList(),
        'segments': segments.map((segment) => segment.toJson()).toList(),
        'warnings': warnings,
        'pending_adjustment': pendingAdjustment?.toJson(),
        'arrival_confirmed_station': arrivalConfirmedStation,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'disclaimer':
            'Editable approximate field guidance only; not turn-by-turn navigation, validated placement geometry, proof of protocol compliance, or a legal boundary.',
      },
      'features': features,
    });
  }

  factory ScoutingRoutePlan.fromGeoJson(String value) {
    final root = jsonDecode(value) as Map<String, Object?>;
    final metadata = (root['wormwise'] as Map).cast<String, Object?>();
    if (metadata['document_version'] != scoutingRouteDocumentVersion) {
      throw const FormatException('Unsupported Cropwise route document.');
    }
    final preparation =
        (metadata['preparation'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return ScoutingRoutePlan(
      assessmentId: metadata['assessment_id'] as String,
      blockRunId: metadata['block_run_id'] as String,
      blockId: metadata['block_id'] as String,
      boundaryVersionId: metadata['boundary_version_id'] as String,
      pattern: metadata['pattern'] as String,
      status: ScoutingRouteStatus.values.firstWhere(
        (status) => status.name == metadata['status'],
        orElse: () => ScoutingRouteStatus.draft,
      ),
      preparation: RoutePreparationData.fromJson(preparation),
      algorithmVersion:
          metadata['algorithm_version'] as String? ??
          retiredRouteAlgorithmVersion,
      targets: _objectList(
        metadata['targets'],
      ).map(ScoutingStationTarget.fromJson).toList(growable: false),
      segments: _objectList(
        metadata['segments'],
      ).map(ScoutingRouteSegment.fromJson).toList(growable: false),
      warnings: (metadata['warnings'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      pendingAdjustment: metadata['pending_adjustment'] is Map
          ? PendingTargetAdjustment.fromJson(
              (metadata['pending_adjustment'] as Map).cast<String, Object?>(),
            )
          : null,
      arrivalConfirmedStation: (metadata['arrival_confirmed_station'] as num?)
          ?.toInt(),
      updatedAt:
          DateTime.tryParse(metadata['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class RouteGenerationException implements Exception {
  const RouteGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScoutingRouteGenerator {
  static List<LatLng> parsePolygon(String geoJson) {
    try {
      final decoded = jsonDecode(geoJson) as Map<String, Object?>;
      if (decoded['type'] != 'Polygon') return const [];
      final rings = decoded['coordinates'] as List?;
      if (rings == null || rings.isEmpty) return const [];
      final points = _lineFromJson(rings.first);
      if (points.length > 1 && points.first == points.last) {
        return points.sublist(0, points.length - 1);
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  static LatLng polygonCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    return LatLng(
      points.map((point) => point.latitude).reduce((a, b) => a + b) /
          points.length,
      points.map((point) => point.longitude).reduce((a, b) => a + b) /
          points.length,
    );
  }

  static bool pointInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static bool validTarget(
    LatLng point,
    List<LatLng> boundary,
    List<List<LatLng>> obstacles,
  ) {
    return pointInsidePolygon(point, boundary) &&
        !obstacles.any((obstacle) => pointInsidePolygon(point, obstacle));
  }

  static ScoutingRoutePlan generate({
    required ScoutingRoutePlan draft,
    required List<LatLng> boundary,
    Map<int, LatLng?> completedStations = const {},
  }) {
    if (boundary.length < 3) {
      throw const RouteGenerationException(
        'The confirmed assessment-block outline is not usable for route guidance.',
      );
    }
    if (draft.pattern != ScoutingSamplingProtocol.daPattern) {
      throw const RouteGenerationException(
        'This scouting method is no longer supported. Start a new assessment with 20 plants per sampling block.',
      );
    }
    return _generateDaPlants(draft, boundary, completedStations);
  }

  /// Fits the booklet's dispersed point arrangement to the local field frame.
  /// This is an app sampling aid; the booklet does not give surveyed coordinates
  /// or prescribe the numbered order in which the farmer walks to the plants.
  static ScoutingRoutePlan _generateDaPlants(
    ScoutingRoutePlan draft,
    List<LatLng> boundary,
    Map<int, LatLng?> completed,
  ) {
    final frame = _LocalFrame(boundary);
    const layout = <(double, double)>[
      (.10, .70),
      (.10, .56),
      (.16, .42),
      (.22, .27),
      (.28, .12),
      (.34, .25),
      (.39, .42),
      (.45, .56),
      (.45, .71),
      (.45, .85),
      (.28, .85),
      (.70, .85),
      (.57, .56),
      (.57, .42),
      (.63, .27),
      (.70, .12),
      (.76, .27),
      (.83, .42),
      (.89, .56),
      (.89, .70),
    ];
    final candidates = <LatLng>[
      for (var u = 1; u < 60; u++)
        for (var v = 1; v < 60; v++)
          if (validDaTarget(
            frame.at(u / 60, v / 60),
            boundary,
            draft.preparation.obstacles,
          ))
            frame.at(u / 60, v / 60),
    ];
    final targets = <ScoutingStationTarget>[];
    final used = <LatLng>[];
    // A minimum separation prevents multiple suggestions pointing to the same
    // plant after fitting a concave/narrow boundary. It is an app rule, not DA's.
    const minimumSeparation = 2.0;
    for (var index = 0; index < layout.length; index++) {
      final number = index + 1;
      final old = draft.targets
          .where((t) => t.stationNumber == number)
          .firstOrNull;
      if (completed.containsKey(number) && old != null) {
        targets.add(old.copyWith(lockedCompleted: true));
        used.add(old.location);
        continue;
      }
      if (old?.adjusted == true &&
          validDaTarget(old!.location, boundary, draft.preparation.obstacles)) {
        targets.add(old.copyWith(lockedCompleted: false));
        used.add(old.location);
        continue;
      }
      final desired = frame.at(layout[index].$1, layout[index].$2);
      final available = candidates
          .where(
            (p) => used.every(
              (previous) => distanceMeters(p, previous) >= minimumSeparation,
            ),
          )
          .toList();
      if (available.isEmpty) {
        throw const RouteGenerationException(
          'The outline cannot fit 20 separate suggestions at least 3 m from the edge. Check the outline or choose a larger accessible sampling block.',
        );
      }
      available.sort(
        (a, b) =>
            distanceMeters(a, desired).compareTo(distanceMeters(b, desired)),
      );
      final point =
          validDaTarget(desired, boundary, draft.preparation.obstacles) &&
              used.every((p) => distanceMeters(p, desired) >= minimumSeparation)
          ? desired
          : available.first;
      used.add(point);
      targets.add(
        ScoutingStationTarget(
          stationNumber: number,
          location: point,
          source: 'da_booklet_layout_app_suggestion',
          lockedCompleted: completed.containsKey(number),
        ),
      );
    }
    final generated = draft.copyWith(
      status: ScoutingRouteStatus.ready,
      algorithmVersion: ScoutingSamplingProtocol.daAlgorithm,
      targets: List.unmodifiable(targets),
      // No connected route is claimed safe across rows, obstacles or concavities.
      segments: const [],
      warnings: const [
        'Suggested plant locations. Choose an actual nearby plant at least 3 m from the edge; use a safe accessible path.',
      ],
      preparation: draft.preparation.copyWith(
        rowBearingDegrees: automaticRouteBearingDegrees(boundary),
        orientationSource: routeOrientationSourceFieldShape,
      ),
      pendingAdjustment: null,
      updatedAt: DateTime.now().toUtc(),
    );
    final fixedThrough = completed.keys.fold<int>(0, math.max);
    return orderDaTargetsForWalk(generated, fixedThrough: fixedThrough);
  }

  /// Reorders only untouched suggestions. Sampling coverage and coordinates
  /// stay unchanged. Distances are straight-line aids, not surveyed safe paths.
  static ScoutingRoutePlan orderDaTargetsForWalk(
    ScoutingRoutePlan plan, {
    int fixedThrough = 0,
  }) {
    if (plan.pattern != ScoutingSamplingProtocol.daPattern || !plan.isReady) {
      return plan;
    }
    final original = [...plan.targets]
      ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber));
    // Keep Plant 1 as the starting point, and every saved/arrived/adjusted
    // number through the highest fixed position. Never relabel captured data.
    var prefixLength = math.max(1, fixedThrough);
    prefixLength = math.max(prefixLength, plan.arrivalConfirmedStation ?? 0);
    for (final target in original) {
      if (target.lockedCompleted || target.adjusted) {
        prefixLength = math.max(prefixLength, target.stationNumber);
      }
    }
    prefixLength = prefixLength.clamp(1, original.length);
    final pending = original.sublist(prefixLength);
    final nearest = original.sublist(0, prefixLength);
    while (pending.isNotEmpty) {
      final from = nearest.last.location;
      var best = 0;
      for (var i = 1; i < pending.length; i++) {
        if (distanceMeters(from, pending[i].location) <
            distanceMeters(from, pending[best].location))
          best = i;
      }
      nearest.add(pending.removeAt(best));
    }
    double length(List<ScoutingStationTarget> points) {
      var total = 0.0;
      for (var i = 1; i < points.length; i++) {
        total += distanceMeters(points[i - 1].location, points[i].location);
      }
      return total;
    }

    var ordered = length(nearest) < length(original) ? nearest : original;
    // Remove avoidable crossings and backtracking from the open walking order.
    var improved = true;
    while (improved) {
      improved = false;
      for (var i = prefixLength; i < ordered.length - 1; i++) {
        for (var j = i + 1; j < ordered.length; j++) {
          final candidate = [
            ...ordered.take(i),
            ...ordered.sublist(i, j + 1).reversed,
            ...ordered.skip(j + 1),
          ];
          if (length(candidate) < length(ordered) - .01) {
            ordered = candidate;
            improved = true;
          }
        }
      }
    }
    return plan.copyWith(
      algorithmVersion: ScoutingSamplingProtocol.daAlgorithm,
      targets: List.unmodifiable([
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(stationNumber: i + 1),
      ]),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  static bool validDaTarget(
    LatLng point,
    List<LatLng> boundary,
    List<List<LatLng>> obstacles,
  ) =>
      validTarget(point, boundary, obstacles) &&
      distanceToBoundaryMeters(point, boundary) >=
          ScoutingSamplingProtocol.edgeMarginMeters;

  static double distanceToBoundaryMeters(LatLng point, List<LatLng> boundary) {
    if (boundary.length < 3) return 0;
    final frame = _LocalFrame(boundary);
    final p = frame._project(point);
    var nearest = double.infinity;
    for (var i = 0; i < boundary.length; i++) {
      final a = frame._project(boundary[i]);
      final b = frame._project(boundary[(i + 1) % boundary.length]);
      final dx = b.x - a.x, dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(
              0.0,
              1.0,
            );
      nearest = math.min(
        nearest,
        math.sqrt(
          math.pow(p.x - a.x - t * dx, 2) + math.pow(p.y - a.y - t * dy, 2),
        ),
      );
    }
    return nearest;
  }

  static double automaticRouteBearingDegrees(List<LatLng> boundary) {
    if (boundary.length < 3) {
      throw const RouteGenerationException(
        'The confirmed assessment-block outline is not usable for route guidance.',
      );
    }
    return _LocalFrame(boundary).majorAxisBearingDegrees;
  }

  static double distanceMeters(LatLng first, LatLng second) {
    const radius = 6371000.0;
    final lat1 = _radians(first.latitude);
    final lat2 = _radians(second.latitude);
    final deltaLat = lat2 - lat1;
    final deltaLon = _radians(second.longitude - first.longitude);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double bearingDegrees(LatLng from, LatLng to) {
    final lat1 = _radians(from.latitude);
    final lat2 = _radians(to.latitude);
    final deltaLon = _radians(to.longitude - from.longitude);
    final y = math.sin(deltaLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static String approximateDirection(double bearing) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return labels[((bearing + 22.5) ~/ 45) % 8];
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

class _LocalFrame {
  _LocalFrame(List<LatLng> polygon)
    : origin = ScoutingRouteGenerator.polygonCenter(polygon) {
    final points = polygon.map(_project).toList(growable: false);
    var xx = 0.0;
    var xy = 0.0;
    var yy = 0.0;
    for (final point in points) {
      xx += point.x * point.x;
      xy += point.x * point.y;
      yy += point.y * point.y;
    }
    angle = 0.5 * math.atan2(2 * xy, xx - yy);
    final rotated = points.map(_rotate).toList(growable: false);
    minU = rotated.map((point) => point.x).reduce(math.min);
    maxU = rotated.map((point) => point.x).reduce(math.max);
    minV = rotated.map((point) => point.y).reduce(math.min);
    maxV = rotated.map((point) => point.y).reduce(math.max);
    diagonalMeters = math.sqrt(
      math.pow(maxU - minU, 2) + math.pow(maxV - minV, 2),
    );
  }

  final LatLng origin;
  late final double angle;
  late final double minU;
  late final double maxU;
  late final double minV;
  late final double maxV;
  late final double diagonalMeters;

  double get majorAxisBearingDegrees =>
      (90 - angle * 180 / math.pi + 360) % 360;

  _XY _project(LatLng point) {
    final latitudeScale = 111320.0;
    final longitudeScale =
        latitudeScale * math.cos(origin.latitude * math.pi / 180);
    return _XY(
      (point.longitude - origin.longitude) * longitudeScale,
      (point.latitude - origin.latitude) * latitudeScale,
    );
  }

  _XY _rotate(_XY point) => _XY(
    point.x * math.cos(angle) + point.y * math.sin(angle),
    -point.x * math.sin(angle) + point.y * math.cos(angle),
  );

  LatLng at(double u, double v) {
    final rotated = _XY(minU + (maxU - minU) * u, minV + (maxV - minV) * v);
    final projected = _XY(
      rotated.x * math.cos(angle) - rotated.y * math.sin(angle),
      rotated.x * math.sin(angle) + rotated.y * math.cos(angle),
    );
    final latitudeScale = 111320.0;
    final longitudeScale =
        latitudeScale * math.cos(origin.latitude * math.pi / 180);
    return LatLng(
      origin.latitude + projected.y / latitudeScale,
      origin.longitude + projected.x / longitudeScale,
    );
  }
}

class _XY {
  const _XY(this.x, this.y);

  final double x;
  final double y;
}

const _absent = Object();

List<double> _pointJson(LatLng point) => [point.longitude, point.latitude];

List<List<double>> _lineJson(List<LatLng> points) =>
    points.map(_pointJson).toList(growable: false);

List<List<double>> _closedLineJson(List<LatLng> points) => [
  ..._lineJson(points),
  if (points.isNotEmpty && points.first != points.last)
    _pointJson(points.first),
];

LatLng? _pointFromJson(Object? value) {
  if (value is! List || value.length < 2) return null;
  return LatLng((value[1] as num).toDouble(), (value[0] as num).toDouble());
}

List<LatLng> _lineFromJson(Object? value) {
  if (value is! List) return const [];
  return value.map(_pointFromJson).whereType<LatLng>().toList(growable: false);
}

List<List<LatLng>> _linesFromJson(Object? value) {
  if (value is! List) return const [];
  return value.map(_lineFromJson).toList(growable: false);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}
