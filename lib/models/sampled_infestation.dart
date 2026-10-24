import '../services/computer_vision/faw_computer_vision_service.dart';
import '../services/cloud/expert_review_service.dart';
import 'da_assessment_results.dart';
import '../data/repositories/scouting_workflow_repository.dart';

/// Provisional presence screening: eggs, larvae or frass count; damage alone is excluded.
/// Null means detection was skipped, failed or otherwise unavailable.
bool? modelSampledInfestation(PlantDiagnosisResult? model) {
  if (model == null) return null;
  if (model.detectionBoxes.any(
    (b) => b.classId == 1 || b.classId == 2 || b.classId == 3,
  )) {
    return true;
  }
  return model.classifierStage == 'overlay_complete' ? false : null;
}

bool? expertSampledInfestation(ExpertPlantRating? rating) {
  if (rating?.outcome != 'scored' ||
      rating!.associationAmbiguous ||
      rating.davisScore == null ||
      rating.davisScore! < 0 ||
      rating.davisScore! > 9) {
    return null;
  }
  if (rating.davisScore == 0) return false;
  return switch (rating.damageFreshness) {
    'fresh' => true,
    'old_only' => false,
    _ => null,
  };
}

class DaSampledInfestation {
  DaSampledInfestation(
    this.sample, {
    this.finalized = false,
    DaExpertResults? expert,
  }) {
    for (final plant in sample.plants) {
      bool? value;
      if (finalized) {
        value = expert?.available == true
            ? expertSampledInfestation(expert!.ratingFor(plant))
            : null;
      } else {
        final screening = sample.screening(plant);
        final signature = screening?.evidenceSignature;
        final checksums =
            sample.photos(plant).map((e) => e.media.sha256Checksum).toList()
              ..sort();
        final current =
            signature == null ||
            (checksums.isNotEmpty && signature == checksums.join(':'));
        value = current ? modelSampledInfestation(screening?.result) : null;
      }
      values['${plant.prepared.run.id}:${plant.stationNumber}'] = value;
    }
  }
  final DaSampleResults sample;
  final bool finalized;
  final Map<String, bool?> values = {};
  bool? forPlant(StationSnapshot plant) =>
      values['${plant.prepared.run.id}:${plant.stationNumber}'];
  int get infested => values.values.where((v) => v == true).length;
  int get notInfested => values.values.where((v) => v == false).length;
  int get assessable => infested + notInfested;
  int get unavailable => sample.expectedPlants - assessable;
  int get denominator => finalized ? assessable : sample.expectedPlants;
  double? get percent =>
      assessable == 0 || denominator <= 0 ? null : infested / denominator * 100;
  String get source => finalized
      ? 'Expert-assessed fresh damage'
      : 'Provisional eggs / larvae / frass detection';
  String get caseLabel => infested > 0
      ? 'Infested'
      : assessable == sample.expectedPlants && assessable > 0
      ? 'Not infested'
      : 'Unavailable';
}
