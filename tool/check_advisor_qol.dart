import 'dart:io';
import 'package:wormwise/services/advisor/advisor_conversation_context.dart';
import 'package:wormwise/services/advisor/advisor_app_action.dart';
import 'package:wormwise/services/advisor/advisor_suggestion_policy.dart';

void main() {
  var checks = 0;
  void check(bool condition, String message) {
    checks++;
    if (!condition) throw StateError(message);
  }

  List<String> suggestions(
    String reason,
    String question, {
    List<String> previous = const [],
    List<String>? fields,
  }) => AdvisorSuggestionPolicy.validate(
    reason: reason,
    question: question,
    proposed: [
      'Explain the result',
      'Compare assessments',
      'Compare assessments',
    ],
    previous: previous,
    fieldChoices: fields,
  );
  check(
    suggestions('none', 'Explain all findings in detail').isEmpty,
    'Long answers must allow zero suggestions',
  );
  check(
    suggestions('assessment_follow_up', 'My results?').length == 2,
    'Short questions must allow useful suggestions',
  );
  check(
    suggestions('uncertainty', 'Hello').isEmpty,
    'Greetings must not generate suggestions',
  );
  check(
    suggestions(
          'uncertainty',
          'What is missing?',
          previous: ['Explain the result'],
        ).length ==
        1,
    'Do not repeat earlier suggestions',
  );
  check(
    suggestions(
      'clarification',
      'Which field?',
      fields: ['North Field'],
    ).isEmpty,
    'Do not invent field options',
  );
  final action = AdvisorAppActionCatalog.viewResults.withTarget(
    fieldId: 'field-1',
    assessmentId: 'assessment-1',
  );
  final restored = AdvisorAppAction.fromJson(action.toJson());
  check(
    restored?.assessmentId == 'assessment-1' && restored?.fieldId == 'field-1',
    'Persist target identity',
  );
  check(
    AdvisorAppActionCatalog.all.map((a) => a.id).toSet().length ==
        AdvisorAppActionCatalog.all.length,
    'Registry IDs must be unique',
  );
  check(
    AdvisorAppActionPolicy.validateForUserRequest('Open language preferences', [
          AdvisorAppActionCatalog.openLanguage,
        ]).single.id ==
        'open_language',
    'Validate implemented destinations',
  );
  check(
    AdvisorAppActionPolicy.validateForUserRequest(
      'Hello',
      AdvisorAppActionCatalog.all,
    ).isEmpty,
    'Do not navigate on greetings',
  );

  check(
    AdvisorAppActionPolicy.validateForUserRequest(
          'where can I choose models',
          [],
        ).single.id ==
        'open_models',
    'Plural Models destination must work',
  );
  check(
    AdvisorAppActionPolicy.validateForUserRequest(
          'Open More > Models',
          [],
        ).single.id ==
        'open_models',
    'Concrete destination must win over its parent',
  );
  check(
    AdvisorAppActionPolicy.validateForUserRequest(
      'what about management about pheromone',
      AdvisorAppActionCatalog.all,
    ).isEmpty,
    'No substring navigation from pheromone or management',
  );
  check(
    AdvisorAppActionPolicy.validateForUserRequest(
      'Tell me more about detection',
      AdvisorAppActionCatalog.all,
    ).isEmpty,
    'Education must not become navigation',
  );
  for (final destination in ['Guidelines', 'Notifications', 'Field trends']) {
    check(
      AdvisorAppActionPolicy.validateForUserRequest(
        'Open $destination',
        [],
      ).isNotEmpty,
      'Plural app destination: $destination',
    );
  }
  AdvisorConversationContext resolved(
    String intent,
    String question, {
    String id = '',
    bool records = false,
    bool references = false,
  }) => AdvisorConversationContext.fromJson({
    'intent': intent,
    'question': question,
    'reference_query': question,
    'action_id': id,
    'needs_records': records,
    'needs_references': references,
  });
  final menu = resolved(
    'navigation',
    'Show the menu path to Models',
    id: 'open_models',
    references: true,
  );
  check(
    !menu.needsReferences && !menu.needsRecords,
    'Resolved menu route must skip agricultural references and private records',
  );
  check(
    menu.actions([AdvisorAppActionCatalog.openMore]).single.id == 'open_models',
    'Resolved destination must beat wrong generated action',
  );
  final scouting = resolved(
    'education',
    'Explain the five-station scouting route',
    references: true,
  );
  check(
    scouting.needsReferences &&
        scouting.actions(AdvisorAppActionCatalog.all).isEmpty,
    'Scouting route must use education without menu actions',
  );
  final samples = resolved(
    'records',
    'Compare stations in my latest assessment',
    records: true,
  );
  check(
    samples.needsRecords &&
        samples.actions(AdvisorAppActionCatalog.all).isEmpty,
    'Sample comparisons must read records without unsolicited navigation',
  );
  final clarify = resolved(
    'clarification',
    'Which field do you mean?',
    records: true,
    references: true,
  );
  check(
    !clarify.needsRecords &&
        !clarify.needsReferences &&
        clarify.actions(AdvisorAppActionCatalog.all).isEmpty,
    'Ambiguity must not select records or actions',
  );
  final greeting = resolved(
    'conversation',
    'Hi',
    records: true,
    references: true,
  );
  check(
    !greeting.needsRecords && !greeting.needsReferences,
    'Greetings must not fetch data',
  );
  var invalidRejected = false;
  try {
    resolved('navigation', 'Open an invented page', id: 'invented');
  } on FormatException {
    invalidRejected = true;
  }
  check(invalidRejected, 'Reject unknown resolver destination');
  check(
    AdvisorSuggestionPolicy.validate(
          reason: 'assessment_follow_up',
          proposed: ['Would you like to explain your results?'],
          question: 'Results?',
        ).single ==
        'Explain my results',
    'Follow-up messages use the user voice',
  );

  check(
    AdvisorAppActionPolicy.validateForUserRequest(
          'Open Artificial Intelligence preferences',
          [],
        ).single.id ==
        'open_artificial_intelligence',
    'AI preferences has a registered direct destination',
  );
  final article = resolved(
    'navigation',
    'Open the guide about larvae',
    id: 'open_guidelines',
    references: true,
  );
  check(
    article.needsReferences && !article.needsRecords,
    'A specific guideline may retrieve article evidence without field data',
  );
  stdout.writeln('Advisor QoL checks passed ($checks checks).');
}
