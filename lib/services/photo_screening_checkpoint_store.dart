import 'dart:convert';
import '../data/local/app_database.dart';
import '../data/repositories/field_repository.dart';
import '../models/automatic_screening.dart';
import 'computer_vision/faw_computer_vision_service.dart';

/// Owns the durable per-photo screening contract, independent of UI state.
class PhotoScreeningCheckpointStore {
  PhotoScreeningCheckpointStore(AppDatabase database)
    : repository = FieldRepository(database);
  final FieldRepository repository;
  Future<PlantDiagnosisResult?> read(
    EvidenceMediaRecord media,
    String pipeline,
  ) async => AutomaticScreening.photoCheckpoint(
    await repository.readPreferenceValue('evidence_model_${media.id}'),
    evidenceId: media.id,
    checksum: media.sha256Checksum,
    pipelineVersion: pipeline,
  );
  Future<void> save(
    EvidenceMediaRecord media,
    PlantDiagnosisResult result,
    String pipeline,
  ) async {
    final json = result.toJson();
    json['detectionBoxes'] = [
      for (final box in result.detectionBoxes.take(100))
        Map<String, dynamic>.from(box.toJson())..remove('sourcePath'),
    ];
    await repository.savePreferenceValue(
      'evidence_model_${media.id}',
      jsonEncode({
        'schema_version': 1,
        'pipelineVersion': pipeline,
        'evidence_id': media.id,
        'sha256': media.sha256Checksum,
        'analyzed_at': DateTime.now().toUtc().toIso8601String(),
        'detector_used': result.classifierStage == 'overlay_complete',
        'result': json,
      }),
    );
  }
}
