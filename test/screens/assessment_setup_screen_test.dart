import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/main.dart';

void main() {
  testWidgets('creates and starts a real SQLite-backed assessment', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final fields = FieldRepository(database);
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Assessment Test Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 1.2,
      boundarySourceMethod: 'reported_area_only',
      boundaryConfirmationStatus: 'location_pending',
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

    await tester.enterText(
      find.byKey(const Key('assessment_evaluator_input')),
      'Test Field Evaluator',
    );

    final rainChoice = find.byKey(const Key('rain_last_48_hours_choice'));
    for (
      var attempt = 0;
      attempt < 10 && rainChoice.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(rainChoice);
    await tester.pumpAndSettle();
    await tester.tap(rainChoice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('No').last);
    await tester.pumpAndSettle();

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

    expect(find.text('Assessment saved and started'), findsOneWidget);
    expect(find.text('In progress and saved locally'), findsOneWidget);

    final assessment = await database.select(database.assessments).getSingle();
    expect(assessment.status, DatabaseCodes.inProgress);
    expect(assessment.assessmentMode, DatabaseCodes.modeVeV6);
    expect(assessment.scoutingPattern, DatabaseCodes.patternW);
    expect(assessment.safetySummaryStatus, DatabaseCodes.noRecentTreatment);
    expect(assessment.weatherContext, contains('rain_wet_field_last_48h=no'));

    final safetyCheck = await database
        .select(database.safetyChecks)
        .getSingle();
    expect(safetyCheck.resultStatus, DatabaseCodes.noRecentTreatment);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
