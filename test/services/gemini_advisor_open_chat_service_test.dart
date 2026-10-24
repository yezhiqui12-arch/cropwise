import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_gemini_settings.dart';
import 'package:wormwise/services/advisor/advisor_app_action.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/services/advisor/gemini_advisor_open_chat_service.dart';

void main() {
  test(
    'PDF capability is supplied without records or retrieved references',
    () async {
      final transport = _RecordingTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(shareFieldContext: false),
        ),
        transport: transport,
      );
      await service.answer(
        const AdvisorOpenChatRequest(
          question: 'Should I share an assessment PDF with a crop expert?',
          history: [
            AdvisorOpenChatTurn(
              role: AdvisorOpenChatRole.advisor,
              text: 'PDF export is not available.',
            ),
            AdvisorOpenChatTurn(
              role: AdvisorOpenChatRole.advisor,
              text:
                  'Use five stations with ten consecutive plants at each station.',
            ),
          ],
        ),
      );
      final instruction =
          ((transport.body!['system_instruction'] as Map)['parts'] as List)
              .map((p) => (p as Map)['text'])
              .join('\n');
      expect(instruction, contains('DOES export'));
      expect(instruction, contains('DA monitoring form'));
      expect(instruction, contains('Expert findings PDF'));
      expect(instruction, contains('only after expert finalization'));
      expect(instruction, contains('20 different plants'));
      expect(instruction, contains('1–3 photos'));
      expect(instruction, isNot(contains('five-station sampling protocol')));
      expect(instruction, contains('Include evidence photos'));
      expect(instruction, contains('device share sheet'));
      expect(instruction, contains('does not submit, update, close'));
      expect(instruction, contains('override historical app-help claims'));
      expect(
        jsonEncode(transport.body),
        isNot(contains('Use five stations with ten consecutive plants')),
      );
    },
  );

  test('PDF navigation opens results rather than expert messages', () {
    final actions = AdvisorAppActionPolicy.validateForUserRequest(
      'How do I share my assessment PDF with an expert?',
      const [],
    );
    expect(actions.single.id, 'view_results');
    expect(actions.single.description, contains('only opens Results'));
    expect(
      AdvisorAppActionPolicy.validateForUserRequest(
        'Should I share a PDF with an expert?',
        const [],
      ),
      isEmpty,
    );
  });

  test('records the model actually chosen by the server', () async {
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(configured: true),
      transport: _RemoteModelTransport(),
    );
    final answer = await service.answer(_request());
    expect(answer.source.version, 'gemini-3.8-flash');
  });

  test('greeting after fields chat does not repeat navigation', () async {
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(configured: true),
      transport: const _ActionTransport(
        answer: 'Hi! What would you like help with?',
        actionId: 'manage_fields',
      ),
    );
    final answer = await service.answer(
      const AdvisorOpenChatRequest(
        question: 'hi',
        history: [
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.farmer,
            text: 'Where can I find my fields?',
          ),
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.advisor,
            text: 'Open Home, then My Fields.',
          ),
        ],
      ),
    );

    expect(answer.summary, 'Hi! What would you like help with?');
    expect(answer.appActions, isEmpty);
  });

  test('correction does not repeat a previous action', () async {
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(configured: true),
      transport: const _ActionTransport(
        answer: 'Sorry, I misunderstood. What would you like to ask?',
        actionId: 'manage_fields',
      ),
    );
    final answer = await service.answer(
      const AdvisorOpenChatRequest(
        question: "I didn't ask to open fields",
        history: [
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.farmer,
            text: 'Where can I find my fields?',
          ),
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.advisor,
            text: 'Open Home, then My Fields.',
          ),
        ],
      ),
    );

    expect(
      answer.summary,
      'Sorry, I misunderstood. What would you like to ask?',
    );
    expect(answer.appActions, isEmpty);
  });

  test(
    'explicit navigation keeps the model answer and offers the button',
    () async {
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(configured: true),
        transport: const _ActionTransport(
          answer: 'Open Home, tap the menu, then choose My Fields.',
          actionId: 'manage_fields',
        ),
      );
      final answer = await service.answer(
        const AdvisorOpenChatRequest(question: 'Open my fields', history: []),
      );

      expect(answer.summary, 'Open Home, tap the menu, then choose My Fields.');
      expect(answer.appActions.single.id, 'manage_fields');
    },
  );

  test(
    'ambiguous where follow-up can resolve the previous field request',
    () async {
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(configured: true),
        transport: const _ActionTransport(
          answer: 'They are under My Fields in the Home menu.',
          actionId: 'manage_fields',
        ),
      );
      final answer = await service.answer(
        const AdvisorOpenChatRequest(
          question: 'where?',
          history: [
            AdvisorOpenChatTurn(
              role: AdvisorOpenChatRole.farmer,
              text: 'I want to find my fields',
            ),
            AdvisorOpenChatTurn(
              role: AdvisorOpenChatRole.advisor,
              text: 'I can help with that.',
            ),
          ],
        ),
      );

      expect(answer.summary, 'They are under My Fields in the Home menu.');
      expect(answer.appActions.single.id, 'manage_fields');
    },
  );

  test('rejected navigation is never offered by the policy', () {
    expect(
      AdvisorAppActionPolicy.validateForUserRequest(
        "I didn't ask to open fields",
        [AdvisorAppActionCatalog.manageFields],
      ),
      isEmpty,
    );
  });

  test('repeated greeting gets a clean retry for a new message', () async {
    final transport = _RepeatingGreetingTransport(
      repairAnswer: 'What would you like me to tell you about?',
    );
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(configured: true),
      transport: transport,
    );
    final answer = await service.answer(
      const AdvisorOpenChatRequest(
        question: 'tell me tell mee',
        history: [
          AdvisorOpenChatTurn(role: AdvisorOpenChatRole.farmer, text: 'hi'),
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.advisor,
            text: 'Hello! How can I help you use WormWise today?',
          ),
        ],
      ),
    );

    expect(transport.callCount, 2);
    expect(transport.repairContents, hasLength(1));
    expect(answer.summary, 'What would you like me to tell you about?');
  });

  test('persistent repeated greeting becomes a clarification', () async {
    final transport = _RepeatingGreetingTransport();
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(configured: true),
      transport: transport,
    );
    final answer = await service.answer(
      const AdvisorOpenChatRequest(
        question: 'tomohawk',
        history: [
          AdvisorOpenChatTurn(role: AdvisorOpenChatRole.farmer, text: 'hi'),
          AdvisorOpenChatTurn(
            role: AdvisorOpenChatRole.advisor,
            text: 'Hello! How can I help you use WormWise today?',
          ),
        ],
      ),
    );

    expect(transport.callCount, 2);
    expect(answer.summary, contains('tomohawk'));
    expect(answer.summary, isNot(contains('Hello!')));
  });

  test(
    'serializes ordered history once and honors historical sharing gates',
    () async {
      for (final shareLocation in [false, true]) {
        final transport = _RecordingTransport();
        final service = GeminiAdvisorOpenChatService(
          settingsStore: _MemorySettingsStore(
            configured: true,
            preferences: AdvisorGeminiPreferences(
              enabled: true,
              shareFieldContext: true,
              shareLocation: shareLocation,
            ),
          ),
          transport: transport,
        );
        await service.answer(
          const AdvisorOpenChatRequest(
            question: 'Explain it further',
            history: [
              AdvisorOpenChatTurn(
                role: AdvisorOpenChatRole.farmer,
                text: 'Earlier question',
              ),
              AdvisorOpenChatTurn(
                role: AdvisorOpenChatRole.advisor,
                text: 'Earlier answer',
              ),
              AdvisorOpenChatTurn(
                role: AdvisorOpenChatRole.farmer,
                text: 'My field',
                requiresFieldContextSharing: true,
                requiresLocationSharing: true,
              ),
              AdvisorOpenChatTurn(
                role: AdvisorOpenChatRole.advisor,
                text: 'Private barangay',
                requiresFieldContextSharing: true,
                requiresLocationSharing: true,
              ),
            ],
          ),
        );
        final contents = transport.body!['contents'] as List;
        expect(contents, hasLength(shareLocation ? 5 : 3));
        expect(contents.first['role'], 'user');
        expect(contents[1]['role'], 'model');
        expect(contents.last['parts'][0]['text'], 'Explain it further');
        expect(
          transport.body.toString().contains('Private barangay'),
          shareLocation,
        );
      }
    },
  );

  test('requires a user-provided API key', () async {
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(),
      transport: _RecordingTransport(),
    );

    expect(
      () => service.answer(_request()),
      throwsA(isA<AdvisorGeminiNotConfiguredException>()),
    );
  });

  test('sends an enabled open question and parses Gemini text', () async {
    final settings = _MemorySettingsStore(
      configured: true,
      preferences: const AdvisorGeminiPreferences(enabled: true),
    );
    final transport = _RecordingTransport();
    final service = GeminiAdvisorOpenChatService(
      settingsStore: settings,
      transport: transport,
    );

    final answer = await service.answer(_request());

    expect(transport.model, GeminiAdvisorOpenChatService.defaultModel);
    expect(answer.topicId, 'gemini_open_chat');
    expect(answer.title, 'WormWise AI');
    expect(answer.summary, 'A farmer-friendly Gemini answer.');
    expect(answer.suggestedActions, [
      'Inspect the newest leaves',
      'Explain common causes',
    ]);
    expect(
      transport.body!['generationConfig'],
      containsPair('responseJsonSchema', isA<Map<String, dynamic>>()),
    );
    expect(answer.details, isEmpty);
    expect(answer.source.label, 'Google Gemini');
    expect(transport.body.toString(), contains('entire WormWise application'));
    expect(transport.body.toString(), contains('Home for the current field'));
  });

  test(
    'field, location, and photo data stay out when sharing is disabled',
    () async {
      final transport = _RecordingTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(enabled: true),
        ),
        transport: transport,
      );

      await service.answer(_request(includeContext: true));
      final encoded = transport.body.toString();

      expect(encoded, isNot(contains('Private Field')));
      expect(encoded, isNot(contains('Boundary coordinates')));
      expect(encoded, isNot(contains('inline_data')));
    },
  );

  test(
    'includes approved context and on-device model findings without photo data',
    () async {
      final transport = _RecordingTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(
            enabled: true,
            shareFieldContext: true,
            shareLocation: true,
          ),
        ),
        transport: transport,
      );

      await service.answer(
        _request(includeContext: true, includeModelFindings: true),
      );
      final encoded = transport.body.toString();

      expect(encoded, contains('Private Field'));
      expect(encoded, contains('Boundary coordinates'));
      expect(encoded, contains('Larval damage'));
      expect(encoded, isNot(contains('inline_data')));
    },
  );

  test(
    'does not spend a second request when output reaches its limit',
    () async {
      final transport = _TruncatingTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(enabled: true),
        ),
        transport: transport,
      );

      final answer = await service.answer(_request());

      expect(transport.callCount, 1);
      expect(answer.summary, 'First portion.');
    },
  );

  test('fails over to a lite backup when the primary is overloaded', () async {
    final transport = _OverloadedPrimaryTransport();
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(
        configured: true,
        preferences: const AdvisorGeminiPreferences(enabled: true),
      ),
      transport: transport,
    );

    final answer = await service.answer(_request());

    expect(transport.models, ['gemini-3.6-flash', 'gemini-3.5-flash-lite']);
    expect(answer.source.version, 'gemini-3.5-flash-lite');
  });

  test(
    'fails over to next model when primary model is retired or unavailable',
    () async {
      final transport = _UnavailablePrimaryTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(enabled: true),
        ),
        transport: transport,
      );

      final answer = await service.answer(_request());

      expect(transport.models, ['gemini-3.6-flash', 'gemini-3.5-flash-lite']);
      expect(answer.source.version, 'gemini-3.5-flash-lite');
    },
  );

  test(
    'creates a dynamic photo question and validated action suggestions',
    () async {
      final transport = _PhotoFollowUpTransport();
      final service = GeminiAdvisorOpenChatService(
        settingsStore: _MemorySettingsStore(
          configured: true,
          preferences: const AdvisorGeminiPreferences(enabled: true),
        ),
        transport: transport,
      );

      final answer = await service.answer(
        _request(includeModelFindings: true, photoFollowUpOnly: true),
      );

      expect(answer.topicId, 'gemini_photo_follow_up');
      expect(
        answer.summary,
        'Which part of these model findings should we explore?',
      );
      expect(answer.suggestedActions, hasLength(3));
      expect(answer.suggestedActions, contains('Explain the detected damage'));
      expect(
        transport.body['generationConfig'],
        containsPair('responseMimeType', 'application/json'),
      );
      expect(
        transport.body['generationConfig'],
        containsPair('responseJsonSchema', isA<Map<String, dynamic>>()),
      );
      expect(transport.body.toString(), isNot(contains('inline_data')));
    },
  );

  test('rejects photo suggestions that the chatbot cannot perform', () async {
    final service = GeminiAdvisorOpenChatService(
      settingsStore: _MemorySettingsStore(
        configured: true,
        preferences: const AdvisorGeminiPreferences(enabled: true),
      ),
      transport: _InvalidPhotoActionTransport(),
    );

    expect(
      () => service.answer(
        _request(includeModelFindings: true, photoFollowUpOnly: true),
      ),
      throwsA(isA<AdvisorGeminiApiException>()),
    );
  });
}

