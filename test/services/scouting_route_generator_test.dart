import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/assessment_protocol_selector.dart';
import 'package:wormwise/services/scouting_route_generator.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';

void main() {
  const boundary = [
    LatLng(17, 121),
    LatLng(17, 121.001),
    LatLng(17.001, 121.001),
    LatLng(17.001, 121),
  ];
  for (final pattern in ['w', 'ladder']) {
    test('$pattern cannot generate or reuse a ready retired route', () {
      final plan = ScoutingRoutePlan(
        assessmentId: 'old',
        blockRunId: 'block',
        blockId: 'field-block',
        boundaryVersionId: 'boundary',
        pattern: pattern,
        status: ScoutingRouteStatus.ready,
        preparation: const RoutePreparationData(),
        targets: [
          for (var i = 1; i <= 5; i++)
            ScoutingStationTarget(stationNumber: i, location: boundary.first),
        ],
        updatedAt: DateTime.utc(2026),
      );
      expect(plan.isReady, isFalse);
      expect(
        () => ScoutingRouteGenerator.generate(draft: plan, boundary: boundary),
        throwsA(isA<RouteGenerationException>()),
      );
      final decoded = ScoutingRoutePlan.fromGeoJson(plan.toGeoJson());
      expect(decoded.pattern, pattern);
      expect(decoded.isReady, isFalse);
    });
  }
  test('every supported growth stage recommends the current DA pattern', () {
    for (final stage in AssessmentProtocolSelector.growthStages) {
      expect(
        AssessmentProtocolSelector.recommendedPatternFor(stage.code),
        ScoutingSamplingProtocol.daPattern,
      );
    }
  });
}
