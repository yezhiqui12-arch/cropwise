import 'dart:convert';
import 'dart:io';
import 'package:wormwise/services/advisor/advisor_answer_validation.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';

void main() {
  const ragService = AdvisorRagService();
  final cases = <(String, String, String?)>[
    ('en', 'what are the characteristics of a faw', 'identify-larva'),
    ('en', 'how do i detect faw', 'identify-larva'),
    ('en', 'What is fresh frass in the whorl?', 'evidence-frass'),
    ('fil', 'Ano ang dumi ng uod sa mais?', 'evidence-frass'),
    ('taglish', 'May fresh dumi sa whorl, ano ito?', 'evidence-frass'),
    ('en', 'How often should I scout maize?', 'scout-schedule'),
    ('fil', 'Gaano kadalas mag-inspeksyon sa mais?', 'scout-schedule'),
    ('taglish', 'How often mag scout ng mais?', 'scout-schedule'),
    ('en', 'What pesticide dose should I spray?', 'safety-pesticide'),
    ('fil', 'Anong dosis ng pestisidyo ang ilalagay?', 'safety-pesticide'),
    ('taglish', 'Anong spray at dose para sa uod?', 'safety-pesticide'),
    ('en', 'Who can help with uncertain identification?', 'expert-escalation'),
    (
      'fil',
      'Saan hihingi ng tulong sa agriculture office?',
      'expert-escalation',
    ),
    ('taglish', 'Need expert help for identification', 'expert-escalation'),
    ('en', 'How do I bake chocolate cake?', null),
    ('fil', 'Paano gumawa ng tsokolateng cake?', null),
    ('taglish', 'Can you debug my Python script?', null),
  ];
  final report = <String>[
    '# Focused Advisor grounding evaluation',
    '',
    'Date: ${DateTime.now().toIso8601String().split('T').first}. Deterministic engineering checks; no live model calls or expert approval.',
    '',
    '| Language | Question | Expected passage | Result |',
    '| --- | --- | --- | --- |',
  ];
  var failed = 0;
  for (final (language, question, expected) in cases) {
    final context = ragService.retrieve(question, forAi: true).bounded();
    final matches = context.results.map((r) => r.chunk.id).toList();
    final passed = expected == null
        ? matches.isEmpty
        : matches.take(3).contains(expected);
    if (!passed) failed++;
    report.add(
      '| $language | $question | ${expected ?? 'No match'} | ${passed ? 'PASS' : 'FAIL'}: ${matches.join(', ')} |',
    );
    if (context.toPromptText().length > 12000 ||
        context.results.any((r) => !AdvisorRagService.isAiEligible(r.chunk))) {
      throw StateError('Evidence eligibility or context budget failed');
    }
  }
  final chunk = AdvisorRagService.chunks.firstWhere(
    (c) => c.id == 'evidence-frass',
  );
  final context = AdvisorRagContext(
    query: 'frass',
    results: [AdvisorRetrievedChunk(chunk: chunk, score: 1)],
    sources: AdvisorRagService.sources,
  );
  final answer = chunk.summary;
  final base = <String, dynamic>{
    'supported': true,
    'safe': true,
    'safety_issues': [],
    'needs_reference': true,
    'has_record_facts': false,
    'passages': [
      {'article_id': chunk.id, 'quote': chunk.summary, 'claim': answer},
    ],
    'record_claims': [],
  };
  bool checked(
    String text,
    Map<String, dynamic> review, {
    Map<String, dynamic>? records,
  }) => AdvisorAnswerValidation.check(
    answer: text,
    review: review,
    rag: context,
    records: records,
  ).accepted;
  final checks = <(String, bool)>[
    ('Exact supporting passage accepted', checked(answer, base)),
    (
      'Fabricated quote rejected',
      !checked(answer, {
        ...base,
        'passages': [
          {
            'article_id': chunk.id,
            'quote': 'This quote does not exist.',
            'claim': answer,
          },
        ],
      }),
    ),
    (
      'Unretrieved article rejected',
      !checked(answer, {
        ...base,
        'passages': [
          {
            'article_id': 'fake-article',
            'quote': chunk.summary,
            'claim': answer,
          },
        ],
      }),
    ),
    (
      'Unsupported answer withheld',
      !checked(answer, {...base, 'supported': false}),
    ),
    (
      'Missing required evidence rejected',
      !checked(answer, {...base, 'passages': []}),
    ),
    (
      'Pesticide dose blocked',
      AdvisorAnswerValidation.hasUnsafeInstruction(
        'Spray 20 ml of pesticide per liter.',
      ),
    ),
    (
      'Definitive model diagnosis blocked',
      AdvisorAnswerValidation.hasProhibitedDecision({
        'safety_issues': ['definitive_model_diagnosis'],
      }),
    ),
    (
      'Feed safety clearance blocked',
      AdvisorAnswerValidation.hasUnsafeInstruction(
        'This grain is safe to feed.',
      ),
    ),
    (
      'Safety refusal retained',
      !AdvisorAnswerValidation.hasUnsafeInstruction(
        'Do not spray 20 ml based on a photo.',
      ),
    ),
  ];
  final records = <String, dynamic>{
    'reads': [
      {
        'result': {'denominator': 20},
      },
    ],
  };
  final recordReview = <String, dynamic>{
    ...base,
    'needs_reference': false,
    'has_record_facts': true,
    'passages': [],
    'record_claims': [
      {
        'claim': '20 plants',
        'path': 'reads.0.result.denominator',
        'value_json': '20',
      },
    ],
  };
  checks.add((
    'Recorded denominator accepted',
    checked('20 plants', recordReview, records: records),
  ));
  checks.add((
    'Altered denominator rejected',
    !checked('99 plants', {
      ...recordReview,
      'record_claims': [
        {
          'claim': '99 plants',
          'path': 'reads.0.result.denominator',
          'value_json': '99',
        },
      ],
    }, records: records),
  ));
  checks.add((
    'False assertion rejected despite matching evidence value',
    !checked('99 plants', {
      ...recordReview,
      'record_claims': [
        {
          'claim': '99 plants',
          'path': 'reads.0.result.denominator',
          'value_json': '20',
        },
      ],
    }, records: records),
  ));
  checks.add((
    'Missing record path rejected',
    !checked('20 plants', {
      ...recordReview,
      'record_claims': [
        {
          'claim': '20 plants',
          'path': 'reads.4.result.denominator',
          'value_json': '20',
        },
      ],
    }, records: records),
  ));
  checks.add((
    'Empty history claim accepted',
    checked(
      'No saved assessments',
      {
        ...recordReview,
        'record_claims': [
          {
            'claim': 'No saved assessments',
            'path': 'assessments',
            'value_json': '[]',
          },
        ],
      },
      records: {'assessments': []},
    ),
  ));
  checks.add((
    'Whitespace in exact quotes accepted',
    checked(answer, {
      ...base,
      'passages': [
        {
          'article_id': chunk.id,
          'quote': chunk.summary.replaceAll(' ', '\n'),
          'claim': answer,
        },
      ],
    }),
  ));
  checks.add((
    'Negative safety verdict rejected even without a listed issue',
    !checked(answer, {...base, 'safe': false, 'safety_issues': []}),
  ));
  checks.add((
    'Explicit prescription rejected',
    !checked(answer, {
      ...base,
      'safety_issues': ['pesticide_prescription'],
    }),
  ));
  checks.add((
    'Recorded confirmation wording is not a photo diagnosis',
    !AdvisorAnswerValidation.hasUnsafeInstruction(
      'The saved assessment records confirmed FAW observations.',
    ),
  ));
  report.addAll(['', '## Evidence, records and safety checks', '']);
  for (final (name, passed) in checks) {
    if (!passed) failed++;
    report.add('- ${passed ? 'PASS' : 'FAIL'}: $name');
  }
  report.addAll([
    '',
    '## Article disposition',
    '',
    '| Article | AI grounding | Sources awaiting verification |',
    '| --- | --- | --- |',
  ]);
  for (final c in AdvisorRagService.chunks) {
    final unchecked = c.sourceIds
        .where(
          (id) =>
              id != 'WORMWISE-PROTOCOL' &&
              AdvisorRagService.sources[id]?.hasVerifiedReference != true,
        )
        .join(', ');
    report.add(
      '| ${c.id} | ${AdvisorRagService.isAiEligible(c) ? 'Eligible for descriptive/operational use' : 'Excluded pending review'} | ${unchecked.isEmpty ? (c.grade == AdvisorEvidenceGrade.expertValidationRequired ? 'Technical validation required' : 'None; expert approval still pending') : unchecked} |',
    );
  }
  report.addAll([
    '',
    'These checks measure expected top-three retrieval matches, exact evidence integrity, record integrity and local safety rules separately. They do not measure live model factual support, helpful refusals, or recall across all farmer questions. The question set is not expert-reviewed.',
    '',
    'Remaining primary-source blockers: CIMMYT repository access denied, PhilRice full PDF too large for browser extraction, and the DA-BPI photographed leaflet has no verified edition/public URL. A source check is not claim-level or local agronomic approval.',
  ]);
  File(
    'docs/ADVISOR_GROUNDING_EVALUATION.md',
  ).writeAsStringSync('${report.join('\n')}\n');
  stdout.writeln(
    jsonEncode({
      'retrieval_questions': cases.length,
      'validation_checks': checks.length,
      'failures': failed,
      'report': 'docs/ADVISOR_GROUNDING_EVALUATION.md',
    }),
  );
  if (failed != 0) exitCode = 1;
}
