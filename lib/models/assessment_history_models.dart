import 'automatic_screening.dart';
import 'dart:convert';

import '../data/services/assessment_validation_types.dart';
import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';

String assessmentStatusLabel(String status) => switch (status) {
  'draft' => 'Setup incomplete',
  'in_progress' => 'In progress',
  'safety_blocked' => 'Safety review needed',
  'completed' => 'Recorded as completed',
  'incomplete' => 'Incomplete',
  'cancelled' => 'Cancelled',
  'invalid' => 'Marked invalid',
  _ => 'Unknown status',
};

String? assessmentResumeLabel(String status) => switch (status) {
  'draft' => 'Continue setup',
  'safety_blocked' => 'Review safety',
  'in_progress' => 'Continue scouting',
  _ => null,
};

class AssessmentHistoryEntry {
  const AssessmentHistoryEntry({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.status,
    required this.growthStage,
    required this.pattern,
    required this.createdAt,
    required this.startedAt,
    required this.blocks,
    required this.stations,
    required this.plants,
    required this.positions,
    required this.photos,
    this.evidenceThumbnailUri,
  });
  final String id, fieldId, fieldName, status, growthStage, pattern;
  final DateTime createdAt;
  final DateTime? startedAt;
  final int blocks, stations, plants, positions, photos;
  final String? evidenceThumbnailUri;
  bool get isSeedling => const {'ve', 'v1', 'v2'}.contains(growthStage);
  DateTime get date => startedAt ?? createdAt;
}

class AssessmentEvidenceEntry {
  const AssessmentEvidenceEntry(
    this.media,
    this.scope, {
    this.stationId,
    this.plantObservationId,
    this.plantPosition,
    this.scopeType,
  });
  final EvidenceMediaRecord media;
  final String scope;
  final String? stationId;
  final String? plantObservationId;
  final int? plantPosition;
  final String? scopeType;
}

class AssessmentHistoryDetail {
  const AssessmentHistoryDetail({
    required this.assessment,
    required this.workspace,
    required this.evaluator,
    required this.stations,
    required this.units,
    required this.evidence,
    required this.safety,
    required this.missingBlocks,
    required this.readiness,
    required this.resultSummary,
    this.metrics = const [],
    this.modelScreenings = const {},
    this.daMonitoringData = const {},
  });
  final Map<String, dynamic> daMonitoringData;
  final Map<String, AutomaticScreening?> modelScreenings;
  AutomaticScreening? screeningFor(StationPlantRecord record) {
    final key = '${record.plant.stationId}:${record.plant.sequenceNumber}';
    return modelScreenings.containsKey(key)
        ? modelScreenings[key]
        : AutomaticScreening.parse(record.plant.wholePlantContextNote);
  }

  final AssessmentRecord assessment;
  final FieldWorkspaceRecord workspace;
  final String evaluator;
  final List<StationSnapshot> stations;
  final List<PlantingUnitObservationRecord> units;
  final List<AssessmentEvidenceEntry> evidence;
  final SafetyCheckRecord? safety;
  final int missingBlocks;
  final BlockValidationResult readiness;
  final AssessmentResultSummary resultSummary;
  final List<MetricResultRecord> metrics;
  bool get canResume =>
      assessmentResumeLabel(assessment.status) != null &&
      !workspace.field.isArchived &&
      workspace.hasApproximateOutline;

  int get expectedStationCount => stations.length;
  int get recordedStationCount =>
      stations.where((station) => station.station != null).length;
  int get currentReviewedStationCount =>
      stations.where((station) => station.reviewIsCurrent).length;
  double get reviewedProgress => expectedStationCount == 0
      ? 0
      : currentReviewedStationCount / expectedStationCount;

  /// Counts actionable destinations, rather than every low-level validation
  /// failure. Several plant/evidence checks can belong to one station review.
  int get requiredWorkAreaCount => readiness.issues
      .map(
        (issue) =>
            '${issue.blockRunId ?? 'assessment'}:${issue.stationNumber ?? 0}',
      )
      .toSet()
      .length;
}

