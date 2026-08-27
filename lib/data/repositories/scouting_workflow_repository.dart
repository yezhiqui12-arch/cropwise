import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import 'evidence_capture_repository.dart';
import 'local_mutation_recorder.dart';

class PilotBlockRequiredException implements Exception {
  const PilotBlockRequiredException(this.areaHectares);

  final double areaHectares;
}

class IncompleteBlockDefinitionsException implements Exception {
  const IncompleteBlockDefinitionsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PreparedScoutingRun {
  const PreparedScoutingRun({required this.block, required this.run});

  final FieldBlockRecord block;
  final AssessmentBlockRunRecord run;
}

class StationPlantRecord {
  const StationPlantRecord({
    required this.plant,
    this._vegetative,
    this.reproductive,
    this.ear,
  });

  final PlantObservationRecord plant;
  final VegetativeObservationRecord? _vegetative;
  final ReproductiveObservationRecord? reproductive;
  final EarObservationRecord? ear;

  VegetativeObservationRecord get vegetative =>
      _vegetative ??
      (throw StateError('This plant does not use the vegetative protocol.'));

  VegetativeObservationRecord? get vegetativeOrNull => _vegetative;
}

class StationSnapshot {
  const StationSnapshot({
    required this.prepared,
    this.stationNumber = 1,
    required this.station,
    required this.plants,
    required this.reviewedAt,
    required this.reviewIsCurrent,
  });

  final PreparedScoutingRun prepared;
  final int stationNumber;
  final StationRecord? station;
  final List<StationPlantRecord> plants;
  final DateTime? reviewedAt;
  final bool reviewIsCurrent;

  int get nextMissingPlantPosition {
    final saved = plants.map((item) => item.plant.sequenceNumber).toSet();
    for (var position = 1; position <= 10; position++) {
      if (!saved.contains(position)) return position;
    }
    return 10;
  }
}

class BlockProgressSnapshot {
  const BlockProgressSnapshot({required this.prepared, required this.stations});

  final PreparedScoutingRun prepared;
  final List<StationSnapshot> stations;

  StationSnapshot station(int stationNumber) =>
      stations.singleWhere((item) => item.stationNumber == stationNumber);

  int? get nextIncompleteStationNumber {
    for (final snapshot in stations) {
      if (!snapshot.reviewIsCurrent) return snapshot.stationNumber;
    }
    return null;
  }

