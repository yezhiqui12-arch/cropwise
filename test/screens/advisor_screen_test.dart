import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/advisor_context_repository.dart';
import 'package:wormwise/main.dart';
import 'package:wormwise/providers/advisor_controller.dart';
import 'package:wormwise/screens/advisor/advisor_screen.dart';
import 'package:wormwise/services/advisor/advisor_connectivity_service.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';
import 'package:wormwise/services/advisor/advisor_gemini_settings.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/theme/app_theme.dart';
import 'package:wormwise/widgets/bottom_nav_bar.dart';

void main() {
  testWidgets('Guide landing page exposes offline topics without top notice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          geminiSettingsStore: _MemoryGeminiSettingsStore(),
          connectivityService: _offlineConnectivity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WormWise AI Assistant'), findsOneWidget);
    expect(find.byKey(const Key('guide_safety_notice')), findsNothing);
    expect(find.textContaining('Guidance only'), findsNothing);
    expect(find.text('How can I help with WormWise?'), findsOneWidget);
    expect(find.text('Explain my assessment'), findsOneWidget);
    expect(find.text('Check a maize photo'), findsOneWidget);
    expect(find.text('Inspect a plant'), findsOneWidget);
    expect(find.text('When to call an expert'), findsOneWidget);
    expect(find.textContaining('Using built-in guidance'), findsOneWidget);
  });

  testWidgets('Guide switches between online and offline phone status', (
    WidgetTester tester,
  ) async {
    final connectivity = _ControllableConnectivity(
      AdvisorConnectionStatus.online,
    );
    addTearDown(connectivity.close);
    final settings = _MemoryGeminiSettingsStore()
      ..preferences = const AdvisorGeminiPreferences(enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          geminiSettingsStore: settings,
          connectivityService: connectivity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Online guide'), findsWidgets);
    expect(find.textContaining('Photos stay on this phone'), findsOneWidget);

    connectivity.emit(AdvisorConnectionStatus.offline);
    await tester.pumpAndSettle();

    expect(find.text('Offline guide'), findsWidgets);
    expect(find.textContaining('on-device photo model'), findsOneWidget);
  });

  testWidgets('offline Guide does not call the online chat service', (
    WidgetTester tester,
  ) async {
    final service = _RetryingOpenChatService();
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);
    final settings = _MemoryGeminiSettingsStore()
      ..preferences = const AdvisorGeminiPreferences(enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          controller: controller,
          geminiSettingsStore: settings,
          connectivityService: _offlineConnectivity,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('guide_question_input')),
      'Why do maize leaves curl at noon?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_guide_question_button')));
    await tester.pumpAndSettle();

    expect(service.callCount, 0);
    expect(find.text('This offline guide has a focused scope'), findsOneWidget);
  });

  testWidgets('suggested question returns a sourced deterministic answer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AdvisorScreen(connectivityService: _offlineConnectivity),
      ),
    );

    final suggestion = find.byKey(const Key('guide_suggestion_inspect_plant'));
    await tester.ensureVisible(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_conversation_list')), findsOneWidget);
    expect(find.text('Inspect the plant systematically'), findsOneWidget);
    expect(find.textContaining('WormWise assessment protocol'), findsOneWidget);
  });

  testWidgets('photo attachment goes directly to camera or gallery', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          geminiSettingsStore: _MemoryGeminiSettingsStore(),
          connectivityService: _offlineConnectivity,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide_photo_quick_action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('analyze_photo_on_device_option')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('analyze_photo_with_gemini_option')),
      findsNothing,
    );
    expect(find.byKey(const Key('guide_photo_camera_option')), findsOneWidget);
    expect(find.byKey(const Key('guide_photo_gallery_option')), findsOneWidget);
  });

  testWidgets('typed pesticide question receives guarded response', (
    WidgetTester tester,
  ) async {
    final controller = AdvisorController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          controller: controller,
          geminiSettingsStore: _MemoryGeminiSettingsStore(),
          connectivityService: _offlineConnectivity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('guide_question_input')),
      'What pesticide should I spray?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_guide_question_button')));
    await tester.pumpAndSettle();

    expect(controller.messages, hasLength(2));
    expect(
      find.text('WormWise does not prescribe pesticide treatment'),
      findsOneWidget,
    );
    expect(find.textContaining('qualified agricultural'), findsWidgets);
  });

  testWidgets('conversation can be cleared back to the minimal welcome', (
    WidgetTester tester,
  ) async {
    final controller = AdvisorController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          controller: controller,
          connectivityService: _offlineConnectivity,
        ),
      ),
    );

    final suggestion = find.byKey(const Key('guide_suggestion_inspect_plant'));
    await tester.ensureVisible(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(controller.messages, hasLength(2));

    await tester.tap(find.byKey(const Key('advisor_saved_chats_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advisor_new_chat')));
    await tester.pumpAndSettle();

    expect(controller.messages, isEmpty);
    expect(find.text('How can I help with WormWise?'), findsOneWidget);
  });

  testWidgets('saved field context opens a read-only assessment explanation', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _insertGuideFixture(database);
    final controller = AdvisorController(
      contextRepository: AdvisorContextRepository(database),
    );
    await controller.loadContext(
      fieldId: 'guide-field',
      cropCycleId: 'guide-cycle',
      preferredAssessmentId: 'guide-assessment',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          controller: controller,
          connectivityService: _offlineConnectivity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_field_context_card')), findsOneWidget);
    expect(find.text('Guide Test Field'), findsOneWidget);
    expect(find.textContaining('V3-V6 · Completed'), findsOneWidget);

    final explain = find.byKey(const Key('explain_latest_assessment_button'));
    await tester.ensureVisible(explain);
    await tester.pumpAndSettle();
    await tester.tap(explain);
    await tester.pumpAndSettle();

    expect(find.text('Latest completed assessment'), findsOneWidget);
    expect(
      find.textContaining('not a treatment recommendation'),
      findsOneWidget,
    );
    expect(find.textContaining('Recorded assessment data'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await database.close();
  });

  testWidgets('app Guide tab reads the selected field through data providers', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _insertGuideFixture(database);

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_guide')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_field_context_card')), findsOneWidget);
    expect(find.text('Guide Test Field'), findsOneWidget);
    expect(find.textContaining('V3-V6 · Completed'), findsOneWidget);

    await (database.update(database.fields)
          ..where((row) => row.id.equals('guide-field')))
        .write(const FieldsCompanion(name: Value('Updated Guide Field')));
    await tester.tap(find.byKey(const Key('bottom_nav_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_guide')));
    await tester.pumpAndSettle();

    expect(find.text('Updated Guide Field'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('open chat failure is retryable without losing the question', (
    WidgetTester tester,
  ) async {
    final service = _RetryingOpenChatService();
    final controller = AdvisorController(openChatService: service);
    final settings = _MemoryGeminiSettingsStore()
      ..preferences = const AdvisorGeminiPreferences(enabled: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdvisorScreen(
          controller: controller,
          geminiSettingsStore: settings,
          connectivityService: _onlineConnectivity,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('guide_question_input')),
      'Why do maize leaves curl at noon?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_guide_question_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_open_chat_error')), findsOneWidget);
    expect(find.text('Why do maize leaves curl at noon?'), findsOneWidget);
    expect(service.callCount, 1);

    await tester.tap(find.byKey(const Key('retry_guide_open_chat_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_open_chat_error')), findsNothing);
    expect(find.text('WormWise AI'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('Generated online'), findsNothing);
    expect(find.textContaining('Google Gemini'), findsNothing);
    expect(service.callCount, 2);
    expect(controller.messages, hasLength(2));
  });

  testWidgets('Guide remains usable at 360 px and 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: AdvisorScreen(connectivityService: _offlineConnectivity),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('guide_question_input'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send_guide_question_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bottom navigation contains Scout and uses Guide instead of Bot',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BottomNavBar(
              currentIndex: 4,
              onTap: _ignoreNavigation,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('bottom_nav_guide')), findsOneWidget);
      expect(find.byKey(const Key('bottom_nav_scan')), findsOneWidget);
      expect(find.text('Scout'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Bot'), findsNothing);

      final barRect = tester.getRect(find.byKey(const Key('bottom_nav_bar')));
      final scoutRect = tester.getRect(
        find.byKey(const Key('bottom_nav_scan')),
      );
      expect(scoutRect.top, greaterThanOrEqualTo(barRect.top));
      expect(scoutRect.bottom, lessThanOrEqualTo(barRect.bottom));
    },
  );
}

