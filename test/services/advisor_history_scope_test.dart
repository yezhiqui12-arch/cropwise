import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/advisor_context_repository.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/services/advisor/advisor_gemini_settings.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/services/advisor/advisor_record_catalog.dart';
import 'package:wormwise/services/advisor/gemini_advisor_open_chat_service.dart';
import '../support/assessment_history_fixture.dart';

void main() {
  group('whole-app history', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'includes previous crop cycles, other fields, archives and all statuses',
      () async {
        final first = await historyFixture(db, status: 'in_progress');
        await db
            .into(db.cropCycles)
            .insert(
              CropCyclesCompanion.insert(
                id: 'old-cycle',
                fieldId: first.field.field.id,
                status: const Value('completed'),
              ),
            );
        final previous = await AssessmentRepository(db).createDraft(
          cropCycleId: 'old-cycle',
          boundaryVersionId: first.field.boundary!.id,
          evaluatorPersonId: first.assessment.evaluatorPersonId,
          assessmentMode: 've_v6',
          scoutingPattern: 'w',
          growthStage: 'v3_v6',
          protocolVersion: 'test-protocol',
          formulaVersion: 'test-formula',
        );
        await (db.update(db.assessments)
              ..where((a) => a.id.equals(previous.id)))
            .write(const AssessmentsCompanion(status: Value('completed')));
        final other = await historyFixture(
          db,
          name: 'Archived south plot',
          status: 'draft',
        );
        await (db.update(db.fields)
              ..where((f) => f.id.equals(other.field.field.id)))
            .write(const FieldsCompanion(isArchived: Value(true)));
        final tools = AdvisorContextRepository(db);
        final catalog = await loadAdvisorRecordCatalog(tools);
        expect(catalog['coverage_complete'], true);
        expect(catalog['total_assessments'], 3);
        expect(catalog['status_counts'], {
          'in_progress': 1,
          'completed': 1,
          'draft': 1,
        });
        expect((catalog['assessments'] as List).map((a) => a['id']).toSet(), {
          first.assessment.id,
          previous.id,
          other.assessment.id,
        });
        final history = await tools.read('list_assessments', {
          'field_id': first.field.field.id,
        });
        expect((history['assessments'] as List).length, 2);
        final archived = await tools.read('get_assessment', {
          'field_id': other.field.field.id,
        });
        expect(archived['assessment_id'], other.assessment.id);
      },
    );

    test('pagination goes beyond the former 50-record cutoff', () async {
      final first = await historyFixture(db);
      for (var i = 0; i < 54; i++) {
        await AssessmentRepository(db).createDraft(
          cropCycleId: first.assessment.cropCycleId,
          boundaryVersionId: first.assessment.boundaryVersionId,
          evaluatorPersonId: first.assessment.evaluatorPersonId,
          assessmentMode: 've_v6',
          scoutingPattern: 'w',
          growthStage: 'v3_v6',
          protocolVersion: 'test-protocol',
          formulaVersion: 'test-formula',
        );
      }
      final tools = AdvisorContextRepository(db);
      final catalog = await loadAdvisorRecordCatalog(tools);
      expect(catalog['total_assessments'], 55);
      expect(catalog['retrieved_assessments'], 55);
      expect(catalog['coverage_complete'], true);
      expect(
        (catalog['assessments'] as List).map((r) => r['id']).toSet().length,
        55,
      );
      final history = await tools.read('list_assessments', {
        'field_id': first.field.field.id,
      });
      expect((history['assessments'] as List).length, 55);
      expect(history['truncated'], false);
    });

    test(
      'deleted assessment is excluded and a subsequent new assessment is discovered',
      () async {
        final first = await historyFixture(db);
        final second = await historyFixture(db, name: 'Second plot');
        await (db.update(db.assessments)
              ..where((a) => a.id.equals(first.assessment.id)))
            .write(AssessmentsCompanion(deletedAt: Value(DateTime.now())));
        final tools = AdvisorContextRepository(db);
        expect((await loadAdvisorRecordCatalog(tools))['total_assessments'], 1);
        final next = await historyFixture(db, name: 'Third plot');
        final catalog = await loadAdvisorRecordCatalog(tools);
        expect(catalog['total_assessments'], 2);
        expect((catalog['assessments'] as List).map((r) => r['id']).toSet(), {
          second.assessment.id,
          next.assessment.id,
        });
      },
    );
  });

  test(
    'all summaries reach the answer even when the planner returns no calls',
    () async {
      final tools = _CatalogTools();
      final transport = _ScopeTransport('all_fields');
      await GeminiAdvisorOpenChatService(
        settingsStore: _Settings(),
        transport: transport,
      ).answer(
        AdvisorOpenChatRequest(
          question: 'How does my newest visit stack up against the rest?',
          history: const [],
          dataTools: tools,
          activeFieldId: 'north',
        ),
      );
      expect(tools.offsets, [0, 2]);
      final payload = (transport.answers.single['contents'] as List)
          .expand((c) => (c as Map)['parts'] as List)
          .map((p) => (p as Map)['text'])
          .whereType<String>()
          .join('\n');
      for (final id in [
        'current-draft',
        'older-completed',
        'other-field-visit',
      ]) {
        expect(payload, contains(id));
      }
      expect(payload, contains('"coverage_complete":true'));
      expect(payload, contains('"total_assessments":3'));
    },
  );

  test(
    'cross-record meaning routes assessment chat without fetching other records',
    () async {
      for (final question in [
        'Put this visit beside the earlier ones',
        'What about my other farm?',
        'Paano ito kumpara sa mga dati kong pagsusuri?',
      ]) {
        final tools = _CatalogTools();
        final transport = _ScopeTransport('field_history');
        final answer =
            await GeminiAdvisorOpenChatService(
              settingsStore: _Settings(),
              transport: transport,
            ).answer(
              AdvisorOpenChatRequest(
                question: question,
                history: const [],
                assessmentScopeId: 'current-draft',
                dataTools: tools,
              ),
            );
        expect(answer.topicId, 'assessment_scope_handoff');
        expect(tools.offsets, isEmpty);
        expect(transport.answers, isEmpty);
        expect(transport.resolverPayload, contains(question));
        expect(transport.resolverInstruction, contains('by MEANING'));
      }
    },
  );

  test(
    'comparison inside one assessment stays in its chat and never reads global tools',
    () async {
      final tools = _CatalogTools();
      final transport = _ScopeTransport('selected_assessment');
      final answer =
          await GeminiAdvisorOpenChatService(
            settingsStore: _Settings(),
            transport: transport,
          ).answer(
            AdvisorOpenChatRequest(
              question: 'Compare the two blocks in this visit',
              history: const [],
              assessmentScopeId: 'current-draft',
              dataTools: tools,
              fieldContext: const AdvisorOpenChatFieldContext(
                fieldAndAssessmentSummary: 'Only current-draft results',
                records: {'assessment_id': 'current-draft'},
              ),
            ),
          );
      expect(answer.topicId, isNot('assessment_scope_handoff'));
      expect(tools.offsets, isEmpty);
      expect(
        jsonEncode(transport.answers.single),
        contains('Only current-draft results'),
      );
      expect(
        jsonEncode(transport.answers.single),
        isNot(contains('older-completed')),
      );
    },
  );

  test('disabled sharing prevents reading any assessment catalogue', () async {
    final tools = _CatalogTools();
    final transport = _ScopeTransport('all_fields');
    await GeminiAdvisorOpenChatService(
      settingsStore: _Settings(share: false),
      transport: transport,
    ).answer(
      AdvisorOpenChatRequest(
        question: 'Summarize my visits',
        history: const [],
        dataTools: tools,
      ),
    );
    expect(tools.offsets, isEmpty);
    expect(
      jsonEncode(transport.answers.single),
      isNot(contains('older-completed')),
    );
  });

  test(
    'context budget explicitly reports omissions instead of claiming only one record',
    () async {
      final catalog = await loadAdvisorRecordCatalog(
        _CatalogTools(),
        maxCharacters: 100,
      );
      expect(catalog['coverage_complete'], false);
      expect(catalog['total_assessments'], 3);
      expect(catalog['omitted_assessments'], greaterThan(0));
      expect(catalog['limitation'], 'context_budget');
    },
  );
}