  bool get allStationsReviewed => nextIncompleteStationNumber == null;
}

// Compatibility names keep the completed Station 1 implementation and tests
// source-compatible while the workflow is generalized to five stations.
typedef PreparedStation1Run = PreparedScoutingRun;
typedef Station1PlantRecord = StationPlantRecord;
typedef Station1Snapshot = StationSnapshot;

class ScoutingWorkflowRepository {
  ScoutingWorkflowRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<AssessmentRecord> assessmentById(String id) {
    return (database.select(
      database.assessments,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<BoundaryRecord> boundaryById(String id) {
    return (database.select(
      database.fieldBoundaryVersions,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> confirmPilotGrowthStage(AssessmentRecord assessment) async {
    if (!DatabaseCodes.isGrowthStageImplemented(assessment.growthStage)) {
      throw StateError('This growth-stage workflow is not implemented.');
    }
    if (!assessment.growthStageUncertain) return;

    await database.transaction(() async {
      final previous = await assessmentById(assessment.id);
      final now = DateTime.now().toUtc();
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessment.id))).write(
        AssessmentsCompanion(
          growthStageUncertain: const Value(false),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await _mutations.record(
        entityType: 'assessments',
        entityId: assessment.id,
        action: 'growth_stage_confirmed',
        actorPersonId: assessment.evaluatorPersonId,
        before: {
          'growth_stage': previous.growthStage,
          'growth_stage_uncertain': previous.growthStageUncertain,
        },
        after: {
          'growth_stage': assessment.growthStage,
          'growth_stage_uncertain': false,
        },
      );
    });
  }

  Future<List<PreparedScoutingRun>> findPreparedRuns(
    String assessmentId,
  ) async {
    final assessment = await assessmentById(assessmentId);
    final boundary = await boundaryById(assessment.boundaryVersionId);
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
    if (blocks.isNotEmpty) _validateExistingBlocks(blocks, boundary);
    final result = <PreparedScoutingRun>[];
    for (final block in blocks) {
      final run =
          await (database.select(database.assessmentBlockRuns)..where(
                (row) =>
                    row.assessmentId.equals(assessmentId) &
                    row.fieldBlockId.equals(block.id) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (run != null) result.add(PreparedScoutingRun(block: block, run: run));
    }
    if (result.isNotEmpty && result.length != blocks.length) {
      return const [];
    }
    return List.unmodifiable(result);
  }

  Future<PreparedScoutingRun?> findPreparedRun(String assessmentId) async {
    final runs = await findPreparedRuns(assessmentId);
    return runs.isEmpty ? null : runs.first;
  }

  Future<List<PreparedScoutingRun>> prepareRequiredBlocks(
    AssessmentRecord assessment,
    BoundaryRecord boundary,
  ) async {
    _validatePreparationGate(assessment, boundary);

    return database.transaction(() async {
      var blocks = await _blocksForAssessment(assessment);
      if (blocks.isEmpty) {
        if (boundary.areaHectares > 1) {
          throw PilotBlockRequiredException(boundary.areaHectares);
        }
        blocks = [await _createWholeFieldBlock(assessment, boundary)];
      }
      _validateExistingBlocks(blocks, boundary);

      final prepared = <PreparedScoutingRun>[];
      for (var index = 0; index < blocks.length; index++) {
        final block = blocks[index];
        final sequence = index + 1;
        var run =
            await (database.select(database.assessmentBlockRuns)..where(
                  (row) =>
                      row.assessmentId.equals(assessment.id) &
                      row.fieldBlockId.equals(block.id) &
                      row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (run == null) {
          run = await _createRun(
            assessment: assessment,
            block: block,
            blockSequence: sequence,
          );
        } else if (run.blockSequence != sequence) {
          throw const IncompleteBlockDefinitionsException(
            'Saved block-run order does not match the current block definitions.',
          );
        }
        prepared.add(PreparedScoutingRun(block: block, run: run));
      }
      return List.unmodifiable(prepared);
    });
  }

  Future<PreparedScoutingRun> prepareBlockOne(
    AssessmentRecord assessment,
    BoundaryRecord boundary,
  ) async {
    final prepared = await prepareRequiredBlocks(assessment, boundary);
    if (prepared.length != 1) {
      throw const IncompleteBlockDefinitionsException(
        'This assessment has multiple prepared blocks.',
      );
    }
    return prepared.single;
  }

  Future<BlockProgressSnapshot> loadBlockSnapshot(
    PreparedScoutingRun prepared,
  ) async {
    final snapshots = <StationSnapshot>[];
    for (var stationNumber = 1; stationNumber <= 5; stationNumber++) {
      snapshots.add(
        await loadStationSnapshot(prepared, stationNumber: stationNumber),
      );
    }
    return BlockProgressSnapshot(
      prepared: prepared,
      stations: List.unmodifiable(snapshots),
    );
  }

  Future<StationSnapshot> loadSnapshot(PreparedScoutingRun prepared) =>
      loadStationSnapshot(prepared, stationNumber: 1);

  Future<StationSnapshot> loadStationSnapshot(
    PreparedScoutingRun prepared, {
    required int stationNumber,
  }) async {
    _validateStationNumber(stationNumber);
    final station =
        await (database.select(database.stations)..where(
              (row) =>
                  row.assessmentBlockRunId.equals(prepared.run.id) &
                  row.stationNumber.equals(stationNumber) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (station == null) {
      return StationSnapshot(
        prepared: prepared,
        stationNumber: stationNumber,
        station: null,
        plants: const [],
        reviewedAt: null,
        reviewIsCurrent: false,
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
      joined.add(
        StationPlantRecord(
          plant: plant,
          vegetative: vegetative,
          reproductive: reproductive,
          ear: ear,
        ),
      );
    }

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
    final reviewedAt = review?.occurredAt;
    final recordedSourceAuditIds = review?.afterJson == null
        ? const <String>[]
        : sourceAuditIdsFromReview(review!.afterJson!);
    final manualConfirmationDeferred = review?.afterJson == null
        ? false
        : manualConfirmationDeferredFromReview(review!.afterJson!);
    final currentSourceAuditIds = await reviewSourceAuditIds(
      station: station,
      plants: joined,
    );

    return StationSnapshot(
      prepared: prepared,
      stationNumber: stationNumber,
      station: station,
      plants: List.unmodifiable(joined),
      reviewedAt: reviewedAt,
      reviewIsCurrent:
          (joined.length == 10 || manualConfirmationDeferred) &&
          reviewedAt != null &&
          sameStrings(recordedSourceAuditIds, currentSourceAuditIds),
    );
  }

  Future<StationRecord> saveStationLocation({
    required PreparedScoutingRun prepared,
    required String actorPersonId,
    int stationNumber = 1,
    double? latitude,
    double? longitude,
    double? gpsAccuracyM,
    DateTime? capturedAt,
    String? notLocatedReason,
    String? accessibilityNotes,
  }) async {
    _validateStationNumber(stationNumber);
    final hasCoordinates = latitude != null || longitude != null;
    final hasReason = notLocatedReason != null && notLocatedReason.isNotEmpty;
    if (hasCoordinates == hasReason ||
        (hasCoordinates && (latitude == null || longitude == null))) {
      throw ArgumentError(
        'Provide complete coordinates or one location-unavailable reason.',
      );
    }
    if (hasCoordinates) {
      if (!latitude!.isFinite ||
          !longitude!.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          gpsAccuracyM == null ||
          !gpsAccuracyM.isFinite ||
          gpsAccuracyM < 0 ||
          capturedAt == null) {
        throw ArgumentError(
          'The station GPS reading is incomplete or invalid.',
        );
      }
    } else if (!DatabaseCodes.stationNotLocatedReasons.contains(
      notLocatedReason,
    )) {
      throw ArgumentError.value(
        notLocatedReason,
        'notLocatedReason',
        'Unsupported station location-unavailable reason',
      );
    }

    return database.transaction(() async {
      final previous =
          await (database.select(database.stations)..where(
                (row) =>
                    row.assessmentBlockRunId.equals(prepared.run.id) &
                    row.stationNumber.equals(stationNumber) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final stationId = previous?.id ?? LocalId.generate();
      final now = DateTime.now().toUtc();
      final values = StationsCompanion(
        latitude: Value(latitude),
        longitude: Value(longitude),
        gpsAccuracyM: Value(gpsAccuracyM),
        capturedAt: Value(capturedAt?.toUtc()),
        notLocatedReason: Value(notLocatedReason),
        accessibilityNotes: Value(accessibilityNotes),
        updatedAt: Value(now),
        syncState: const Value(DatabaseCodes.queued),
      );
      if (previous == null) {
        await database
            .into(database.stations)
            .insert(
              StationsCompanion.insert(
                id: stationId,
                assessmentBlockRunId: prepared.run.id,
                stationNumber: stationNumber,
                latitude: values.latitude,
                longitude: values.longitude,
                gpsAccuracyM: values.gpsAccuracyM,
                capturedAt: values.capturedAt,
                notLocatedReason: values.notLocatedReason,
                accessibilityNotes: values.accessibilityNotes,
                updatedAt: values.updatedAt,
                syncState: values.syncState,
              ),
            );
      } else {
        await (database.update(
          database.stations,
        )..where((row) => row.id.equals(stationId))).write(values);
      }

      final saved = await (database.select(
        database.stations,
      )..where((row) => row.id.equals(stationId))).getSingle();
      await _mutations.record(
        entityType: 'stations',
        entityId: stationId,
        action: previous == null ? 'create' : 'location_update',
        actorPersonId: actorPersonId,
        before: previous == null ? null : _stationSnapshot(previous),
        after: _stationSnapshot(saved),
      );
      return saved;
    });
  }

  Future<void> recordResumeCheck({
    required AssessmentRecord assessment,
    required String conditionCode,
    required bool continuingSameAssessment,
    String? note,
  }) {
    return database.transaction(
      () => _mutations.record(
        entityType: 'assessments',
        entityId: assessment.id,
        action: 'resume_check',
        actorPersonId: assessment.evaluatorPersonId,
        after: {
          'condition_code': conditionCode,
          'continuing_same_assessment': continuingSameAssessment,
          'note': note,
        },
      ),
    );
  }

  Future<void> confirmStationReview({
    required StationSnapshot snapshot,
    required String actorPersonId,
    bool manualConfirmationDeferred = false,
  }) async {
    if (snapshot.station == null ||
        (!manualConfirmationDeferred && snapshot.plants.length != 10)) {
      throw StateError(
        'Station ${snapshot.stationNumber} requires ten saved plant positions.',
      );
    }
    if (manualConfirmationDeferred) {
      final bundles = await EvidenceCaptureRepository(
        database,
      ).loadStationBundles(snapshot.station!.id);
      final capturedPositions = {
        for (final bundle in bundles)
          if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
              bundle.session.plantPosition != null &&
              bundle.session.completedAt != null)
            bundle.session.plantPosition!,
      };
      if (!sameInts(capturedPositions, List<int>.generate(10, (i) => i + 1))) {
        throw StateError(
          'Capture all ten plant positions before skipping manual confirmation.',
        );
      }
    }
    await database.transaction(() async {
      final sourceAuditIds = await reviewSourceAuditIds(
        station: snapshot.station!,
        plants: snapshot.plants,
      );
      await _mutations.record(
        entityType: 'stations',
        entityId: snapshot.station!.id,
        action: 'review_confirmed',
        actorPersonId: actorPersonId,
        after: {
          'block_sequence': snapshot.prepared.run.blockSequence,
          'station_number': snapshot.stationNumber,
          'plant_positions_reviewed': snapshot.plants.length,
          'manual_confirmation_deferred': manualConfirmationDeferred,
          'source_audit_ids': sourceAuditIds,
        },
      );
      final now = DateTime.now().toUtc();
      await (database.update(database.veV2StationInspections)..where(
            (row) =>
                row.stationId.equals(snapshot.station!.id) &
                row.completedAt.isNull(),
          ))
          .write(
            VeV2StationInspectionsCompanion(
              evaluatorWorkloadRating: const Value(3),
              completedAt: Value(now),
              updatedAt: Value(now),
              syncState: const Value(DatabaseCodes.queued),
            ),
          );
    });
  }

  Future<List<String>> reviewSourceAuditIds({
    required StationRecord station,
    required List<StationPlantRecord> plants,
  }) async {
    final evidenceSessions = await (database.select(
      database.evidenceCaptureSessions,
    )..where((row) => row.stationId.equals(station.id))).get();
    final evidenceSessionIds = evidenceSessions
        .map((session) => session.id)
        .toList(growable: false);
    final evidenceMedia = evidenceSessionIds.isEmpty
        ? const <EvidenceMediaRecord>[]
        : await (database.select(database.evidenceMedia)
                ..where((row) => row.captureSessionId.isIn(evidenceSessionIds)))
              .get();
    final plantIds = plants
        .map((item) => item.plant.id)
        .toList(growable: false);
    final reproductive = plantIds.isEmpty
        ? const <ReproductiveObservationRecord>[]
        : await (database.select(
            database.reproductiveObservations,
          )..where((row) => row.plantObservationId.isIn(plantIds))).get();
    final ears = plantIds.isEmpty
        ? const <EarObservationRecord>[]
        : await (database.select(database.earObservations)..where(
                (row) =>
                    row.plantObservationId.isIn(plantIds) &
                    row.deletedAt.isNull(),
              ))
              .get();
    final entityIds = <String>[
      station.id,
      ...plants.map((item) => item.plant.id),
      ...evidenceSessionIds,
      ...evidenceMedia.map((item) => item.id),
      ...reproductive.map((item) => item.plantObservationId),
      ...ears.map((item) => item.id),
    ];
    final audits = entityIds.isEmpty
        ? const <AuditLogRecord>[]
        : await (database.select(
            database.auditLogs,
          )..where((row) => row.entityId.isIn(entityIds))).get();
    final ids =
        audits
            .where(
              (audit) =>
                  (audit.entityType == 'stations' &&
                      audit.entityId == station.id &&
                      audit.action != 'review_confirmed') ||
                  (audit.entityType == 'plant_observations' &&
                      plants.any((item) => item.plant.id == audit.entityId)) ||
                  (audit.entityType == 'evidence_capture_sessions' &&
                      evidenceSessionIds.contains(audit.entityId)) ||
                  (audit.entityType == 'evidence_media' &&
                      evidenceMedia.any((item) => item.id == audit.entityId)) ||
                  (audit.entityType == 'reproductive_observations' &&
                      reproductive.any(
                        (item) => item.plantObservationId == audit.entityId,
                      )) ||
                  (audit.entityType == 'ear_observations' &&
                      ears.any((item) => item.id == audit.entityId)),
            )
            .map((audit) => audit.id)
            .toList(growable: false)
          ..sort();
    return ids;
  }

  List<String> sourceAuditIdsFromReview(String afterJson) {
    try {
      final decoded = jsonDecode(afterJson) as Map<String, dynamic>;
      final values = decoded['source_audit_ids'] as List<dynamic>?;
      if (values == null) return const [];
      return values.whereType<String>().toList(growable: false)..sort();
    } catch (_) {
      return const [];
    }
  }

  bool manualConfirmationDeferredFromReview(String afterJson) {
    try {
      final decoded = jsonDecode(afterJson) as Map<String, dynamic>;
      return decoded['manual_confirmation_deferred'] == true;
    } catch (_) {
      return false;
    }
  }

  bool sameInts(Set<int> actual, List<int> expected) =>
      actual.length == expected.length && expected.every(actual.contains);

  bool sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _validatePreparationGate(
    AssessmentRecord assessment,
    BoundaryRecord boundary,
  ) {
    if (assessment.status != DatabaseCodes.inProgress ||
        (assessment.safetySummaryStatus != DatabaseCodes.noRecentTreatment &&
            assessment.safetySummaryStatus !=
                DatabaseCodes.safeIntervalCompleted)) {
      throw StateError(
        'Field-entry safety must be confirmed before preparing stations.',
      );
    }
    if (boundary.id != assessment.boundaryVersionId ||
        boundary.confirmationStatus != 'user_confirmed') {
      throw StateError(
        'A confirmed approximate field outline is required before station work.',
      );
    }
    if (boundary.areaHectares <= 0) {
      throw StateError('The confirmed field outline has no usable area.');
    }
  }

  Future<List<FieldBlockRecord>> _blocksForAssessment(
    AssessmentRecord assessment,
  ) {
    return (database.select(database.fieldBlocks)
          ..where(
            (row) =>
                row.cropCycleId.equals(assessment.cropCycleId) &
                row.boundaryVersionId.equals(assessment.boundaryVersionId) &
                row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.blockNumber)]))
        .get();
  }

  void _validateExistingBlocks(
    List<FieldBlockRecord> blocks,
    BoundaryRecord boundary,
  ) {
    if (blocks.any((block) => block.isProvisional)) {
      throw const IncompleteBlockDefinitionsException(
        'Assessment block definitions still require evaluator confirmation.',
      );
    }
    if (boundary.areaHectares > 1 && blocks.length < 2) {
      throw PilotBlockRequiredException(boundary.areaHectares);
    }
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block.blockNumber != index + 1 ||
          block.areaHectares <= 0 ||
          block.geometryGeojson.trim().isEmpty) {
        throw const IncompleteBlockDefinitionsException(
          'Assessment block definitions are missing, invalid, or out of order.',
        );
      }
    }
  }

  Future<FieldBlockRecord> _createWholeFieldBlock(
    AssessmentRecord assessment,
    BoundaryRecord boundary,
  ) async {
    final blockId = LocalId.generate();
    await database
        .into(database.fieldBlocks)
        .insert(
          FieldBlocksCompanion.insert(
            id: blockId,
            cropCycleId: assessment.cropCycleId,
            boundaryVersionId: assessment.boundaryVersionId,
            blockNumber: 1,
            geometryGeojson: boundary.geometryGeojson,
            areaHectares: boundary.areaHectares,
            separationReason: const Value('whole_field_up_to_one_hectare'),
            isProvisional: const Value(false),
          ),
        );
    await _mutations.record(
      entityType: 'field_blocks',
      entityId: blockId,
      action: 'create',
      actorPersonId: assessment.evaluatorPersonId,
      after: {
        'crop_cycle_id': assessment.cropCycleId,
        'boundary_version_id': assessment.boundaryVersionId,
        'block_number': 1,
        'area_hectares': boundary.areaHectares,
        'scope': 'whole_field_up_to_one_hectare',
      },
    );
    return (database.select(
      database.fieldBlocks,
    )..where((row) => row.id.equals(blockId))).getSingle();
  }

  Future<AssessmentBlockRunRecord> _createRun({
    required AssessmentRecord assessment,
    required FieldBlockRecord block,
    required int blockSequence,
  }) async {
    final runId = LocalId.generate();
    final now = DateTime.now().toUtc();
    await database
        .into(database.assessmentBlockRuns)
        .insert(
          AssessmentBlockRunsCompanion.insert(
            id: runId,
            assessmentId: assessment.id,
            fieldBlockId: block.id,
            blockSequence: blockSequence,
            scoutingPattern: assessment.scoutingPattern,
            patternReason: Value(assessment.patternReason),
            status: const Value(DatabaseCodes.inProgress),
            startedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await _mutations.record(
      entityType: 'assessment_block_runs',
      entityId: runId,
      action: 'create',
      actorPersonId: assessment.evaluatorPersonId,
      after: {
        'assessment_id': assessment.id,
        'field_block_id': block.id,
        'block_sequence': blockSequence,
        'scouting_pattern': assessment.scoutingPattern,
      },
    );
    return (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(runId))).getSingle();
  }

  Map<String, Object?> _stationSnapshot(StationRecord station) {
    return {
      'assessment_block_run_id': station.assessmentBlockRunId,
      'station_number': station.stationNumber,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'gps_accuracy_m': station.gpsAccuracyM,
      'captured_at': station.capturedAt?.toIso8601String(),
      'not_located_reason': station.notLocatedReason,
      'accessibility_notes': station.accessibilityNotes,
    };
  }

  void _validateStationNumber(int stationNumber) {
    if (stationNumber < 1 || stationNumber > 5) {
      throw ArgumentError.value(stationNumber, 'stationNumber', 'Must be 1-5');
    }
  }
}