AdvisorOpenChatRequest _request({
  bool includeContext = false,
  bool includeModelFindings = false,
  bool photoFollowUpOnly = false,
}) {
  return AdvisorOpenChatRequest(
    question: 'Why are the leaves curling?',
    history: const [
      AdvisorOpenChatTurn(
        role: AdvisorOpenChatRole.farmer,
        text: 'Earlier question',
      ),
      AdvisorOpenChatTurn(
        role: AdvisorOpenChatRole.advisor,
        text: 'Earlier answer',
      ),
    ],
    fieldContext: includeContext
        ? const AdvisorOpenChatFieldContext(
            fieldAndAssessmentSummary: 'Private Field assessment values',
            locationSummary: 'Boundary coordinates',
          )
        : null,
    modelFindings: includeModelFindings
        ? 'Larval damage: 82% at normalized box (0.1, 0.2, 0.5, 0.7)'
        : null,
    photoFollowUpOnly: photoFollowUpOnly,
  );
}

class _MemorySettingsStore implements AdvisorGeminiSettingsStore {
  _MemorySettingsStore({this.configured = false, AdvisorGeminiPreferences? preferences})
    : preferences = preferences ?? const AdvisorGeminiPreferences();

  bool configured;
  AdvisorGeminiPreferences preferences;

