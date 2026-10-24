import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/scouting_route_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/data/services/atomic_ve_v2_save_service.dart';
import 'package:wormwise/data/services/scouting_completion_service.dart';
import 'package:wormwise/providers/scouting_workflow_provider.dart';
import 'package:wormwise/providers/scouting_workflow_state.dart';
import 'package:wormwise/screens/station1/station1_workflow_screen.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import '../support/da_results_fixture.dart';

void main() {
  testWidgets(
    'Plant 20 asks for natural enemies before review and persists selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      late Directory directory;
      late ScoutingWorkflowProvider workflow;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('da_plant20_');
        final history = await daResultsFixture(db, recorded: 19);
        final evidence = EvidenceCaptureRepository(db);
        workflow = ScoutingWorkflowProvider(
          assessmentId: history.assessment.id,
          workflowRepository: ScoutingWorkflowRepository(db),
          assessmentRepository: AssessmentRepository(db),
          plantSaveService: AtomicPlantSaveService(
            db,
            evidenceRepository: evidence,
          ),
          completionService: ScoutingCompletionService(db),
          veV2SaveService: AtomicVeV2SaveService(db),
          routeRepository: ScoutingRouteRepository(db),
          evidenceCoordinator: EvidenceCaptureCoordinator(
            repository: evidence,
            storage: EvidenceStorageService(
              rootDirectory: () async => directory,
            ),
          ),
          computerVisionService: _Screening(),
        );
        await workflow.initialize();
        await workflow.submitResumeCheck(
          condition: ResumeCondition.unchanged,
          safeToContinue: true,
        );
        await workflow.confirmReachedActiveStation();
        await workflow.selectCapturePlant(1, analyzePrevious: false);
        final source = File('${directory.path}/source.jpg');
        await source.writeAsBytes(
          img.encodeJpg(img.Image(width: 96, height: 96)),
        );
        final media = await workflow.stageEvidence(
          viewType: workflow.primaryEvidenceViewType,
          sourcePath: source.path,
          deleteSourceAfterCopy: false,
          fromCamera: true,
        );
        await workflow.acceptEvidence(media);
        await workflow.analyzeDaActivePlantForPreview();
      });
      expect(workflow.stationNumber, 20);
      expect(workflow.state, isNot(Station1ViewState.blockReview));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: workflow,
          child: MaterialApp(
            home: Station1WorkflowScreen(
              fieldName: 'Corn plot',
              captureLocation: () async =>
                  throw StateError('GPS not required for this test'),
              watchLocation: () async => const Stream.empty(),
              debugFeaturesEnabled: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('guided_walk_primary_action')),
      );
      await tester.tap(find.byKey(const Key('guided_walk_primary_action')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // The underlying walk stays busy while its confirmation dialog is open.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Likas na mga kaaway'), findsOneWidget);
      expect(workflow.state, isNot(Station1ViewState.blockReview));
      await tester.tap(find.byKey(const Key('da_enemy_predators')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('da_enemy_continue')));
      for (
        var attempt = 0;
        attempt < 100 && workflow.state != Station1ViewState.blockReview;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(workflow.error, isNull);
      expect(
        workflow.state,
        Station1ViewState.blockReview,
        reason:
            'saving=${workflow.isSaving}, reviewed=${workflow.snapshot?.reviewIsCurrent}, completed=${workflow.completedDaPlantCount}',
      );
      expect(await tester.runAsync(workflow.loadDaNaturalEnemies), [
        'predators',
      ]);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      workflow.dispose();
      await tester.runAsync(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
    },
  );
}

class _Screening implements FawComputerVisionService {
  @override
  bool get isModelLoaded => true;
  @override
  String get modelIdentifier => 'WormWise-AutoScreen-v1:test';
  @override
  Future<PlantDiagnosisResult> analyzeImage(File file) async =>
      const PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'screen',
        confidenceScore: .9,
        classificationLabel: 'No FAW damage',
        modelName: 'WormWise-AutoScreen-v1:test',
      );
}
