import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/providers/advisor_controller.dart';
import 'package:wormwise/services/advisor/advisor_gemini_settings.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';
import 'package:wormwise/services/advisor/gemini_advisor_open_chat_service.dart';
import 'advisor_answer_validation_test.dart' show acceptedReview;

void main() {
  test('server quota rejection stops client model failover', () async {
    final transport = _GateTransport()..failure = 'server_quota';
    await expectLater(
      _service(transport).answer(_request()),
      throwsA(isA<AdvisorGeminiApiException>()),
    );
    expect(transport.totalCalls, 1);
  });
  for (final showSources in [false, true]) {
    test(
      'keeps verified supporting passages with source display $showSources',
      () async {
        const question = 'What does frass mean?';
        final chunk = const AdvisorRagService()
            .retrieve(question, forAi: true)
            .results
            .first
            .chunk;
        final transport = _GateTransport()
          ..referenceQuery = question
          ..answer = chunk.summary
          ..review = {
            ...acceptedReview(),
            'needs_reference': true,
            'passages': [
              {
                'article_id': chunk.id,
                'quote': chunk.summary,
                'claim': chunk.summary,
              },
            ],
          };
        final answer = await _service(
          transport,
          showSources: showSources,
        ).answer(_request(question: question));
        expect(answer.supportingPassages.single.articleId, chunk.id);
        expect(answer.supportingPassages.single.quote, chunk.summary);
        expect(transport.reviewCalls, 1);
      },
    );
    test(
      'reviews substantive answers with supporting sources $showSources',
      () async {
        final transport = _GateTransport();
        final answer = await _service(
          transport,
          showSources: showSources,
        ).answer(_request());
        expect(answer.summary, transport.answer);
        expect(transport.reviewCalls, 1);
      },
    );
    test(
      'withholds rejected drafts with supporting sources $showSources',
      () async {
        final transport = _GateTransport()
          ..review = {...acceptedReview(), 'supported': false};
        await expectLater(
          _service(transport, showSources: showSources).answer(_request()),
          throwsA(isA<AdvisorGeminiApiException>()),
        );
        expect(transport.reviewCalls, 1);
      },
    );
  }
  test(
    'withholds a negative safety verdict without a specific issue',
    () async {
      final transport = _GateTransport()
        ..review = {...acceptedReview(), 'safe': false};
      await expectLater(
        _service(transport).answer(_request()),
        throwsA(isA<AdvisorGeminiApiException>()),
      );
    },
  );
  for (final failure in [
    'timeout',
    'invalid_json',
    'missing_text',
    'array_json',
  ]) {
    test('$failure in review cannot return the unchecked draft', () async {
      final transport = _GateTransport()..failure = failure;
      await expectLater(
        _service(transport).answer(_request()),
        throwsA(isA<AdvisorGeminiApiException>()),
      );
      expect(transport.reviewCalls, 1);
    });
  }
  test('a greeting request cannot bypass an unsafe generated answer', () async {
    final transport = _GateTransport()
      ..answer = 'Do not overwater; spray 2.5 ml per litre.';
    await expectLater(
      _service(transport).answer(_request(question: 'Hi')),
      throwsA(isA<AdvisorGeminiApiException>()),
    );
    expect(transport.reviewCalls, 0);
  });
  test('a bare greeting avoids the extra review request', () async {
    final transport = _GateTransport()..answer = 'Hello!';
    expect(
      (await _service(transport).answer(_request(question: 'Hi'))).summary,
      'Hello!',
    );
    expect(transport.reviewCalls, 0);
  });
  test('photo follow-up output is reviewed while sources are hidden', () async {
    final transport = _GateTransport()..photo = true;
    final reply = await _service(transport).answer(
      const AdvisorOpenChatRequest(
        question: '',
        history: [],
        photoFollowUpOnly: true,
        modelFindings:
            'The saved model suggests a larva; identity is unconfirmed.',
      ),
    );
    expect(reply.summary, transport.answer);
    expect(transport.reviewCalls, 1);
  });
  test('mismatched saved-record claims are withheld', () async {
    final transport = _GateTransport()
      ..answer = 'The sample contains 20 plants.'
      ..review = {
        ...acceptedReview(),
        'has_record_facts': true,
        'record_claims': [
          {
            'path': 'selected_context.sample.plants',
            'value_json': '20',
            'claim': '20 plants',
          },
        ],
      };
    await expectLater(
      _service(transport).answer(
        const AdvisorOpenChatRequest(
          question: 'Explain this sample',
          history: [],
          fieldContext: AdvisorOpenChatFieldContext(
            fieldAndAssessmentSummary: 'The sample contains 18 plants.',
            records: {
              'sample': {'plants': 18},
            },
          ),
        ),
      ),
      throwsA(isA<AdvisorGeminiApiException>()),
    );
  });
  test(
    'failed review leaves no guide bubble and retry does not duplicate the question',
    () async {
      final transport = _GateTransport()
        ..review = {...acceptedReview(), 'supported': false};
      final controller = AdvisorController(
        openChatService: _service(transport),
      );
      addTearDown(controller.dispose);
      await controller.ask('Explain the app help menu');
      expect(controller.replyState, AdvisorReplyState.error);
      expect(controller.canRetryOpenChat, isTrue);
      expect(controller.messages, hasLength(1));
      transport.review = acceptedReview();
      await controller.retryOpenChat();
      expect(controller.replyState, AdvisorReplyState.idle);
      expect(controller.messages, hasLength(2));
      expect(controller.messages.last.answer!.summary, transport.answer);
    },
  );
}

