import 'dart:io';

import '../../data/local/database_codes.dart';
import '../computer_vision/faw_computer_vision_service.dart';
import 'advisor_knowledge_service.dart';

class AdvisorImageAnalysisService {
  const AdvisorImageAnalysisService(this._model);

  final FawComputerVisionService _model;

  Future<AdvisorImageAnalysisResult> analyze(File imageFile) async {
    final result = await _model.analyzeImage(imageFile);
    final confidence = (result.confidenceScore * 100).clamp(0, 100);
    final speciesBoxes =
        result.detectionBoxes
            .where((box) => box.classId >= 4 && box.classId <= 6)
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final species = speciesBoxes.isEmpty ? null : speciesBoxes.first;
    final speciesSummary = species == null
        ? ''
        : ' Pest identification suggests ${species.label} with '
              '${(species.confidence * 100).toStringAsFixed(0)}% confidence.';
    final hasDetections = result.detectionBoxes.isNotEmpty;
    final hasCondition =
        hasDetections ||
        result.isInfested ||
        result.suggestedPlantStatus != DatabaseCodes.plantNegative;

    final summary = hasCondition
        ? 'The damage screen suggests “${result.classificationLabel ?? result.pestLabel}” with ${confidence.toStringAsFixed(0)}% confidence.$speciesSummary These are visual suggestions, not a confirmed diagnosis.'
        : (result.advisoryNotes ??
              'The WormWise model did not detect one of its configured visual classes in this photo. That does not prove the plant is pest-free.');

    return AdvisorImageAnalysisResult(
      answer: AdvisorAnswer(
        topicId: 'on_device_image_analysis',
        title: 'On-device image-model result',
        summary: summary,
        details: [
          if (result.advisoryNotes != null) 'Advisory: ${result.advisoryNotes}',
          if (result.classifierStage != null)
            'Pipeline Stage: ${result.classifierStage}',
          if (result.classificationProbabilities.isNotEmpty)
            'FAW damage screen: ${result.classificationProbabilities.entries.map((e) => '${e.key}: ${(e.value * 100).toStringAsFixed(0)}%').join(', ')}',
          if (result.detectedSigns.isNotEmpty)
            'Model-detected signs: ${result.detectedSigns.join(', ')}',
          'Model: ${result.modelName}',
          'Processing time: ${result.inferenceDurationMs} ms',
          'No field observation or assessment record was changed.',
        ],
        nextAction:
            'Use the Scout workflow for structured evidence and evaluator confirmation.',
        source: AdvisorKnowledgeSource(
          label: 'WormWise on-device image model',
          reference: 'Selected photo processed on this phone',
          version: _model.modelIdentifier,
        ),
      ),
      imagePath: imageFile.path,
      detectionBoxes: result.detectionBoxes,
      structuredFindings: _structuredFindings(result),
    );
  }

  String _structuredFindings(PlantDiagnosisResult result) {
    final detections = result.detectionBoxes
        .map(
          (box) =>
              '${box.label}: ${(box.confidence * 100).toStringAsFixed(0)}% at normalized box '
              '(${box.left.toStringAsFixed(3)}, ${box.top.toStringAsFixed(3)}, '
              '${box.right.toStringAsFixed(3)}, ${box.bottom.toStringAsFixed(3)})',
        )
        .join('\n');
    return [
      'Model: ${result.modelName}',
      'Suggested label: ${result.pestLabel}',
      'Damage-screen confidence: ${(result.confidenceScore * 100).toStringAsFixed(0)}%',
      'Detected signs: ${result.detectedSigns.isEmpty ? 'none' : result.detectedSigns.join(', ')}',
      'Detections: ${result.detectionBoxes.length}',
      if (detections.isNotEmpty) detections,
    ].join('\n');
  }
}

class AdvisorImageAnalysisResult {
  const AdvisorImageAnalysisResult({
    required this.answer,
    required this.imagePath,
    required this.detectionBoxes,
    required this.structuredFindings,
  });

  final AdvisorAnswer answer;
  final String imagePath;
  final List<ModelDetectionBox> detectionBoxes;
  final String structuredFindings;
}
