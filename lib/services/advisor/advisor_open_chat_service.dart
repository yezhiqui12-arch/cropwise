import 'advisor_knowledge_service.dart';

/// Signals that the online Advisor response could not be reached.
class AdvisorOnlineUnavailableException implements Exception {
  const AdvisorOnlineUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum AdvisorOpenChatRole { farmer, advisor }

class AdvisorOpenChatTurn {
  const AdvisorOpenChatTurn({
    required this.role,
    required this.text,
    this.requiresFieldContextSharing = false,
    this.requiresLocationSharing = false,
  });

  final bool requiresFieldContextSharing;
  final bool requiresLocationSharing;
  final AdvisorOpenChatRole role;
  final String text;
}

class AdvisorOpenChatRequest {
  const AdvisorOpenChatRequest({
    required this.question,
    required this.history,
    this.fieldContext,
    this.modelFindings,
    this.modelSummary,
    this.photoFollowUpOnly = false,
    this.preferFastModel = false,
    this.languageCode = 'en',
    this.dataTools,
    this.activeFieldId,
    this.assessmentScopeId,
    this.previousSuggestions = const [],
  });

  final String question;
  final List<AdvisorOpenChatTurn> history;
  final AdvisorOpenChatFieldContext? fieldContext;
  final String? modelFindings;
  final String? modelSummary;
  final bool photoFollowUpOnly;
  final bool preferFastModel;
  final String languageCode;
  final AdvisorDataTools? dataTools;
  final String? activeFieldId;

  /// Non-null only for an assessment conversation. Overall Advisor leaves it null.
  final String? assessmentScopeId;
  final List<String> previousSuggestions;
}

/// Read-only, bounded access to records. Never exposes database writes to AI.
abstract interface class AdvisorDataTools {
  Future<Map<String, dynamic>> read(
    String tool,
    Map<String, dynamic> arguments,
  );
}

class AdvisorOpenChatFieldContext {
  const AdvisorOpenChatFieldContext({
    required this.fieldAndAssessmentSummary,
    this.locationSummary,
    this.records,
  });

  final String fieldAndAssessmentSummary;
  final String? locationSummary;
  final Map<String, dynamic>? records;
}

/// Optional boundary for open-ended chat that the built-in guide cannot answer.
///
/// Optional field context and structured findings from the on-device image
/// model may be present. Raw photos are never part of this boundary.
abstract interface class AdvisorOpenChatService {
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request);
}
