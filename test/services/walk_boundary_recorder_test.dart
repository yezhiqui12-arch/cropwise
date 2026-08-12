import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/walk_boundary_recorder.dart';

void main() {
  final startTime = DateTime.utc(2026, 8, 12, 8);

  WalkBoundarySample sample(
    double latitude,
    double longitude,
    int seconds, {
    double accuracy = 5,
  }) {
    return WalkBoundarySample(
      position: LatLng(latitude, longitude),
      accuracyMeters: accuracy,
      capturedAt: startTime.add(Duration(seconds: seconds)),
    );
  }

  test(
    'keeps spaced accurate samples and rejects weak or crowded readings',
    () {
      final recorder = WalkBoundaryRecorder();

      expect(
        recorder.addSample(sample(17.7900, 121.4780, 0)),
        WalkSampleDecision.accepted,
      );
      expect(
        recorder.addSample(sample(17.7901, 121.4780, 2, accuracy: 30)),
        WalkSampleDecision.poorAccuracy,
      );
      expect(
        recorder.addSample(sample(17.79001, 121.4780, 3)),
        WalkSampleDecision.tooClose,
      );
      expect(
        recorder.addSample(sample(17.79006, 121.4780, 6)),
        WalkSampleDecision.accepted,
      );

      expect(recorder.points, hasLength(2));
      expect(recorder.rejectedAccuracyCount, 1);
      expect(recorder.rejectedMovementCount, 1);
    },
  );

  test('rejects an implausible phone GPS jump while walking', () {
    final recorder = WalkBoundaryRecorder();
    recorder.addSample(sample(17.7900, 121.4780, 0));

    final decision = recorder.addSample(sample(17.7910, 121.4780, 1));

    expect(decision, WalkSampleDecision.implausibleJump);
    expect(recorder.points, hasLength(1));
  });

  test('marked corners survive route simplification', () {
    final recorder = WalkBoundaryRecorder(
      minimumPointDistanceMeters: 1,
      maximumWalkingSpeedMetersPerSecond: 100,
    );
    recorder.addSample(sample(17.79000, 121.47800, 0));
    recorder.addSample(sample(17.79000, 121.47805, 2));
    recorder.addSample(sample(17.79005, 121.47810, 4), markedCorner: true);
    recorder.addSample(sample(17.79000, 121.47815, 6));
    recorder.addSample(sample(17.79000, 121.47820, 8));

    final simplified = recorder.simplified(toleranceMeters: 10);

    expect(simplified.first.position, recorder.points.first.position);
    expect(simplified.last.position, recorder.points.last.position);
    expect(simplified.where((point) => point.isMarkedCorner), hasLength(1));
  });

  test(
    'a nearby corner replaces the last route point instead of duplicating it',
    () {
      final recorder = WalkBoundaryRecorder();
      recorder.addSample(sample(17.7900, 121.4780, 0));
      recorder.addSample(sample(17.79006, 121.4780, 6));

      final decision = recorder.addSample(
        sample(17.790061, 121.4780, 8),
        markedCorner: true,
      );

      expect(decision, WalkSampleDecision.replacedWithCorner);
      expect(recorder.points, hasLength(2));
      expect(recorder.points.last.isMarkedCorner, isTrue);
    },
  );
}
