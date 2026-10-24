import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/screens/assess/assessment_assistant_screen.dart';
import 'package:wormwise/services/advisor/advisor_gemini_settings.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets(
    'broader question opens Advisor with the original question and keeps a reusable route',
    (tester) async {
      final record = (await tester.runAsync(
        () => historyFixture(db, status: 'completed'),
      ))!;
      final other = (await tester.runAsync(
        () => historyFixture(db, name: 'Other field', status: 'completed'),
      ))!;
      const question = 'Put this visit next to the previous ones';
      final service = _Chat(handoff: true);
      String? routedQuestion;
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentAssistantScreen(
            database: db,
            assessmentId: record.assessment.id,
            fieldName: 'North',
            assessmentContext: 'Unused stale snapshot',
            geminiSettingsStore: _Settings(),
            openChatService: service,
            advisorBuilder: (value) {
              routedQuestion = value;
              return Scaffold(
                appBar: AppBar(title: const Text('Overall Advisor')),
                body: Text(value),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assessment_assistant_input')),
        question,
      );
      await tester.tap(find.byKey(const Key('assessment_assistant_send')));
      await tester.pumpAndSettle();
      expect(find.text('Overall Advisor'), findsOneWidget);
      expect(routedQuestion, question);
      expect(service.request!.assessmentScopeId, record.assessment.id);
      expect(service.request!.dataTools, isNull);
      expect(
        jsonEncode(service.request!.fieldContext!.records),
        isNot(contains(other.assessment.id)),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assessment_open_advisor')), findsOneWidget);
      final saved = await tester.runAsync(
        () =>
            (db.select(db.appPreferences)..where(
                  (p) => p.preferenceKey.equals(
                    'assessment_assistant_thread_${record.assessment.id}',
                  ),
                ))
                .getSingle(),
      );
      expect(saved!.preferenceValue, contains('advisorQuestion'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'within-assessment reply stays local and supplies only the selected record',
    (tester) async {
      final record = (await tester.runAsync(() => historyFixture(db)))!;
      final service = _Chat(handoff: false);
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentAssistantScreen(
            database: db,
            assessmentId: record.assessment.id,
            fieldName: 'North',
            assessmentContext: 'Unused stale snapshot',
            geminiSettingsStore: _Settings(),
            openChatService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assessment_assistant_input')),
        'How do the blocks differ?',
      );
      await tester.tap(find.byKey(const Key('assessment_assistant_send')));
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentAssistantScreen), findsOneWidget);
      expect(find.byKey(const Key('assessment_open_advisor')), findsNothing);
      expect(service.request!.assessmentScopeId, record.assessment.id);
      expect(service.request!.dataTools, isNull);
      expect(
        (service.request!.fieldContext!.records!['assessment_results']
            as Map)['assessment_id'],
        record.assessment.id,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _Chat implements AdvisorOpenChatService {
  _Chat({required this.handoff});
  final bool handoff;
  AdvisorOpenChatRequest? request;
  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) async {
    this.request = request;
    return AdvisorAnswer(
      topicId: handoff ? 'assessment_scope_handoff' : 'gemini_open_chat',
      title: '',
      summary: handoff ? 'Opening Advisor.' : 'These are the saved blocks.',
      details: const [],
      source: const AdvisorKnowledgeSource(
        label: 'Test',
        reference: 'Test',
        version: '1',
      ),
    );
  }
}

class _Settings implements AdvisorGeminiSettingsStore {
  @override
  Future<bool> isServiceConfigured() async => true;
  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async =>
      const AdvisorGeminiPreferences();
  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {}
}
