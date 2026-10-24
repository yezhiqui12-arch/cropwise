import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';

void main() {
  const service = AdvisorRagService();

  group('AdvisorRagService retrieval', () {
    test('answers a generic FAW question with relevant grounded content', () {
      final context = service.retrieve('What is FAW?');

      expect(context.results, isNotEmpty);
      expect(context.results.first.chunk.category, 'Identification');
      expect(context.results.first.chunk.body.toLowerCase(), contains('faw'));
    });

    test('ranks larva identification first for an English farmer query', () {
      final context = service.retrieve(
        'How can I identify a fall armyworm larva in my corn?',
      );

      expect(context.results, isNotEmpty);
      expect(context.results.first.chunk.id, 'identify-larva');
      expect(context.results.first.chunk.category, 'Identification');
    });

    test('understands Filipino aliases for common field evidence', () {
      final frass = service.retrieve('May dumi ng uod sa whorl ng mais');
      final eggs = service.retrieve('May itlog sa dahon ng mais');
      final larva = service.retrieve('May uod sa mais, paano ito kilalanin?');

      expect(frass.results.first.chunk.id, 'evidence-frass');
      expect(eggs.results.first.chunk.id, 'identify-eggs');
      expect(larva.results.first.chunk.id, 'identify-larva');
    });

    test('ranks representative scouting and boundary articles correctly', () {
      final scouting = service.retrieve(
        'How many stations should I use for a representative field assessment?',
      );
      final boundary = service.retrieve(
        'Should a field boundary include a road, pond, or house?',
      );

      expect(scouting.results.first.chunk.id, 'scout-field');
      expect(scouting.results.first.chunk.category, 'Scouting Protocol');
      expect(boundary.results.first.chunk.id, 'scout-boundary');
      expect(boundary.results.first.chunk.category, 'Scouting Protocol');
    });

    test('always places pesticide safety guidance first for pesticide advice', () {
      final context = service.retrieve(
        'What pesticide should I spray and what dose should I mix?',
        maxResults: 3,
      );

      expect(context.results, isNotEmpty);
      expect(context.results.first.chunk.id, 'safety-pesticide');
      expect(
        context.results.first.chunk.warning,
        AdvisorRagService.pesticideWarning,
      );
      expect(
        context.results.first.chunk.sourceIds,
        containsAll(<String>['FPA', 'FAO-SAFETY']),
      );
    });

    test('does not interpret moderate as the pesticide term rate', () {
      final context = service.retrieve(
        'Why is my assessment marked moderate risk?',
      );

      expect(context.results, isNotEmpty);
      expect(context.results.first.chunk.id, isNot('safety-pesticide'));
      expect(context.results.first.chunk.id, 'management-threshold');
    });

    test('includes validation-required guidance for treatment thresholds', () {
      final context = service.retrieve(
        'At what treatment threshold percentage should I spray?',
        maxResults: 5,
      );
      final threshold = context.results.singleWhere(
        (result) => result.chunk.id == 'management-threshold',
      );

      expect(context.results.first.chunk.id, 'safety-pesticide');
      expect(
        threshold.chunk.grade,
        AdvisorEvidenceGrade.expertValidationRequired,
      );
      expect(threshold.chunk.isPublishable, isFalse);
      expect(threshold.chunk.warning, AdvisorRagService.decisionWarning);
      expect(
        context.toPromptText(),
        contains('Actionable publication status: false'),
      );
    });

    test('matches whole terms without substring safety false positives', () {
      final context = service.retrieve('Explain the moderate assessment label');

      expect(
        context.results.map((result) => result.chunk.id),
        isNot(contains('safety-pesticide')),
      );
    });

    test('returns an empty context for empty or unrelated input', () {
      final empty = service.retrieve('   ');
      final unrelated = service.retrieve('quartz nebula violin');

      expect(empty.isEmpty, isTrue);
      expect(empty.query, isEmpty);
      expect(unrelated.isEmpty, isTrue);
      expect(unrelated.query, 'quartz nebula violin');
    });

    test('exposes resolvable source metadata in results and prompt context', () {
      final context = service.retrieve('How do I inspect maize leaf damage?');
      final sourceIds = context.results
          .expand((result) => result.chunk.sourceIds)
          .toSet();

      expect(sourceIds, isNotEmpty);
      for (final sourceId in sourceIds) {
        final source = context.sources[sourceId];
        expect(
          source,
          isNotNull,
          reason: 'Missing source metadata for $sourceId',
        );
        expect(source!.label, isNotEmpty);
        expect(source.reference, isNotEmpty);
        expect(source.jurisdiction, isNotEmpty);
      }
      expect(context.sourceSummary, isNotEmpty);
      expect(context.toPromptText(), contains('SOURCE CATALOG'));
      expect(context.toPromptText(), contains('[${sourceIds.first}]'));
    });
  });
}
