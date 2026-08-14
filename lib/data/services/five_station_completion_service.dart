import 'package:drift/drift.dart';

import '../../services/station_evidence_policy.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../repositories/evidence_capture_repository.dart';
import '../repositories/scouting_workflow_repository.dart';
import 'assessment_completion_validator.dart';

/// Completes five-station sampling without calculating an assessment result.
class FiveStationCompletionService {
  const FiveStationCompletionService(this.database);

  final AppDatabase database;

  Future<BlockValidationResult> validateBlock(String blockRunId) async {
    final run = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(blockRunId))).getSingle();
    final assessment = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(run.assessmentId))).getSingle();
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
    if (!_isPilotStage(assessment.growthStage)) {
      issues.add(
        const ValidationIssue(
          'unsupported_stage',
          'Increment A completion is available only for the V3-V12 workflow.',
        ),
      );
    }
    final expectedStations = List<int>.generate(5, (index) => index + 1);
    final actualStations = stations
        .map((station) => station.stationNumber)
        .toList(growable: false);
    if (!_sameSequence(actualStations, expectedStations)) {
      issues.add(
        ValidationIssue(
          'station_count',
          'A sampling-complete block requires Stations 1-5 exactly; found ${stations.length}.',
        ),
      );
    }
    for (final station in stations) {
      await _validateStation(
        assessment: assessment,
        station: station,
        issues: issues,
      );
    }
    return BlockValidationResult(List.unmodifiable(issues));
  }

  Future<void> completeBlock(String blockRunId) async {
    final result = await validateBlock(blockRunId);
    if (!result.isValid) throw AssessmentValidationException(result.issues);
    final run = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(blockRunId))).getSingle();
    final requiredRuns = await _requiredRuns(run.assessmentId);
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      await (database.update(
        database.assessmentBlockRuns,
      )..where((row) => row.id.equals(blockRunId))).write(
        AssessmentBlockRunsCompanion(
          status: const Value(DatabaseCodes.completed),
          completedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      final allBlocksComplete = requiredRuns.every(
        (item) =>
            item.id == blockRunId || item.status == DatabaseCodes.completed,
      );
      if (allBlocksComplete) {
        await (database.update(
          database.assessments,
        )..where((row) => row.id.equals(run.assessmentId))).write(
          AssessmentsCompanion(
            status: const Value(DatabaseCodes.completed),
            completedAt: Value(now),
            updatedAt: Value(now),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
      }
    });
  }

  Future<void> _validateStation({
    required AssessmentRecord assessment,
    required StationRecord station,
    required List<ValidationIssue> issues,
  }) async {
    if (!_hasLocation(station)) {
      issues.add(
        ValidationIssue(
          'station_location_missing',
          'Station ${station.stationNumber} needs GPS or a documented unavailable reason.',
          stationId: station.id,
        ),
      );
    }
    final plants =
        await (database.select(database.plantObservations)
              ..where(
                (row) =>
                    row.stationId.equals(station.id) & row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)]))
            .get();
    final positions = plants.map((plant) => plant.sequenceNumber).toList();
    if (!_sameSequence(
      positions,
      List<int>.generate(10, (index) => index + 1),
    )) {
      issues.add(
        ValidationIssue(
          'plant_positions',
          'Station ${station.stationNumber} requires plant positions 1-10 exactly; found ${plants.length}.',
          stationId: station.id,
        ),
      );
    }

    final joined = <StationPlantRecord>[];
    for (final plant in plants) {
      final vegetative =
          await (database.select(database.vegetativeObservations)
                ..where((row) => row.plantObservationId.equals(plant.id)))
              .getSingleOrNull();
      if (vegetative == null) {
        issues.add(
          ValidationIssue(
            'stage_record_missing',
            'Plant ${plant.sequenceNumber} at Station ${station.stationNumber} is missing its V3-V12 observation.',
            stationId: station.id,
          ),
        );
      } else {
        joined.add(StationPlantRecord(plant: plant, vegetative: vegetative));
      }
    }
    await _validateEvidence(
      assessmentId: assessment.id,
      station: station,
      plants: joined,
      issues: issues,
    );
    await _validateReview(station: station, plants: joined, issues: issues);
  }

  Future<void> _validateEvidence({
    required String assessmentId,
    required StationRecord station,
    required List<StationPlantRecord> plants,
    required List<ValidationIssue> issues,
  }) async {
    final bundles = await EvidenceCaptureRepository(
      database,
    ).loadStationBundles(station.id);
    final context = bundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopeStationContext,
    );
    if (context.length != 1 ||
        context.single.session.assessmentId != assessmentId ||
        context.single.session.completedAt == null ||
        !context.single.isViewSatisfied(
          DatabaseCodes.evidenceViewStationContext,
        )) {
      issues.add(
        ValidationIssue(
          'station_context_missing',
          'Station ${station.stationNumber} needs station-context evidence or documented manual fallback.',
          stationId: station.id,
        ),
      );
    }
    final evidenceReviews = await EvidenceCaptureRepository(
      database,
    ).loadPlantEvidenceReviews(station.id);
    for (final item in plants) {
      final matches = bundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == item.plant.sequenceNumber,
      );
      if (matches.length != 1) {
        issues.add(
          ValidationIssue(
            'plant_evidence_session',
            'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs one correctly associated evidence record.',
            stationId: station.id,
          ),
        );
        continue;
      }
      final bundle = matches.single;
      if (bundle.session.assessmentId != assessmentId ||
          bundle.session.stationId != station.id ||
          bundle.session.plantObservationId != item.plant.id) {
        issues.add(
          ValidationIssue(
            'plant_evidence_association',
            'Plant ${item.plant.sequenceNumber} evidence is not attached to the correct assessment, station, and plant.',
            stationId: station.id,
          ),
        );
      }
      StationEvidencePolicy? sessionPolicy;
      try {
        sessionPolicy = StationEvidencePolicy.fromRequirementsVersion(
          bundle.session.requirementsVersion,
        );
      } catch (_) {
        sessionPolicy = null;
      }
      if (sessionPolicy == null) {
        issues.add(
          ValidationIssue(
            'evidence_policy_version',
            'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} has an unsupported evidence-policy version.',
            stationId: station.id,
          ),
        );
      }
      if (bundle.session.completedAt == null) {
        issues.add(
          ValidationIssue(
            'plant_evidence_incomplete',
            'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} has unfinished evidence collection.',
            stationId: station.id,
          ),
        );
      }
      for (final view
          in (sessionPolicy ??
                  StationEvidencePolicy.cameraFirstOverviewConditional)
              .requiredViewsForObservation(
                plant: item.plant,
                vegetative: item.vegetative,
              )) {
        if (!bundle.isViewSatisfied(view)) {
          issues.add(
            ValidationIssue(
              'required_evidence_missing',
              'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs supporting evidence or documented manual fallback.',
              stationId: station.id,
            ),
          );
        }
      }
      if (item.plant.assessable &&
          sessionPolicy ==
              StationEvidencePolicy.cameraFirstOverviewConditional) {
        final review = evidenceReviews[item.plant.sequenceNumber];
        if (review == null ||
            !review.isCurrent ||
            review.status != DatabaseCodes.evidenceReviewSufficient) {
          issues.add(
            ValidationIssue(
              'plant_evidence_review',
              'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs a current sufficient evidence review.',
              stationId: station.id,
            ),
          );
        }
      }
    }
  }

  Future<void> _validateReview({
    required StationRecord station,
    required List<StationPlantRecord> plants,
    required List<ValidationIssue> issues,
  }) async {
    final repository = ScoutingWorkflowRepository(database);
    final review =
        await (database.select(database.auditLogs)
              ..where(
                (row) =>
                    row.entityType.equals('stations') &
                    row.entityId.equals(station.id) &
                    row.action.equals('review_confirmed'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.occurredAt)])
              ..limit(1))
            .getSingleOrNull();
    if (review == null ||
        !repository.sameStrings(
          repository.sourceAuditIdsFromReview(review.afterJson ?? '{}'),
          await repository.reviewSourceAuditIds(
            station: station,
            plants: plants,
          ),
        )) {
      issues.add(
        ValidationIssue(
          'station_review_required',
          'Station ${station.stationNumber} needs a current evaluator review.',
          stationId: station.id,
        ),
      );
    }
  }

  Future<List<AssessmentBlockRunRecord>> _requiredRuns(
    String assessmentId,
  ) async {
    final assessment = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(assessmentId))).getSingle();
    final boundary = await (database.select(
      database.fieldBoundaryVersions,
    )..where((row) => row.id.equals(assessment.boundaryVersionId))).getSingle();
    final blocks =
        await (database.select(database.fieldBlocks)
              ..where(
                (row) =>
                    row.cropCycleId.equals(assessment.cropCycleId) &
                    row.boundaryVersionId.equals(assessment.boundaryVersionId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.blockNumber)]))
            .get();
    final expectedNumbers = List<int>.generate(
      blocks.length,
      (index) => index + 1,
    );
    if (blocks.isEmpty ||
        blocks.any(
          (block) =>
              block.isProvisional ||
              block.areaHectares <= 0 ||
              block.geometryGeojson.trim().isEmpty,
        ) ||
        !_sameSequence(
          blocks.map((block) => block.blockNumber).toList(),
          expectedNumbers,
        ) ||
        (boundary.areaHectares > 1 && blocks.length < 2)) {
      throw const AssessmentValidationException([
        ValidationIssue(
          'block_definitions_incomplete',
          'Every required block must be explicitly defined and confirmed before sampling can be completed.',
        ),
      ]);
    }
    final runs =
        await (database.select(database.assessmentBlockRuns)
              ..where(
                (row) =>
                    row.assessmentId.equals(assessmentId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.blockSequence)]))
            .get();
    if (runs.length != blocks.length) {
      throw const AssessmentValidationException([
        ValidationIssue(
          'block_run_missing',
          'Every required block needs one assessment block run.',
        ),
      ]);
    }
    for (var index = 0; index < blocks.length; index++) {
      if (runs[index].fieldBlockId != blocks[index].id ||
          runs[index].blockSequence != index + 1) {
        throw const AssessmentValidationException([
          ValidationIssue(
            'block_run_association',
            'Assessment block runs do not match the confirmed block definitions.',
          ),
        ]);
      }
    }
    return runs;
  }

  bool _hasLocation(StationRecord station) {
    final coordinates = station.latitude != null && station.longitude != null;
    final reason = station.notLocatedReason?.isNotEmpty == true;
    return coordinates != reason;
  }

  bool _sameSequence(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  bool _isPilotStage(String value) => value == 'v3_v6' || value == 'v7_v12';
}
