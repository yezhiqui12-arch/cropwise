import '../../services/scouting_sampling_protocol.dart';
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import 'scouting_completion_service.dart';
import 'assessment_validation_types.dart';
export 'assessment_validation_types.dart';

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

    final locationCount = ScoutingSamplingProtocol.locationCount(
      assessment.protocolVersion,
    );
    final plantCount = ScoutingSamplingProtocol.plantsPerLocation(
      assessment.protocolVersion,
    );
    final issues = <ValidationIssue>[];
    if (stations.length != locationCount) {
      issues.add(
        ValidationIssue(
          'station_count',
          'A completed formal block requires exactly $locationCount sampling locations; found ${stations.length}.',
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
      if (plants.length != plantCount) {
        issues.add(
          ValidationIssue(
            'plant_count',
            'Station ${station.stationNumber} requires $plantCount explicit plant position(s); found ${plants.length}.',
            stationId: station.id,
          ),
        );
      }

      final expectedSequence = List<int>.generate(
        plantCount,
        (index) => index + 1,
      );
      final actualSequence = plants
          .map((plant) => plant.sequenceNumber)
          .toList();
      if (actualSequence.length == plantCount &&
          !_sameSequence(actualSequence, expectedSequence)) {
        issues.add(
          ValidationIssue(
            'plant_sequence',
            'Station ${station.stationNumber} must contain plant positions 1-$plantCount.',
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
        if (plantingUnits.length != plantCount) {
          issues.add(
            ValidationIssue(
              'planting_unit_count',
              'Station ${station.stationNumber} requires $plantCount explicit VE-V2 planting position(s); found ${plantingUnits.length}.',
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

  Future<void> completeAssessment(String assessmentId) =>
      ScoutingCompletionService(database).completeAssessment(assessmentId);

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
