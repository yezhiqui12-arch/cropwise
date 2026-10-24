import 'dart:io';
import '../../data/local/database_codes.dart';

class ModelDetectionBox {
  const ModelDetectionBox({
    required this.sourcePath,
    required this.classId,
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String sourcePath;
  final int classId;
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int imageWidth;
  final int imageHeight;

  Map<String, dynamic> toJson() => {
    'sourcePath': sourcePath,
    'classId': classId,
    'label': label,
    'confidence': confidence,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };
}

/// Detection result produced by on-device or cloud computer vision models.
class PlantDiagnosisResult {
  const PlantDiagnosisResult({
    required this.isInfested,
    required this.pestLabel,
    required this.confidenceScore,
    this.suggestedPlantStatus = DatabaseCodes.plantNegative,
    this.detectedSigns = const [],
    this.larvaVisible = false,
    this.larvalSize = 'none_seen',
    this.windowpanes = false,
    this.scraping = false,
    this.cutting = false,
    this.frass = false,
    this.whorlFeeding = false,
    this.inferenceDurationMs = 0,
    this.modelName = 'FawDetector-v1',
    this.detectionBoxes = const [],
    this.classificationLabel,
    this.classificationProbabilities = const {},
    this.classifierStage,
    this.advisoryNotes,
  });

  final bool isInfested;
  final String pestLabel;
  final double confidenceScore;
  final String suggestedPlantStatus;
  final List<String> detectedSigns;
  final bool larvaVisible;
  final String larvalSize;
  final bool windowpanes;
  final bool scraping;
  final bool cutting;
  final bool frass;
  final bool whorlFeeding;
  final int inferenceDurationMs;
  final String modelName;
  final List<ModelDetectionBox> detectionBoxes;
  final String? classificationLabel;
  final Map<String, double> classificationProbabilities;
  final String? classifierStage;
  final String? advisoryNotes;

  static const cleanPlant = PlantDiagnosisResult(
    isInfested: false,
    pestLabel: 'No Pest Detected',
    confidenceScore: 0.95,
    suggestedPlantStatus: DatabaseCodes.plantNegative,
  );

  static PlantDiagnosisResult oldDamagePlant({
    double confidence = 0.88,
    int durationMs = 100,
  }) => PlantDiagnosisResult(
    isInfested: false,
    pestLabel: 'Weathering / Old Damage',
    confidenceScore: confidence,
    suggestedPlantStatus: DatabaseCodes.plantOldDamageOnly,
    detectedSigns: const ['old_feeding_scars'],
    inferenceDurationMs: durationMs,
  );

  static PlantDiagnosisResult nonFawPlant({
    double confidence = 0.85,
    int durationMs = 100,
  }) => PlantDiagnosisResult(
    isInfested: false,
    pestLabel: 'Non-FAW Insect / Physical Injury',
    confidenceScore: confidence,
    suggestedPlantStatus: DatabaseCodes.plantPossibleNonFaw,
    detectedSigns: const ['non_faw_damage'],
    inferenceDurationMs: durationMs,
  );

  static PlantDiagnosisResult fawInfested({
    double confidence = 0.92,
    bool larvaSeen = true,
    String larvaSize = 'medium',
    bool frassSeen = true,
    bool whorlSeen = true,
    int durationMs = 120,
  }) => PlantDiagnosisResult(
    isInfested: true,
    pestLabel: 'Fall Armyworm (Spodoptera frugiperda)',
    confidenceScore: confidence,
    suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
    detectedSigns: [
      if (whorlSeen) 'whorl_feeding',
      if (frassSeen) 'fresh_frass',
      if (larvaSeen) 'larva',
    ],
    larvaVisible: larvaSeen,
    larvalSize: larvaSize,
    frass: frassSeen,
    whorlFeeding: whorlSeen,
    windowpanes: true,
    inferenceDurationMs: durationMs,
  );

  /// Aggregates multiple image diagnoses (1-3 photos) for a single plant into a
  /// unified multi-view diagnosis.
  static PlantDiagnosisResult merge(List<PlantDiagnosisResult> results) {
    if (results.isEmpty) return cleanPlant;
    if (results.length == 1) return results.first;

    if (results.any((r) => r.modelName.startsWith('WormWise-AutoScreen-v1:'))) {
      final positive = results
          .where((r) => r.classificationLabel == 'FAW damage')
          .toList();
      final unavailable = results.any((r) => r.classificationLabel == null);
      final candidates = positive.isNotEmpty ? positive : results;
      final primary = candidates.reduce(
        (a, b) => a.confidenceScore >= b.confidenceScore ? a : b,
      );
      final label = positive.isNotEmpty
          ? 'FAW damage'
          : unavailable
          ? null
          : 'No FAW damage';
      return PlantDiagnosisResult(
        isInfested: false,
        pestLabel: label ?? 'Not assessed',
        confidenceScore: label == null ? 0 : primary.confidenceScore,
        suggestedPlantStatus: label == null
            ? 'damage_screen_unavailable'
            : positive.isNotEmpty
            ? 'damage_screen_positive'
            : 'damage_screen_negative',
        classificationLabel: label,
        classificationProbabilities: primary.classificationProbabilities,
        classifierStage:
            results.any(
              (r) =>
                  r.classifierStage == 'overlay_unavailable' ||
                  r.classifierStage == 'overlay_partial',
            )
            ? 'overlay_partial'
            : results.any((r) => r.classifierStage == 'overlay_complete')
            ? 'overlay_complete'
            : 'overlay_off',
        modelName: primary.modelName,
        inferenceDurationMs: results.fold<int>(
          0,
          (sum, r) => sum + r.inferenceDurationMs,
        ),
        detectionBoxes: [for (final r in results) ...r.detectionBoxes],
        detectedSigns: positive.isNotEmpty
            ? const ['faw_damage_screen_positive']
            : const [],
      );
    }

    final infestedResults = results.where((r) => r.isInfested).toList();
    if (infestedResults.isNotEmpty) {
      var maxConfidence = 0.0;
      var totalDuration = 0;
      final allSigns = <String>{};
      var larva = false;
      var larvalSize = 'none_seen';
      var windowpanes = false;
      var scraping = false;
      var cutting = false;
      var frass = false;
      var whorlFeeding = false;

      for (final r in results) {
        totalDuration += r.inferenceDurationMs;
        if (r.confidenceScore > maxConfidence) {
          maxConfidence = r.confidenceScore;
        }
        allSigns.addAll(r.detectedSigns);
        if (r.larvaVisible) {
          larva = true;
          if (r.larvalSize != 'none_seen' && r.larvalSize != 'uncertain') {
            larvalSize = r.larvalSize;
          } else if (larvalSize == 'none_seen') {
            larvalSize = r.larvalSize;
          }
        }
        if (r.windowpanes) windowpanes = true;
        if (r.scraping) scraping = true;
        if (r.cutting) cutting = true;
        if (r.frass) frass = true;
        if (r.whorlFeeding) whorlFeeding = true;
      }

      final primary = infestedResults.reduce(
        (a, b) => a.confidenceScore >= b.confidenceScore ? a : b,
      );

      return PlantDiagnosisResult(
        isInfested: true,
        pestLabel: primary.pestLabel,
        confidenceScore: maxConfidence,
        suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
        detectedSigns: allSigns.toList(),
        larvaVisible: larva,
        larvalSize: larvalSize,
        windowpanes: windowpanes,
        scraping: scraping,
        cutting: cutting,
        frass: frass,
        whorlFeeding: whorlFeeding,
        inferenceDurationMs: totalDuration,
        modelName: primary.modelName,
        detectionBoxes: [
          for (final result in results) ...result.detectionBoxes,
        ],
      );
    }

    final oldDamageResult = results.firstWhere(
      (r) => r.suggestedPlantStatus == DatabaseCodes.plantOldDamageOnly,
      orElse: () => results.first,
    );
    if (oldDamageResult.suggestedPlantStatus ==
        DatabaseCodes.plantOldDamageOnly) {
      return oldDamageResult;
    }

    final maxConfidence = results
        .map((r) => r.confidenceScore)
        .reduce((a, b) => a > b ? a : b);
    final totalDuration = results.fold<int>(
      0,
      (sum, r) => sum + r.inferenceDurationMs,
    );
    return PlantDiagnosisResult(
      isInfested: false,
      pestLabel: 'No Pest Detected',
      confidenceScore: maxConfidence,
      suggestedPlantStatus: DatabaseCodes.plantNegative,
      inferenceDurationMs: totalDuration,
      modelName: results.first.modelName,
    );
  }

  Map<String, dynamic> toJson() => {
    'isInfested': isInfested,
    'pestLabel': pestLabel,
    'confidenceScore': confidenceScore,
    'suggestedPlantStatus': suggestedPlantStatus,
    'detectedSigns': detectedSigns,
    'larvaVisible': larvaVisible,
    'larvalSize': larvalSize,
    'windowpanes': windowpanes,
    'scraping': scraping,
    'cutting': cutting,
    'frass': frass,
    'whorlFeeding': whorlFeeding,
    'inferenceDurationMs': inferenceDurationMs,
    'modelName': modelName,
    'detectionBoxes': detectionBoxes.map((box) => box.toJson()).toList(),
    if (classificationLabel != null) 'classificationLabel': classificationLabel,
    if (classificationProbabilities.isNotEmpty)
      'classificationProbabilities': classificationProbabilities,
    if (classifierStage != null) 'classifierStage': classifierStage,
    if (advisoryNotes != null) 'advisoryNotes': advisoryNotes,
  };

  factory PlantDiagnosisResult.fromJson(
    Map<String, dynamic> json,
  ) => PlantDiagnosisResult(
    isInfested: json['isInfested'] == true,
    pestLabel: json['pestLabel'] as String? ?? '',
    confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
    suggestedPlantStatus:
        json['suggestedPlantStatus'] as String? ?? DatabaseCodes.plantNegative,
    detectedSigns: (json['detectedSigns'] as List? ?? const []).cast<String>(),
    larvaVisible: json['larvaVisible'] == true,
    larvalSize: json['larvalSize'] as String? ?? 'none_seen',
    windowpanes: json['windowpanes'] == true,
    scraping: json['scraping'] == true,
    cutting: json['cutting'] == true,
    frass: json['frass'] == true,
    whorlFeeding: json['whorlFeeding'] == true,
    inferenceDurationMs: (json['inferenceDurationMs'] as num?)?.toInt() ?? 0,
    modelName: json['modelName'] as String? ?? 'FawDetector-v1',
    detectionBoxes: (json['detectionBoxes'] as List? ?? const []).map((entry) {
      final box = Map<String, dynamic>.from(entry as Map);
      return ModelDetectionBox(
        sourcePath: box['sourcePath'] as String? ?? '',
        classId: (box['classId'] as num?)?.toInt() ?? 0,
        label: box['label'] as String? ?? '',
        confidence: (box['confidence'] as num?)?.toDouble() ?? 0,
        left: (box['left'] as num?)?.toDouble() ?? 0,
        top: (box['top'] as num?)?.toDouble() ?? 0,
        right: (box['right'] as num?)?.toDouble() ?? 0,
        bottom: (box['bottom'] as num?)?.toDouble() ?? 0,
        imageWidth: (box['imageWidth'] as num?)?.toInt() ?? 0,
        imageHeight: (box['imageHeight'] as num?)?.toInt() ?? 0,
      );
    }).toList(),
    classificationLabel: json['classificationLabel'] as String?,
    classificationProbabilities:
        (json['classificationProbabilities'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ),
    classifierStage: json['classifierStage'] as String?,
    advisoryNotes: json['advisoryNotes'] as String?,
  );
}

/// Plug-and-play contract for Computer Vision models.
abstract interface class FawComputerVisionService {
  Future<PlantDiagnosisResult> analyzeImage(File imageFile);
  bool get isModelLoaded;
  String get modelIdentifier;
}
