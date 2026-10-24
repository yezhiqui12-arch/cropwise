import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/scouting_route_generator.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';

void main() {
  const square = [
    LatLng(17, 121),
    LatLng(17, 121.00094),
    LatLng(17.0009, 121.00094),
    LatLng(17.0009, 121),
  ];
  ScoutingRoutePlan draft() => ScoutingRoutePlan(
    assessmentId: 'a',
    blockRunId: 'r',
    blockId: 'b',
    boundaryVersionId: 'v',
    pattern: ScoutingSamplingProtocol.daPattern,
    status: ScoutingRouteStatus.draft,
    preparation: const RoutePreparationData(),
    updatedAt: DateTime.utc(2026),
  );
  test(
    '20 unique targets stay 3 m inside an approximately one hectare field',
    () {
      final plan = ScoutingRouteGenerator.generate(
        draft: draft(),
        boundary: square,
      );
      expect(plan.isReady, isTrue);
      expect(
        plan.targets.map((p) => p.stationNumber),
        orderedEquals(List.generate(20, (i) => i + 1)),
      );
      for (final target in plan.targets) {
        // Independently measure all four edges of this axis-aligned rectangle.
        final northSouth = ScoutingRouteGenerator.distanceMeters(
          square.first,
          LatLng(target.location.latitude, square.first.longitude),
        );
        final totalHeight = ScoutingRouteGenerator.distanceMeters(
          square.first,
          square.last,
        );
        final westEast = ScoutingRouteGenerator.distanceMeters(
          square.first,
          LatLng(square.first.latitude, target.location.longitude),
        );
        final totalWidth = ScoutingRouteGenerator.distanceMeters(
          square.first,
          square[1],
        );
        expect(northSouth, greaterThanOrEqualTo(3));
        expect(totalHeight - northSouth, greaterThanOrEqualTo(3));
        expect(westEast, greaterThanOrEqualTo(3));
        expect(totalWidth - westEast, greaterThanOrEqualTo(3));
        expect(
          ScoutingRouteGenerator.validDaTarget(target.location, square, []),
          isTrue,
        );
        for (final other in plan.targets.where(
          (t) => t.stationNumber != target.stationNumber,
        )) {
          expect(
            ScoutingRouteGenerator.distanceMeters(
              target.location,
              other.location,
            ),
            greaterThanOrEqualTo(2),
          );
        }
      }
      expect(plan.segments, isEmpty); // Suggested pins do not claim safe paths.
      expect(
        ScoutingRoutePlan.fromGeoJson(plan.toGeoJson()).targets,
        hasLength(20),
      );
    },
  );
  test(
    'walking order removes cross-field jumps without moving sampling points',
    () {
      final scattered = ScoutingRouteGenerator.generate(
        draft: draft(),
        boundary: square,
      );
      final byLongitude = [...scattered.targets]
        ..sort((a, b) => a.location.longitude.compareTo(b.location.longitude));
      final zigzag = <ScoutingStationTarget>[];
      while (byLongitude.isNotEmpty) {
        zigzag.add(byLongitude.removeAt(0));
        if (byLongitude.isNotEmpty) zigzag.add(byLongitude.removeLast());
      }
      final old = scattered.copyWith(
        algorithmVersion: 'da_manual_scattered_points_v1',
        targets: [
          for (var i = 0; i < zigzag.length; i++)
            zigzag[i].copyWith(stationNumber: i + 1),
        ],
      );
      double length(ScoutingRoutePlan plan) {
        var sum = 0.0;
        for (var i = 1; i < plan.targets.length; i++) {
          sum += ScoutingRouteGenerator.distanceMeters(
            plan.targets[i - 1].location,
            plan.targets[i].location,
          );
        }
        return sum;
      }

      final ordered = ScoutingRouteGenerator.orderDaTargetsForWalk(old);
      expect(length(ordered), lessThan(length(old) * .7));
      expect(
        ordered.targets.map((t) => t.location),
        unorderedEquals(old.targets.map((t) => t.location)),
      );
      expect(ordered.targetFor(1).location, old.targetFor(1).location);
      final partial = ScoutingRouteGenerator.orderDaTargetsForWalk(
        old.copyWith(arrivalConfirmedStation: 11),
        fixedThrough: 10,
      );
      for (var number = 1; number <= 11; number++) {
        expect(
          partial.targetFor(number).location,
          old.targetFor(number).location,
        );
      }
      expect(length(partial), lessThanOrEqualTo(length(old)));
      expect(
        partial.targets.map((t) => t.location),
        unorderedEquals(old.targets.map((t) => t.location)),
      );
      expect(partial.algorithmVersion, ScoutingSamplingProtocol.daAlgorithm);
      expect(
        ScoutingRouteGenerator.orderDaTargetsForWalk(
          partial,
          fixedThrough: 11,
        ).targets.map((t) => t.location),
        orderedEquals(partial.targets.map((t) => t.location)),
      );
    },
  );
  test('concave field and marked obstacle are respected', () {
    const concave = [
      LatLng(17, 121),
      LatLng(17, 121.001),
      LatLng(17.001, 121.001),
      LatLng(17.001, 121.0006),
      LatLng(17.0004, 121.0006),
      LatLng(17.0004, 121),
    ];
    const obstacle = [
      LatLng(17.0001, 121.00075),
      LatLng(17.0001, 121.0009),
      LatLng(17.0003, 121.0009),
      LatLng(17.0003, 121.00075),
    ];
    final plan = ScoutingRouteGenerator.generate(
      draft: draft().copyWith(
        preparation: const RoutePreparationData(obstacles: [obstacle]),
      ),
      boundary: concave,
    );
    expect(
      plan.targets.every(
        (p) => ScoutingRouteGenerator.validDaTarget(p.location, concave, [
          obstacle,
        ]),
      ),
      isTrue,
    );
  });
  test(
    'completed suggested location survives regeneration independently of measured GPS',
    () {
      final first = ScoutingRouteGenerator.generate(
        draft: draft(),
        boundary: square,
      );
      final second = ScoutingRouteGenerator.generate(
        draft: first,
        boundary: square,
        completedStations: {1: const LatLng(17.0001, 121.0001)},
      );
      expect(second.targetFor(1).location, first.targetFor(1).location);
      expect(second.targetFor(1).lockedCompleted, isTrue);
    },
  );
  test(
    'unusable narrow outline fails rather than placing pins outside the margin',
    () {
      const narrow = [
        LatLng(17, 121),
        LatLng(17, 121.00001),
        LatLng(17.001, 121.00001),
        LatLng(17.001, 121),
      ];
      expect(
        () => ScoutingRouteGenerator.generate(draft: draft(), boundary: narrow),
        throwsA(isA<RouteGenerationException>()),
      );
    },
  );
}
