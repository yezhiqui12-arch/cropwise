import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';

class ValidationIssue {
  const ValidationIssue(this.code, this.message, {this.stationId});

  final String code;
  final String message;
  final String? stationId;
}

class BlockValidationResult {
  const BlockValidationResult(this.issues);

  final List<ValidationIssue> issues;
  bool get isValid => issues.isEmpty;
}

class AssessmentValidationException implements Exception {
  const AssessmentValidationException(this.issues);

  final List<ValidationIssue> issues;

  @override
  String toString() => issues.map((issue) => issue.message).join('; ');
}

class AssessmentCompletionValidator {
  const AssessmentCompletionValidator(this.database);

  final AppDatabase database;

  Future<BlockValidationResult> validateBlock(String blockRunId) async {
    final blockRun = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(blockRunId))).getSingle();
    final assessment = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(blockRun.assessmentId))).getSingle();
    final stations =
        await (database.select(database.stations)
              ..where(
                (row) =>
                    row.assessmentBlockRunId.equals(blockRunId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.stationNumber)]))
            .get();

    final issues = <ValidationIssue>[];
    if (stations.length != 5) {
      issues.add(
        ValidationIssue(
          'station_count',
          'A completed formal block requires exactly 5 stations; found ${stations.length}.',
        ),
      );
    }

    for (final station in stations) {
      final plants =
          await (database.select(database.plantObservations)
                ..where(
                  (row) =>
                      row.stationId.equals(station.id) & row.deletedAt.isNull(),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)]))
              .get();
      if (plants.length != 10) {
        issues.add(
          ValidationIssue(
            'plant_count',
            'Station ${station.stationNumber} requires 10 explicit plant positions; found ${plants.length}.',
            stationId: station.id,
          ),
        );
      }

      final expectedSequence = List<int>.generate(10, (index) => index + 1);
      final actualSequence = plants
          .map((plant) => plant.sequenceNumber)
          .toList();
      if (actualSequence.length == 10 &&
          !_sameSequence(actualSequence, expectedSequence)) {
        issues.add(
          ValidationIssue(
            'plant_sequence',
            'Station ${station.stationNumber} must contain plant positions 1-10.',
            stationId: station.id,
          ),
        );
      }

      if (_requiresPlantingUnitSupplement(assessment.growthStage)) {
        final plantingUnits =
            await (database.select(database.plantingUnitObservations)
                  ..where(
                    (row) =>
                        row.stationId.equals(station.id) &
                        row.deletedAt.isNull(),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)]))
                .get();
        if (plantingUnits.length != 10) {
          issues.add(
            ValidationIssue(
              'planting_unit_count',
              'Station ${station.stationNumber} requires 10 explicit VE-V2 planting positions; found ${plantingUnits.length}.',
              stationId: station.id,
            ),
          );
        }
      }

      for (final plant in plants.where((item) => item.assessable)) {
        final hasStageRecord = switch (assessment.assessmentMode) {
          DatabaseCodes.modeVeV6 ||
          DatabaseCodes.modeV7V12 => await _hasVegetativeRecord(plant.id),
          DatabaseCodes.modeVtR2 => await _hasReproductiveRecord(plant.id),
          DatabaseCodes.modeR3R6 => await _hasEarRecord(plant.id),
          _ => false,
        };
        if (!hasStageRecord) {
          issues.add(
            ValidationIssue(
              'stage_record_missing',
              'Plant ${plant.sequenceNumber} at station ${station.stationNumber} is missing its ${assessment.assessmentMode} observation.',
              stationId: station.id,
            ),
          );
        }
      }
    }

    return BlockValidationResult(List.unmodifiable(issues));
  }

  Future<void> completeAssessment(String assessmentId) async {
    final assessment = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(assessmentId))).getSingle();
    final blockRuns =
        await (database.select(database.assessmentBlockRuns)..where(
              (row) =>
                  row.assessmentId.equals(assessmentId) &
                  row.deletedAt.isNull(),
            ))
            .get();

    final issues = <ValidationIssue>[];
    if (blockRuns.isEmpty) {
      issues.add(
        const ValidationIssue(
          'block_missing',
          'A completed formal assessment requires at least one assessment block.',
        ),
      );
    }
    for (final blockRun in blockRuns) {
      issues.addAll((await validateBlock(blockRun.id)).issues);
    }
    if (issues.isNotEmpty) {
      throw AssessmentValidationException(List.unmodifiable(issues));
    }

    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      for (final blockRun in blockRuns) {
        await (database.update(
          database.assessmentBlockRuns,
        )..where((row) => row.id.equals(blockRun.id))).write(
          AssessmentBlockRunsCompanion(
            status: const Value(DatabaseCodes.completed),
            completedAt: Value(now),
            updatedAt: Value(now),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
      }
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessment.id))).write(
        AssessmentsCompanion(
          status: const Value(DatabaseCodes.completed),
          completedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
    });
  }

  Future<bool> _hasVegetativeRecord(String plantId) async {
    return await (database.select(database.vegetativeObservations)
              ..where((row) => row.plantObservationId.equals(plantId)))
            .getSingleOrNull() !=
        null;
  }

  Future<bool> _hasReproductiveRecord(String plantId) async {
    return await (database.select(database.reproductiveObservations)
              ..where((row) => row.plantObservationId.equals(plantId)))
            .getSingleOrNull() !=
        null;
  }

  Future<bool> _hasEarRecord(String plantId) async {
    return await (database.select(database.earObservations)..where(
              (row) =>
                  row.plantObservationId.equals(plantId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull() !=
        null;
  }

  bool _sameSequence(List<int> actual, List<int> expected) {
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  bool _requiresPlantingUnitSupplement(String growthStage) {
    return growthStage == 've' || growthStage == 'v1' || growthStage == 'v2';
  }
}
