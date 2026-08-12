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
    final assessable = plants.where((plant) => plant.assessable).toList();
    final assessableIds = assessable.map((plant) => plant.id).toList();
    final metrics = <_MetricValue>[];

    switch (assessment.assessmentMode) {
      case DatabaseCodes.modeVeV6:
      case DatabaseCodes.modeV7V12:
        final vegetative = assessableIds.isEmpty
            ? <VegetativeObservationRecord>[]
            : await (database.select(
                    database.vegetativeObservations,
                  )..where((row) => row.plantObservationId.isIn(assessableIds)))
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
      case DatabaseCodes.modeVtR2:
        final reproductive = assessableIds.isEmpty
            ? <ReproductiveObservationRecord>[]
            : await (database.select(
                    database.reproductiveObservations,
                  )..where((row) => row.plantObservationId.isIn(assessableIds)))
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
                value: Value(metric.percent),
                unit: 'percent',
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
  const _MetricValue(this.code, this.numerator, this.denominator);

  final String code;
  final int numerator;
  final int denominator;

  double? get percent =>
      denominator == 0 ? null : (numerator / denominator) * 100;
}