AdvisorOpenChatRequest _request({
  String question = 'Explain the app help menu',
}) => AdvisorOpenChatRequest(question: question, history: const []);
GeminiAdvisorOpenChatService _service(
  _GateTransport transport, {
  bool showSources = false,
}) => GeminiAdvisorOpenChatService(
  settingsStore: _Settings(showSources),
  transport: transport,
  model: 'test-model',
);

class _Settings implements AdvisorGeminiSettingsStore {
  _Settings(this.showSources);
  final bool showSources;
  @override
  Future<bool> isServiceConfigured() async => true;
  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async =>
      AdvisorGeminiPreferences(showSupportingSources: showSources);
  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {}
}

class _GateTransport implements AdvisorGeminiTransport {
  String answer = 'Open Help to read the app instructions.';
  Map<String, dynamic> review = acceptedReview();
  String? failure;
  bool photo = false;
  String referenceQuery = '';
  int reviewCalls = 0;
  int totalCalls = 0;
  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    totalCalls++;
    if (failure == 'server_quota') {
      throw const AdvisorGeminiApiException(
        'You have reached the Advisor request limit. Please try again later.',
        statusCode: 429,
        terminal: true,
      );
    }
    final properties =
        (body['generationConfig'] as Map)['responseJsonSchema']['properties']
            as Map;
    Object output;
    if (properties.containsKey('supported')) {
      reviewCalls++;
      if (failure == 'timeout') throw TimeoutException('test review timeout');
      if (failure == 'missing_text') return {};
      if (failure == 'invalid_json') return _response('{');
      if (failure == 'array_json') return _response('[]');
      output = review;
    } else if (properties.containsKey('intent')) {
      output = {
        'question': 'Explain the app help menu',
        'intent': referenceQuery.isEmpty ? 'conversation' : 'education',
        'reference_query': referenceQuery,
        'action_id': '',
        'needs_records': false,
        'needs_references': referenceQuery.isNotEmpty,
        'record_scope': 'none',
        'reason': 'test',
      };
    } else {
      output = {
        photo ? 'question' : 'answer': answer,
        'suggestion_reason': 'none',
        'suggestions': [],
        'action_ids': [],
      };
    }
    return _response(jsonEncode(output));
  }

  Map<String, dynamic> _response(String text) => {
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  };
}
