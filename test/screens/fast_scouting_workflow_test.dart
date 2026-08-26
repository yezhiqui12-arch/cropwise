import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/screens/station1/plant_observation_step.dart';
import 'package:wormwise/screens/station1/plant_selection_step.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  testWidgets(
    'PlantSelectionStep shows All 10 Plants Clean button and triggers callback',
    (WidgetTester tester) async {
      bool cleanTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantSelectionStep(
              blockNumber: 1,
              stationNumber: 1,
              onBegin: () {},
              onMarkAllHealthy: () {
                cleanTriggered = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mark_all_healthy_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mark_all_healthy_button')));
      await tester.pumpAndSettle();

      expect(cleanTriggered, true);
    },
  );

  testWidgets(
    'PlantObservationStep renders AI diagnosis card and auto-fills observations',
    (WidgetTester tester) async {
      final aiResult = PlantDiagnosisResult.fawInfested(
        confidence: 0.95,
        davisGrade: 4,
        larvaSeen: true,
        larvaSize: 'medium',
        frassSeen: true,
        whorlSeen: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantObservationStep(
              position: 1,
              savedCount: 0,
              stationId: 'station-1',
              actorPersonId: 'evaluator-1',
              existing: null,
              isSaving: false,
              cvDiagnosis: aiResult,
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AI: Fall Armyworm'), findsOneWidget);
      expect(
        find.byKey(const Key('apply_ai_diagnosis_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('apply_ai_diagnosis_button')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Current FAW-consistent evidence'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Current FAW-consistent evidence'), findsWidgets);
    },
  );
}
