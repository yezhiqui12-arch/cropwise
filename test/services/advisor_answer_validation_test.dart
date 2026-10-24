import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_answer_validation.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';

const emptyContext = AdvisorRagContext(query: '', results: [], sources: {});
Map<String, dynamic> acceptedReview() => {
  'supported': true,
  'safe': true,
  'safety_issues': [],
  'needs_reference': false,
  'has_record_facts': false,
  'passages': [],
  'record_claims': [],
};

void main() {
  bool accepted(
    Map<String, dynamic> review, {
    String answer = 'Open Assess to view saved assessments.',
  }) => AdvisorAnswerValidation.check(
    answer: answer,
    review: review,
    rag: emptyContext,
  ).accepted;
  test(
    'requires an affirmative safety verdict and a well-formed empty issues list',
    () {
      expect(accepted(acceptedReview()), isTrue);
      expect(accepted({...acceptedReview(), 'safe': false}), isFalse);
      for (final issues in [
        null,
        'none',
        ['pesticide_prescription'],
        ['unknown_issue'],
      ]) {
        expect(
          accepted({...acceptedReview(), 'safety_issues': issues}),
          isFalse,
        );
      }
      expect(accepted({...acceptedReview(), 'supported': false}), isFalse);
    },
  );
  test(
    'decimal doses and separate warning clauses do not bypass the local check',
    () {
      for (final text in [
        'Spray 2.5 ml per litre.',
        'Do not overwater; spray 5 ml per litre.',
        'Huwag sobrahan pero ilagay 2.5 ml.',
        'Do not spray without checking, but apply 5 ml per litre.',
        'This grain is safe to feed.',
      ]) {
        expect(
          AdvisorAnswerValidation.hasUnsafeInstruction(text),
          isTrue,
          reason: text,
        );
      }
      expect(
        AdvisorAnswerValidation.hasUnsafeInstruction(
          'Do not spray 2.5 ml per litre.',
        ),
        isFalse,
      );
      expect(
        AdvisorAnswerValidation.hasUnsafeInstruction(
          'This grain is not confirmed safe to feed.',
        ),
        isFalse,
      );
      expect(
        accepted(acceptedReview(), answer: 'Spray 2.5 ml per litre.'),
        isFalse,
      );
    },
  );
  test('unsupported or fabricated evidence cannot certify an answer', () {
    expect(accepted({...acceptedReview(), 'needs_reference': true}), isFalse);
    expect(
      accepted({
        ...acceptedReview(),
        'passages': [
          {
            'article_id': 'invented',
            'quote': 'Invented reference quote',
            'claim': 'Open Assess',
          },
        ],
      }),
      isFalse,
    );
  });
  test('record claims require existing paths and matching values', () {
    final review = {
      ...acceptedReview(),
      'has_record_facts': true,
      'record_claims': [
        {'path': 'sample.plants', 'value_json': '20', 'claim': '20 plants'},
      ],
    };
    bool checked(Map<String, dynamic> evidence, Map<String, dynamic> verdict) =>
        AdvisorAnswerValidation.check(
          answer: 'The sample contains 20 plants.',
          review: verdict,
          rag: emptyContext,
          records: evidence,
        ).accepted;
    expect(
      checked({
        'sample': {'plants': 20},
      }, review),
      isTrue,
    );
    expect(
      checked({
        'sample': {'plants': 18},
      }, review),
      isFalse,
    );
    expect(checked({}, review), isFalse);
    expect(
      checked(
        {
          'sample': {'plants': 20},
        },
        {
          ...review,
          'record_claims': [
            {'path': '', 'value_json': '20', 'claim': ''},
          ],
        },
      ),
      isFalse,
    );
  });
}
