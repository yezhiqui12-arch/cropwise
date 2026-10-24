import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/main.dart';

void main() {
  testWidgets(
    'navigating between tabs and using Guide causes no assertion errors',
    (WidgetTester tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await _insertTestFieldAndAssessment(database);

      await tester.pumpWidget(WormWiseApp(database: database));
      await tester.pumpAndSettle();

      // Start at Home (tab 0)
      expect(find.text('Home'), findsWidgets);

      // Navigate: Home -> Scout
      await tester.tap(find.byKey(const Key('bottom_nav_scan')));
      await tester.pumpAndSettle();

      // Navigate: Scout -> Map
      await tester.tap(find.byKey(const Key('bottom_nav_map')));
      await tester.pumpAndSettle();

      // Navigate: Map -> Guide (tab 4)
      await tester.tap(find.byKey(const Key('bottom_nav_guide')));
      await tester.pumpAndSettle();

      // Verify Guide landing page elements
      expect(find.text('WormWise AI Assistant'), findsOneWidget);
      expect(find.text('How can I help with WormWise?'), findsOneWidget);
      expect(find.text('Explain my assessment'), findsOneWidget);
      expect(find.text('Check a maize photo'), findsOneWidget);
      expect(find.text('Inspect a plant'), findsOneWidget);
      expect(find.text('When to call an expert'), findsOneWidget);
      expect(find.byKey(const Key('guide_question_input')), findsOneWidget);

      // Repeatedly switch tabs to ensure no element retaking or lifecycle assertions occur
      for (final tabKey in [
        'bottom_nav_home',
        'bottom_nav_guide',
        'bottom_nav_scan',
        'bottom_nav_guide',
        'bottom_nav_map',
        'bottom_nav_guide',
      ]) {
        await tester.tap(find.byKey(Key(tabKey)));
        await tester.pumpAndSettle();
      }

      // Tap "Inspect a plant" quick action
      await tester.tap(find.byKey(const Key('guide_suggestion_inspect_plant')));
      await tester.pumpAndSettle();

      // Conversation view is now active
      expect(find.text('Inspect the plant systematically'), findsOneWidget);
      expect(
        find.byKey(const Key('advisor_saved_chats_button')),
        findsOneWidget,
      );

      // Clear the conversation back to welcome
      await tester.tap(find.byKey(const Key('advisor_saved_chats_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advisor_new_chat')));
      await tester.pumpAndSettle();

      expect(find.text('How can I help with WormWise?'), findsOneWidget);

      // Cleanup
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

Future<void> _insertTestFieldAndAssessment(AppDatabase database) async {
  final now = DateTime.utc(2026, 9, 3);
  await database
      .into(database.fields)
      .insert(
        FieldsCompanion.insert(
          id: 'guide-test-field-1',
          name: 'Corn Valley Field',
          activeBoundaryVersionId: const Value('guide-boundary-1'),
        ),
      );
  await database
      .into(database.fieldBoundaryVersions)
      .insert(
        FieldBoundaryVersionsCompanion.insert(
          id: 'guide-boundary-1',
          fieldId: 'guide-test-field-1',
          versionNumber: 1,
          geometryGeojson:
              '{"type":"Polygon","coordinates":[[[121,17],[121.01,17],[121,17.01],[121,17]]]}',
          sourceMethod: 'map_drawn',
          areaHectares: 2.5,
          confirmationStatus: const Value('user_confirmed'),
        ),
      );
  await database
      .into(database.cropCycles)
      .insert(
        CropCyclesCompanion.insert(
          id: 'guide-cycle-1',
          fieldId: 'guide-test-field-1',
        ),
      );
  await database
      .into(database.people)
      .insert(
        PeopleCompanion.insert(id: 'evaluator-1', displayName: 'Field Officer'),
      );
  await database
      .into(database.assessments)
      .insert(
        AssessmentsCompanion.insert(
          id: 'guide-assessment-1',
          cropCycleId: 'guide-cycle-1',
          boundaryVersionId: 'guide-boundary-1',
          evaluatorPersonId: 'evaluator-1',
          assessmentMode: DatabaseCodes.modeVeV6,
          scoutingPattern: 'w_pattern',
          growthStage: 'v3_v6',
          protocolVersion: 'protocol-v1',
          formulaVersion: 'formula-v1',
          status: const Value(DatabaseCodes.completed),
          completedAt: Value(now),
        ),
      );
}
