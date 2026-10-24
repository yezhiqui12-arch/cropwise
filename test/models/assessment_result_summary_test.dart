import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/models/assessment_history_models.dart';

void main() {
  test('combines exact block numerators instead of averaging percentages', () {
    final result = buildAssessmentMetricRollups(
      expectedBlockIds: const {'b1', 'b2'},
      blockMetrics: [
        _metric('b1', numerator: 1, denominator: 10),
        _metric('b2', numerator: 9, denominator: 30),
      ],
    ).single;

    expect(result.isAggregatable, isTrue);
    expect(result.numerator, 10);
    expect(result.denominator, 40);
    expect(result.value, 25);
  });

  test('does not publish a partial rollup when a block metric is missing', () {
    final result = buildAssessmentMetricRollups(
      expectedBlockIds: const {'b1', 'b2'},
      blockMetrics: [_metric('b1', numerator: 1, denominator: 10)],
    ).single;

    expect(result.isAggregatable, isFalse);
    expect(result.value, isNull);
    expect(result.unavailableReason, contains('every assessment block'));
  });

  test('reconstructs a whole-assessment median from block distributions', () {
    final result = buildAssessmentMetricRollups(
      expectedBlockIds: const {'b1', 'b2'},
      blockMetrics: [
        _metric(
          'b1',
          code: 'da_bafs_median_score',
          unit: 'ordinal_score',
          numerator: 2,
          denominator: 2,
          distribution: {
            'counts': {'1': 2},
            'uncertain_count': 0,
          },
        ),
        _metric(
          'b2',
          code: 'da_bafs_median_score',
          unit: 'ordinal_score',
          numerator: 2,
          denominator: 2,
          distribution: {
            'counts': {'5': 2},
            'uncertain_count': 1,
          },
        ),
      ],
    ).single;

    expect(result.isAggregatable, isTrue);
    expect(result.value, 3);
    expect(result.scoreDistribution, {1: 2, 5: 2});
    expect(result.uncertainScoreCount, 1);
  });
}

MetricResultRecord _metric(
  String blockId, {
  String code = 'current_infestation_percent',
  String unit = 'percent',
  required double numerator,
  required double denominator,
  Map<String, Object>? distribution,
}) {
  final now = DateTime.utc(2026, 9, 9);
  return MetricResultRecord(
    id: '$blockId-$code',
    createdAt: now,
    updatedAt: now,
    syncState: 'queued',
    serverVersion: 0,
    assessmentId: 'assessment',
    scopeType: 'block',
    scopeId: blockId,
    metricCode: code,
    numerator: numerator,
    denominator: denominator,
    value: denominator == 0 ? null : numerator / denominator * 100,
    unit: unit,
    distributionJson: distribution == null ? null : jsonEncode(distribution),
    formulaVersion: 'v1',
    validationStatus: 'provisional',
    calculatedAt: now,
  );
}
