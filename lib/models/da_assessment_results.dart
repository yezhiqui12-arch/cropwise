import 'dart:math' as math;
import '../data/local/database_codes.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../services/assessment_area_policy.dart';
import '../services/cloud/expert_review_service.dart';
import '../services/scouting_sampling_protocol.dart';
import 'assessment_history_models.dart';
import 'automatic_screening.dart';

/// One observation per sampling location; photographs never enter denominators.
class DaSampleResults {
  DaSampleResults.fromDetail(this.detail) {
    final area = detail.workspace.boundary?.areaHectares ?? 0;
    final requiredBlocks = AssessmentAreaPolicy.requiredBlockCount(area);
    expectedPlants =
        math.max(
          1,
          math.max(
            requiredBlocks,
            detail.stations.map((s) => s.prepared.run.id).toSet().length,
          ),
        ) *
        ScoutingSamplingProtocol.plantsPerBlock;
    final unique = <String, StationSnapshot>{};
    for (final station in detail.stations) {
      unique['${station.prepared.run.id}:${station.stationNumber}'] = station;
    }
    plants = unique.values.toList()
      ..sort((a, b) {
        final block = a.prepared.run.blockSequence.compareTo(
          b.prepared.run.blockSequence,
        );
        return block != 0 ? block : a.stationNumber.compareTo(b.stationNumber);
      });
  }

  final AssessmentHistoryDetail detail;
  late final int expectedPlants;
  late final List<StationSnapshot> plants;
  StationPlantRecord? observation(StationSnapshot plant) => plant.plants
      .where((p) => p.plant.sequenceNumber == 1 && p.plant.deletedAt == null)
      .firstOrNull;
  AutomaticScreening? screening(StationSnapshot plant) {
    final record = observation(plant);
    if (record == null) return null;
    final screen = detail.screeningFor(record);
    final media = photos(plant);
    final signature =
        (media.map((p) => p.media.sha256Checksum).toList()..sort()).join(':');
    return screen?.matchesEvidence(signature, hasEvidence: media.isNotEmpty) ==
            true
        ? screen
        : null;
  }

  bool isAssessable(StationSnapshot plant) => const [
    'FAW damage',
    'No FAW damage',
  ].contains(screening(plant)?.result.classificationLabel);
  bool isPositive(StationSnapshot plant) =>
      isAssessable(plant) && screening(plant)!.positive;
  int get recordedPlants => plants.where((s) => observation(s) != null).length;
  int get savedPlants =>
      plants.where((s) => observation(s) != null && s.reviewIsCurrent).length;
  int get assessablePlants => plants.where(isAssessable).length;
  int get positivePlants => plants.where(isPositive).length;
  int get unavailablePlants => recordedPlants - assessablePlants;
  int get remainingPlants =>
      (expectedPlants - recordedPlants).clamp(0, expectedPlants);
  double? get screeningPercent =>
      assessablePlants == 0 ? null : positivePlants / assessablePlants * 100;
  bool get sampleComplete =>
      expectedPlants > 0 &&
      savedPlants == expectedPlants &&
      detail.assessment.status == DatabaseCodes.completed &&
      detail.readiness.isValid;
  List<AssessmentEvidenceEntry> photos(StationSnapshot plant) {
    final record = observation(plant);
    if (record == null) return const [];
    final unique = <String, AssessmentEvidenceEntry>{};
    for (final evidence in detail.evidence) {
      if (evidence.media.deletedAt == null &&
          evidence.media.storageState == DatabaseCodes.evidenceStorageReady &&
          evidence.stationId == plant.station?.id &&
          (evidence.plantObservationId == record.plant.id ||
              (evidence.plantPosition == 1 &&
                  evidence.scopeType == DatabaseCodes.evidenceScopePlant))) {
        unique[evidence.media.id] = evidence;
      }
    }
    return unique.values.toList();
  }
}

/// Mean of actual finalized, uniquely matched 0–9 scores, including zeros.
/// Incomplete payloads or ambiguous multi-block associations produce no average.
class DaExpertResults {
  DaExpertResults.fromRatings({
    required DaSampleResults sample,
    required ExpertSeveritySummary summary,
    required List<ExpertPlantRating> ratings,
  }) {
    final seen = <String>{};
    final mapped = <String, ExpertPlantRating>{};
    var valid = summary.monitoring['association_status'] != 'ambiguous';
    var insufficient = 0;
    var sum = 0;
    for (final rating in ratings) {
      final key = rating.identityKey;
      final matches = sample.plants
          .where(
            (s) =>
                (rating.blockRunId == null ||
                    s.prepared.run.id == rating.blockRunId) &&
                s.stationNumber == rating.stationNumber &&
                sample.observation(s)?.plant.sequenceNumber ==
                    rating.plantNumber,
          )
          .toList();
      if (!seen.add(key) || matches.length != 1) {
        valid = false;
        continue;
      }
      final location = matches.single;
      final locationKey =
          '${location.prepared.run.id}:${location.stationNumber}';
      if (mapped.containsKey(locationKey)) {
        valid = false;
        continue;
      }
      mapped[locationKey] = rating;
      if (rating.outcome == 'scored' &&
          rating.davisScore != null &&
          rating.davisScore! >= 0 &&
          rating.davisScore! <= 9) {
        scoredPlants++;
        sum += rating.davisScore!;
      } else if (rating.outcome == 'insufficient_evidence' &&
          rating.davisScore == null) {
        insufficient++;
      } else {
        valid = false;
      }
    }
    valid =
        valid &&
        ratings.length == summary.reviewedPlants &&
        scoredPlants == summary.scoredPlants &&
        insufficient == summary.insufficientPlants;
    available = valid;
    byLocation = valid ? mapped : const {};
    mean = valid && scoredPlants > 0 ? sum / scoredPlants : null;
    insufficientPlants = insufficient;
  }
  int get damagedPlants => byLocation.values
      .where((r) => r.outcome == 'scored' && (r.davisScore ?? 0) > 0)
      .length;
  double? get damagePercent =>
      scoredPlants == 0 ? null : 100 * damagedPlants / scoredPlants;
  int scoredPlants = 0;
  late final int insufficientPlants;
  late final bool available;
  late final double? mean;
  late final Map<String, ExpertPlantRating> byLocation;
  ExpertPlantRating? ratingFor(StationSnapshot plant) =>
      byLocation['${plant.prepared.run.id}:${plant.stationNumber}'];
}
