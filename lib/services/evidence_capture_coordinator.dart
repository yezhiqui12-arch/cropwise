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
  }) async {
    final session = await _repository.ensurePlantSession(
      assessmentId: assessmentId,
      stationId: stationId,
      plantPosition: plantPosition,
      actorPersonId: actorPersonId,
      requirementsVersion: requirementsVersion,
    );
    return _repository.loadBundle(session.id);
  }

  Future<EvidenceCaptureBundle> stageCapture({
    required EvidenceCaptureSessionRecord session,
    required String viewType,
    required String sourcePath,
    required String actorPersonId,
    bool deleteSourceAfterCopy = true,
  }) async {
    final mediaId = LocalId.generate();
    StoredEvidenceFile? stored;
    try {
      stored = await _storage.stageCapturedFile(
        sourcePath: sourcePath,
        assessmentId: session.assessmentId,
        stationId: session.stationId,
        scopeKey: session.scopeKey,
        mediaId: mediaId,
        deleteSourceAfterCopy: deleteSourceAfterCopy,
      );
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
        capturedAt: DateTime.now().toUtc(),
        actorPersonId: actorPersonId,
      );
      return _repository.loadBundle(session.id);
    } catch (_) {
      if (stored != null) {
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
    required int newestLeavesInspectedCount,
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

  Future<void> reconcileAssessment({
    required String assessmentId,
    required String actorPersonId,
  }) async {
    final media = await _repository.activeMediaForAssessment(assessmentId);
    if (media.isEmpty) return;
    for (final item in media) {
      switch (item.storageState) {
        case DatabaseCodes.evidenceStorageStaged:
          if (await _storage.exists(item.localUri)) break;
          final readyUri = _storage.readyUriFor(item.localUri);
          if (await _storage.exists(readyUri)) {
            await _repository.markReady(
              media: item,
              localUri: readyUri,
              thumbnailLocalUri: item.thumbnailLocalUri == null
                  ? readyUri
                  : _storage.readyUriFor(item.thumbnailLocalUri!),
              actorPersonId: actorPersonId,
              recovered: true,
            );
          } else {
            await _repository.markMissing(
              media: item,
              actorPersonId: actorPersonId,
            );
          }
        case DatabaseCodes.evidenceStorageReady:
          if (!await _storage.exists(item.localUri)) {
            await _repository.markMissing(
              media: item,
              actorPersonId: actorPersonId,
            );
          }
        case DatabaseCodes.evidenceStorageDeletionPending:
          await _storage.deleteArtifacts(
            localUri: item.localUri,
            thumbnailLocalUri: item.thumbnailLocalUri,
          );
          await _repository.finalizeDeletion(
            media: item,
            actorPersonId: actorPersonId,
            recovered: true,
          );
        case DatabaseCodes.evidenceStorageMissing:
          if (await _storage.exists(item.localUri)) {
            await _repository.markReady(
              media: item,
              localUri: item.localUri,
              thumbnailLocalUri: item.thumbnailLocalUri ?? item.localUri,
              actorPersonId: actorPersonId,
              recovered: true,
            );
          }
        case DatabaseCodes.evidenceStorageDeleted:
          // Deleted rows are tombstones and are not returned by the active query.
          break;
        default:
          await _repository.markMissing(
            media: item,
            actorPersonId: actorPersonId,
          );
      }
    }

    final refreshed = await _repository.activeMediaForAssessment(assessmentId);
    final referenced = <String>{
      for (final item in refreshed) item.localUri,
      for (final item in refreshed)
        if (item.thumbnailLocalUri != null) item.thumbnailLocalUri!,
    };
    final files = await _storage.listRelativeFiles(assessmentId);
    for (final path in files) {
      if (path.contains('/staging/') && !referenced.contains(path)) {
        final orphan = await _storage.resolve(path);
        if (await orphan.exists()) await orphan.delete();
      }
    }
  }
}
