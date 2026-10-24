import 'evidence_reconciliation_service.dart';
import 'prepared_capture_store.dart';
import 'dart:io';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/local/local_id.dart';
import '../data/repositories/evidence_capture_repository.dart';
import 'evidence_storage_service.dart';

class PilotWorkloadMetrics {
  const PilotWorkloadMetrics({
    required this.activeTimeByPlant,
    required this.retakeCount,
    required this.acceptedImageCount,
    required this.manualFallbackCount,
    this.manualFormUseCount = 0,
    this.guidedTapCount = 0,
    required this.storageBytes,
  });

  final Map<int, Duration> activeTimeByPlant;
  final int retakeCount;
  final int acceptedImageCount;
  final int manualFallbackCount;
  final int manualFormUseCount;
  final int guidedTapCount;
  final int storageBytes;

  static const empty = PilotWorkloadMetrics(
    activeTimeByPlant: {},
    retakeCount: 0,
    acceptedImageCount: 0,
    manualFallbackCount: 0,
    manualFormUseCount: 0,
    guidedTapCount: 0,
    storageBytes: 0,
  );
}

class EvidenceCaptureCoordinator {
  factory EvidenceCaptureCoordinator({
    required EvidenceCaptureRepository repository,
    required EvidenceStorageService storage,
  }) => EvidenceCaptureCoordinator._(repository, storage);

  EvidenceCaptureCoordinator._(this._repository, this._storage);

  final EvidenceCaptureRepository _repository;
  final EvidenceStorageService _storage;

  EvidenceCaptureRepository get repository => _repository;
  late final _prepared = PreparedCaptureStore(_storage);

  Future<EvidenceCaptureBundle> ensureStationContext({
    required String assessmentId,
    required String stationId,
    required String actorPersonId,
  }) async {
    final session = await _repository.ensureStationContextSession(
      assessmentId: assessmentId,
      stationId: stationId,
      actorPersonId: actorPersonId,
    );
    return _repository.loadBundle(session.id);
  }

  Future<EvidenceCaptureBundle> ensurePlant({
    required String assessmentId,
    required String stationId,
    required int plantPosition,
    required String actorPersonId,
    String requirementsVersion = DatabaseCodes.evidencePolicyStation1TwoViewV1,
    String? sourcePlantingUnitObservationId,
  }) async {
    final session = await _repository.ensurePlantSession(
      assessmentId: assessmentId,
      stationId: stationId,
      plantPosition: plantPosition,
      actorPersonId: actorPersonId,
      requirementsVersion: requirementsVersion,
      sourcePlantingUnitObservationId: sourcePlantingUnitObservationId,
    );
    return _repository.loadBundle(session.id);
  }

  Future<EvidenceCaptureBundle> ensurePlantingUnit({
    required String assessmentId,
    required String stationId,
    required int sequenceNumber,
    required String actorPersonId,
  }) async {
    final session = await _repository.ensurePlantingUnitSession(
      assessmentId: assessmentId,
      stationId: stationId,
      sequenceNumber: sequenceNumber,
      actorPersonId: actorPersonId,
    );
    return _repository.loadBundle(session.id);
  }

  Future<EvidenceCaptureBundle> ensureVeRowContext({
    required String assessmentId,
    required String stationId,
    required String actorPersonId,
  }) async {
    final session = await _repository.ensureVeRowContextSession(
      assessmentId: assessmentId,
      stationId: stationId,
      actorPersonId: actorPersonId,
    );
    return _repository.loadBundle(session.id);
  }

