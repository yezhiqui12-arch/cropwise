import 'dart:io';
import '../../data/local/database_codes.dart';

/// Detection result produced by on-device or cloud computer vision models.
class PlantDiagnosisResult {
  const PlantDiagnosisResult({
    required this.isInfested,
    required this.pestLabel,
    required this.confidenceScore,
    this.davisDamageGrade = 1,
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
  });

  final bool isInfested;
  final String pestLabel;
  final double confidenceScore;
  final int davisDamageGrade;
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

  static const cleanPlant = PlantDiagnosisResult(
    isInfested: false,
    pestLabel: 'No Pest Detected',
    confidenceScore: 0.95,
    davisDamageGrade: 1,
    suggestedPlantStatus: DatabaseCodes.plantNegative,
  );

  static PlantDiagnosisResult fawInfested({
    double confidence = 0.92,
    int davisGrade = 3,
    bool larvaSeen = true,
    String larvaSize = 'medium',
    bool frassSeen = true,
    bool whorlSeen = true,
    int durationMs = 120,
  }) => PlantDiagnosisResult(
    isInfested: true,
    pestLabel: 'Fall Armyworm (Spodoptera frugiperda)',
    confidenceScore: confidence,
    davisDamageGrade: davisGrade,
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

  Map<String, dynamic> toJson() => {
    'isInfested': isInfested,
    'pestLabel': pestLabel,
    'confidenceScore': confidenceScore,
    'davisDamageGrade': davisDamageGrade,
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
  };
}

/// Plug-and-play contract for Computer Vision models.
abstract interface class FawComputerVisionService {
  Future<PlantDiagnosisResult> analyzeImage(File imageFile);
  bool get isModelLoaded;
  String get modelIdentifier;
}