/// Read-only projection used by the whole-assessment results experience.
/// It never writes metrics and never invents values for missing blocks.
class AssessmentResultSummary {
  const AssessmentResultSummary({
    required this.growthStage,
    required this.formulaVersion,
    required this.blockCount,
    required this.expectedStationCount,
    required this.recordedStationCount,
    required this.currentReviewedStationCount,
    required this.recordedObservationCount,
    required this.assessableObservationCount,
    required this.notAssessableObservationCount,
    required this.stationsWithCoordinates,
    required this.outstandingIssueCount,
    required this.isReady,
    required this.metrics,
    required this.stations,
  });

  final String growthStage;
  final String formulaVersion;
  final int blockCount;
  final int expectedStationCount;
  final int recordedStationCount;
  final int currentReviewedStationCount;
  final int recordedObservationCount;
  final int assessableObservationCount;
  final int notAssessableObservationCount;
  final int stationsWithCoordinates;
  final int outstandingIssueCount;
  final bool isReady;
  final List<AssessmentMetricRollup> metrics;
  final List<StationResultSummary> stations;

  factory AssessmentResultSummary.fromRecords({
    required String growthStage,
    required String formulaVersion,
    required List<StationSnapshot> stations,
    required List<MetricResultRecord> blockMetrics,
    required BlockValidationResult readiness,
  }) {
    final blockIds = stations.map((station) => station.prepared.run.id).toSet();
    final stationResults = [
      for (final station in stations)
        StationResultSummary.fromSnapshot(
          growthStage: growthStage,
          snapshot: station,
          hasOutstandingWork: readiness.issues.any(
            (issue) =>
                issue.blockRunId == station.prepared.run.id &&
                issue.stationNumber == station.stationNumber,
          ),
        ),
    ];
    return AssessmentResultSummary(
      growthStage: growthStage,
      formulaVersion: formulaVersion,
      blockCount: blockIds.length,
      expectedStationCount: stations.length,
      recordedStationCount: stationResults
          .where((station) => station.stationId != null)
          .length,
      currentReviewedStationCount: stationResults
          .where((station) => station.reviewIsCurrent)
          .length,
      recordedObservationCount: stationResults.fold(
        0,
        (sum, station) => sum + station.recordedObservationCount,
      ),
      assessableObservationCount: stationResults.fold(
        0,
        (sum, station) => sum + station.assessableObservationCount,
      ),
      notAssessableObservationCount: stationResults.fold(
        0,
        (sum, station) => sum + station.notAssessableObservationCount,
      ),
      stationsWithCoordinates: stationResults
          .where((station) => station.hasCoordinates)
          .length,
      outstandingIssueCount: readiness.issues.length,
      isReady: readiness.isValid,
      metrics: buildAssessmentMetricRollups(
        expectedBlockIds: blockIds,
        blockMetrics: blockMetrics,
      ),
      stations: List.unmodifiable(stationResults),
    );
  }
}

class StationResultSummary {
  const StationResultSummary({
    required this.blockRunId,
    required this.blockSequence,
    required this.stationNumber,
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.gpsAccuracyM,
    required this.recordedObservationCount,
    required this.assessableObservationCount,
    required this.currentSignsCount,
    required this.notAssessableObservationCount,
    required this.reviewIsCurrent,
    required this.hasOutstandingWork,
  });

  final String blockRunId;
  final int blockSequence;
  final int stationNumber;
  final String? stationId;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracyM;
  final int recordedObservationCount;
  final int assessableObservationCount;
  final int currentSignsCount;
  final int notAssessableObservationCount;
  final bool reviewIsCurrent;
  final bool hasOutstandingWork;

  bool get hasCoordinates => latitude != null && longitude != null;
  double? get observedIncidencePercent => assessableObservationCount == 0
      ? null
      : currentSignsCount / assessableObservationCount * 100;
  String get label => 'B$blockSequence-S$stationNumber';