void _ignoreNavigation(int _) {}

Future<void> _insertGuideFixture(AppDatabase database) async {
  final now = DateTime.utc(2026, 9, 3);
  await database
      .into(database.fields)
      .insert(
        FieldsCompanion.insert(
          id: 'guide-field',
          name: 'Guide Test Field',
          activeBoundaryVersionId: const Value('guide-boundary'),
        ),
      );
  await database
      .into(database.fieldBoundaryVersions)
      .insert(
        FieldBoundaryVersionsCompanion.insert(
          id: 'guide-boundary',
          fieldId: 'guide-field',
          versionNumber: 1,
          geometryGeojson:
              '{"type":"Polygon","coordinates":[[[121,17],[121.01,17],[121,17.01],[121,17]]]}',
          sourceMethod: 'map_drawn',
          areaHectares: 1,
          confirmationStatus: const Value('user_confirmed'),
        ),
      );
  await database
      .into(database.cropCycles)
      .insert(
        CropCyclesCompanion.insert(id: 'guide-cycle', fieldId: 'guide-field'),
      );
  await database
      .into(database.people)
      .insert(
        PeopleCompanion.insert(id: 'guide-person', displayName: 'Evaluator'),
      );
  await database
      .into(database.assessments)
      .insert(
        AssessmentsCompanion.insert(
          id: 'guide-assessment',
          cropCycleId: 'guide-cycle',
          boundaryVersionId: 'guide-boundary',
          evaluatorPersonId: 'guide-person',
          assessmentMode: DatabaseCodes.modeVeV6,
          scoutingPattern: 'w_pattern',
          growthStage: 'v3_v6',
          protocolVersion: 'protocol-test-v1',
          formulaVersion: 'formula-test-v1',
          status: const Value(DatabaseCodes.completed),
          completedAt: Value(now),
        ),
      );
}