  @override
  Future<bool> isServiceConfigured() async => configured;

  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _RemoteModelTransport implements AdvisorGeminiTransport {
  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async => {
    'wormwiseModel': 'gemini-3.8-flash',
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text':
                  '{"answer":"A farmer-friendly Gemini answer.","suggestions":[]}',
            },
          ],
        },
      },
    ],
  };
}

class _RecordingTransport implements AdvisorGeminiTransport {
  String? model;
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    this.model = model;
    this.body = body;
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"answer":"A farmer-friendly Gemini answer.",'
                    '"suggestions":["Inspect the newest leaves",'
                    '"Explain common causes"]}',
              },
            ],
          },
        },
      ],
    };
  }
}

class _ActionTransport implements AdvisorGeminiTransport {
  const _ActionTransport({required this.answer, required this.actionId});

  final String answer;
  final String actionId;

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async => {
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text':
                  '{"answer":${_jsonString(answer)},"suggestions":[],"action_ids":[${_jsonString(actionId)}]}',
            },
          ],
        },
      },
    ],
  };
}

class _RepeatingGreetingTransport implements AdvisorGeminiTransport {
  _RepeatingGreetingTransport({this.repairAnswer});

  final String? repairAnswer;
  int callCount = 0;
  List<dynamic>? repairContents;

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    callCount++;
    if (callCount == 2) repairContents = body['contents'] as List;
    final answer = callCount == 2 && repairAnswer != null
        ? repairAnswer!
        : 'Hello! How can I help you use WormWise today?';
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"answer":${_jsonString(answer)},"suggestions":[],"action_ids":[]}',
              },
            ],
          },
        },
      ],
    };
  }
}