  factory StationResultSummary.fromSnapshot({
    required String growthStage,
    required StationSnapshot snapshot,
    required bool hasOutstandingWork,
  }) {
    final stage = growthStage;
    final screeningMode = snapshot.plants.any(
      (p) => AutomaticScreening.parse(p.plant.wholePlantContextNote) != null,
    );
    final assessed = snapshot.plants.where((plant) {
      if (screeningMode)
        return AutomaticScreening.parse(
              plant.plant.wholePlantContextNote,
            )?.available ==
            true;
      if (stage == 'r3_r6') {
        return plant.ear?.externallyAssessable == true;
      }
      return plant.plant.assessable;
    }).toList();
    final currentSigns = assessed.where((plant) {
      if (screeningMode)
        return AutomaticScreening.parse(
              plant.plant.wholePlantContextNote,
            )?.positive ==
            true;
      if (stage == 'vt_r2') {
        return plant.reproductive?.percentInfestedPositive == true;
      }
      if (stage == 'r3_r6') {
        return plant.ear?.activeInfestationPresent == true;
      }
      return plant.plant.plantStatus == DatabaseCodes.plantCurrentPositive;
    }).length;
    final station = snapshot.station;
    return StationResultSummary(
      blockRunId: snapshot.prepared.run.id,
      blockSequence: snapshot.prepared.run.blockSequence,
      stationNumber: snapshot.stationNumber,
      stationId: station?.id,
      latitude: station?.latitude,
      longitude: station?.longitude,
      gpsAccuracyM: station?.gpsAccuracyM,
      recordedObservationCount: snapshot.plants.length,
      assessableObservationCount: assessed.length,
      currentSignsCount: currentSigns,
      notAssessableObservationCount: snapshot.plants.length - assessed.length,
      reviewIsCurrent: snapshot.reviewIsCurrent,
      hasOutstandingWork: hasOutstandingWork,
    );
  }
}

class AssessmentMetricRollup {
  const AssessmentMetricRollup({
    required this.metricCode,
    required this.unit,
    required this.numerator,
    required this.denominator,
    required this.value,
    required this.includedBlockCount,
    required this.expectedBlockCount,
    required this.isAggregatable,
    required this.unavailableReason,
    required this.warningCodes,
    required this.calculatedAt,
    this.scoreDistribution = const {},
    this.uncertainScoreCount = 0,
  });

  final String metricCode;
  final String unit;
  final double? numerator;
  final double? denominator;
  final double? value;
  final int includedBlockCount;
  final int expectedBlockCount;
  final bool isAggregatable;
  final String? unavailableReason;
  final Set<String> warningCodes;
  final DateTime? calculatedAt;
  final Map<int, int> scoreDistribution;
  final int uncertainScoreCount;

  bool get isAvailable => isAggregatable && value != null;
}

List<AssessmentMetricRollup> buildAssessmentMetricRollups({
  required Set<String> expectedBlockIds,
  required List<MetricResultRecord> blockMetrics,
}) {
  final grouped = <String, List<MetricResultRecord>>{};
  for (final metric in blockMetrics) {
    grouped.putIfAbsent(metric.metricCode, () => []).add(metric);
  }
  final codes = grouped.keys.toList()..sort();
  return List.unmodifiable([
    for (final code in codes)
      _rollupMetric(
        code: code,
        rows: grouped[code]!,
        expectedBlockIds: expectedBlockIds,
      ),
  ]);
}

