import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';

void main() {
  const service = AdvisorRagService();

  AdvisorKnowledgeChunk top(String query) =>
      service.retrieve(query).results.first.chunk;

  group('AdvisorRagService retrieval', () {
    test('answers a generic FAW question from identification content', () {
      final result = service.retrieve('What is fall armyworm?');

      expect(result.results, isNotEmpty);
      expect(result.results.first.chunk.category, 'Identification');
    });

    test('ranks English larva identification guidance', () {
      expect(top('How do I identify an FAW larva?').id, 'identify-larva');
    });

    test('expands nonspecific Filipino caterpillar language cautiously', () {
      final result = service.retrieve('Ano itong uod sa mais?');

      expect(result.results, isNotEmpty);
      expect(result.results.first.chunk.id, 'identify-larva');
      expect(result.results.first.chunk.warning, isNotNull);
    });

    test('retrieves frass for Filipino farmer wording', () {
      expect(top('May dumi ng uod sa busbos ng mais').id, 'evidence-frass');
    });

    test('treats itlog as an egg query without confirming FAW', () {
      final article = top('May itlog sa dahon ng mais');

      expect(article.id, 'identify-eggs');
      expect(article.body.toLowerCase(), contains('not definitive'));
    });

    test('ranks boundary guidance for roads inside a polygon', () {
      expect(
        top('Should I include a road inside the field boundary?').id,
        'scout-boundary',
      );
    });

    test('forces pesticide safety to the first result', () {
      final result = service.retrieve('What pesticide dose should I spray?');

      expect(result.results.first.chunk.id, 'safety-pesticide');
      expect(
        result.results.first.chunk.warning,
        AdvisorRagService.pesticideWarning,
      );
    });

    test('moderate risk does not match the rate safety term', () {
      final result = service.retrieve('What does moderate risk mean?');

      expect(result.results, isNotEmpty);
      expect(result.results.first.chunk.id, isNot('safety-pesticide'));
    });

    test('unvalidated threshold content cannot be actionable', () {
      final article = service
          .retrieve('What treatment threshold should I use?')
          .results
          .map((item) => item.chunk)
          .firstWhere((item) => item.id == 'management-threshold');

      expect(article.grade, AdvisorEvidenceGrade.expertValidationRequired);
      expect(article.isPublishable, isFalse);
    });

    test('empty and unrelated queries return no grounding passages', () {
      expect(service.retrieve(' ').results, isEmpty);
      expect(service.retrieve('bitcoin exchange price').results, isEmpty);
      expect(service.retrieve('quartz nebula violin sa mais').results, isEmpty);
    });

    test(
      'uses Taglish topic cues without treating maize as enough evidence',
      () {
        expect(top('May amag sa corn ear').id, 'safety-ear-grain');
        expect(top('May dumi ng uod sa busbos').id, 'evidence-frass');
      },
    );

    test('filters stage-specific passages while keeping general guidance', () {
      final result = service.retrieve(
        'How should I inspect maize at R4?',
        growthStage: 'R4',
      );
      expect(result.results, isNotEmpty);
      expect(
        result.results.where(
          (item) =>
              item.chunk.growthStages.isNotEmpty &&
              !item.chunk.growthStages.contains('R4'),
        ),
        isEmpty,
      );
      expect(
        service
            .retrieve('How do I inspect an ear?', category: 'Safety')
            .results
            .every((item) => item.chunk.category == 'Safety'),
        isTrue,
      );
    });

    test('prompt contains article and source provenance', () {
      final context = service.retrieve('How should I scout the field?');
      final prompt = context.toPromptText();

      expect(prompt, contains('WORMWISE CURATED REFERENCE CONTEXT'));
      expect(prompt, contains('Actionable publication status:'));
      expect(prompt, contains('SOURCE CATALOG'));
      for (final result in context.results) {
        for (final sourceId in result.chunk.sourceIds) {
          expect(AdvisorRagService.sources, contains(sourceId));
        }
      }
    });
  });
}