class _CatalogTools implements AdvisorDataTools {
  final offsets = <int>[];
  @override
  Future<Map<String, dynamic>> read(
    String tool,
    Map<String, dynamic> arguments,
  ) async {
    if (tool == 'list_fields') {
      return {
        'fields': [
          {'id': 'north', 'name': 'North'},
        ],
      };
    }
    if (tool != 'get_assessment_catalog') {
      throw StateError('Unexpected tool $tool');
    }
    final offset = arguments['offset'] as int? ?? 0;
    offsets.add(offset);
    return {
      'scope': 'all_saved_fields_and_crop_cycles',
      'total_assessments': 3,
      'total_fields': 2,
      'fields': [
        {'id': 'north', 'name': 'North'},
        {'id': 'south', 'name': 'South'},
      ],
      'status_counts': {'in_progress': 1, 'completed': 2},
      'assessments': offset == 0
          ? [
              {
                'id': 'current-draft',
                'status': 'in_progress',
                'field_id': 'north',
                'damage_screen': {'percent': 20},
              },
              {
                'id': 'older-completed',
                'status': 'completed',
                'field_id': 'north',
                'damage_screen': {'percent': 10},
              },
            ]
          : [
              {
                'id': 'other-field-visit',
                'status': 'completed',
                'field_id': 'south',
              },
            ],
      'next_offset': offset == 0 ? 2 : null,
    };
  }
}

class _ScopeTransport implements AdvisorGeminiTransport {
  _ScopeTransport(this.scope);
  final String scope;
  final answers = <Map<String, dynamic>>[];
  String resolverPayload = '', resolverInstruction = '';
  @override
  Future<Map<String, dynamic>> generate({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    final config = body['generationConfig'] as Map;
    final properties =
        (config['responseJsonSchema'] as Map)['properties'] as Map;
    Map<String, dynamic> result;
    if (properties.containsKey('record_scope')) {
      resolverPayload = jsonEncode(body['contents']);
      resolverInstruction = jsonEncode(body['system_instruction']);
      result = {
        'question': 'Compare saved records',
        'intent': 'records',
        'reference_query': '',
        'action_id': '',
        'needs_records': true,
        'needs_references': false,
        'record_scope': scope,
      };
    } else if (properties.containsKey('calls')) {
      result = {'calls': []};
    } else {
      answers.add(body);
      result = {
        'answer': 'Saved records are available.',
        'suggestion_reason': 'none',
        'suggestions': [],
        'action_ids': [],
        'visual_article_ids': [],
      };
    }
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(result)},
            ],
          },
        },
      ],
    };
  }
}

class _Settings implements AdvisorGeminiSettingsStore {
  _Settings({this.share = true});
  final bool share;
  @override
  Future<bool> isServiceConfigured() async => true;
  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async =>
      AdvisorGeminiPreferences(shareFieldContext: share);
  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {}
}