  Future<EvidenceCaptureBundle> stageCapture({
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String sourcePath,
    required String actorPersonId,
    bool deleteSourceAfterCopy = true,
    String? stableMediaId,
  }) async {
    final mediaId = stableMediaId ?? LocalId.generate();
    StoredEvidenceFile? stored;
    var registered = false;
    var journaled = false;
    try {
      final current = await _repository.loadBundle(session.id);
      final previous = current.mediaForView(viewType);
      if (previous?.id == mediaId) {
        throw StateError('This evidence identifier is already registered.');
      }
      stored = await _storage.stageCapturedFile(
        sourcePath: sourcePath,
        assessmentId: session.assessmentId,
        stationId: session.stationId,
        scopeKey: session.scopeKey,
        mediaId: mediaId,
        deleteSourceAfterCopy: false,
      );
      final capturedAt = DateTime.now().toUtc();
      await _prepared.prepare(
        session: current.session,
        mediaId: mediaId,
        actorId: actorPersonId,
        viewType: viewType,
        stored: stored,
        previousId: previous?.id,
        capturedAt: capturedAt,
      );
      journaled = true;
      await _repository.insertStagedMedia(
        mediaId: mediaId,
        session: session,
        viewType: viewType,
        localUri: stored.localUri,
        thumbnailLocalUri: stored.thumbnailLocalUri,
        byteSize: stored.byteSize,
        sha256Checksum: stored.sha256Checksum,
        widthPx: stored.widthPx,
        heightPx: stored.heightPx,
        capturedAt: capturedAt,
        actorPersonId: actorPersonId,
      );
      registered = true;
      await _prepared.finish(stored.localUri);
      if (previous != null) {
        try {
          await _storage.deleteArtifacts(
            localUri: previous.localUri,
            thumbnailLocalUri: previous.thumbnailLocalUri,
          );
        } on FileSystemException {
          // The replacement is committed. Keep its success even if an old
          // tombstone's private files cannot be cleaned up on this attempt.
        }
      }
      if (deleteSourceAfterCopy) await _storage.discardSource(sourcePath);
      return await _repository.loadBundle(session.id);
    } catch (_) {
      if (stored != null && !registered && !journaled) {
        await _storage.deleteArtifacts(
          localUri: stored.localUri,
          thumbnailLocalUri: stored.thumbnailLocalUri,
        );
      }
      rethrow;
    }
  }

  Future<EvidenceCaptureBundle> accept({
    required EvidenceMediaRecord media,
    required String actorPersonId,
  }) async {
    if (media.captureSessionId == null || media.thumbnailLocalUri == null) {
      throw StateError('The evidence record is missing its capture session.');
    }
    if (media.storageState != DatabaseCodes.evidenceStorageStaged) {
      throw StateError('Only a staged preview can be accepted.');
    }
    final ready = await _storage.promote(
      localUri: media.localUri,
      thumbnailLocalUri: media.thumbnailLocalUri!,
    );
    await _repository.markReady(
      media: media,
      localUri: ready.localUri,
      thumbnailLocalUri: ready.thumbnailLocalUri,
      actorPersonId: actorPersonId,
    );
    return _repository.loadBundle(media.captureSessionId!);
  }

  Future<EvidenceCaptureBundle> remove({
    required EvidenceMediaRecord media,
    required String actorPersonId,
    bool retake = false,
  }) async {
    final sessionId = media.captureSessionId;
    if (sessionId == null) {
      throw StateError('The evidence record is missing its capture session.');
    }
    await _repository.markDeletionPending(
      media: media,
      actorPersonId: actorPersonId,
      removalIntent: retake ? 'retake' : 'remove',
    );
    await _storage.deleteArtifacts(
      localUri: media.localUri,
      thumbnailLocalUri: media.thumbnailLocalUri,
    );
    await _repository.finalizeDeletion(
      media: media,
      actorPersonId: actorPersonId,
    );
    return _repository.loadBundle(sessionId);
  }

  Future<EvidenceCaptureBundle> waive({
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String reasonCode,
    required String actorPersonId,
    String? note,
  }) async {
    await _repository.waiveRequiredView(
      session: session,
      viewType: viewType,
      reasonCode: reasonCode,
      actorPersonId: actorPersonId,
      note: note,
    );
    return _repository.loadBundle(session.id);
  }

  Future<void> completeStationContext({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
  }) => _repository.completeStationContext(
    session: session,
    actorPersonId: actorPersonId,
  );

  Future<void> completePlantCapture({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
    required Duration activeDuration,
    required int? newestLeavesInspectedCount,
    Set<String> requiredViewTypes = const {
      DatabaseCodes.evidenceViewWhorlOverview,
      DatabaseCodes.evidenceViewCloseUp,
    },
  }) => _repository.completePlantCapture(
    session: session,
    actorPersonId: actorPersonId,
    pilotActiveDurationMs: activeDuration.inMilliseconds,
    newestLeavesInspectedCount: newestLeavesInspectedCount,
    requiredViewTypes: requiredViewTypes,
  );

  Future<void> recordPlantCaptureInspection({
    required EvidenceCaptureSessionRecord session,
    required String actorPersonId,
    required int newestLeavesInspectedCount,
  }) => _repository.recordPlantCaptureInspection(
    session: session,
    actorPersonId: actorPersonId,
    newestLeavesInspectedCount: newestLeavesInspectedCount,
  );

