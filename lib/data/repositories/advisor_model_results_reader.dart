import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/automatic_screening.dart';
import '../../models/sampled_infestation.dart';
import '../../services/scouting_sampling_protocol.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';

class AdvisorModelSample {
  const AdvisorModelSample({
    required this.stationId,
    required this.position,
    required this.images,
    required this.availability,
    this.plant,
    this.result,
    this.source,
  });
  final String stationId;
  final int position;
  final PlantObservationRecord? plant;
  final List<EvidenceMediaRecord> images;
  final PlantDiagnosisResult? result;
  final String availability;
  final String? source;
  bool get eligible => availability == 'available';
  bool get positive => eligible && result!.classificationLabel == 'FAW damage';

  Map<String, dynamic>? get modelJson => result == null
      ? null
      : {
          'modelName': result!.modelName,
          'classificationLabel': result!.classificationLabel,
          'classificationProbabilities': result!.classificationProbabilities,
          'confidenceScore': result!.confidenceScore,
          'classifierStage': result!.classifierStage,
          'inferenceDurationMs': result!.inferenceDurationMs,
          'detectionBoxes': [
            for (final box in result!.detectionBoxes)
              Map<String, dynamic>.from(box.toJson())..remove('sourcePath'),
          ],
        };
}

class AdvisorModelResults {
  const AdvisorModelResults(this.samples, {this.plannedPlants});
  final List<AdvisorModelSample> samples;
  final int? plannedPlants;

  Map<String, dynamic> get sampledInfestationSummary {
    final unique = <String, bool?>{};
    for (final sample in samples) {
      final key = '${sample.stationId}:${sample.position}';
      final value = sample.eligible
          ? modelSampledInfestation(sample.result)
          : null;
      unique[key] = unique.containsKey(key) && unique[key] != value
          ? null
          : value;
    }
    final infested = unique.values.where((v) => v == true).length;
    final notInfested = unique.values.where((v) => v == false).length;
    final eligible = infested + notInfested;
    final denominator = plannedPlants ?? unique.length;
    return {
      'version': 2,
      'source': 'model_eggs_or_larvae_or_frass',
      'planned_plants': denominator,
      'denominator': denominator,
      'infested_count': infested,
      'not_infested_count': notInfested,
      'eligible_count': eligible,
      'sample_count': unique.length,
      'unavailable_count': denominator - eligible,
      'percent': eligible == 0 || denominator <= 0
          ? null
          : infested / denominator * 100,
    };
  }

  Map<String, dynamic> get summary {
    final eligible = samples.where((s) => s.eligible).toList();
    final positive = eligible.where((s) => s.positive).length;
    final missing = samples.where((s) => s.availability == 'missing').length;
    final stale = samples.where((s) => s.availability == 'stale').length;
    final unavailable = samples.length - eligible.length - missing - stale;
    return {
      'sampled_infestation': sampledInfestationSummary,
      'automatic_damage_screen': {
        'availability': samples.isEmpty
            ? 'no_samples'
            : eligible.isEmpty
            ? 'results_unavailable'
            : eligible.length == samples.length
            ? 'available'
            : 'partial',
        'positive_count': positive,
        'negative_count': eligible.length - positive,
        'eligible_count': eligible.length,
        'sample_count': samples.length,
        'missing_result_count': missing,
        'stale_result_count': stale,
        'unavailable_count': unavailable,
        'percent': eligible.isEmpty ? null : 100 * positive / eligible.length,
        'source':
            'Saved Model 1 classification; plant record or matching evidence cache',
      },
      'meaning':
          'This is sampled plant-level model damage screening. Missing '
          'saved results do not mean the model was not run or that damage is absent. '
          'Do not report unavailable results as 0/0 or a zero percent rate. '
          'Manual infestation and legacy observation categories are not supplied.',
    };
  }
}

/// Reads the same plant-model cache used by the assessment workflow. Never
/// infers classifications from legacy plant statuses or manual observations.
class AdvisorModelResultsReader {
  const AdvisorModelResultsReader(this.database);
  final AppDatabase database;

