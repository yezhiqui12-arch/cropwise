import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/scouting_route_generator.dart';

void main() {
  const boundary = [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ];

  test('W guidance creates five editable interior targets', () {
    final plan = ScoutingRouteGenerator.generate(
      draft: _draft(
        pattern: DatabaseCodes.patternW,
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
      ),
      boundary: boundary,
    );

    expect(plan.targets, hasLength(5));
    expect(
      plan.targets.map((target) => target.stationNumber),
      orderedEquals([1, 2, 3, 4, 5]),
    );
    expect(
      plan.targets.every(
        (target) => ScoutingRouteGenerator.pointInsidePolygon(
          target.location,
          boundary,
        ),
      ),
      isTrue,
    );
    expect(
      ScoutingRouteGenerator.distanceMeters(
        plan.preparation.entrance!,
        plan.targets.first.location,
      ),
      lessThan(
        ScoutingRouteGenerator.distanceMeters(
          plan.preparation.entrance!,
          plan.targets.last.location,
        ),
      ),
    );
  });

  test('ladder guidance uses confirmed passes and alternates side hints', () {
    final plan = ScoutingRouteGenerator.generate(
      draft: _draft(
        pattern: DatabaseCodes.patternLadder,
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          rowBearingDegrees: 0,
          accessiblePaths: [
            [LatLng(17.001, 121.005), LatLng(17.009, 121.005)],
          ],
          obstaclesReviewed: true,
        ),
      ),
      boundary: boundary,
    );

    expect(plan.targets, hasLength(5));
    expect(
      plan.targets.map((target) => target.sideHint),
      orderedEquals([
        'right_when_accessible',
        'left_when_accessible',
        'right_when_accessible',
        'left_when_accessible',
        'right_when_accessible',
      ]),
    );
    expect(
      plan.segments.every(
        (segment) =>
            segment.kind == 'evaluator_confirmed_accessible_path' &&
            segment.drawable,
      ),
      isTrue,
    );
  });

  test('ladder rejects a claimed pass that leaves the block', () {
    expect(
      () => ScoutingRouteGenerator.generate(
        draft: _draft(
          pattern: DatabaseCodes.patternLadder,
          preparation: const RoutePreparationData(
            entrance: LatLng(17.0002, 121.0002),
            rowBearingDegrees: 0,
            accessiblePaths: [
              [LatLng(17.001, 121.005), LatLng(17.02, 121.005)],
            ],
            obstaclesReviewed: true,
          ),
        ),
        boundary: boundary,
      ),
      throwsA(isA<RouteGenerationException>()),
    );
  });

  test('concave fields do not receive unsafe connecting lines', () {
    const concave = [
      LatLng(17.000, 121.000),
      LatLng(17.000, 121.010),
      LatLng(17.010, 121.010),
      LatLng(17.010, 121.006),
      LatLng(17.004, 121.006),
      LatLng(17.004, 121.004),
      LatLng(17.010, 121.004),
      LatLng(17.010, 121.000),
    ];
    final plan = ScoutingRouteGenerator.generate(
      draft: _draft(
        pattern: DatabaseCodes.patternW,
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
      ),
      boundary: concave,
    );

    expect(plan.targets, hasLength(5));
    expect(plan.segments.any((segment) => !segment.drawable), isTrue);
    expect(plan.warnings, isNotEmpty);
  });

  test('recalculation locks completed locations and preserves valid edits', () {
    final first = ScoutingRouteGenerator.generate(
      draft: _draft(
        pattern: DatabaseCodes.patternW,
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
      ),
      boundary: boundary,
    );
    final edited = first.copyWith(
      targets: [
        first.targets.first,
        first.targets[1].copyWith(
          location: const LatLng(17.004, 121.004),
          source: 'evaluator_adjusted',
          adjusted: true,
          adjustmentReason: 'Ditch beside generated target',
        ),
        ...first.targets.skip(2),
      ],
    );
    const recorded = LatLng(17.002, 121.002);
    final recalculated = ScoutingRouteGenerator.generate(
      draft: edited,
      boundary: boundary,
      completedStations: const {1: recorded},
    );

    expect(recalculated.targetFor(1).location, recorded);
    expect(recalculated.targetFor(1).lockedCompleted, isTrue);
    expect(recalculated.targetFor(2).location, const LatLng(17.004, 121.004));
    expect(recalculated.targetFor(2).adjusted, isTrue);
  });

  test('route document round trip preserves unfinished workflow state', () {
    final plan =
        _draft(
          pattern: DatabaseCodes.patternW,
          preparation: const RoutePreparationData(
            entrance: LatLng(17.0002, 121.0002),
            obstaclesReviewed: true,
            wCrossingConfirmed: true,
            draftGeometry: RouteDraftGeometry.obstacle,
            draftPoints: [LatLng(17.003, 121.003), LatLng(17.003, 121.004)],
          ),
        ).copyWith(
          pendingAdjustment: const PendingTargetAdjustment(
            stationNumber: 3,
            candidate: LatLng(17.006, 121.006),
            reason: 'Dense unsafe growth',
          ),
          arrivalConfirmedStation: 2,
        );

    final restored = ScoutingRoutePlan.fromGeoJson(plan.toGeoJson());
    expect(restored.preparation.draftGeometry, RouteDraftGeometry.obstacle);
    expect(restored.preparation.draftPoints, hasLength(2));
    expect(restored.pendingAdjustment?.stationNumber, 3);
    expect(restored.pendingAdjustment?.reason, 'Dense unsafe growth');
    expect(restored.arrivalConfirmedStation, 2);
  });
}

ScoutingRoutePlan _draft({
  required String pattern,
  required RoutePreparationData preparation,
}) => ScoutingRoutePlan(
  assessmentId: 'assessment-1',
  blockRunId: 'run-1',
  blockId: 'block-1',
  boundaryVersionId: 'boundary-1',
  pattern: pattern,
  status: ScoutingRouteStatus.draft,
  preparation: preparation,
  updatedAt: DateTime.utc(2026, 8, 14),
);
