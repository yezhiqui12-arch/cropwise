import '../data/local/app_database.dart';
import 'dart:math' as math;
import '../data/local/database_codes.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../models/assessment_history_models.dart';
import '../models/automatic_screening.dart';
import '../services/scouting_sampling_protocol.dart';

class AssessmentEvidenceStats {
  const AssessmentEvidenceStats({
    this.screeningMode = false,
    this.highlightedPlants = 0,
    required this.damageCount,
    required this.frassCount,
    required this.larvaCount,
    required this.eggCount,
    required this.totalAssessable,
    required this.totalRecorded,
    required this.cleanCount,
    required this.overallInfestationPercent,
    required this.primaryNumerator,
    required this.primaryDenominator,
    required this.primaryMetricCode,
    required this.primaryUnit,
    required this.isZeroDenominator,
    required this.stationStats,
  });

  final bool screeningMode;
  final int highlightedPlants;
  final int damageCount;
  final int frassCount;
  final int larvaCount;
  final int eggCount;
  final int totalAssessable;
  final int totalRecorded;
  final int cleanCount;
  final double overallInfestationPercent;
  final double primaryNumerator;
  final double primaryDenominator;
  final String primaryMetricCode;
  final String primaryUnit;
  final bool isZeroDenominator;
  final List<StationEvidenceStats> stationStats;
}

class StationEvidenceStats {
  const StationEvidenceStats({
    this.screeningMode = false,
    this.highlightedPlants = 0,
    required this.stationNumber,
    required this.blockSequence,
    required this.damageCount,
    required this.frassCount,
    required this.larvaCount,
    required this.eggCount,
    required this.assessableCount,
    required this.positiveCount,
    required this.recordedCount,
    required this.infestationPercent,
    required this.photoCount,
    required this.snapshot,
  });

  final bool screeningMode;
  final int highlightedPlants;
  final int stationNumber;
  final int blockSequence;
  final int damageCount;
  final int frassCount;
  final int larvaCount;
  final int eggCount;
  final int assessableCount;
  final int positiveCount;
  final int recordedCount;
  final double infestationPercent;
  final int photoCount;
  final StationSnapshot snapshot;

  int get evidenceCount => damageCount + frassCount + larvaCount + eggCount;
  String get ref => 'B$blockSequence-S$stationNumber';
}

