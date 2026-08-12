import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/main.dart';
import 'package:wormwise/providers/assessment_workspace_provider.dart';
import 'package:wormwise/providers/field_workspace_provider.dart';
import 'package:wormwise/screens/scan/scan_landing_screen.dart';
import 'package:wormwise/widgets/bottom_nav_bar.dart';

void main() {
  testWidgets('Scan no-field state supports 200 percent text scaling', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final database = AppDatabase(NativeDatabase.memory());
    final fieldProvider = FieldWorkspaceProvider(FieldRepository(database));
    final assessmentProvider = AssessmentWorkspaceProvider(
      AssessmentRepository(database),
      PeopleRepository(database),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: fieldProvider),
          ChangeNotifierProvider.value(value: assessmentProvider),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(2),
            ),
            child: ScanLandingScreen(
              onRegisterField: () {},
              onCompleteFieldOutline: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register a maize field'), findsOneWidget);
    final primaryAction = find.byKey(
      const Key('register_field_from_scan_button'),
    );
    await tester.ensureVisible(primaryAction);
    await tester.pumpAndSettle();
    expect(tester.getSize(primaryAction).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);

    fieldProvider.dispose();
    assessmentProvider.dispose();
    await _closeApp(tester, database);
  });

  testWidgets('Scan bottom destination remains usable at 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            bottomNavigationBar: BottomNavBar(
              currentIndex: 2,
              onTap: _ignoreNavigation,
            ),
          ),
        ),
      ),
    );

    final scanTab = find.byKey(const Key('bottom_nav_scan'));
    expect(scanTab, findsOneWidget);
    expect(tester.getSize(scanTab).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(scanTab).height, greaterThanOrEqualTo(48));
    expect(find.text('Scan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan requires an outline and preserves an existing draft', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final fixture = await _createAssessmentFixture(
      database,
      confirmationStatus: 'location_pending',
      startState: _AssessmentStartState.draft,
    );

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.text('Complete field outline'), findsWidgets);
    expect(find.textContaining('remains saved on this phone'), findsOneWidget);
    expect(find.textContaining('not a legal or survey-grade'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('complete_field_outline_from_scan_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manage_boundary_button')), findsOneWidget);
    expect(
      (await database.select(database.assessments).getSingle()).id,
      fixture.assessmentId,
    );

    await _closeApp(tester, database);
  });

  testWidgets('Scan opens existing setup for a confirmed field', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _createAssessmentFixture(
      database,
      confirmationStatus: 'user_confirmed',
      startState: _AssessmentStartState.none,
    );

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.text('Set up an assessment'), findsOneWidget);
    expect(
      find.text('Field outline confirmed. Saved on this phone.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('setup_assessment_from_scan_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assessment Setup'), findsOneWidget);

    await _closeApp(tester, database);
  });

  testWidgets('Scan shows and resumes a saved draft setup', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _createAssessmentFixture(
      database,
      confirmationStatus: 'user_confirmed',
      startState: _AssessmentStartState.draft,
    );

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.text('Finish assessment setup'), findsOneWidget);
    expect(find.text('Saved on this phone.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resume_setup_from_scan_button')));
    await tester.pumpAndSettle();
    expect(find.text('Review Assessment Safety'), findsOneWidget);

    await _closeApp(tester, database);
  });

  testWidgets('Scan keeps a safety-blocked assessment out of fieldwork', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _createAssessmentFixture(
      database,
      confirmationStatus: 'user_confirmed',
      startState: _AssessmentStartState.safetyBlocked,
    );

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.text('Field entry needs review'), findsOneWidget);
    expect(find.textContaining('Do not enter the field'), findsOneWidget);
    expect(
      find.byKey(const Key('resume_assessment_from_scan_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('review_safety_from_scan_button')),
      findsOneWidget,
    );

    await _closeApp(tester, database);
  });

  testWidgets('Scan opens Station 1 preparation for an active assessment', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _createAssessmentFixture(
      database,
      confirmationStatus: 'user_confirmed',
      startState: _AssessmentStartState.active,
    );

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.text('Resume assessment'), findsWidgets);
    expect(find.text('Saved on this phone.'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('resume_assessment_from_scan_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Block 1 · Station 1'), findsWidgets);
    expect(find.text('Block 1 is the whole field'), findsOneWidget);

    await _closeApp(tester, database);
  });
}

enum _AssessmentStartState { none, draft, safetyBlocked, active }

class _AssessmentFixture {
  const _AssessmentFixture({required this.assessmentId});

  final String? assessmentId;
}

Future<_AssessmentFixture> _createAssessmentFixture(
  AppDatabase database, {
  required String confirmationStatus,
  required _AssessmentStartState startState,
}) async {
  final fields = FieldRepository(database);
  final created = await fields.createFieldWithBoundaryAndCycle(
    name: 'Scan Test Field',
    geometryGeojson: '{"type":"Polygon","coordinates":[]}',
    areaHectares: 0.8,
    boundarySourceMethod: confirmationStatus == 'user_confirmed'
        ? 'draw'
        : 'reported_area_only',
    boundaryConfirmationStatus: confirmationStatus,
  );
  await fields.savePreferredFieldId(created.field.id);

  if (startState == _AssessmentStartState.none) {
    return const _AssessmentFixture(assessmentId: null);
  }

  final people = PeopleRepository(database);
  final evaluator = await people.findOrCreateEvaluator('Scan Test Evaluator');
  final assessments = AssessmentRepository(database);
  final assessment = await assessments.createDraft(
    cropCycleId: created.cropCycle.id,
    boundaryVersionId: created.boundary.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: 'v3_v6',
    protocolVersion: 'test-protocol',
    formulaVersion: 'test-formula',
  );

  if (startState == _AssessmentStartState.safetyBlocked) {
    await assessments.recordSafetyCheck(
      assessmentId: assessment.id,
      checkedByPersonId: evaluator.id,
      resultStatus: DatabaseCodes.cannotConfirmSafety,
    );
  } else if (startState == _AssessmentStartState.active) {
    await assessments.recordSafetyCheck(
      assessmentId: assessment.id,
      checkedByPersonId: evaluator.id,
      resultStatus: DatabaseCodes.noRecentTreatment,
    );
    await assessments.startAssessment(assessment.id);
  }

  return _AssessmentFixture(assessmentId: assessment.id);
}

Future<void> _closeApp(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await database.close();
  await tester.pump(const Duration(milliseconds: 1));
}

void _ignoreNavigation(int _) {}
