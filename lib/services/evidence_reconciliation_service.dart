import '../data/local/database_codes.dart';
import '../data/repositories/evidence_capture_repository.dart';
import 'evidence_storage_service.dart';
import 'prepared_capture_store.dart';

/// Repairs file transitions independently from capture and workflow UI state.
class EvidenceReconciliationService {
  EvidenceReconciliationService(this._repository, this._storage);
  final EvidenceCaptureRepository _repository;
  final EvidenceStorageService _storage;
  late final _prepared = PreparedCaptureStore(_storage);
  Future<void> reconcileAssessment({
    required String assessmentId,
    required String actorPersonId,
  }) async {
    final db = _repository.database;
    final all = await (db.select(
      db.evidenceMedia,
    )..where((m) => m.assessmentId.equals(assessmentId))).get();
    final media = all.where((m) => m.deletedAt == null).toList();
    final retained = {
      for (final m in media) m.localUri,
      for (final m in media) _storage.readyUriFor(m.localUri),
      for (final m in media)
        if (m.thumbnailLocalUri != null) m.thumbnailLocalUri!,
    };
    for (final tombstone in all.where(
      (m) =>
          m.deletedAt != null &&
          m.storageState == DatabaseCodes.evidenceStorageDeleted,
    )) {
      if (!retained.contains(tombstone.localUri) &&
          !retained.contains(_storage.readyUriFor(tombstone.localUri))) {
        await _storage.deleteArtifacts(
          localUri: tombstone.localUri,
          thumbnailLocalUri: tombstone.thumbnailLocalUri,
        );
      }
    }
    if (media.isEmpty) return;
    for (final item in media) {
      switch (item.storageState) {
        case DatabaseCodes.evidenceStorageStaged:
          if (await _storage.exists(item.localUri)) {
            if (item.thumbnailLocalUri != null) {
              await _storage.repairThumbnail(
                item.localUri,
                item.thumbnailLocalUri!,
              );
            }
            break;
          }
          final readyUri = _storage.readyUriFor(item.localUri);
          if (await _storage.exists(readyUri)) {
            await _storage.promote(
              localUri: item.localUri,
              thumbnailLocalUri:
                  item.thumbnailLocalUri ?? '${item.localUri}_thumb.jpg',
            );
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
          if (await _storage.exists(item.localUri) &&
              item.thumbnailLocalUri != null) {
            await _storage.repairThumbnail(
              item.localUri,
              item.thumbnailLocalUri!,
            );
          }
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
            if (item.thumbnailLocalUri != null) {
              await _storage.repairThumbnail(
                item.localUri,
                item.thumbnailLocalUri!,
              );
            }
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
    if (await _prepared.hasPending(assessmentId)) return;
    final files = await _storage.listRelativeFiles(assessmentId);
    for (final path in files) {
      if (path.contains('/staging/') && !referenced.contains(path)) {
        final orphan = await _storage.resolve(path);
        if (await orphan.exists()) await orphan.delete();
      }
    }
  }
}
