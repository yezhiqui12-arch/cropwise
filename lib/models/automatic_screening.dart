import 'dart:convert';
import '../services/computer_vision/faw_computer_vision_service.dart';

class AutomaticScreening {
  const AutomaticScreening(this.result, {this.evidenceSignature});
  final PlantDiagnosisResult result;
  final String? evidenceSignature;
  static const metric = 'sampled_damage_screen_positive_percent';
  static const positiveStatus = 'damage_screen_positive';
  static const negativeStatus = 'damage_screen_negative';
  static const unavailableStatus = 'damage_screen_unavailable';
  bool get available => result.classificationLabel != null;
  bool get positive => result.classificationLabel == 'FAW damage';
  bool get screeningSucceeded => const [
    'FAW damage',
    'No FAW damage',
  ].contains(result.classificationLabel);
  // A Stage 2 failure still has a Stage 1 result, but must remain retryable.
  bool get processingComplete =>
      screeningSucceeded &&
      result.classifierStage != 'overlay_unavailable' &&
      result.classifierStage != 'overlay_partial';

  bool matchesEvidence(
    String signature, {
    required bool hasEvidence,
    bool allowLegacy = true,
  }) => evidenceSignature == null
      ? allowLegacy
      : hasEvidence && evidenceSignature == signature;

  /// Durable plant results take precedence over a stale or malformed cache.
  /// The cache is a recovery source, never a reason to discard a valid result.
  static AutomaticScreening? resolveSaved({
    required String? note,
    required String? cache,
    required String signature,
    required bool hasEvidence,
    String? pipelineVersion,
    bool allowLegacy = true,
  }) {
    final saved = parse(note);
    final validSaved =
        saved != null &&
            saved.matchesEvidence(
              signature,
              hasEvidence: hasEvidence,
              allowLegacy: allowLegacy,
            ) &&
            (pipelineVersion == null ||
                saved.result.modelName == pipelineVersion)
        ? saved
        : null;
    if (validSaved?.processingComplete == true) return validSaved;
    if (cache != null && hasEvidence) {
      try {
        final data = jsonDecode(cache) as Map<String, dynamic>;
        final result = PlantDiagnosisResult.fromJson(
          Map<String, dynamic>.from(data['result'] as Map),
        );
        if (data['signature'] == signature &&
            data['pipelineVersion'] == result.modelName &&
            (pipelineVersion == null || result.modelName == pipelineVersion)) {
          final cached = AutomaticScreening(
            result,
            evidenceSignature: signature,
          );
          if (cached.processingComplete || validSaved == null) return cached;
        }
      } catch (_) {
        // Corrupt caches do not invalidate the durable plant observation.
      }
    }
    return validSaved;
  }

  bool get highlighted =>
      result.classifierStage?.contains('overlay_complete') == true;
  static PlantDiagnosisResult? photoCheckpoint(
    String? stored, {
    required String evidenceId,
    required String checksum,
    String? pipelineVersion,
  }) {
    if (stored == null) return null;
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      final result = PlantDiagnosisResult.fromJson(
        Map<String, dynamic>.from(data['result'] as Map),
      );
      if (data['evidence_id'] != evidenceId ||
          data['sha256'] != checksum ||
          (pipelineVersion != null && result.modelName != pipelineVersion) ||
          (data['pipelineVersion'] != null &&
              data['pipelineVersion'] != result.modelName) ||
          (result.modelName.startsWith('WormWise-AutoScreen-v1:') &&
              !AutomaticScreening(result).processingComplete))
        return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  String get label => !available
      ? 'Not assessed'
      : positive
      ? 'Damage detected'
      : 'No damage detected';
  String get status => !available
      ? unavailableStatus
      : positive
      ? positiveStatus
      : negativeStatus;
  bool suggested(int classId) =>
      highlighted && result.detectionBoxes.any((box) => box.classId == classId);
  String encode() => jsonEncode({
    'source': 'automatic_screening_v1',
    'result': result.toJson(),
    if (evidenceSignature != null) 'evidence_signature': evidenceSignature,
  });
  static AutomaticScreening? parse(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['source'] != 'automatic_screening_v1') {
        return null;
      }
      return AutomaticScreening(
        PlantDiagnosisResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map),
        ),
        evidenceSignature: json['evidence_signature'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