AssessmentMetricRollup _rollupMetric({
  required String code,
  required List<MetricResultRecord> rows,
  required Set<String> expectedBlockIds,
}) {
  final includedIds = rows
      .map((row) => row.scopeId)
      .whereType<String>()
      .toSet();
  final units = rows.map((row) => row.unit).toSet();
  final warnings = rows
      .map((row) => row.warningCode)
      .whereType<String>()
      .toSet();
  final calculatedAt = rows.isEmpty
      ? null
      : rows
            .map((row) => row.calculatedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
  String? reason;
  if (expectedBlockIds.isEmpty) {
    reason = 'No assessment blocks are available.';
  } else if (includedIds.length != expectedBlockIds.length ||
      !includedIds.containsAll(expectedBlockIds) ||
      rows.length != includedIds.length) {
    reason = 'This metric is not saved once for every assessment block.';
  } else if (units.length != 1) {
    reason = 'Block metric units are incompatible.';
  } else if (rows.any(
    (row) =>
        row.numerator == null ||
        row.denominator == null ||
        !row.numerator!.isFinite ||
        !row.denominator!.isFinite ||
        row.denominator! < 0,
  )) {
    reason = 'A block is missing a valid numerator or denominator.';
  }

  final unit = units.length == 1 ? units.single : 'unknown';
  final numerator = reason == null
      ? rows.fold<double>(0, (sum, row) => sum + row.numerator!)
      : null;
  final denominator = reason == null
      ? rows.fold<double>(0, (sum, row) => sum + row.denominator!)
      : null;
  final scoreDistribution = <int, int>{};
  var uncertainScoreCount = 0;
  double? value;

  if (reason == null && denominator == 0) {
    reason = 'The combined denominator is zero.';
  } else if (reason == null && unit == 'ordinal_score') {
    for (final row in rows) {
      final distribution = _decodeScoreDistribution(row.distributionJson);
      if (distribution == null) {
        reason = 'A block is missing its score distribution.';
        break;
      }
      for (final entry in distribution.counts.entries) {
        scoreDistribution[entry.key] =
            (scoreDistribution[entry.key] ?? 0) + entry.value;
      }
      uncertainScoreCount += distribution.uncertainCount;
    }
    if (reason == null) value = _medianFromCounts(scoreDistribution);
  } else if (reason == null) {
    value = unit == 'percent'
        ? numerator! / denominator! * 100
        : numerator! / denominator!;
  }

  return AssessmentMetricRollup(
    metricCode: code,
    unit: unit,
    numerator: numerator,
    denominator: denominator,
    value: value,
    includedBlockCount: includedIds.length,
    expectedBlockCount: expectedBlockIds.length,
    isAggregatable: reason == null,
    unavailableReason: reason,
    warningCodes: Set.unmodifiable(warnings),
    calculatedAt: calculatedAt,
    scoreDistribution: Map.unmodifiable(scoreDistribution),
    uncertainScoreCount: uncertainScoreCount,
  );
}

class _ScoreDistribution {
  const _ScoreDistribution(this.counts, this.uncertainCount);
  final Map<int, int> counts;
  final int uncertainCount;
}

_ScoreDistribution? _decodeScoreDistribution(String? encoded) {
  if (encoded == null) return null;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['counts'] is! Map) return null;
    final counts = <int, int>{};
    for (final entry in (decoded['counts'] as Map).entries) {
      final score = int.tryParse('${entry.key}');
      final count = entry.value is num ? (entry.value as num).toInt() : null;
      if (score == null || count == null || count < 0) return null;
      counts[score] = count;
    }
    final uncertain = decoded['uncertain_count'];
    return _ScoreDistribution(counts, uncertain is num ? uncertain.toInt() : 0);
  } catch (_) {
    return null;
  }
}

double? _medianFromCounts(Map<int, int> counts) {
  final total = counts.values.fold<int>(0, (sum, count) => sum + count);
  if (total == 0) return null;
  final sorted = counts.keys.toList()..sort();
  int valueAt(int target) {
    var seen = 0;
    for (final score in sorted) {
      seen += counts[score]!;
      if (seen > target) return score;
    }
    return sorted.last;
  }

  final upper = valueAt(total ~/ 2);
  if (total.isOdd) return upper.toDouble();
  final lower = valueAt(total ~/ 2 - 1);
  return (lower + upper) / 2;
}
