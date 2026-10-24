import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';

void main() {
  const service = AdvisorKnowledgeService();

  group('AdvisorKnowledgeService', () {
    test('provides field-aware and offline knowledge suggestions', () {
      expect(AdvisorKnowledgeService.suggestedQuestions, hasLength(10));
      expect(
        AdvisorKnowledgeService.suggestedQuestions.map((item) => item.id),
        containsAll(<String>[
          'field_context',
          'assessment_explanation',
          'inspect_plant',
          'frass',
          'recognize_faw',
          'photos',
          'uncertain',
          'expert_help',
          'cultural_practices',
          'natural_predators',
        ]),
      );
    });

    test('routes natural-language frass questions to approved guidance', () {
      final answer = service.answer('What are the droppings in the whorl?');

      expect(answer.topicId, 'frass');
      expect(answer.summary, contains('does not confirm fall armyworm'));
      expect(answer.source.reference, contains('DA-provided Harabas booklet'));
      expect(answer.source.version, isNotEmpty);
    });

    test('does not turn FAW-like damage into a confirmed diagnosis', () {
      final answer = service.answer('How do I recognize armyworm damage?');

      expect(answer.topicId, 'recognize_faw');
      expect(answer.title, contains('cannot confirm FAW'));
      expect(answer.summary, contains('Confirming the species requires'));
      expect(answer.details.join(' '), contains('not enough to confirm FAW'));
    });

    test('refuses pesticide prescription and directs qualified review', () {
      final answer = service.answer(
        'What pesticide treatment should I spray on my maize plants?',
      );
      final completeAnswer = <String>[
        answer.title,
        answer.summary,
        ...answer.details,
        if (answer.nextAction != null) answer.nextAction!,
      ].join(' ');

      expect(answer.topicId, 'treatment_safety');
      expect(completeAnswer, contains('does not prescribe'));
      expect(completeAnswer, contains('qualified agricultural professional'));
      expect(completeAnswer, isNot(contains(RegExp(r'\bml\b|\bgrams?\b'))));
    });

    test('unknown questions remain inside the declared offline scope', () {
      final answer = service.answer('How much will corn sell for next year?');

      expect(answer.topicId, 'unknown');
      expect(answer.title, contains('focused scope'));
      expect(answer.details, contains(contains('selected field status')));
      expect(
        service.tryAnswer('How much will corn sell for next year?'),
        isNull,
      );
    });

    test('cultural FAW question routes to cultural practices topic', () {
      final answer = service.answer('What cultural practices help manage FAW?');
      expect(answer.topicId, 'cultural_practices');
    });

    test('natural predator FAW question routes to natural predators topic', () {
      final answer = service.answer('What natural predators control FAW?');
      expect(answer.topicId, 'natural_predators');
    });
  });
}
