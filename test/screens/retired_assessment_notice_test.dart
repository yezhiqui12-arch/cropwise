import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/providers/assessment_workspace_provider.dart';
import 'package:wormwise/screens/assess/assessment_details_screen.dart';
import 'package:wormwise/screens/assess/assessment_results_screen.dart';
import 'package:wormwise/screens/assess/assessment_resume_screen.dart';
import 'package:wormwise/screens/assess/retired_assessment_notice.dart';
import 'package:wormwise/screens/assessment_setup_screen.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';

import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase db;
  var databaseClosed = false;
  setUp(() {
    databaseClosed = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    if (!databaseClosed) await db.close();
  });

  Future<void> disposeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(db.close);
    databaseClosed = true;
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget harness(Widget destination) => WormWiseDataScope(
    database: db,
    disposeDatabase: false,
    dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => destination),
            ),
            child: const Text('Open saved assessment'),
          ),
        ),
      ),
    ),
  );

  for (final entry in <String, Widget Function(String)>{
    'results': (id) => AssessmentResultsScreen(assessmentId: id),
    'details': (id) => AssessmentDetailsScreen(assessmentId: id),
    'resume': (id) => AssessmentResumeScreen(assessmentId: id),
  }.entries) {
    testWidgets(
      'retired ${entry.key} opens a notice and Close returns safely',
      (tester) async {
        final saved = (await tester.runAsync(
          () => historyFixture(db, status: 'in_progress'),
        ))!;
        await tester.pumpWidget(harness(entry.value(saved.assessment.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open saved assessment'));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const Key('retired_assessment_dialog'));
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(RetiredAssessmentNotice.message),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assessment_details_resume_button')),
          findsNothing,
        );
        expect(find.byKey(const Key('queue_report_button')), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Open saved assessment'), findsOneWidget);
        expect(find.byType(RetiredAssessmentNotice), findsNothing);
        expect(
          (await tester.runAsync(
            () => db.select(db.assessments).get(),
          ))!.single.id,
          saved.assessment.id,
        );
        expect(tester.takeException(), isNull);
        await disposeHarness(tester);
      },
    );
  }

  testWidgets(
    'new assessment opens setup without resuming retired ladder record',
    (tester) async {
      final saved = (await tester.runAsync(() async {
        final saved = await historyFixture(db, status: 'in_progress');
        await (db.update(
          db.assessments,
        )..where((row) => row.id.equals(saved.assessment.id))).write(
          const AssessmentsCompanion(scoutingPattern: drift.Value('ladder')),
        );
        return saved;
      }))!;
      await tester.pumpWidget(
        harness(AssessmentResumeScreen(assessmentId: saved.assessment.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open saved assessment'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Start new assessment'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentSetupScreen), findsOneWidget);
      expect(find.byType(RetiredAssessmentNotice), findsNothing);
      final setup = tester.element(find.byType(AssessmentSetupScreen));
      expect(
        setup.read<AssessmentWorkspaceProvider>().currentAssessment,
        isNull,
      );
      expect(
        (await tester.runAsync(
          () => db.select(db.assessments).get(),
        ))!.single.id,
        saved.assessment.id,
      );
      expect(tester.takeException(), isNull);
      await disposeHarness(tester);
    },
  );

  test(
    'retired draft does not hide a current DA draft for the same crop cycle',
    () async {
      final saved = await historyFixture(db);
      final repository = AssessmentRepository(db);
      expect(
        await repository
            .watchOpenAssessmentForCropCycle(saved.field.cropCycle.id)
            .first,
        isNull,
      );
      final current = await repository.createDraft(
        cropCycleId: saved.field.cropCycle.id,
        boundaryVersionId: saved.field.boundary!.id,
        evaluatorPersonId: saved.assessment.evaluatorPersonId,
        assessmentMode: 've_v6',
        scoutingPattern: ScoutingSamplingProtocol.daPattern,
        growthStage: 'v3_v6',
        protocolVersion: ScoutingSamplingProtocol.daVersion,
        formulaVersion: 'test-formula',
      );
      expect(
        (await repository
                .watchOpenAssessmentForCropCycle(saved.field.cropCycle.id)
                .first)
            ?.id,
        current.id,
      );
    },
  );
}
