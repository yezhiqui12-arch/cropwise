import 'advisor_app_action.dart';

/// One interpretation shared by retrieval, record tools and response actions.
/// It is conversational intent, never evidence of saved facts.
class AdvisorConversationContext {
  const AdvisorConversationContext({
    required this.question,
    required this.intent,
    required this.referenceQuery,
    this.actionId,
    this.needsRecords = false,
    this.needsReferences = false,
    this.recordScope = 'unspecified',
  });
  final String question;
  final String intent;
  final String referenceQuery;
  final String? actionId;
  final bool needsRecords;
  final bool needsReferences;
  final String recordScope;

  factory AdvisorConversationContext.fromJson(Map<String, dynamic> json) {
    final question = json['question'];
    final intent = json['intent'];
    if (question is! String ||
        question.trim().isEmpty ||
        question.length > 2000 ||
        json['needs_records'] is! bool ||
        json['needs_references'] is! bool ||
        !const [
          'navigation',
          'records',
          'education',
          'photo',
          'conversation',
          'clarification',
        ].contains(intent)) {
      throw const FormatException('Invalid conversation interpretation');
    }
    final id = json['action_id'];
    final action = id is String ? AdvisorAppActionCatalog.byId(id) : null;
    if (id != null && id != '' && (action == null || intent != 'navigation')) {
      throw const FormatException('Invalid navigation destination');
    }
    final query = json['reference_query'];
    return AdvisorConversationContext(
      question: question.trim(),
      intent: intent as String,
      referenceQuery: query is String
          ? query.substring(0, query.length.clamp(0, 2000))
          : question,
      actionId: action?.id,
      recordScope:
          const [
            'selected_assessment',
            'field_history',
            'all_fields',
            'none',
          ].contains(json['record_scope'])
          ? json['record_scope'] as String
          : 'unspecified',
      needsRecords:
          (intent == 'records' ||
              json['needs_records'] == true ||
              const [
                'selected_assessment',
                'field_history',
                'all_fields',
              ].contains(json['record_scope'])) &&
          intent != 'conversation' &&
          intent != 'clarification',
      needsReferences:
          json['needs_references'] == true &&
          (intent != 'navigation' || action?.id == 'open_guidelines') &&
          intent != 'conversation' &&
          intent != 'clarification',
    );
  }
  List<AdvisorAppAction> actions(Iterable<AdvisorAppAction> proposed) {
    if (intent != 'navigation') return const [];
    final action = actionId == null
        ? null
        : AdvisorAppActionCatalog.byId(actionId!);
    return action == null
        ? AdvisorAppActionPolicy.validateForUserRequest(question, proposed)
        : [action];
  }

  Map<String, dynamic> toJson() => {
    'question': question,
    'intent': intent,
    'action_id': actionId,
    'reference_query': referenceQuery,
    'needs_records': needsRecords,
    'needs_references': needsReferences,
    'record_scope': recordScope,
  };
}
