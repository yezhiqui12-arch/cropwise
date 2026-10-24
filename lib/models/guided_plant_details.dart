import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../services/computer_vision/faw_computer_vision_service.dart';
import 'da_monitoring.dart';

/// Opening a pin never changes the active scouting plant or model result.
/// Optional DA report observations are stored separately in [monitoring].
class GuidedPlantDetails {
  const GuidedPlantDetails({
    required this.snapshot,
    this.evidence,
    this.diagnosis,
    this.monitoring,
  });
  final StationSnapshot snapshot;
  final EvidenceCaptureBundle? evidence;
  final PlantDiagnosisResult? diagnosis;
  final DaMonitoringRecord? monitoring;
  PlantObservationRecord? get plant => snapshot.plants.firstOrNull?.plant;
  List<EvidenceMediaRecord> get photos =>
      evidence?.media
          .where(
            (m) =>
                m.deletedAt == null &&
                m.storageState == DatabaseCodes.evidenceStorageReady,
          )
          .toList() ??
      const [];
  String get samplingStatus => snapshot.reviewIsCurrent
      ? 'Sampled'
      : photos.isNotEmpty || plant != null
      ? 'In progress'
      : 'Not sampled';
}
