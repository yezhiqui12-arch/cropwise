import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/main.dart';
import 'package:wormwise/providers/assessment_workspace_provider.dart';

void main() {
  testWidgets('creates and starts a real SQLite-backed assessment', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final fields = FieldRepository(database);
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Assessment Test Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.8,
      boundarySourceMethod: 'draw',
      boundaryConfirmationStatus: 'user_confirmed',
    );
    await fields.savePreferredFieldId(created.field.id);

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    expect(find.text('Assessment Test Field'), findsWidgets);
    final startButton = find.byKey(const Key('start_assessment_button'));
    await tester.ensureVisible(startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    expect(find.text('Assessment Setup'), findsOneWidget);
    expect(find.text('Guided assessment language'), findsNothing);
    expect(
      find.byKey(const Key('growth_stage_uncertain_checkbox')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('assessment_evaluator_input')),
      'Test Field Evaluator',
    );

    for (
      var attempt = 0;
      attempt < 8 &&
          find.byKey(const Key('automatic_scouting_route')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -220));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('automatic_scouting_route')), findsOneWidget);
    expect(find.byKey(const Key('scouting_pattern_choice')), findsNothing);
    expect(
      find.byKey(
        const Key('field_surface_condition_choice'),
        skipOffstage: false,
      ),
      findsNothing,
    );

    final safetyOption = find.byKey(
      const Key('safety_no_recent_treatment_option'),
    );
    for (
      var attempt = 0;
      attempt < 12 && safetyOption.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
    }
    expect(safetyOption, findsOneWidget);
    await tester.ensureVisible(safetyOption);
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(safetyOption);
    await tester.pump();

    await tester.tap(find.byKey(const Key('save_assessment_setup_button')));
    await tester.pumpAndSettle();

    expect(find.text('Block 1 · Station 1'), findsWidgets);
    expect(find.text('Block 1 is the whole field'), findsOneWidget);

    final assessment = await database.select(database.assessments).getSingle();
    expect(assessment.status, DatabaseCodes.inProgress);
    expect(assessment.assessmentMode, DatabaseCodes.modeVeV6);
    expect(assessment.scoutingPattern, DatabaseCodes.patternW);
    expect(assessment.growthStageUncertain, isFalse);
    expect(assessment.safetySummaryStatus, DatabaseCodes.noRecentTreatment);
    expect(assessment.weatherContext, isNull);

    final safetyCheck = await database
        .select(database.safetyChecks)
        .getSingle();
    expect(safetyCheck.resultStatus, DatabaseCodes.noRecentTreatment);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('legacy setup route cannot bypass the confirmed outline gate', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final fields = FieldRepository(database);
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Outline Required Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.8,
      boundarySourceMethod: 'reported_area_only',
      boundaryConfirmationStatus: 'location_pending',
    );
    await fields.savePreferredFieldId(created.field.id);

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    final startButton = find.byKey(const Key('start_assessment_button'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('Complete field outline'), findsWidgets);
    expect(
      find.byKey(const Key('complete_field_outline_from_setup_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save_assessment_setup_button')), findsNothing);
    expect(await database.select(database.assessments).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  test(
    'provider refuses assessment creation without a confirmed outline',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final fields = FieldRepository(database);
      final created = await fields.createFieldWithBoundaryAndCycle(
        name: 'Repository Gate Field',
        geometryGeojson: '{"type":"Polygon","coordinates":[]}',
        areaHectares: 0.9,
        boundarySourceMethod: 'entrance_gps',
        boundaryConfirmationStatus: 'location_only',
        centroidLatitude: 17.0,
        centroidLongitude: 121.0,
      );
      final provider =
          AssessmentWorkspaceProvider(
            AssessmentRepository(database),
            PeopleRepository(database),
          )..bindFieldWorkspace(
            FieldWorkspaceRecord(
              field: created.field,
              boundary: created.boundary,
              cropCycle: created.cropCycle,
            ),
          );

      await expectLater(
        provider.createAssessment(
          evaluatorName: 'Test Evaluator',
          assessmentMode: DatabaseCodes.modeVeV6,
          scoutingPattern: DatabaseCodes.patternW,
          growthStage: 'v3_v6',
          safetyStatus: DatabaseCodes.noRecentTreatment,
          interventionHistoryStatus: 'no',
          preferredLanguage: 'en',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await database.select(database.assessments).get(), isEmpty);

      provider.dispose();
      await database.close();
    },
  );

  test(
    'implemented reproductive stages start before progress records exist',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final fields = FieldRepository(database);
      final created = await fields.createFieldWithBoundaryAndCycle(
        name: 'Stage Gate Field',
        geometryGeojson: '{"type":"Polygon","coordinates":[]}',
        areaHectares: 0.7,
        boundarySourceMethod: 'draw',
        boundaryConfirmationStatus: 'user_confirmed',
      );
      final assessments = AssessmentRepository(database);
      final provider =
          AssessmentWorkspaceProvider(assessments, PeopleRepository(database))
            ..bindFieldWorkspace(
              FieldWorkspaceRecord(
                field: created.field,
                boundary: created.boundary,
                cropCycle: created.cropCycle,
              ),
            );

      final draft = await provider.createAssessment(
        evaluatorName: 'Stage Gate Evaluator',
        assessmentMode: DatabaseCodes.modeVtR2,
        scoutingPattern: DatabaseCodes.patternLadder,
        growthStage: 'vt_r2',
        safetyStatus: DatabaseCodes.noRecentTreatment,
        interventionHistoryStatus: 'no',
        preferredLanguage: 'en',
      );

      expect(draft.status, DatabaseCodes.inProgress);
      expect(draft.startedAt, isNotNull);
      expect(
        await database.select(database.assessmentBlockRuns).get(),
        isEmpty,
      );
      expect(await database.select(database.stations).get(), isEmpty);
      expect(await database.select(database.plantObservations).get(), isEmpty);
      await assessments.startAssessment(draft.id);

      provider.dispose();
      await database.close();
    },
  );
}