AssessmentEvidenceStats computeAssessmentEvidenceStats(
  AssessmentHistoryDetail detail,
) {
  final screeningMode =
      ScoutingSamplingProtocol.isDa(detail.assessment.protocolVersion) ||
      detail.stations.any(
        (s) => s.plants.any((p) => detail.screeningFor(p) != null),
      );
  int highlightedPlants = 0;
  int totalDamage = 0;
  int totalFrass = 0;
  int totalLarvae = 0;
  int totalEggs = 0;
  int totalCurrentSigns = 0;

  final stationStatsList = <StationEvidenceStats>[];

  for (final s in detail.stations) {
    int stHighlighted = 0;
    int stDamage = 0;
    int stFrass = 0;
    int stLarva = 0;
    int stEgg = 0;

    int stAssessable = 0;
    int stCurrentSigns = 0;

    for (final p in s.plants) {
      final veg = p.vegetativeOrNull;
      final rep = p.reproductive;
      final ear = p.ear;
      final plant = p.plant;
      if (screeningMode) {
        final screen = detail.screeningFor(p);
        if (screen == null) continue;
        if (!screen.screeningSucceeded) continue;
        stAssessable++;
        if (screen.positive) {
          stDamage++;
          stCurrentSigns++;
        }
        if (screen.result.detectionBoxes.isNotEmpty || screen.highlighted) {
          highlightedPlants++;
          stHighlighted++;
          if (screen.result.detectionBoxes.any((b) => b.classId == 1)) {
            stFrass++;
          }
          if (screen.result.detectionBoxes.any((b) => b.classId == 2)) {
            stLarva++;
          }
          if (screen.result.detectionBoxes.any((b) => b.classId == 3)) stEgg++;
        }
        continue;
      }

      if (plant.assessable || ear?.externallyAssessable == true) {
        stAssessable++;
      }

      // Check damage
      final hasDamage =
          (veg != null &&
              (veg.smallFreshWindowpanes ||
                  veg.infestedWhorl ||
                  veg.scraping ||
                  veg.cuttingOrTearing ||
                  veg.whorlFeedingSign ||
                  (veg.daBafsLeafDamageScore != null &&
                      veg.daBafsLeafDamageScore! > 0))) ||
          (rep != null &&
              (rep.freshFeedingPresent || rep.earHuskPenetrationVisible)) ||
          (ear != null &&
              (ear.externalDamagePresent == true ||
                  ear.internalDamagePresent == true)) ||
          plant.plantStatus == DatabaseCodes.plantCurrentPositive;

      // Check frass
      final hasFrass =
          (veg != null && veg.freshFrass) ||
          (rep != null && rep.frassPresent) ||
          (ear != null && ear.frassPresent == true);

      // Check larva
      final hasLarva =
          (veg != null &&
              (veg.larvaVisible ||
                  (veg.larvaCount != null && veg.larvaCount! > 0))) ||
          (rep != null &&
              (rep.larvaPresent ||
                  (rep.larvaCount != null && rep.larvaCount! > 0))) ||
          (ear != null && ear.larvaPresent == true);

      // Check eggs
      final hasEgg = (veg != null && veg.eggMassVisible == true);

      if (hasDamage) stDamage++;
      if (hasFrass) stFrass++;
      if (hasLarva) stLarva++;
      if (hasEgg) stEgg++;

      if (plant.plantStatus == DatabaseCodes.plantCurrentPositive ||
          rep?.percentInfestedPositive == true ||
          ear?.activeInfestationPresent == true) {
        stCurrentSigns++;
      }
    }

    // Include planting unit observations if seedling
    for (final unit
        in screeningMode ? <PlantingUnitObservationRecord>[] : detail.units) {
      if (unit.stationId == s.station?.id) {
        if (unit.visibleCutting == true || unit.visibleSeedlingInjury == true) {
          stDamage++;
        }
        if (unit.freshFrass == true) stFrass++;
        if (unit.larvaVisible == true) stLarva++;
      }
    }

    // Prefer the repository's persisted station summary for the rate
    // denominator/current-sign count. This avoids deriving a denominator from
    // unrelated evidence-category counts.
    StationResultSummary? persistedStationSummary;
    for (final summaryStation in detail.resultSummary.stations) {
      if (summaryStation.blockRunId == s.prepared.run.id &&
          summaryStation.stationNumber == s.stationNumber) {
        persistedStationSummary = summaryStation;
        break;
      }
    }
    if (persistedStationSummary != null && !screeningMode) {
      stAssessable = persistedStationSummary.assessableObservationCount;
      stCurrentSigns = persistedStationSummary.currentSignsCount;
    }

    totalDamage += stDamage;
    totalFrass += stFrass;
    totalLarvae += stLarva;
    totalEggs += stEgg;
    totalCurrentSigns += stCurrentSigns;

    final stationId = s.station?.id;
    final photoCount = stationId == null
        ? 0
        : detail.evidence
              .where(
                (e) =>
                    e.stationId == stationId &&
                    e.media.storageState == DatabaseCodes.evidenceStorageReady,
              )
              .length;

    final stRate = stAssessable > 0
        ? (stCurrentSigns / stAssessable * 100)
        : 0.0;

    stationStatsList.add(
      StationEvidenceStats(
        screeningMode: screeningMode,
        highlightedPlants: stHighlighted,
        stationNumber: s.stationNumber,
        blockSequence: s.prepared.run.blockSequence,
        damageCount: stDamage,
        frassCount: stFrass,
        larvaCount: stLarva,
        eggCount: stEgg,
        assessableCount: stAssessable,
        positiveCount: stCurrentSigns,
        recordedCount: s.plants.length,
        infestationPercent: stRate,
        photoCount: photoCount,
        snapshot: s,
      ),
    );
  }

  // Determine whole-assessment primary metric
  final summary = detail.resultSummary;
  AssessmentMetricRollup? primary;
  for (final m in summary.metrics) {
    if (screeningMode
        ? m.metricCode == AutomaticScreening.metric
        : (m.metricCode == DatabaseCodes.vegetativeCurrentInfestationPercent ||
              m.metricCode == DatabaseCodes.vtR2InfestedPlantPercent ||
              m.metricCode == DatabaseCodes.externalEarDamagePercent ||
              m.metricCode == DatabaseCodes.pooledDamagedKernelPercent)) {
      primary = m;
      break;
    }
  }
  primary ??= summary.metrics.isNotEmpty ? summary.metrics.first : null;

  final double num;
  final double den;
  final double percent;
  final bool isZeroDen;
  final String code;
  final String unit;

  if (screeningMode) {
    code = AutomaticScreening.metric;
    unit = 'percent';
    num = totalDamage.toDouble();
    den = stationStatsList
        .fold<int>(0, (sum, station) => sum + station.assessableCount)
        .toDouble();
    isZeroDen = den == 0;
    percent = isZeroDen ? 0.0 : num / den * 100;
  } else if (primary != null) {
    code = primary.metricCode;
    unit = primary.unit;
    num = primary.numerator ?? 0;
    den = primary.denominator ?? 0;
    isZeroDen = den == 0 || primary.warningCodes.contains('zero_denominator');
    percent = isZeroDen
        ? 0.0
        : (primary.value ?? (den > 0 ? (num / den * 100) : 0.0));
  } else {
    code = screeningMode
        ? AutomaticScreening.metric
        : DatabaseCodes.vegetativeCurrentInfestationPercent;
    unit = 'percent';
    den = summary.assessableObservationCount.toDouble();
    num = summary.stations
        .fold<int>(0, (sum, s) => sum + s.currentSignsCount)
        .toDouble();
    isZeroDen = den == 0;
    percent = isZeroDen ? 0.0 : (num / den * 100);
  }

  // Evidence-category cards are counts of recorded observation records, so
  // their denominator must remain an observation denominator even when the
  // primary whole-assessment metric uses ears or kernels.
  final totalAssessable = screeningMode
      ? den.toInt()
      : summary.assessableObservationCount;
  final clean = math.max(0, totalAssessable - totalCurrentSigns);

  return AssessmentEvidenceStats(
    screeningMode: screeningMode,
    highlightedPlants: highlightedPlants,
    damageCount: totalDamage,
    frassCount: totalFrass,
    larvaCount: totalLarvae,
    eggCount: totalEggs,
    totalAssessable: totalAssessable,
    totalRecorded: summary.recordedObservationCount,
    cleanCount: clean,
    overallInfestationPercent: percent,
    primaryNumerator: num,
    primaryDenominator: den,
    primaryMetricCode: code,
    primaryUnit: unit,
    isZeroDenominator: isZeroDen,
    stationStats: stationStatsList,
  );
}
