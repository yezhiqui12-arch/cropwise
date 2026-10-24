import 'dart:async';
import 'faw_inference_worker.dart';
import 'managed_inference_worker.dart';
import 'dart:io';
import 'detection_preferences.dart';
import '../../models/automatic_screening.dart';

import 'package:flutter/foundation.dart';

import 'faw_computer_vision_service.dart';
import 'maize_leaf_classifier.dart';
import 'tflite_faw_detector.dart';

/// FAW-only two-stage computer-vision pipeline.
///
/// Stage 1 is a binary FAW-damage screening gate. Stage 2 runs only after
/// Stage 1 suspects FAW damage.
class TwoStageFawCvService
    implements FawComputerVisionService, DisposableFawComputerVisionService {
  TwoStageFawCvService({
    MaizeLeafClassifier? classifier,
    TfliteFawDetector? detector,
    this.simulatedResult,
    this.loadPreferences = true,
    this.fawDamageThreshold = 0.50,
  }) : _useWorker = classifier == null && detector == null,
       _ownsClassifier = classifier == null,
       _ownsDetector = detector == null,
       _classifier = classifier ?? MaizeLeafClassifier(),
       _detector = detector ?? TfliteFawDetector();

  final MaizeLeafClassifier _classifier;
  final TfliteFawDetector _detector;
  final double fawDamageThreshold;
  final bool loadPreferences;
  final bool _useWorker;
  final bool _ownsClassifier;
  final bool _ownsDetector;
  ManagedInferenceWorker? _worker;
  bool? _workerHighlighting;
  Future<PlantDiagnosisResult>? _active;
  Future<void>? _closing;
  bool _disposed = false;
  bool _workerLoaded = false;
  PlantDiagnosisResult? simulatedResult;

  bool? _assessmentHighlighting;
  bool get _highlightingEnabled =>
      _assessmentHighlighting ?? DetectionPreferences.enabled.value;
  void useAssessmentHighlighting(bool enabled) {
    if (_assessmentHighlighting != null && _assessmentHighlighting != enabled) {
      throw StateError('The assessment model setting is locked.');
    }
    _assessmentHighlighting = enabled;
  }

  MaizeLeafClassifier get classifier => _classifier;
  TfliteFawDetector get detector => _detector;

  @override
  bool get isModelLoaded =>
      !_disposed &&
      (simulatedResult != null ||
          _workerLoaded ||
          (_classifier.isModelLoaded &&
              (!_highlightingEnabled || _detector.isModelLoaded)));

  @override
  String get modelIdentifier =>
      'WormWise-AutoScreen-v1:${_classifier.modelIdentifier}:overlay=$_highlightingEnabled';

  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) {
    if (_disposed) {
      return Future.error(StateError('The model service is closed.'));
    }
    if (_active != null) {
      return Future.error(
        StateError('Screening is still running. Please wait.'),
      );
    }
    final operation = _analyzeImage(imageFile);
    _active = operation;
    return operation.whenComplete(() => _active = null);
  }

  Future<PlantDiagnosisResult> _analyzeImage(File imageFile) async {
    if (loadPreferences) await DetectionPreferences.load();
    if (simulatedResult != null) return simulatedResult!;
    final isSimulated =
        _classifier.simulatedResult != null ||
        _detector.simulatedResult != null;
    if (!isSimulated && !await imageFile.exists()) {
      return PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'Not assessed',
        confidenceScore: 0,
        suggestedPlantStatus: AutomaticScreening.unavailableStatus,
        modelName: modelIdentifier,
      );
    }

    if (_useWorker) {
      final highlighting = _highlightingEnabled;
      if (_worker != null && _workerHighlighting != highlighting) {
        await _worker!.close();
        _worker = null;
      }
      _workerHighlighting = highlighting;
      final worker = _worker ??= createFawInferenceWorker(
        highlighting: highlighting,
      );
      try {
        final json = await worker.run({
          'path': imageFile.path,
          'highlighting': highlighting,
          'threshold': fawDamageThreshold,
        });
        final result = PlantDiagnosisResult.fromJson(
          Map<String, dynamic>.from(json as Map),
        );
        _workerLoaded = result.classificationLabel != null;
        return result;
      } catch (error) {
        await worker.close();
        _worker = null;
        _workerLoaded = false;
        return PlantDiagnosisResult(
          isInfested: false,
          pestLabel: 'FAW damage screening unavailable',
          confidenceScore: 0,
          suggestedPlantStatus: AutomaticScreening.unavailableStatus,
          modelName: modelIdentifier,
          classifierStage: 'Stage 1 unavailable — Stage 2 not run',
          advisoryNotes: 'Screening could not finish. Retry this photo.',
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    MaizeClassificationResult screening;
    try {
      screening = await _classifier.classifyImage(imageFile);
      final probability = screening.probabilities['faw_damage'];
      if (probability == null ||
          !probability.isFinite ||
          probability < 0 ||
          probability > 1) {
        throw const FormatException('Invalid damage-screen probability.');
      }
    } catch (error, stackTrace) {
      debugPrint('[TwoStageCV] FAW damage screen failed: $error\n$stackTrace');
      stopwatch.stop();
      return PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'FAW damage screening unavailable',
        confidenceScore: 0,
        suggestedPlantStatus: AutomaticScreening.unavailableStatus,
        detectedSigns: const ['faw_screen_unavailable'],
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
        modelName: modelIdentifier,
        classifierStage: 'Stage 1 unavailable — Stage 2 not run',
        advisoryNotes:
            'The FAW-damage screening model could not evaluate this photo. '
            'No automated FAW conclusion was produced; inspect the plant or '
            'capture another clear photo.',
      );
    }

    final fawProbability = screening.fawDamageProbability;
    final noFawProbability = (1.0 - fawProbability).clamp(0.0, 1.0);
    final binaryProbabilities = <String, double>{
      'FAW damage': fawProbability,
      'No FAW damage': noFawProbability,
    };
    final fawDamageSuspected = fawProbability >= fawDamageThreshold;

    if (!fawDamageSuspected) {
      stopwatch.stop();
      return PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'No FAW damage detected',
        confidenceScore: noFawProbability,
        suggestedPlantStatus: AutomaticScreening.negativeStatus,
        detectedSigns: const ['no_faw_damage_screened'],
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
        modelName: modelIdentifier,
        classificationLabel: 'No FAW damage',
        classificationProbabilities: binaryProbabilities,
        classifierStage: 'Stage 1 (No FAW damage — Stage 2 not run)',
        advisoryNotes:
            'The first model did not detect enough FAW-compatible damage to '
            'run the FAW evidence detector.',
      );
    }

    var boxes = <ModelDetectionBox>[];
    var overlayState = 'overlay_off';
    if (_highlightingEnabled) {
      try {
        final detection = await _detector.analyzeImage(imageFile);
        boxes = detection.detectionBoxes;
        overlayState = 'overlay_complete';
      } catch (error) {
        debugPrint('Optional highlighting unavailable: $error');
        overlayState = 'overlay_unavailable';
      }
    }
    final pestCandidates = boxes
        .where((box) => box.classId >= 4 && box.classId <= 6)
        .map((box) => box.label)
        .toSet();
    stopwatch.stop();
    return PlantDiagnosisResult(
      isInfested: false,
      pestLabel: 'FAW damage detected',
      confidenceScore: fawProbability,
      suggestedPlantStatus: AutomaticScreening.positiveStatus,
      detectedSigns: const ['faw_damage_screen_positive'],
      inferenceDurationMs: stopwatch.elapsedMilliseconds,
      modelName: modelIdentifier,
      detectionBoxes: boxes,
      classificationLabel: 'FAW damage',
      classificationProbabilities: binaryProbabilities,
      classifierStage: overlayState,
      advisoryNotes:
          'Damage screening only. Highlighted objects and pest identification '
          'are model suggestions requiring evaluator review.'
          '${pestCandidates.isEmpty ? '' : ' Pest candidate: ${pestCandidates.join(', ')}.'}',
    );
  }

  @override
  Future<void> close() {
    _disposed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _active;
    } catch (_) {
      // The inference caller receives the original error.
    }
    await _worker?.close();
    _worker = null;
    _workerLoaded = false;
    if (_ownsClassifier) _classifier.close();
    if (_ownsDetector) _detector.close();
  }
}
