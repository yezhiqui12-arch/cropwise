import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';

/// Versioned evidence requirements for the V3-V12 five-station pilot.
///
/// New sessions use one overview plus an evaluator-selected conditional
/// close-up. Older policies remain readable to preserve accepted evidence.
enum StationEvidencePolicy {
  cameraFirstOverviewConditional(
    DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
  ),
  station1TwoView(
    DatabaseCodes.evidencePolicyStation1TwoViewV1,
    stationNumber: 1,
  ),
  humanWorkloadSafe(DatabaseCodes.evidencePolicyHumanWorkloadSafeV1);

  const StationEvidencePolicy(this.requirementsVersion, {this.stationNumber});

  final String requirementsVersion;
  final int? stationNumber;

  static StationEvidencePolicy forStation(int stationNumber) {
    if (stationNumber < 1 || stationNumber > 5) {
      throw ArgumentError.value(stationNumber, 'stationNumber', 'Must be 1-5');
    }
    return StationEvidencePolicy.cameraFirstOverviewConditional;
  }

  static StationEvidencePolicy fromRequirementsVersion(String value) {
    return switch (value) {
      DatabaseCodes.evidencePolicyStation1TwoViewV1 =>
        StationEvidencePolicy.station1TwoView,
      DatabaseCodes.evidencePolicyHumanWorkloadSafeV1 =>
        StationEvidencePolicy.humanWorkloadSafe,
      DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1 =>
        StationEvidencePolicy.cameraFirstOverviewConditional,
      'camera_phase_a_v1' => StationEvidencePolicy.station1TwoView,
      _ => throw StateError('Unsupported evidence requirements: $value'),
    };
  }

  Set<String> captureCompletionViews(EvidenceCaptureBundleView bundle) {
    if (this == StationEvidencePolicy.station1TwoView) {
      return const {
        DatabaseCodes.evidenceViewWhorlOverview,
        DatabaseCodes.evidenceViewCloseUp,
      };
    }
    if (this == StationEvidencePolicy.cameraFirstOverviewConditional) {
      return const {DatabaseCodes.evidenceViewWhorlOverview};
    }
    return {
      for (final viewType in const {
        DatabaseCodes.evidenceViewWhorlOverview,
        DatabaseCodes.evidenceViewCloseUp,
        DatabaseCodes.evidenceViewDiagnosticDetail,
      })
        if (bundle.isViewSatisfied(viewType)) viewType,
    };
  }

  Set<String> requiredViewsForObservation({
    required PlantObservationRecord plant,
    required VegetativeObservationRecord vegetative,
  }) {
    if (!plant.assessable) return const {};
    if (this == StationEvidencePolicy.station1TwoView) {
      return const {
        DatabaseCodes.evidenceViewWhorlOverview,
        DatabaseCodes.evidenceViewCloseUp,
      };
    }
    if (this == StationEvidencePolicy.cameraFirstOverviewConditional) {
      // The accepted overview is the policy baseline. A close-up is captured
      // when the evaluator decides the overview is insufficient to confirm an
      // observation; the presence of a raw sign alone must not force a return
      // to the plant after continuous capture.
      return const {DatabaseCodes.evidenceViewWhorlOverview};
    }
    final supportingImageRequired =
        plant.currentFawEvidence == true ||
        plant.possibleNonFawEvidence == true ||
        plant.uncertainEvidence == true ||
        vegetative.larvaVisible ||
        vegetative.eggMassVisible == true;
    return supportingImageRequired
        ? const {DatabaseCodes.evidenceViewWhorlOverview}
        : const {};
  }
}

/// Minimal view used by the policy to avoid coupling it to a repository type.
abstract interface class EvidenceCaptureBundleView {
  bool isViewSatisfied(String viewType);
}
