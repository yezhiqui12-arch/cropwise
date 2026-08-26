import '../data/repositories/field_repository.dart';
import 'evidence_storage_service.dart';

class FieldRetentionService {
  FieldRetentionService(
    this._repository, {
    EvidenceStorageService? evidenceStorage,
  }) : _evidenceStorage = evidenceStorage ?? EvidenceStorageService();

  final FieldRepository _repository;
  final EvidenceStorageService _evidenceStorage;

  Future<int> purgeExpired({DateTime? nowUtc}) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final candidates = await _repository.expiredDeletionCandidates(now);
    var purged = 0;
    for (final candidate in candidates) {
      for (final media in candidate.media) {
        await _evidenceStorage.deleteArtifacts(
          localUri: media.localUri,
          thumbnailLocalUri: media.thumbnailLocalUri,
        );
      }
      await _repository.finalizeExpiredDeletion(
        candidate: candidate,
        deletedAtUtc: now,
      );
      purged++;
    }
    return purged;
  }
}