class _RetryingOpenChatService implements AdvisorOpenChatService {
  int callCount = 0;

  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) async {
    callCount++;
    if (callCount == 1) throw StateError('Simulated open chat failure');
    return const AdvisorAnswer(
      topicId: 'gemini_open_chat',
      title: 'Gemini response',
      summary: '**Current field:**\n* A simulated response.',
      details: ['Generated online. Verify important claims.'],
      source: AdvisorKnowledgeSource(
        label: 'Google Gemini',
        reference: 'Gemini API',
        version: 'gemini-test',
      ),
    );
  }
}

class _MemoryGeminiSettingsStore implements AdvisorGeminiSettingsStore {
  AdvisorGeminiPreferences preferences = const AdvisorGeminiPreferences();

  @override
  Future<bool> isServiceConfigured() async => true;

  @override
  Future<AdvisorGeminiPreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(AdvisorGeminiPreferences preferences) async {
    this.preferences = preferences;
  }
}

const _offlineConnectivity = _FixedConnectivity(
  AdvisorConnectionStatus.offline,
);
const _onlineConnectivity = _FixedConnectivity(AdvisorConnectionStatus.online);

class _FixedConnectivity implements AdvisorConnectivityService {
  const _FixedConnectivity(this.status);

  final AdvisorConnectionStatus status;

  @override
  Future<AdvisorConnectionStatus> check() async => status;

  @override
  Stream<AdvisorConnectionStatus> get statusChanges => const Stream.empty();
}

class _ControllableConnectivity implements AdvisorConnectivityService {
  _ControllableConnectivity(this.status);

  AdvisorConnectionStatus status;
  final _controller = StreamController<AdvisorConnectionStatus>.broadcast();

  void emit(AdvisorConnectionStatus value) {
    status = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();

  @override
  Future<AdvisorConnectionStatus> check() async => status;

  @override
  Stream<AdvisorConnectionStatus> get statusChanges => _controller.stream;
}
