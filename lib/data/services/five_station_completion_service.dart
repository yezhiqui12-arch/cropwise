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
    if (!_isSupportedStage(assessment.growthStage)) {
      issues.add(
        const ValidationIssue(
          'unsupported_stage',
          'Five-station completion is unavailable for this growth stage.',
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
    final latestReview =
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
    final reviewRepository = ScoutingWorkflowRepository(database);
    final manualConfirmationDeferred =
        latestReview?.afterJson != null &&
        reviewRepository.manualConfirmationDeferredFromReview(
          latestReview!.afterJson!,
        );
    final positions = plants.map((plant) => plant.sequenceNumber).toList();
    if (!manualConfirmationDeferred &&
        !_sameSequence(
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
      if (vegetative == null &&
          !manualConfirmationDeferred &&
          !_isVeV2Stage(assessment.growthStage)) {
        issues.add(
          ValidationIssue(
            'stage_record_missing',
            'Plant ${plant.sequenceNumber} at Station ${station.stationNumber} is missing its V3-V12 observation.',
            stationId: station.id,
          ),
        );
      }
      joined.add(
        StationPlantRecord(
          plant: plant,
          vegetative:
              vegetative ??
              VegetativeObservationRecord(
                plantObservationId: plant.id,
                smallFreshWindowpanes: false,
                infestedWhorl: false,
                scraping: false,
                cuttingOrTearing: false,
                freshFrass: false,
                whorlFeedingSign: false,
                larvaVisible: false,
                larvalSize: 'none_seen',
                damageScoreUncertain: false,
                createdAt: plant.createdAt,
                updatedAt: plant.updatedAt,
              ),
        ),
      );
    }
    if (manualConfirmationDeferred) {
      await _validateDeferredManualConfirmation(
        assessmentId: assessment.id,
        station: station,
        issues: issues,
      );
    } else if (_isVeV2Stage(assessment.growthStage)) {
      await _validateVeV2Station(
        assessmentId: assessment.id,
        station: station,
        plants: joined,
        issues: issues,
      );
    } else {
      await _validateEvidence(
        assessmentId: assessment.id,
        station: station,
        plants: joined,
        issues: issues,
      );
    }
    await _validateReview(station: station, plants: joined, issues: issues);
  }

  Future<void> _validateDeferredManualConfirmation({
    required String assessmentId,
    required StationRecord station,
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
          'Station ${station.stationNumber} needs station-context evidence or documented fallback.',
          stationId: station.id,
        ),
      );
    }
    for (var position = 1; position <= 10; position++) {
      final matches = bundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == position,
      );
      if (matches.length != 1 || matches.single.session.completedAt == null) {
        issues.add(
          ValidationIssue(
            'unconfirmed_capture_missing',
            'Plant $position at Station ${station.stationNumber} needs completed evidence capture before manual confirmation can be skipped.',
            stationId: station.id,
          ),
        );
        continue;
      }
      final bundle = matches.single;
      final hasPrimaryView =
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview) ||
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling);
      if (!hasPrimaryView) {
        issues.add(
          ValidationIssue(
            'unconfirmed_primary_view_missing',
            'Plant $position at Station ${station.stationNumber} needs its primary photograph or documented fallback.',
            stationId: station.id,
          ),
        );
      }
    }
  }

  Future<void> _validateVeV2Station({
    required String assessmentId,
    required StationRecord station,
    required List<StationPlantRecord> plants,
    required List<ValidationIssue> issues,
  }) async {
    final inspection = await (database.select(
      database.veV2StationInspections,
    )..where((row) => row.stationId.equals(station.id))).getSingleOrNull();
    if (inspection != null && inspection.completedAt == null) {
      final now = DateTime.now().toUtc();
      await (database.update(
        database.veV2StationInspections,
      )..where((row) => row.id.equals(inspection.id))).write(
        VeV2StationInspectionsCompanion(
          completedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
    }

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
          'Station ${station.stationNumber} needs station-context evidence or documented fallback.',
          stationId: station.id,
        ),
      );
    }

    for (final item in plants) {
      final matches = bundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == item.plant.sequenceNumber,
      );
      if (matches.length != 1) {
        issues.add(
          ValidationIssue(
            've_v2_seedling_evidence',
            'Living plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs one associated evidence record.',
            stationId: station.id,
          ),
        );
        continue;
      }
      final bundle = matches.single;
      if (bundle.session.assessmentId != assessmentId ||
          bundle.session.stationId != station.id ||
          bundle.session.plantObservationId != item.plant.id ||
          bundle.session.completedAt == null) {
        issues.add(
          ValidationIssue(
            've_v2_evidence_association',
            'Living plant ${item.plant.sequenceNumber} evidence is incomplete or attached incorrectly.',
            stationId: station.id,
          ),
        );
        continue;
      }
      final hasPrimary =
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling) ||
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview);
      if (!hasPrimary) {
        issues.add(
          ValidationIssue(
            've_v2_capture_missing',
            'Living plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs its required capture or documented fallback.',
            stationId: station.id,
          ),
        );
      }
    }
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
      final review = evidenceReviews[item.plant.sequenceNumber];
      if (item.plant.assessable &&
          (review?.isCurrent != true ||
              review?.status != DatabaseCodes.evidenceReviewSufficient)) {
        issues.add(
          ValidationIssue(
            'evidence_review_required',
            'Plant ${item.plant.sequenceNumber} at Station ${station.stationNumber} needs a current sufficient-evidence review.',
            stationId: station.id,
          ),
        );
      }
    }
  }

  Future<void> _validateReview({
    required StationRecord station,
    required List<StationPlantRecord> plants,
    required List<ValidationIssue> issues,
  }) async {
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
    if (review == null) {
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

  bool _isSupportedStage(String value) =>
      _isVeV2Stage(value) || value == 'v3_v6' || value == 'v7_v12';

  bool _isVeV2Stage(String value) => const {'ve', 'v1', 'v2'}.contains(value);
}
