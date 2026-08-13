import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class EvidenceCaptureBundle {
  const EvidenceCaptureBundle({required this.session, required this.media});

  final EvidenceCaptureSessionRecord session;
  final List<EvidenceMediaRecord> media;

  Set<String> get waivedViewTypes {
    final value = session.waivedViewTypesJson;
    if (value == null) return <String>{};
    try {
      return (jsonDecode(value) as List<dynamic>).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  EvidenceMediaRecord? mediaForView(String viewType) {
    for (final item in media.reversed) {
      if (item.viewType == viewType && item.deletedAt == null) return item;
    }
    return null;
  }

  bool hasReadyView(String viewType) =>
      mediaForView(viewType)?.storageState ==
      DatabaseCodes.evidenceStorageReady;

  bool isViewSatisfied(String viewType) =>
      hasReadyView(viewType) || waivedViewTypes.contains(viewType);
}

class PilotWorkloadAuditSummary {
  const PilotWorkloadAuditSummary({
    required this.activeTimeByPlant,
    required this.retakeCount,
    required this.manualFormUseCount,
    required this.inspectedLeavesByPlant,
    required this.guidedTapCount,
  });

  final Map<int, Duration> activeTimeByPlant;
  final int retakeCount;
  final int manualFormUseCount;
  final Map<int, int> inspectedLeavesByPlant;
  final int guidedTapCount;
}

class EvidenceCaptureRepository {
  EvidenceCaptureRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<EvidenceCaptureSessionRecord> ensureStationContextSession({
    required String assessmentId,
    required String stationId,
    required String actorPersonId,
  }) => _ensureSession(
    assessmentId: assessmentId,
    stationId: stationId,
    scopeType: DatabaseCodes.evidenceScopeStationContext,
    scopeKey: DatabaseCodes.evidenceScopeStationContext,
    plantPosition: null,
    actorPersonId: actorPersonId,
    requirementsVersion: 'camera_phase_a_v1',
  );

  Future<EvidenceCaptureSessionRecord> ensurePlantSession({
    required String assessmentId,
    required String stationId,
    required int plantPosition,
    required String actorPersonId,
  }) {
    if (plantPosition < 1 || plantPosition > 10) {
      throw ArgumentError.value(
        plantPosition,
        'plantPosition',
        'Plant position must be 1-10',
      );
    }
    return _ensureSession(
      assessmentId: assessmentId,
      stationId: stationId,
      scopeType: DatabaseCodes.evidenceScopePlant,
      scopeKey: 'plant_${plantPosition.toString().padLeft(2, '0')}',
      plantPosition: plantPosition,
      actorPersonId: actorPersonId,
      requirementsVersion: 'capture_first_station1_v1',
    );
  }

  Future<EvidenceCaptureSessionRecord> _ensureSession({
    required String assessmentId,
    required String stationId,
    required String scopeType,
    required String scopeKey,
    required int? plantPosition,
    required String actorPersonId,
    required String requirementsVersion,
  }) {
    return database.transaction(() async {
      await _validateStationAssessment(
        assessmentId: assessmentId,
        stationId: stationId,
      );
      final existing =
          await (database.select(database.evidenceCaptureSessions)..where(
                (row) =>
                    row.stationId.equals(stationId) &
                    row.scopeKey.equals(scopeKey) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (existing != null) {
        if (existing.assessmentId != assessmentId ||
            existing.scopeType != scopeType ||
            existing.plantPosition != plantPosition) {
          throw StateError(
            'The existing evidence session has the wrong scope.',
          );
        }
        if (existing.requirementsVersion != requirementsVersion) {
          final now = DateTime.now().toUtc();
          await (database.update(
            database.evidenceCaptureSessions,
          )..where((row) => row.id.equals(existing.id))).write(
            EvidenceCaptureSessionsCompanion(
              requirementsVersion: Value(requirementsVersion),
              collectionStatus: const Value(
                DatabaseCodes.evidenceSessionInProgress,
              ),
              completedAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
          await _mutations.record(
            entityType: 'evidence_capture_sessions',
            entityId: existing.id,
            action: 'capture_requirements_updated',
            actorPersonId: actorPersonId,
            before: {'requirements_version': existing.requirementsVersion},
            after: {'requirements_version': requirementsVersion},
            queueForSync: false,
          );
          return (database.select(
            database.evidenceCaptureSessions,
          )..where((row) => row.id.equals(existing.id))).getSingle();
        }
        return existing;
      }

      final id = LocalId.generate();
      await database
          .into(database.evidenceCaptureSessions)
          .insert(
            EvidenceCaptureSessionsCompanion.insert(
              id: id,
              assessmentId: assessmentId,
              stationId: stationId,
              scopeType: scopeType,
              scopeKey: scopeKey,
              plantPosition: Value(plantPosition),
              requirementsVersion: Value(requirementsVersion),
            ),
          );
      await _mutations.record(
        entityType: 'evidence_capture_sessions',
        entityId: id,
        action: 'create',
        actorPersonId: actorPersonId,
        after: {
          'assessment_id': assessmentId,
          'station_id': stationId,
          'scope_type': scopeType,
          'scope_key': scopeKey,
          'plant_position': plantPosition,
          'requirements_version': requirementsVersion,
        },
        queueForSync: false,
      );
      return (database.select(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals(id))).getSingle();
    });
  }

  Future<EvidenceCaptureBundle> loadBundle(String sessionId) async {
    final session = await (database.select(
      database.evidenceCaptureSessions,
    )..where((row) => row.id.equals(sessionId))).getSingle();
    final media =
        await (database.select(database.evidenceMedia)
              ..where((row) => row.captureSessionId.equals(sessionId))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return EvidenceCaptureBundle(session: session, media: media);
  }

  Future<List<EvidenceCaptureBundle>> loadStationBundles(
    String stationId,
  ) async {
    final sessions =
        await (database.select(database.evidenceCaptureSessions)
              ..where(
                (row) =>
                    row.stationId.equals(stationId) & row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.plantPosition)]))
            .get();
    final result = <EvidenceCaptureBundle>[];
    for (final session in sessions) {
      result.add(await loadBundle(session.id));
    }
    return result;
  }

  Future<PilotWorkloadAuditSummary> loadPilotWorkloadAuditSummary(
    String stationId,
  ) async {
    final audits =
        await (database.select(database.auditLogs)
              ..where(
                (row) =>
                    row.entityType.equals('evidence_capture_sessions') |
                    row.entityType.equals('evidence_media'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.occurredAt)]))
            .get();
    final activeMilliseconds = <int, int>{};
    final manualFormPlants = <int>{};
    final inspectedLeaves = <int, int>{};
    var guidedTapCount = 0;
    var retakes = 0;
    for (final audit in audits) {
      if (audit.afterJson == null) continue;
      Map<String, dynamic> after;
      try {
        after = jsonDecode(audit.afterJson!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (after['station_id'] != stationId) continue;
      guidedTapCount += switch (audit.action) {
        'capture_staged' => 2,
        'evaluator_accepted' => 1,
        'required_view_waived' => 3,
        'deletion_requested' => 2,
        'plant_capture_completed' =>
          2 + (after['conditional_detail_used'] == true ? 1 : 0),
        _ => 0,
      };
      if (audit.action == 'attached_to_plant' ||
          audit.action == 'plant_capture_completed') {
        final position = after['plant_position'];
        final duration = after['pilot_active_duration_ms'];
        if (position is int && duration is int && duration >= 0) {
          activeMilliseconds.update(
            position,
            (value) => value + duration,
            ifAbsent: () => duration,
          );
        }
      }
      if (audit.action == 'attached_to_plant' &&
          after['manual_form_used'] == true &&
          after['plant_position'] is int) {
        manualFormPlants.add(after['plant_position'] as int);
      }
      if (audit.action == 'plant_capture_completed' &&
          after['plant_position'] is int &&
          after['newest_leaves_inspected_count'] is int) {
        inspectedLeaves[after['plant_position'] as int] =
            after['newest_leaves_inspected_count'] as int;
      }
      if (audit.action == 'plant_capture_inspection_confirmed' &&
          after['plant_position'] is int &&
          after['newest_leaves_inspected_count'] is int) {
        inspectedLeaves[after['plant_position'] as int] =
            after['newest_leaves_inspected_count'] as int;
      }
      if (audit.action == 'deletion_requested' &&
          after['removal_intent'] == 'retake') {
        retakes++;
      }
    }
    return PilotWorkloadAuditSummary(
      activeTimeByPlant: {
        for (final entry in activeMilliseconds.entries)
          entry.key: Duration(milliseconds: entry.value),
      },
      retakeCount: retakes,
      manualFormUseCount: manualFormPlants.length,
      inspectedLeavesByPlant: inspectedLeaves,
      guidedTapCount: guidedTapCount,
    );
  }

  Future<List<EvidenceMediaRecord>> activeMediaForAssessment(
    String assessmentId,
  ) {
    return (database.select(database.evidenceMedia)..where(
          (row) =>
              row.assessmentId.equals(assessmentId) & row.deletedAt.isNull(),
        ))
        .get();
  }

  Future<EvidenceMediaRecord> insertStagedMedia({
    required String mediaId,
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String localUri,
    required String thumbnailLocalUri,
    required int byteSize,
    required String sha256Checksum,
    required int widthPx,
    required int heightPx,
    required DateTime capturedAt,
    required String actorPersonId,
  }) {
    return database.transaction(() async {
      _validateViewForSession(session, viewType);
      final current = await loadBundle(session.id);
      final active = current.mediaForView(viewType);
      if (active != null) {
        throw StateError(
          'Remove or retake the existing $viewType image first.',
        );
      }
      final waived = current.waivedViewTypes..remove(viewType);
      final fallbackCleared = waived.isEmpty;
      await (database.update(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals(session.id))).write(
        EvidenceCaptureSessionsCompanion(
          waivedViewTypesJson: Value(
            waived.isEmpty ? null : jsonEncode(waived.toList()..sort()),
          ),
          collectionStatus: const Value(
            DatabaseCodes.evidenceSessionInProgress,
          ),
          collectionMode: Value(
            fallbackCleared
                ? DatabaseCodes.evidenceCollectionCamera
                : current.session.collectionMode,
          ),
          fallbackReasonCode: fallbackCleared
              ? const Value(null)
              : const Value.absent(),
          fallbackNote: fallbackCleared
              ? const Value(null)
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await database
          .into(database.evidenceMedia)
          .insert(
            EvidenceMediaCompanion.insert(
              id: mediaId,
              assessmentId: session.assessmentId,
              stationId: Value(session.stationId),
              plantObservationId: Value(session.plantObservationId),
              captureSessionId: Value(session.id),
              mediaType: 'image',
              viewType: Value(viewType),
              localUri: localUri,
              thumbnailLocalUri: Value(thumbnailLocalUri),
              mimeType: const Value('image/jpeg'),
              byteSize: Value(byteSize),
              sha256Checksum: sha256Checksum,
              capturedAt: Value(capturedAt.toUtc()),
              captureSource: const Value(
                DatabaseCodes.evidenceCaptureSourceCamera,
              ),
              widthPx: Value(widthPx),
              heightPx: Value(heightPx),
              storageState: const Value(DatabaseCodes.evidenceStorageStaged),
              uploadState: const Value(DatabaseCodes.localOnly),
              syncState: const Value(DatabaseCodes.localOnly),
            ),
          );
      await _mutations.record(
        entityType: 'evidence_media',
        entityId: mediaId,
        action: 'capture_staged',
        actorPersonId: actorPersonId,
        after: _mediaAudit(
          session: session,
          viewType: viewType,
          checksum: sha256Checksum,
          byteSize: byteSize,
          storageState: DatabaseCodes.evidenceStorageStaged,
        ),
        queueForSync: false,
      );
      return (database.select(
        database.evidenceMedia,
      )..where((row) => row.id.equals(mediaId))).getSingle();
    });
  }

  Future<void> markReady({
    required EvidenceMediaRecord media,
    required String localUri,
    required String thumbnailLocalUri,
    required String actorPersonId,
    bool recovered = false,
  }) {
    return database.transaction(() async {
      await (database.update(
        database.evidenceMedia,
      )..where((row) => row.id.equals(media.id))).write(
        EvidenceMediaCompanion(
          localUri: Value(localUri),
          thumbnailLocalUri: Value(thumbnailLocalUri),
          storageState: const Value(DatabaseCodes.evidenceStorageReady),
          qualityStatus: const Value(
            DatabaseCodes.evidenceQualityEvaluatorConfirmed,
          ),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_media',
        entityId: media.id,
        action: recovered ? 'ready_reconciled' : 'evaluator_accepted',
        actorPersonId: actorPersonId,
        before: {'storage_state': media.storageState},
        after: {
          'station_id': media.stationId,
          'storage_state': DatabaseCodes.evidenceStorageReady,
          'sha256_checksum': media.sha256Checksum,
          'view_type': media.viewType,
        },
        queueForSync: false,
      );
    });
  }

  Future<void> markMissing({
    required EvidenceMediaRecord media,
    required String actorPersonId,
  }) {
    return database.transaction(() async {
      await (database.update(
        database.evidenceMedia,
      )..where((row) => row.id.equals(media.id))).write(
        EvidenceMediaCompanion(
          storageState: const Value(DatabaseCodes.evidenceStorageMissing),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_media',
        entityId: media.id,
        action: 'file_missing',
        actorPersonId: actorPersonId,
        before: {'storage_state': media.storageState},
        after: {
          'storage_state': DatabaseCodes.evidenceStorageMissing,
          'sha256_checksum': media.sha256Checksum,
          'view_type': media.viewType,
        },
        queueForSync: false,
      );
    });
  }

  Future<void> waiveRequiredView({
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String reasonCode,
    required String actorPersonId,
    String? note,
  }) {
    if (!DatabaseCodes.evidenceFallbackReasons.contains(reasonCode)) {
      throw ArgumentError.value(reasonCode, 'reasonCode', 'Unsupported reason');
    }
    _validateViewForSession(session, viewType);
    return database.transaction(() async {
      final current = await loadBundle(session.id);
      final waived = current.waivedViewTypes..add(viewType);
      final now = DateTime.now().toUtc();
      await (database.update(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals(session.id))).write(
        EvidenceCaptureSessionsCompanion(
          collectionMode: const Value(
            DatabaseCodes.evidenceCollectionCameraWithFallback,
          ),
          collectionStatus: const Value(
            DatabaseCodes.evidenceSessionManualFallback,
          ),
          waivedViewTypesJson: Value(jsonEncode(waived.toList()..sort())),
          fallbackReasonCode: Value(reasonCode),
          fallbackNote: Value(
            note?.trim().isEmpty == true ? null : note?.trim(),
          ),
          updatedAt: Value(now),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_capture_sessions',
        entityId: session.id,
        action: 'required_view_waived',
        actorPersonId: actorPersonId,
        after: {
          'station_id': session.stationId,
          'plant_position': session.plantPosition,
          'view_type': viewType,
          'reason_code': reasonCode,
          'note': note,
          'waived_view_types': waived.toList()..sort(),
        },
        reason: reasonCode,
        queueForSync: false,
      );
    });
  }

  Future<void> markDeletionPending({
    required EvidenceMediaRecord media,
    required String actorPersonId,
    required String removalIntent,
  }) async {
    await database.transaction(() async {
      await (database.update(
        database.evidenceMedia,
      )..where((row) => row.id.equals(media.id))).write(
        EvidenceMediaCompanion(
          storageState: const Value(
            DatabaseCodes.evidenceStorageDeletionPending,
          ),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_media',
        entityId: media.id,
        action: 'deletion_requested',
        actorPersonId: actorPersonId,
        after: {
          'view_type': media.viewType,
          'station_id': media.stationId,
          'removal_intent': removalIntent,
          'sha256_checksum': media.sha256Checksum,
          'storage_state': DatabaseCodes.evidenceStorageDeletionPending,
        },
        queueForSync: false,
      );
    });
  }

  Future<void> finalizeDeletion({
    required EvidenceMediaRecord media,
    required String actorPersonId,
    bool recovered = false,
  }) async {
    await database.transaction(() async {
      final now = DateTime.now().toUtc();
      await (database.update(
        database.evidenceMedia,
      )..where((row) => row.id.equals(media.id))).write(
        EvidenceMediaCompanion(
          storageState: const Value(DatabaseCodes.evidenceStorageDeleted),
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_media',
        entityId: media.id,
        action: recovered ? 'deletion_reconciled' : 'deleted',
        actorPersonId: actorPersonId,
        after: {
          'view_type': media.viewType,
          'sha256_checksum': media.sha256Checksum,
          'byte_size': media.byteSize,
          'file_retained': false,
          'storage_state': DatabaseCodes.evidenceStorageDeleted,
        },
        queueForSync: false,
      );
    });
  }

  Future<void> completeStationContext({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
  }) async {
    final bundle = await loadBundle(session.id);
    if (bundle.session.scopeType != DatabaseCodes.evidenceScopeStationContext ||
        !bundle.isViewSatisfied(DatabaseCodes.evidenceViewStationContext)) {
      throw StateError(
        'Accept the station-context image or document manual fallback.',
      );
    }
    await database.transaction(() async {
      final fallback = bundle.waivedViewTypes.isNotEmpty;
      final now = DateTime.now().toUtc();
      await (database.update(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals(session.id))).write(
        EvidenceCaptureSessionsCompanion(
          collectionStatus: Value(
            fallback
                ? DatabaseCodes.evidenceSessionManualFallback
                : DatabaseCodes.evidenceSessionComplete,
          ),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_capture_sessions',
        entityId: session.id,
        action: 'station_context_completed',
        actorPersonId: actorPersonId,
        after: {
          'station_id': session.stationId,
          'station_context_documented': !fallback,
          'manual_fallback': fallback,
          'sampling_procedure_proven': false,
        },
        queueForSync: false,
      );
    });
  }

  Future<void> completePlantCapture({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
    required int pilotActiveDurationMs,
    required int newestLeavesInspectedCount,
  }) async {
    if (pilotActiveDurationMs < 0) {
      throw ArgumentError.value(
        pilotActiveDurationMs,
        'pilotActiveDurationMs',
        'Capture duration cannot be negative',
      );
    }
    if (newestLeavesInspectedCount != 3 && newestLeavesInspectedCount != 4) {
      throw ArgumentError.value(
        newestLeavesInspectedCount,
        'newestLeavesInspectedCount',
        'Capture completion requires inspection of 3 or 4 newest leaves',
      );
    }
    final bundle = await loadBundle(session.id);
    if (bundle.session.scopeType != DatabaseCodes.evidenceScopePlant ||
        bundle.session.plantPosition == null) {
      throw StateError('This is not a plant evidence session.');
    }
    const requiredViews = {
      DatabaseCodes.evidenceViewWhorlOverview,
      DatabaseCodes.evidenceViewCloseUp,
    };
    for (final viewType in requiredViews) {
      if (!bundle.isViewSatisfied(viewType)) {
        throw StateError(
          'Accept the required $viewType image or document manual fallback.',
        );
      }
    }

    await database.transaction(() async {
      final fallback = bundle.waivedViewTypes
          .intersection(requiredViews)
          .isNotEmpty;
      final now = DateTime.now().toUtc();
      await (database.update(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals(session.id))).write(
        EvidenceCaptureSessionsCompanion(
          collectionStatus: Value(
            fallback
                ? DatabaseCodes.evidenceSessionManualFallback
                : DatabaseCodes.evidenceSessionComplete,
          ),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _mutations.record(
        entityType: 'evidence_capture_sessions',
        entityId: session.id,
        action: 'plant_capture_completed',
        actorPersonId: actorPersonId,
        after: {
          'station_id': session.stationId,
          'plant_position': session.plantPosition,
          'required_view_types': requiredViews.toList()..sort(),
          'waived_view_types': bundle.waivedViewTypes.toList()..sort(),
          'pilot_active_duration_ms': pilotActiveDurationMs,
          'newest_leaves_inspected_count': newestLeavesInspectedCount,
          'conditional_detail_used': bundle.isViewSatisfied(
            DatabaseCodes.evidenceViewDiagnosticDetail,
          ),
        },
        queueForSync: false,
      );
    });
  }

  Future<void> recordPlantCaptureInspection({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
    required int newestLeavesInspectedCount,
  }) async {
    if (session.scopeType != DatabaseCodes.evidenceScopePlant ||
        session.plantPosition == null) {
      throw StateError('This is not a plant evidence session.');
    }
    if (newestLeavesInspectedCount != 3 && newestLeavesInspectedCount != 4) {
      throw ArgumentError.value(
        newestLeavesInspectedCount,
        'newestLeavesInspectedCount',
        'Plant capture requires inspection of 3 or 4 newest leaves',
      );
    }
    await _mutations.record(
      entityType: 'evidence_capture_sessions',
      entityId: session.id,
      action: 'plant_capture_inspection_confirmed',
      actorPersonId: actorPersonId,
      after: {
        'station_id': session.stationId,
        'plant_position': session.plantPosition,
        'newest_leaves_inspected_count': newestLeavesInspectedCount,
      },
      queueForSync: false,
    );
  }

  /// Runs inside the plant save transaction. File promotion happens earlier;
  /// a rollback therefore leaves evidence safely scoped to station + position.
  Future<void> attachPlantEvidenceInCurrentTransaction({
    required String sessionId,
    required String stationId,
    required int plantPosition,
    required String plantObservationId,
    required Set<String> requiredViewTypes,
    required String actorPersonId,
    required int pilotActiveDurationMs,
    required bool manualFormUsed,
  }) async {
    final bundle = await loadBundle(sessionId);
    final session = bundle.session;
    if (session.stationId != stationId ||
        session.scopeType != DatabaseCodes.evidenceScopePlant ||
        session.plantPosition != plantPosition) {
      throw StateError('Evidence does not match the active station and plant.');
    }
    for (final viewType in requiredViewTypes) {
      if (!bundle.isViewSatisfied(viewType)) {
        throw StateError(
          'Accept the required $viewType image or document manual fallback.',
        );
      }
    }

    final now = DateTime.now().toUtc();
    await (database.update(database.evidenceMedia)..where(
          (row) =>
              row.captureSessionId.equals(session.id) &
              row.deletedAt.isNull() &
              row.storageState.equals(DatabaseCodes.evidenceStorageReady),
        ))
        .write(
          EvidenceMediaCompanion(
            plantObservationId: Value(plantObservationId),
            updatedAt: Value(now),
          ),
        );
    final fallback = bundle.waivedViewTypes.isNotEmpty;
    await (database.update(
      database.evidenceCaptureSessions,
    )..where((row) => row.id.equals(session.id))).write(
      EvidenceCaptureSessionsCompanion(
        plantObservationId: Value(plantObservationId),
        collectionStatus: Value(
          fallback
              ? DatabaseCodes.evidenceSessionManualFallback
              : DatabaseCodes.evidenceSessionComplete,
        ),
        completedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _mutations.record(
      entityType: 'evidence_capture_sessions',
      entityId: session.id,
      action: 'attached_to_plant',
      actorPersonId: actorPersonId,
      after: {
        'station_id': stationId,
        'plant_position': plantPosition,
        'plant_observation_id': plantObservationId,
        'required_view_types': requiredViewTypes.toList()..sort(),
        'waived_view_types': bundle.waivedViewTypes.toList()..sort(),
        'pilot_active_duration_ms': pilotActiveDurationMs,
        'manual_form_used': manualFormUsed,
      },
      queueForSync: false,
    );
  }

  Future<void> _validateStationAssessment({
    required String assessmentId,
    required String stationId,
  }) async {
    final station = await (database.select(
      database.stations,
    )..where((row) => row.id.equals(stationId))).getSingle();
    final run = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(station.assessmentBlockRunId))).getSingle();
    if (run.assessmentId != assessmentId) {
      throw StateError('The evidence station belongs to another assessment.');
    }
  }

  void _validateViewForSession(
    EvidenceCaptureSessionRecord session,
    String viewType,
  ) {
    final allowed =
        session.scopeType == DatabaseCodes.evidenceScopeStationContext
        ? const {DatabaseCodes.evidenceViewStationContext}
        : session.scopeType == DatabaseCodes.evidenceScopePlant
        ? const {
            DatabaseCodes.evidenceViewWhorlOverview,
            DatabaseCodes.evidenceViewCloseUp,
            DatabaseCodes.evidenceViewDiagnosticDetail,
          }
        : const <String>{};
    if (!allowed.contains(viewType)) {
      throw ArgumentError.value(
        viewType,
        'viewType',
        'The evidence view does not match this capture session',
      );
    }
  }

  Map<String, Object?> _mediaAudit({
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String checksum,
    required int byteSize,
    required String storageState,
  }) {
    return {
      'assessment_id': session.assessmentId,
      'station_id': session.stationId,
      'capture_session_id': session.id,
      'plant_position': session.plantPosition,
      'view_type': viewType,
      'sha256_checksum': checksum,
      'byte_size': byteSize,
      'storage_state': storageState,
      'upload_state': DatabaseCodes.localOnly,
    };
  }
}
