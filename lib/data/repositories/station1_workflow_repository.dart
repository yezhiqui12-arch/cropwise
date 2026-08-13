import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class PilotBlockRequiredException implements Exception {
  const PilotBlockRequiredException(this.areaHectares);

  final double areaHectares;
}

class PreparedStation1Run {
  const PreparedStation1Run({required this.block, required this.run});

  final FieldBlockRecord block;
  final AssessmentBlockRunRecord run;
}

class Station1PlantRecord {
  const Station1PlantRecord({required this.plant, required this.vegetative});

  final PlantObservationRecord plant;
  final VegetativeObservationRecord vegetative;
}

class Station1Snapshot {
  const Station1Snapshot({
    required this.prepared,
    required this.station,
    required this.plants,
    required this.reviewedAt,
    required this.reviewIsCurrent,
  });

  final PreparedStation1Run prepared;
  final StationRecord? station;
  final List<Station1PlantRecord> plants;
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

class Station1WorkflowRepository {
  Station1WorkflowRepository(this.database)
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
    if (assessment.growthStage != 'v3_v6' &&
        assessment.growthStage != 'v7_v12') {
      throw StateError('Only V3-V12 can be confirmed for this pilot.');
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

  Future<PreparedStation1Run?> findPreparedRun(String assessmentId) async {
    final assessment = await assessmentById(assessmentId);
    final block =
        await (database.select(database.fieldBlocks)..where(
              (row) =>
                  row.cropCycleId.equals(assessment.cropCycleId) &
                  row.boundaryVersionId.equals(assessment.boundaryVersionId) &
                  row.blockNumber.equals(1) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (block == null) return null;

    final run =
        await (database.select(database.assessmentBlockRuns)..where(
              (row) =>
                  row.assessmentId.equals(assessmentId) &
                  row.fieldBlockId.equals(block.id) &
                  row.blockSequence.equals(1) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return run == null ? null : PreparedStation1Run(block: block, run: run);
  }

  Future<PreparedStation1Run> prepareBlockOne(
    AssessmentRecord assessment,
    BoundaryRecord boundary,
  ) async {
    if (assessment.status != DatabaseCodes.inProgress ||
        (assessment.safetySummaryStatus != DatabaseCodes.noRecentTreatment &&
            assessment.safetySummaryStatus !=
                DatabaseCodes.safeIntervalCompleted)) {
      throw StateError(
        'Field-entry safety must be confirmed before preparing Station 1.',
      );
    }
    if (boundary.id != assessment.boundaryVersionId ||
        boundary.confirmationStatus != 'user_confirmed') {
      throw StateError(
        'A confirmed approximate field outline is required before Station 1.',
      );
    }
    if (boundary.areaHectares > 1) {
      throw PilotBlockRequiredException(boundary.areaHectares);
    }
    if (boundary.areaHectares <= 0) {
      throw StateError('The confirmed field outline has no usable area.');
    }

    return database.transaction(() async {
      var block =
          await (database.select(database.fieldBlocks)..where(
                (row) =>
                    row.cropCycleId.equals(assessment.cropCycleId) &
                    row.boundaryVersionId.equals(assessment.boundaryVersionId) &
                    row.blockNumber.equals(1) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (block == null) {
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
        block = await (database.select(
          database.fieldBlocks,
        )..where((row) => row.id.equals(blockId))).getSingle();
      }
      final preparedBlock = block;

      var run =
          await (database.select(database.assessmentBlockRuns)..where(
                (row) =>
                    row.assessmentId.equals(assessment.id) &
                    row.fieldBlockId.equals(preparedBlock.id) &
                    row.blockSequence.equals(1) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (run == null) {
        final runId = LocalId.generate();
        final now = DateTime.now().toUtc();
        await database
            .into(database.assessmentBlockRuns)
            .insert(
              AssessmentBlockRunsCompanion.insert(
                id: runId,
                assessmentId: assessment.id,
                fieldBlockId: preparedBlock.id,
                blockSequence: 1,
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
            'field_block_id': preparedBlock.id,
            'block_sequence': 1,
            'scouting_pattern': assessment.scoutingPattern,
          },
        );
        run = await (database.select(
          database.assessmentBlockRuns,
        )..where((row) => row.id.equals(runId))).getSingle();
      }
      final preparedRun = run;

      return PreparedStation1Run(block: preparedBlock, run: preparedRun);
    });
  }

  Future<Station1Snapshot> loadSnapshot(PreparedStation1Run prepared) async {
    final station =
        await (database.select(database.stations)..where(
              (row) =>
                  row.assessmentBlockRunId.equals(prepared.run.id) &
                  row.stationNumber.equals(1) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (station == null) {
      return Station1Snapshot(
        prepared: prepared,
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
    final joined = <Station1PlantRecord>[];
    for (final plant in plants) {
      final vegetative = await (database.select(
        database.vegetativeObservations,
      )..where((row) => row.plantObservationId.equals(plant.id))).getSingle();
      joined.add(Station1PlantRecord(plant: plant, vegetative: vegetative));
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
        : _sourceAuditIdsFromReview(review!.afterJson!);
    final currentSourceAuditIds = await _reviewSourceAuditIds(
      station: station,
      plants: joined,
    );

    return Station1Snapshot(
      prepared: prepared,
      station: station,
      plants: List.unmodifiable(joined),
      reviewedAt: reviewedAt,
      reviewIsCurrent:
          joined.length == 10 &&
          reviewedAt != null &&
          _sameStrings(recordedSourceAuditIds, currentSourceAuditIds),
    );
  }

  Future<StationRecord> saveStationLocation({
    required PreparedStation1Run prepared,
    required String actorPersonId,
    double? latitude,
    double? longitude,
    double? gpsAccuracyM,
    DateTime? capturedAt,
    String? notLocatedReason,
    String? accessibilityNotes,
  }) async {
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
                    row.stationNumber.equals(1) &
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
                stationNumber: 1,
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
    required Station1Snapshot snapshot,
    required String actorPersonId,
  }) async {
    if (snapshot.station == null || snapshot.plants.length != 10) {
      throw StateError('Station 1 requires ten saved plant positions.');
    }
    await database.transaction(() async {
      final sourceAuditIds = await _reviewSourceAuditIds(
        station: snapshot.station!,
        plants: snapshot.plants,
      );
      await _mutations.record(
        entityType: 'stations',
        entityId: snapshot.station!.id,
        action: 'review_confirmed',
        actorPersonId: actorPersonId,
        after: {
          'block_sequence': 1,
          'station_number': 1,
          'plant_positions_reviewed': 10,
          'source_audit_ids': sourceAuditIds,
        },
      );
    });
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

  Future<List<String>> _reviewSourceAuditIds({
    required StationRecord station,
    required List<Station1PlantRecord> plants,
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
    final entityIds = <String>[
      station.id,
      ...plants.map((item) => item.plant.id),
      ...evidenceSessionIds,
      ...evidenceMedia.map((item) => item.id),
    ];
    final audits = await (database.select(
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
                      evidenceMedia.any((item) => item.id == audit.entityId)),
            )
            .map((audit) => audit.id)
            .toList(growable: false)
          ..sort();
    return ids;
  }

  List<String> _sourceAuditIdsFromReview(String afterJson) {
    try {
      final decoded = jsonDecode(afterJson) as Map<String, dynamic>;
      final values = decoded['source_audit_ids'] as List<dynamic>?;
      if (values == null) return const [];
      return values.whereType<String>().toList(growable: false)..sort();
    } catch (_) {
      return const [];
    }
  }

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