  Future<File> resolve(String localUri) => _storage.resolve(localUri);

  Future<PilotWorkloadMetrics> loadPilotWorkloadMetrics(
    String stationId,
  ) async {
    final bundles = await _repository.loadStationBundles(stationId);
    final audit = await _repository.loadPilotWorkloadAuditSummary(stationId);
    var accepted = 0;
    var fallbacks = 0;
    var storageBytes = 0;
    for (final bundle in bundles) {
      fallbacks += bundle.waivedViewTypes.length;
      for (final media in bundle.media) {
        if (media.deletedAt != null ||
            media.storageState != DatabaseCodes.evidenceStorageReady) {
          continue;
        }
        accepted++;
        for (final uri in {
          media.localUri,
          if (media.thumbnailLocalUri != null) media.thumbnailLocalUri!,
        }) {
          final file = await _storage.resolve(uri);
          if (await file.exists()) storageBytes += await file.length();
        }
      }
    }
    return PilotWorkloadMetrics(
      activeTimeByPlant: audit.activeTimeByPlant,
      retakeCount: audit.retakeCount,
      acceptedImageCount: accepted,
      manualFallbackCount: fallbacks,
      manualFormUseCount: audit.manualFormUseCount,
      guidedTapCount: audit.guidedTapCount,
      storageBytes: storageBytes,
    );
  }

  /// Returns unresolved descriptors; they remain private and are never discarded
  /// as orphans. Matching committed entries are safe to replay repeatedly.
  Future<int> recoverPreparedCaptures() async {
    var unresolved = 0;
    for (final file in await _prepared.pending()) {
      try {
        final data = await _prepared.read(file);
        final db = _repository.database;
        final session =
            await (db.select(db.evidenceCaptureSessions)
                  ..where((s) => s.id.equals(data['session_id'] as String)))
                .getSingleOrNull();
        // Other account/guest views must never acquire this capture.
        if (session == null) continue;
        if (session.deletedAt != null ||
            session.assessmentId != data['assessment_id'] ||
            session.stationId != data['station_id'] ||
            session.scopeKey != data['scope_key']) {
          unresolved++;
          continue;
        }
        final assessment = await (db.select(
          db.assessments,
        )..where((a) => a.id.equals(session.assessmentId))).getSingle();
        if (assessment.deletedAt != null ||
            assessment.evaluatorPersonId != data['actor_id']) {
          unresolved++;
          continue;
        }
        final bundle = await _repository.loadBundle(session.id);
        final current = bundle.mediaForView(data['view_type'] as String);
        if (current?.id == data['media_id']) {
          await file.delete();
          continue;
        }
        if (current != null &&
            current.id != data['previous_id'] &&
            current.storageState == DatabaseCodes.evidenceStorageReady &&
            current.capturedAt?.isAfter(
                  DateTime.parse(data['captured_at'] as String),
                ) ==
                true) {
          // An explicitly accepted newer photo supersedes this unfinished save.
          await _storage.deleteArtifacts(
            localUri: data['local_uri'] as String,
            thumbnailLocalUri: data['thumbnail_uri'] as String,
          );
          await file.delete();
          continue;
        }

        if (current?.id != data['previous_id'] ||
            session.updatedAt.toUtc().toIso8601String() !=
                data['session_updated_at'] ||
            !await _storage.exists(data['local_uri'] as String)) {
          unresolved++;
          continue;
        }
        await _repository.insertStagedMedia(
          mediaId: data['media_id'] as String,
          session: session,
          viewType: data['view_type'] as String,
          localUri: data['local_uri'] as String,
          thumbnailLocalUri: data['thumbnail_uri'] as String,
          byteSize: data['byte_size'] as int,
          sha256Checksum: data['sha256'] as String,
          widthPx: data['width'] as int,
          heightPx: data['height'] as int,
          capturedAt: DateTime.parse(data['captured_at'] as String),
          actorPersonId: data['actor_id'] as String,
        );
        await file.delete();
      } catch (_) {
        unresolved++;
      }
    }
    return unresolved;
  }

  Future<void> reconcileAssessment({
    required String assessmentId,
    required String actorPersonId,
  }) =>
      EvidenceReconciliationService(_repository, _storage).reconcileAssessment(
        assessmentId: assessmentId,
        actorPersonId: actorPersonId,
      );
}
