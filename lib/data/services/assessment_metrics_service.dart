import '../../models/automatic_screening.dart';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';

class AssessmentMetricsService {
  const AssessmentMetricsService(this.database);

  final AppDatabase database;

  Future<List<MetricResultRecord>> recalculateBlock(String blockRunId) async {
    final blockRun = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(blockRunId))).getSingle();
    final assessment = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(blockRun.assessmentId))).getSingle();
    final stations =
        await (database.select(database.stations)..where(
              (row) =>
                  row.assessmentBlockRunId.equals(blockRunId) &
                  row.deletedAt.isNull(),
            ))
            .get();
    final stationIds = stations.map((station) => station.id).toList();
    if (stationIds.isEmpty) return const [];

    final plants =
        await (database.select(database.plantObservations)..where(
              (row) => row.stationId.isIn(stationIds) & row.deletedAt.isNull(),
            ))
            .get();
    final assessable = plants
        .where(
          (plant) =>
              plant.assessable &&
              AutomaticScreening.parse(plant.wholePlantContextNote) == null,
        )
        .toList();
    final assessableIds = assessable.map((plant) => plant.id).toList();
    final metrics = <_MetricValue>[];

    final screens = plants
        .map((plant) => AutomaticScreening.parse(plant.wholePlantContextNote))
        .whereType<AutomaticScreening>()
        .toList();
    if (screens.isNotEmpty) {
      metrics.add(
        _MetricValue(
          AutomaticScreening.metric,
          screens.where((screen) => screen.available && screen.positive).length,
          screens.where((screen) => screen.available).length,
        ),
      );
    }
    if (assessable.isNotEmpty || screens.isEmpty)
      switch (assessment.assessmentMode) {
        case DatabaseCodes.modeVeV6:
        case DatabaseCodes.modeV7V12:
          final vegetative = assessableIds.isEmpty
              ? <VegetativeObservationRecord>[]
              : await (database.select(database.vegetativeObservations)..where(
                      (row) => row.plantObservationId.isIn(assessableIds),
                    ))
                    .get();
          metrics.addAll([
            _MetricValue(
              DatabaseCodes.vegetativeCurrentInfestationPercent,
              assessable
                  .where(
                    (plant) =>
                        plant.plantStatus == DatabaseCodes.plantCurrentPositive,
                  )
                  .length,
              assessable.length,
            ),
            _MetricValue(
              DatabaseCodes.smallFreshWindowpanePercent,
              vegetative.where((item) => item.smallFreshWindowpanes).length,
              assessable.length,
            ),
            _MetricValue(
              DatabaseCodes.infestedWhorlPercent,
              vegetative.where((item) => item.infestedWhorl).length,
              assessable.length,
            ),
          ]);
          if (assessment.assessmentMode == DatabaseCodes.modeV7V12) {
            final scored = vegetative
                .where((item) => item.daBafsLeafDamageScore != null)
                .toList();
            final scores =
                scored.map((item) => item.daBafsLeafDamageScore!).toList()
                  ..sort();
            if (scores.isNotEmpty) {
              final distribution = <String, int>{};
              for (final score in scores) {
                distribution['$score'] = (distribution['$score'] ?? 0) + 1;
              }
              metrics.add(
                _MetricValue(
                  DatabaseCodes.daBafsMedianScore,
                  scores.length,
                  scores.length,
                  unit: 'ordinal_score',
                  explicitValue: _median(scores),
                  distributionJson: jsonEncode({
                    'counts': distribution,
                    'minimum': scores.first,
                    'maximum': scores.last,
                    'uncertain_count': scored
                        .where((item) => item.damageScoreUncertain)
                        .length,
                  }),
                ),
              );
            }
          }
        case DatabaseCodes.modeVtR2:
          final reproductive = assessableIds.isEmpty
              ? <ReproductiveObservationRecord>[]
              : await (database.select(database.reproductiveObservations)
                      ..where(
                        (row) => row.plantObservationId.isIn(assessableIds),
                      ))
                    .get();
          metrics.add(
            _MetricValue(
              DatabaseCodes.vtR2InfestedPlantPercent,
              reproductive.where((item) => item.percentInfestedPositive).length,
              assessable.length,
            ),
          );
        case DatabaseCodes.modeR3R6:
          final ears = assessableIds.isEmpty
              ? <EarObservationRecord>[]
              : await (database.select(database.earObservations)..where(
                      (row) =>
                          row.plantObservationId.isIn(assessableIds) &
                          row.deletedAt.isNull(),
                    ))
                    .get();
          final externallyAssessable = ears
              .where((ear) => ear.externallyAssessable)
              .toList();
          metrics.addAll([
            _MetricValue(
              DatabaseCodes.externalEarDamagePercent,
              externallyAssessable
                  .where((ear) => ear.externalDamagePresent == true)
                  .length,
              externallyAssessable.length,
            ),
            _MetricValue(
              DatabaseCodes.activeEarInfestationPercent,
              externallyAssessable
                  .where((ear) => ear.activeInfestationPresent == true)
                  .length,
              externallyAssessable.length,
            ),
          ]);
          final opened = ears.where((ear) => ear.opened).toList();
          final countable = opened
              .where(
                (ear) =>
                    ear.totalKernelsCounted != null &&
                    ear.totalKernelsCounted! > 0 &&
                    ear.damagedKernelsCounted != null,
              )
              .toList();
          final totalKernels = countable.fold<int>(
            0,
            (sum, ear) => sum + ear.totalKernelsCounted!,
          );
          final damagedKernels = countable.fold<int>(
            0,
            (sum, ear) => sum + ear.damagedKernelsCounted!,
          );
          metrics.addAll([
            _MetricValue(
              DatabaseCodes.openedEarInternalDamagePercent,
              opened.where((ear) => ear.internalDamagePresent == true).length,
              opened.length,
            ),
            _MetricValue(
              DatabaseCodes.pooledDamagedKernelPercent,
              damagedKernels,
              totalKernels,
              distributionJson: jsonEncode([
                for (final ear in countable)
                  {
                    'ear_id': ear.id,
                    'damaged': ear.damagedKernelsCounted,
                    'total': ear.totalKernelsCounted,
                  },
              ]),
            ),
            _MetricValue(
              DatabaseCodes.meanDamagedKernelsPerOpenedEar,
              damagedKernels,
              countable.length,
              unit: 'kernels_per_ear',
              explicitValue: countable.isEmpty
                  ? null
                  : damagedKernels / countable.length,
            ),
            _MetricValue(
              DatabaseCodes.earRotIncidencePercent,
              opened.where((ear) => ear.earRotPresent == true).length,
              opened.length,
            ),
          ]);
      }

    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      await (database.delete(database.metricResults)..where(
            (row) =>
                row.assessmentId.equals(assessment.id) &
                row.scopeType.equals('block') &
                row.scopeId.equals(blockRunId) &
                row.formulaVersion.equals(assessment.formulaVersion),
          ))
          .go();
      for (final metric in metrics) {
        await database
            .into(database.metricResults)
            .insert(
              MetricResultsCompanion.insert(
                id: LocalId.generate(),
                assessmentId: assessment.id,
                scopeType: 'block',
                scopeId: Value(blockRunId),
                metricCode: metric.code,
                numerator: Value(metric.numerator.toDouble()),
                denominator: Value(metric.denominator.toDouble()),
                value: Value(metric.value),
                unit: metric.unit,
                distributionJson: Value(metric.distributionJson),
                formulaVersion: assessment.formulaVersion,
                calculatedAt: now,
                warningCode: Value(
                  metric.denominator == 0 ? 'zero_denominator' : null,
                ),
                syncState: const Value(DatabaseCodes.queued),
              ),
            );
      }
    });

    return (database.select(database.metricResults)..where(
          (row) =>
              row.assessmentId.equals(assessment.id) &
              row.scopeType.equals('block') &
              row.scopeId.equals(blockRunId),
        ))
        .get();
  }
}

class _MetricValue {
  const _MetricValue(
    this.code,
    this.numerator,
    this.denominator, {
    this.unit = 'percent',
    this.explicitValue,
    this.distributionJson,
  });

  final String code;
  final int numerator;
  final int denominator;
  final String unit;
  final double? explicitValue;
  final String? distributionJson;

  double? get value =>
      explicitValue ??
      (denominator == 0
          ? null
          : unit == 'percent'
          ? (numerator / denominator) * 100
          : numerator / denominator);
}

double _median(List<int> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
