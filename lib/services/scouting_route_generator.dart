import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' show LatLng;

import '../data/local/database_codes.dart';

const scoutingRouteDocumentVersion = 'scan_route_guidance_v1';
const scoutingRouteAlgorithmVersion = 'automatic_field_geometry_v3';
const previousScoutingRouteAlgorithmVersion = 'automatic_ladder_progress_v2';
const legacyScoutingRouteAlgorithmVersion = 'manual_ladder_v1';

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
    LatLng? location,
    String? source,
    bool? adjusted,
    Object? adjustmentReason = _absent,
    bool? lockedCompleted,
    Object? sideHint = _absent,
  }) {
    return ScoutingStationTarget(
      stationNumber: stationNumber,
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
      status == ScoutingRouteStatus.ready && targets.length == 5;

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
      throw const FormatException('Unsupported WormWise route document.');
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
          legacyScoutingRouteAlgorithmVersion,
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
    final savedPreparation = draft.preparation;
    if (!savedPreparation.obstaclesReviewed) {
      throw const RouteGenerationException(
        'Review obstacles and unsafe areas before generating the pattern.',
      );
    }
    final automaticBearing = automaticRouteBearingDegrees(boundary);
    final preparation = savedPreparation.copyWith(
      entrance:
          savedPreparation.entrance ??
          automaticBoundaryStart(
            boundary,
            obstacles: savedPreparation.obstacles,
          ),
      startSource: savedPreparation.entrance == null
          ? routeStartSourceFieldOutlineFallback
          : savedPreparation.startSource ?? routeStartSourceLegacySaved,
      rowBearingDegrees: automaticBearing,
      orientationSource: routeOrientationSourceFieldShape,
      draftGeometry: RouteDraftGeometry.none,
      draftPoints: const [],
    );

    late final List<ScoutingStationTarget> generated;
    if (draft.pattern == DatabaseCodes.patternW) {
      generated = _generateWTargets(
        boundary,
        preparation.entrance!,
        preparation.obstacles,
      );
    } else if (draft.pattern == DatabaseCodes.patternLadder) {
      generated = _generateAutomaticLadder(
        boundary,
        preparation.entrance!,
        preparation.rowBearingDegrees!,
        preparation.obstacles,
      ).targets;
    } else {
      throw const RouteGenerationException('Select a W or ladder pattern.');
    }

    final oldTargets = {
      for (final target in draft.targets) target.stationNumber: target,
    };
    final targets = <ScoutingStationTarget>[];
    for (final target in generated) {
      final completed = completedStations.containsKey(target.stationNumber);
      final recorded = completedStations[target.stationNumber];
      final old = oldTargets[target.stationNumber];
      if (completed) {
        targets.add(
          (old ?? target).copyWith(
            location: recorded ?? old?.location ?? target.location,
            source: recorded == null
                ? 'completed_station_target_preserved'
                : 'recorded_station_location',
            lockedCompleted: true,
          ),
        );
      } else if (old?.adjusted == true &&
          validTarget(old!.location, boundary, preparation.obstacles)) {
        targets.add(old.copyWith(lockedCompleted: false));
      } else {
        targets.add(target);
      }
    }

    final warnings = <String>[];
    late final List<ScoutingRouteSegment> segments;
    if (draft.pattern == DatabaseCodes.patternW) {
      segments = _wSegments(
        preparation.entrance!,
        targets,
        boundary,
        preparation.obstacles,
        warnings,
      );
    } else {
      final ladder = _generateAutomaticLadder(
        boundary,
        preparation.entrance!,
        preparation.rowBearingDegrees!,
        preparation.obstacles,
      );
      segments = _retargetLadderSegments(ladder.segments, targets);
      warnings.addAll(ladder.warnings);
    }
    return draft.copyWith(
      algorithmVersion: scoutingRouteAlgorithmVersion,
      status: ScoutingRouteStatus.ready,
      preparation: preparation,
      targets: List.unmodifiable(targets),
      segments: List.unmodifiable(segments),
      warnings: List.unmodifiable(warnings),
      pendingAdjustment: null,
      arrivalConfirmedStation: null,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  static List<ScoutingStationTarget> _generateWTargets(
    List<LatLng> boundary,
    LatLng entrance,
    List<List<LatLng>> obstacles,
  ) {
    final frame = _LocalFrame(boundary);
    final desired = const [
      (0.14, 0.20),
      (0.32, 0.78),
      (0.50, 0.34),
      (0.68, 0.78),
      (0.86, 0.20),
    ];
    final chosen = <LatLng>[];
    for (final (u, v) in desired) {
      chosen.add(
        _nearestInteriorGridPoint(
          frame: frame,
          desiredU: u,
          desiredV: v,
          boundary: boundary,
          obstacles: obstacles,
          alreadyChosen: chosen,
        ),
      );
    }
    if (distanceMeters(entrance, chosen.last) <
        distanceMeters(entrance, chosen.first)) {
      final reversed = chosen.reversed.toList(growable: false);
      chosen.setAll(0, reversed);
    }
    return [
      for (var index = 0; index < chosen.length; index++)
        ScoutingStationTarget(
          stationNumber: index + 1,
          location: chosen[index],
        ),
    ];
  }

  static double automaticRouteBearingDegrees(List<LatLng> boundary) {
    if (boundary.length < 3) {
      throw const RouteGenerationException(
        'The confirmed assessment-block outline is not usable for route guidance.',
      );
    }
    return _LocalFrame(boundary).majorAxisBearingDegrees;
  }

  static LatLng automaticBoundaryStart(
    List<LatLng> boundary, {
    List<List<LatLng>> obstacles = const [],
  }) {
    if (boundary.length < 3) {
      throw const RouteGenerationException(
        'The confirmed assessment-block outline is not usable for route guidance.',
      );
    }
    final frame = _LocalFrame(boundary);
    return _nearestInteriorGridPoint(
      frame: frame,
      desiredU: 0.06,
      desiredV: 0.18,
      boundary: boundary,
      obstacles: obstacles,
      alreadyChosen: const [],
    );
  }

  static _LadderGeneration _generateAutomaticLadder(
    List<LatLng> boundary,
    LatLng entrance,
    double rowBearingDegrees,
    List<List<LatLng>> obstacles,
  ) {
    final projection = _RouteMetricProjection(boundary);
    final center = polygonCenter(boundary);
    final radians = _radians(rowBearingDegrees);
    final along = _MetricVector(math.sin(radians), math.cos(radians));
    final diagonal = projection.diagonalMeters;
    final samples = <LatLng>[];
    List<LatLng> bestRun = const [];
    for (var step = -240; step <= 240; step++) {
      final point = projection.offset(
        center,
        along.east * diagonal * step / 240,
        along.north * diagonal * step / 240,
      );
      if (validTarget(point, boundary, obstacles)) {
        samples.add(point);
      } else {
        if (samples.length > bestRun.length) bestRun = List.of(samples);
        samples.clear();
      }
    }
    if (samples.length > bestRun.length) bestRun = List.of(samples);
    if (bestRun.length < 10) {
      throw const RouteGenerationException(
        'WormWise could not generate a usable central ladder spine from this outline and row direction. Adjust the row direction or a station target.',
      );
    }
    var spineStart = bestRun.first;
    var spineEnd = bestRun.last;
    if (distanceMeters(entrance, spineEnd) <
        distanceMeters(entrance, spineStart)) {
      final swap = spineStart;
      spineStart = spineEnd;
      spineEnd = swap;
    }
    final fractions = const [0.10, 0.30, 0.50, 0.70, 0.90];
    final anchors = <LatLng>[];
    final targets = <ScoutingStationTarget>[];
    final warnings = <String>[
      'The ladder spine and branches are automatically generated approximate guidance from the current phone start, saved block outline, and field-shape orientation. They are not observed crop rows or validated walking paths.',
    ];
    for (var index = 0; index < fractions.length; index++) {
      final anchor = _interpolate(spineStart, spineEnd, fractions[index]);
      anchors.add(anchor);
      final desiredRight = index.isEven;
      var branchBearing = rowBearingDegrees + (desiredRight ? 90 : -90);
      var available = _availableRayDistance(
        anchor,
        branchBearing,
        diagonal,
        projection,
        boundary,
        obstacles,
      );
      var usedRight = desiredRight;
      if (available <= 0) {
        branchBearing = rowBearingDegrees + (desiredRight ? -90 : 90);
        available = _availableRayDistance(
          anchor,
          branchBearing,
          diagonal,
          projection,
          boundary,
          obstacles,
        );
        usedRight = !desiredRight;
      }
      if (available <= 0) {
        throw RouteGenerationException(
          'Station ${index + 1} has no usable automatic ladder branch inside the outline.',
        );
      }
      final branchRadians = _radians(branchBearing);
      final location = projection.offset(
        anchor,
        math.sin(branchRadians) * available * 0.55,
        math.cos(branchRadians) * available * 0.55,
      );
      if (usedRight != desiredRight) {
        warnings.add(
          'Station ${index + 1} used the opposite side because the intended alternating side had no usable space in the saved outline.',
        );
      }
      targets.add(
        ScoutingStationTarget(
          stationNumber: index + 1,
          location: location,
          source: 'automatic_ladder_geometry_v2',
          sideHint: usedRight
              ? 'right_when_accessible'
              : 'left_when_accessible',
        ),
      );
    }
    final entryDrawable = _segmentInside(
      entrance,
      spineStart,
      boundary,
      obstacles,
    );
    if (!entryDrawable) {
      warnings.add(
        'The direct line from the entrance to the generated central spine leaves the usable outline or crosses saved legacy obstacle geometry. It is marked invalid, not asserted as a walking path.',
      );
    }
    final segments = <ScoutingRouteSegment>[
      ScoutingRouteSegment(
        points: [entrance, spineStart],
        kind: 'ladder_entry_to_spine',
        drawable: entryDrawable,
        stationNumber: 1,
        warning: entryDrawable
            ? null
            : 'Entrance-to-spine line is orientation only and is not a confirmed safe path.',
      ),
    ];
    for (var index = 0; index < anchors.length; index++) {
      segments.add(
        ScoutingRouteSegment(
          points: [
            index == 0 ? spineStart : anchors[index - 1],
            anchors[index],
          ],
          kind: 'ladder_spine_approach',
          drawable: true,
          stationNumber: index + 1,
        ),
      );
      segments.add(
        ScoutingRouteSegment(
          points: [anchors[index], targets[index].location],
          kind: 'ladder_branch_outbound',
          drawable: true,
          stationNumber: index + 1,
        ),
      );
      segments.add(
        ScoutingRouteSegment(
          points: [targets[index].location, anchors[index]],
          kind: 'ladder_branch_return',
          drawable: true,
          stationNumber: index + 1,
        ),
      );
    }
    return _LadderGeneration(
      targets: List.unmodifiable(targets),
      segments: List.unmodifiable(segments),
      warnings: List.unmodifiable(warnings),
    );
  }

  static List<ScoutingRouteSegment> _wSegments(
    LatLng entrance,
    List<ScoutingStationTarget> targets,
    List<LatLng> boundary,
    List<List<LatLng>> obstacles,
    List<String> warnings,
  ) {
    final result = <ScoutingRouteSegment>[];
    for (var index = 0; index < targets.length; index++) {
      final points = [
        index == 0 ? entrance : targets[index - 1].location,
        targets[index].location,
      ];
      final drawable = _segmentInside(
        points.first,
        points.last,
        boundary,
        obstacles,
      );
      final warning = drawable
          ? null
          : index == 0
          ? 'The direct orientation line from the entrance to Station 1 leaves the usable outline or crosses a marked obstacle; it is marked invalid, not asserted as a walking path.'
          : 'The direct orientation line between Stations $index and ${index + 1} leaves the usable outline or crosses a marked obstacle; it is marked invalid, not asserted as a walking path.';
      if (warning != null) warnings.add(warning);
      result.add(
        ScoutingRouteSegment(
          points: points,
          kind: 'suggested_orientation_only',
          drawable: drawable,
          stationNumber: index + 1,
          warning: warning,
        ),
      );
    }
    return result;
  }

  static List<ScoutingRouteSegment> _retargetLadderSegments(
    List<ScoutingRouteSegment> segments,
    List<ScoutingStationTarget> targets,
  ) {
    final byStation = {
      for (final target in targets) target.stationNumber: target,
    };
    return [
      for (final segment in segments)
        if (segment.kind == 'ladder_branch_outbound')
          ScoutingRouteSegment(
            points: [
              segment.points.first,
              byStation[segment.stationNumber]!.location,
            ],
            kind: segment.kind,
            drawable: segment.drawable,
            stationNumber: segment.stationNumber,
            warning: segment.warning,
          )
        else if (segment.kind == 'ladder_branch_return')
          ScoutingRouteSegment(
            points: [
              byStation[segment.stationNumber]!.location,
              segment.points.last,
            ],
            kind: segment.kind,
            drawable: segment.drawable,
            stationNumber: segment.stationNumber,
            warning: segment.warning,
          )
        else
          segment,
    ];
  }

  static double _availableRayDistance(
    LatLng start,
    double bearingDegrees,
    double maximum,
    _RouteMetricProjection projection,
    List<LatLng> boundary,
    List<List<LatLng>> obstacles,
  ) {
    final radians = _radians(bearingDegrees);
    var lastValid = 0.0;
    for (var step = 1; step <= 180; step++) {
      final distance = maximum * step / 180;
      final point = projection.offset(
        start,
        math.sin(radians) * distance,
        math.cos(radians) * distance,
      );
      if (!validTarget(point, boundary, obstacles)) break;
      lastValid = distance;
    }
    return lastValid;
  }

  static LatLng _interpolate(LatLng start, LatLng end, double fraction) =>
      LatLng(
        start.latitude + (end.latitude - start.latitude) * fraction,
        start.longitude + (end.longitude - start.longitude) * fraction,
      );

  static bool _segmentInside(
    LatLng start,
    LatLng end,
    List<LatLng> boundary,
    List<List<LatLng>> obstacles,
  ) {
    for (var step = 0; step <= 24; step++) {
      final t = step / 24;
      final point = LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      );
      if (!validTarget(point, boundary, obstacles)) return false;
    }
    return true;
  }

  static LatLng _nearestInteriorGridPoint({
    required _LocalFrame frame,
    required double desiredU,
    required double desiredV,
    required List<LatLng> boundary,
    required List<List<LatLng>> obstacles,
    required List<LatLng> alreadyChosen,
  }) {
    LatLng? best;
    var bestScore = double.infinity;
    for (var uIndex = 2; uIndex <= 38; uIndex++) {
      for (var vIndex = 2; vIndex <= 38; vIndex++) {
        final u = uIndex / 40;
        final v = vIndex / 40;
        final point = frame.at(u, v);
        if (!validTarget(point, boundary, obstacles)) continue;
        var score = math.pow(u - desiredU, 2) + math.pow(v - desiredV, 2);
        for (final chosen in alreadyChosen) {
          final separation = distanceMeters(point, chosen);
          if (separation < frame.diagonalMeters * 0.08) score += 10;
        }
        if (score < bestScore) {
          best = point;
          bestScore = score.toDouble();
        }
      }
    }
    if (best == null) {
      throw const RouteGenerationException(
        'Five usable interior targets could not be generated. Review the marked obstacles and try generating the pattern again.',
      );
    }
    return best;
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

class _LadderGeneration {
  const _LadderGeneration({
    required this.targets,
    required this.segments,
    required this.warnings,
  });

  final List<ScoutingStationTarget> targets;
  final List<ScoutingRouteSegment> segments;
  final List<String> warnings;
}

class _MetricVector {
  const _MetricVector(this.east, this.north);

  final double east;
  final double north;
}

class _RouteMetricProjection {
  _RouteMetricProjection(List<LatLng> boundary)
    : origin = ScoutingRouteGenerator.polygonCenter(boundary) {
    _points = boundary.map(_project).toList(growable: false);
    final minEast = _points.map((point) => point.east).reduce(math.min);
    final maxEast = _points.map((point) => point.east).reduce(math.max);
    final minNorth = _points.map((point) => point.north).reduce(math.min);
    final maxNorth = _points.map((point) => point.north).reduce(math.max);
    diagonalMeters = math.sqrt(
      math.pow(maxEast - minEast, 2) + math.pow(maxNorth - minNorth, 2),
    );
  }

  final LatLng origin;
  late List<_MetricVector> _points;
  late final double diagonalMeters;

  _MetricVector _project(LatLng point) {
    const earthRadius = 6371000.0;
    final latitudeRadians = origin.latitude * math.pi / 180;
    return _MetricVector(
      (point.longitude - origin.longitude) *
          math.pi /
          180 *
          earthRadius *
          math.cos(latitudeRadians),
      (point.latitude - origin.latitude) * math.pi / 180 * earthRadius,
    );
  }

  LatLng offset(LatLng point, double eastMeters, double northMeters) {
    const earthRadius = 6371000.0;
    final latitudeRadians = origin.latitude * math.pi / 180;
    return LatLng(
      point.latitude + northMeters / earthRadius * 180 / math.pi,
      point.longitude +
          eastMeters /
              (earthRadius * math.cos(latitudeRadians)) *
              180 /
              math.pi,
    );
  }
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