String _jsonString(String value) => jsonEncode(value);

class _TruncatingTransport implements AdvisorGeminiTransport {
  int callCount = 0;
  Map<String, dynamic> lastBody = const {};

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    callCount++;
    lastBody = body;
    return {
      'candidates': [
        {
          if (callCount == 1) 'finishReason': 'MAX_TOKENS',
          'content': {
            'parts': [
              {
                'text': callCount == 1
                    ? '{"answer":"First portion.","suggestions":['
                          '"Explain this","Tell me more"]}'
                    : '{"answer":"Final portion.","suggestions":['
                          '"Explain this","Tell me more"]}',
              },
            ],
          },
        },
      ],
    };
  }
}

class _PhotoFollowUpTransport implements AdvisorGeminiTransport {
  Map<String, dynamic> body = const {};

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    this.body = body;
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"question":"Which part of these model findings should we explore?",'
                    '"suggestions":["Explain the detected damage",'
                    '"Check whether the signs are FAW-consistent",'
                    '"Explain the confidence score"]}',
              },
            ],
          },
        },
      ],
    };
  }
}

class _OverloadedPrimaryTransport implements AdvisorGeminiTransport {
  final List<String> models = [];

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    models.add(model);
    if (models.length == 1) {
      throw const AdvisorGeminiApiException('Overloaded', statusCode: 503);
    }
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"answer":"Backup response.","suggestions":['
                    '"Explain this","Tell me more"]}',
              },
            ],
          },
        },
      ],
    };
  }
}

class _UnavailablePrimaryTransport implements AdvisorGeminiTransport {
  final List<String> models = [];

  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    models.add(model);
    if (models.length == 1) {
      throw const AdvisorGeminiApiException(
        'This model models/gemini-3.6-flash is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite.',
        statusCode: 400,
      );
    }
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"answer":"Fallback model response.","suggestions":['
                    '"Explain this","Tell me more"]}',
              },
            ],
          },
        },
      ],
    };
  }
}

class _InvalidPhotoActionTransport implements AdvisorGeminiTransport {
  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async => {
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text':
                  '{"question":"What next?","suggestions":['
                  '"Continue assessment","Open Scout"]}',
            },
          ],
        },
      },
    ],
  };
}
