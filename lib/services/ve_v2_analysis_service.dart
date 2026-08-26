import '../data/repositories/evidence_capture_repository.dart';

/// UI states reserved for a future validated, asynchronous VE-V2 model.
///
/// The current production adapter returns [unavailable] immediately. It never
/// invents a queue delay, a finding, a confidence value, or a diagnosis.
enum VeV2AnalysisState {
  waiting,
  processing,
  suggestionsReady,
  insufficientEvidence,
  unsupportedEvidence,
  failed,
  unavailable,
}

class VeV2AnalysisPresentation {
  const VeV2AnalysisPresentation({
    required this.state,
    this.suggestedLabels = const [],
  });

  final VeV2AnalysisState state;

  /// Suggestions stay separate from evaluator-confirmed database fields.
  /// This is empty in the current build because no validated model is present.
  final List<String> suggestedLabels;

  static const unavailable = VeV2AnalysisPresentation(
    state: VeV2AnalysisState.unavailable,
  );
}

abstract interface class VeV2AnalysisService {
  Future<VeV2AnalysisPresentation> presentationFor(
    EvidenceCaptureBundle evidence,
  );
}

/// Honest current implementation used until a validated model is integrated.
final class UnavailableVeV2AnalysisService implements VeV2AnalysisService {
  const UnavailableVeV2AnalysisService();

  @override
  Future<VeV2AnalysisPresentation> presentationFor(
    EvidenceCaptureBundle evidence,
  ) async => VeV2AnalysisPresentation.unavailable;
}
