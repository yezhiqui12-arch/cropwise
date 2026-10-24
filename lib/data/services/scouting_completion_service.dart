import '../../services/scouting_sampling_protocol.dart';
import 'package:drift/drift.dart';

import '../../services/station_evidence_policy.dart';
import '../../services/assessment_area_policy.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../repositories/evidence_capture_repository.dart';
import '../repositories/scouting_workflow_repository.dart';
import 'assessment_validation_types.dart';
import 'assessment_metrics_service.dart';

/// Shared, read-only readiness checks and transactional completion gates.
class ScoutingCompletionService {
  const ScoutingCompletionService(this.database);

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
          'Assessment completion is unavailable for this growth stage.',
        ),
      );
    }
    final expectedStations = List<int>.generate(
      ScoutingSamplingProtocol.locationCount(assessment.protocolVersion),
      (index) => index + 1,
    );
    final actualStations = stations
        .map((station) => station.stationNumber)
        .toList(growable: false);
    if (!_sameSequence(actualStations, expectedStations)) {
      issues.add(
        ValidationIssue(
          'station_count',
          'A sampling-complete block requires ${ScoutingSamplingProtocol.locationCount(assessment.protocolVersion)} sampling locations exactly; found ${stations.length}.',
        ),
      );
    }
    for (final number in expectedStations.where(
      (n) => !actualStations.contains(n),
    )) {
      issues.add(
        ValidationIssue(
          'station_missing',
          'Station $number has not been recorded.',
          stationNumber: number,
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

  Future<BlockValidationResult> validateAssessment(String assessmentId) async {
    final issues = <ValidationIssue>[];
    final assessment =
        await (database.select(database.assessments)
              ..where((r) => r.id.equals(assessmentId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    if (assessment == null) {
      return const BlockValidationResult([
        ValidationIssue('assessment_missing', 'The assessment is unavailable.'),
      ]);
    }
    if (assessment.growthStageUncertain) {
      issues.add(
        const ValidationIssue(
          'stage_uncertain',
          'Confirm the growth stage before completing fieldwork.',
        ),
      );
    }
    if (assessment.status == DatabaseCodes.safetyBlocked) {
      issues.add(
        const ValidationIssue(
          'safety_blocked',
          'Review field-entry safety before continuing.',
        ),
      );
    }
    try {
      await _requiredRuns(assessmentId);
    } on AssessmentValidationException catch (error) {
      issues.addAll(error.issues);
    }
    final runs =
        await (database.select(database.assessmentBlockRuns)
              ..where(
                (r) =>
                    r.assessmentId.equals(assessmentId) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.blockSequence)]))
            .get();
    for (final run in runs) {
      final result = await validateBlock(run.id);
      for (final issue in result.issues) {
        final station = issue.stationId == null
            ? null
            : await (database.select(
                database.stations,
              )..where((r) => r.id.equals(issue.stationId!))).getSingleOrNull();
        issues.add(
          ValidationIssue(
            issue.code,
            'Block ${run.blockSequence}: ${issue.message}',
            stationId: issue.stationId,
            blockRunId: run.id,
            stationNumber: issue.stationNumber ?? station?.stationNumber,
          ),
        );
      }
    }
    return BlockValidationResult(List.unmodifiable(issues));
  }

  Future<void> _requireActive(String id) async {
    final assessment = await (database.select(
      database.assessments,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
    if (assessment != null &&
        (!ScoutingSamplingProtocol.isDa(assessment.protocolVersion) ||
            assessment.scoutingPattern != ScoutingSamplingProtocol.daPattern)) {
      throw const AssessmentValidationException([
        ValidationIssue(
          'retired_protocol',
          'Start a new assessment with 20 plants per sampling block.',
        ),
      ]);
    }
    if (assessment?.status != DatabaseCodes.inProgress ||
        assessment!.growthStageUncertain) {
      throw const AssessmentValidationException([
        ValidationIssue(
          'assessment_not_active',
          'Only an in-progress assessment with a confirmed growth stage can be completed.',
        ),
      ]);
    }
  }

  Future<void> completeAssessment(String id) => database.transaction(() async {
    await _requireActive(id);
    final result = await validateAssessment(id);
    if (!result.isValid) throw AssessmentValidationException(result.issues);
    final runs = await _requiredRuns(id);
    for (final run in runs) {
      await _markBlockComplete(run.id);
    }
    await _markAssessmentComplete(id);
    for (final run in runs) {
      await AssessmentMetricsService(database).recalculateBlock(run.id);
    }
  });

  Future<void> completeBlock(
    String blockRunId,
  ) => database.transaction(() async {
    final run =
        await (database.select(database.assessmentBlockRuns)
              ..where((r) => r.id.equals(blockRunId) & r.deletedAt.isNull()))
            .getSingle();
    await _requireActive(run.assessmentId);
    final result = await validateBlock(blockRunId);
    if (!result.isValid) throw AssessmentValidationException(result.issues);
    final runs = await _requiredRuns(run.assessmentId);
    final allComplete = runs.every(
      (r) => r.id == blockRunId || r.status == DatabaseCodes.completed,
    );
    if (allComplete) {
      // Recheck earlier blocks; their observations may have changed since completion.
      final readiness = await validateAssessment(run.assessmentId);
      if (!readiness.isValid) {
        throw AssessmentValidationException(readiness.issues);
      }
    }
    await _markBlockComplete(blockRunId);
    if (allComplete) await _markAssessmentComplete(run.assessmentId);
    await AssessmentMetricsService(database).recalculateBlock(blockRunId);
  });

  Future<void> _markBlockComplete(String id) async {
    final now = DateTime.now().toUtc();
    await (database.update(
      database.assessmentBlockRuns,
    )..where((r) => r.id.equals(id))).write(
      AssessmentBlockRunsCompanion(
        status: const Value(DatabaseCodes.completed),
        completedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value(DatabaseCodes.queued),
      ),
    );
  }

  Future<void> _markAssessmentComplete(String id) async {
    final now = DateTime.now().toUtc();
    await (database.update(
      database.assessments,
    )..where((r) => r.id.equals(id))).write(
      AssessmentsCompanion(
        status: const Value(DatabaseCodes.completed),
        completedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value(DatabaseCodes.queued),
      ),
    );
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
          List<int>.generate(
            ScoutingSamplingProtocol.plantsPerLocation(
              assessment.protocolVersion,
            ),
            (index) => index + 1,
          ),
        )) {
      issues.add(
        ValidationIssue(
          'plant_positions',
          'Station ${station.stationNumber} requires ${ScoutingSamplingProtocol.plantsPerLocation(assessment.protocolVersion)} plant position(s) exactly; found ${plants.length}.',
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
      final reproductive =
          await (database.select(database.reproductiveObservations)
                ..where((row) => row.plantObservationId.equals(plant.id)))
              .getSingleOrNull();
      final ear =
          await (database.select(database.earObservations)..where(
                (row) =>
                    row.plantObservationId.equals(plant.id) &
                    row.earSequence.equals(1) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final stagePresent = switch (assessment.assessmentMode) {
        DatabaseCodes.modeVeV6 || DatabaseCodes.modeV7V12 => vegetative != null,
        DatabaseCodes.modeVtR2 => reproductive != null,
        DatabaseCodes.modeR3R6 => ear != null,
        _ => false,
      };
      if (!manualConfirmationDeferred && plant.assessable && !stagePresent) {
        issues.add(
          ValidationIssue(
            'stage_record_missing',
            'Plant ${plant.sequenceNumber} at Station ${station.stationNumber} needs its growth-stage observation.',
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
          reproductive: reproductive,
          ear: ear,
        ),
      );
    }
    if (manualConfirmationDeferred) {
      await _validateDeferredManualConfirmation(
        assessmentId: assessment.id,
        station: station,
        requiredPlantCount: ScoutingSamplingProtocol.plantsPerLocation(
          assessment.protocolVersion,
        ),
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
        assessmentMode: assessment.assessmentMode,
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
    required int requiredPlantCount,
    required StationRecord station,
    required List<ValidationIssue> issues,
  }) async {
    final bundles = await EvidenceCaptureRepository(
      database,
    ).loadStationBundles(station.id);
    for (var position = 1; position <= requiredPlantCount; position++) {
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
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling) ||
          bundle.isViewSatisfied(DatabaseCodes.evidenceViewEarRegionOverview);
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
    if (inspection == null || inspection.completedAt == null) {
      issues.add(
        ValidationIssue(
          'seedling_inspection_incomplete',
          'Station ${station.stationNumber} needs a completed seedling inspection.',
          stationId: station.id,
        ),
      );
    }
    final units =
        await (database.select(database.plantingUnitObservations)
              ..where(
                (r) => r.stationId.equals(station.id) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.sequenceNumber)]))
            .get();
    if (inspection?.plantingUnitSequenceAssessable == true &&
        !_sameSequence(
          units.map((u) => u.sequenceNumber).toList(),
          List.generate(plants.length, (i) => i + 1),
        )) {
      issues.add(
        ValidationIssue(
          'planting_positions',
          'Station ${station.stationNumber} needs the planting position for each sampled plant.',
          stationId: station.id,
        ),
      );
    }

    final bundles = await EvidenceCaptureRepository(
      database,
    ).loadStationBundles(station.id);
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
    required String assessmentMode,
    required String assessmentId,
    required StationRecord station,
    required List<StationPlantRecord> plants,
    required List<ValidationIssue> issues,
  }) async {
    final bundles = await EvidenceCaptureRepository(
      database,
    ).loadStationBundles(station.id);

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
      final requiredViews =
          assessmentMode == DatabaseCodes.modeVtR2 ||
              assessmentMode == DatabaseCodes.modeR3R6
          ? item.plant.assessable
                ? {
                    bundle.isViewSatisfied(
                          DatabaseCodes.evidenceViewEarRegionOverview,
                        )
                        ? DatabaseCodes.evidenceViewEarRegionOverview
                        : DatabaseCodes.evidenceViewWhorlOverview,
                  }
                : const <String>{}
          : (sessionPolicy ??
                    StationEvidencePolicy.cameraFirstOverviewConditional)
                .requiredViewsForObservation(
                  plant: item.plant,
                  vegetative: item.vegetative,
                );
      for (final view in requiredViews) {
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
    final repository = ScoutingWorkflowRepository(database);
    final sourceIds = await repository.reviewSourceAuditIds(
      station: station,
      plants: plants,
    );
    final isCurrent =
        review?.afterJson != null &&
        repository.sameStrings(
          repository.sourceAuditIdsFromReview(review!.afterJson!),
          sourceIds,
        );
    if (!isCurrent) {
      issues.add(
        ValidationIssue(
          review == null ? 'station_review_required' : 'station_review_stale',
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
    final boundary =
        await (database.select(database.fieldBoundaryVersions)..where(
              (row) =>
                  row.id.equals(assessment.boundaryVersionId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (boundary == null || boundary.confirmationStatus != 'user_confirmed') {
      throw const AssessmentValidationException([
        ValidationIssue(
          'boundary_unavailable',
          'The original field outline must be available and confirmed.',
        ),
      ]);
    }
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
    final requiredBlockCount = AssessmentAreaPolicy.requiredBlockCount(
      boundary.areaHectares,
    );
    final expectedNumbers = List<int>.generate(
      requiredBlockCount,
      (index) => index + 1,
    );
    if (!AssessmentAreaPolicy.isWithinAssessmentLimit(boundary.areaHectares) ||
        blocks.length != requiredBlockCount ||
        blocks.any(
          (block) =>
              block.isProvisional ||
              !AssessmentAreaPolicy.isValidBlockArea(block.areaHectares) ||
              block.geometryGeojson.trim().isEmpty,
        ) ||
        !_sameSequence(
          blocks.map((block) => block.blockNumber).toList(),
          expectedNumbers,
        )) {
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
    final reason = station.notLocatedReason?.trim().isNotEmpty == true;
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
      DatabaseCodes.isGrowthStageImplemented(value);

  bool _isVeV2Stage(String value) => const {'ve', 'v1', 'v2'}.contains(value);
}