  Future<AdvisorModelResults> load({
    required String assessmentId,
    required List<StationRecord> stations,
    required List<PlantObservationRecord> plants,
  }) async {
    final stationIds = stations.map((s) => s.id).toSet();
    final images =
        await (database.select(database.evidenceMedia)..where(
              (m) =>
                  m.assessmentId.equals(assessmentId) &
                  m.deletedAt.isNull() &
                  m.isCanonicalEvidence.equals(true) &
                  m.storageState.equals(DatabaseCodes.evidenceStorageReady),
            ))
            .get();
    final sessions =
        await (database.select(database.evidenceCaptureSessions)..where(
              (s) => s.assessmentId.equals(assessmentId) & s.deletedAt.isNull(),
            ))
            .get();
    final positions = <String, (String, int)>{};
    String key(String station, int position) =>
        'plant_model_${station}_$position';
    for (final plant in plants) {
      if (stationIds.contains(plant.stationId)) {
        positions[key(plant.stationId, plant.sequenceNumber)] = (
          plant.stationId,
          plant.sequenceNumber,
        );
      }
    }
    // An ongoing assessment may have a cache and captured images before its
    // plant observation is written. Include those actual capture positions.
    for (final session in sessions) {
      final position = session.plantPosition;
      if (position != null &&
          stationIds.contains(session.stationId) &&
          images.any((m) => m.captureSessionId == session.id)) {
        positions[key(session.stationId, position)] = (
          session.stationId,
          position,
        );
      }
    }
    final preferences = positions.isEmpty
        ? const <AppPreferenceRecord>[]
        : await (database.select(database.appPreferences)..where(
                (p) => p.preferenceKey.isIn([
                  ...positions.keys,
                  for (final image in images) 'evidence_model_${image.id}',
                ]),
              ))
              .get();
    final caches = {
      for (final p in preferences) p.preferenceKey: p.preferenceValue,
    };
    final samples = <AdvisorModelSample>[];
    for (final entry in positions.entries) {
      final (stationId, position) = entry.value;
      final matchingPlants = plants.where(
        (p) => p.stationId == stationId && p.sequenceNumber == position,
      );
      final plant = matchingPlants.isEmpty ? null : matchingPlants.first;
      final matchingSessions = sessions
          .where((s) => s.stationId == stationId && s.plantPosition == position)
          .map((s) => s.id)
          .toSet();
      final media = images
          .where(
            (m) =>
                (m.stationId == null || m.stationId == stationId) &&
                ((plant != null && m.plantObservationId == plant.id) ||
                    (plant?.sourcePlantingUnitObservationId != null &&
                        m.plantingUnitObservationId ==
                            plant!.sourcePlantingUnitObservationId) ||
                    matchingSessions.contains(m.captureSessionId)),
          )
          .toList();
      final checksums = media.map((m) => m.sha256Checksum).toList()..sort();
      final signature = checksums.join(':');
      PlantDiagnosisResult? result;
      String? source;
      var availability = 'missing';
      final cached = caches[entry.key];
      final saved = AutomaticScreening.resolveSaved(
        note: plant?.wholePlantContextNote,
        cache: cached,
        signature: signature,
        hasEvidence: media.isNotEmpty,
      );
      if (saved != null) {
        result = saved.result;
        final durable = AutomaticScreening.parse(plant?.wholePlantContextNote);
        source =
            durable?.matchesEvidence(
                      signature,
                      hasEvidence: media.isNotEmpty,
                    ) ==
                    true &&
                jsonEncode(durable!.result.toJson()) ==
                    jsonEncode(result.toJson())
            ? 'saved_plant_model_result'
            : 'evidence_matched_model_cache';
      } else if (cached != null) {
        try {
          final data = jsonDecode(cached) as Map<String, dynamic>;
          availability = media.isEmpty || data['signature'] != signature
              ? 'stale'
              : 'invalid_saved_result';
        } catch (_) {
          availability = 'invalid_saved_result';
        }
      } else if (AutomaticScreening.parse(plant?.wholePlantContextNote) !=
          null) {
        availability = 'stale';
      }
      // Recover a quit between the last photo checkpoint and the aggregate
      // save. Every photo must match; partial checkpoints never become a plant.
      if ((result == null || !AutomaticScreening(result).processingComplete) &&
          media.isNotEmpty) {
        final checkpoints = [
          for (final image in media)
            AutomaticScreening.photoCheckpoint(
              caches['evidence_model_${image.id}'],
              evidenceId: image.id,
              checksum: image.sha256Checksum,
            ),
        ];
        if (checkpoints.every(
              (r) => r != null && AutomaticScreening(r).processingComplete,
            ) &&
            checkpoints.map((r) => r!.modelName).toSet().length == 1) {
          result = PlantDiagnosisResult.merge(
            checkpoints.cast<PlantDiagnosisResult>(),
          );
          source = 'recovered_photo_model_results';
        }
      }
      if (result != null) {
        availability =
            const [
              'FAW damage',
              'No FAW damage',
            ].contains(result.classificationLabel)
            ? 'available'
            : 'screening_unavailable';
      }
      samples.add(
        AdvisorModelSample(
          stationId: stationId,
          position: position,
          plant: plant,
          images: media,
          result: result,
          source: source,
          availability: availability,
        ),
      );
    }
    final order = {for (var i = 0; i < stations.length; i++) stations[i].id: i};
    samples.sort((a, b) {
      final stationOrder = order[a.stationId]!.compareTo(order[b.stationId]!);
      return stationOrder == 0
          ? a.position.compareTo(b.position)
          : stationOrder;
    });
    final assessment = await (database.select(
      database.assessments,
    )..where((a) => a.id.equals(assessmentId))).getSingleOrNull();
    int? plannedPlants;
    if (assessment != null &&
        ScoutingSamplingProtocol.isDa(assessment.protocolVersion)) {
      final runs =
          await (database.select(database.assessmentBlockRuns)..where(
                (r) =>
                    r.assessmentId.equals(assessmentId) & r.deletedAt.isNull(),
              ))
              .get();
      plannedPlants =
          (runs.isEmpty ? 1 : runs.length) *
          ScoutingSamplingProtocol.plantsPerBlock;
    }
    return AdvisorModelResults(samples, plannedPlants: plannedPlants);
  }
}
