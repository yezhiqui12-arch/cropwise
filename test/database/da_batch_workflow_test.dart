import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/data/repositories/advisor_model_results_reader.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/models/da_assessment_results.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/scouting_route_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/data/services/atomic_ve_v2_save_service.dart';
import 'package:wormwise/data/services/scouting_completion_service.dart';
import 'package:wormwise/providers/scouting_workflow_provider.dart';
import 'package:wormwise/providers/scouting_workflow_state.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/services/da_batch_import_store.dart';
import '../support/da_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final quitDuringInference in [false, true]) {
    test(
      'restart after ${quitDuringInference ? 'leaving during inference' : 'failed photo'} preserves checkpoints and atomic saves',
      () async {
        final dir = await Directory.systemTemp.createTemp('da_screen_restart_');
        final databaseFile = File('${dir.path}/assessment.sqlite');
        var db = AppDatabase(NativeDatabase(databaseFile));
        var closed = false;
        addTearDown(() async {
          if (!closed) await db.close();
          await dir.delete(recursive: true);
        });
        final history = await daResultsFixture(db, recorded: 19);
        final cv = _Cv()
          ..failAt = quitDuringInference ? null : 2
          ..pauseAt = quitDuringInference ? 2 : null
          ..positiveFirst = true;
        final expectedCalls = quitDuringInference ? 3 : 4;
        ScoutingWorkflowProvider create() {
          final evidence = EvidenceCaptureRepository(db);
          return ScoutingWorkflowProvider(
            assessmentId: history.assessment.id,
            workflowRepository: ScoutingWorkflowRepository(db),
            assessmentRepository: AssessmentRepository(db),
            plantSaveService: AtomicPlantSaveService(
              db,
              evidenceRepository: evidence,
            ),
            completionService: ScoutingCompletionService(db),
            veV2SaveService: AtomicVeV2SaveService(db),
            computerVisionService: cv,
            evidenceCoordinator: EvidenceCaptureCoordinator(
              repository: evidence,
              storage: EvidenceStorageService(rootDirectory: () async => dir),
            ),
          );
        }

        var workflow = create();
        await workflow.initialize();
        await workflow.submitResumeCheck(
          condition: ResumeCondition.unchanged,
          safeToContinue: true,
        );
        final paths = <String>[];
        for (var i = 0; i < 3; i++) {
          final file = File('${dir.path}/source$i.jpg');
          final image = img.Image(width: 96, height: 96);
          img.fill(image, color: img.ColorRgb8(60 + i * 40, 140, 70));
          await file.writeAsBytes(img.encodeJpg(image));
          paths.add(file.path);
        }
        final draft =
            await DaBatchImportStore(db, rootDirectory: () async => dir).create(
              assessmentId: history.assessment.id,
              blockId: workflow.prepared!.run.id,
              plantNumbers: [20],
              paths: paths,
            );
        final views = [
          workflow.primaryEvidenceViewType,
          DatabaseCodes.evidenceViewCloseUp,
          DatabaseCodes.evidenceViewDiagnosticDetail,
        ];
        for (var i = 0; i < 3; i++) {
          await workflow.saveDaBatchPhoto(
            blockId: draft.blockId,
            number: 20,
            viewType: views[i],
            photo: draft.photos[i],
          );
        }
        final ids = draft.photos.map((p) => p.id).toSet();
        final interrupted = workflow.screenDaBatchPlant(draft.blockId, 20, ids);
        final failure = expectLater(interrupted, throwsStateError);
        if (quitDuringInference) {
          await cv.entered.future;
          workflow.dispose();
          cv.release.complete();
        }
        await failure;
        expect(cv.calls, 2);
        expect(
          await workflow.daBatchPlantIsScreened(draft.blockId, 20, ids),
          false,
        );
        expect(await db.select(db.plantObservations).get(), hasLength(19));
        final station = (await workflow.loadDaPlantDetails(
          20,
        )).snapshot.station!;
        final key = 'plant_model_${station.id}_1';
        expect(await FieldRepository(db).readPreferenceValue(key), isNull);
        if (!quitDuringInference) workflow.dispose();
        await db.close();
        db = AppDatabase(NativeDatabase(databaseFile));
        workflow = create();
        await workflow.initialize();
        await workflow.submitResumeCheck(
          condition: ResumeCondition.unchanged,
          safeToContinue: true,
        );
        // Simulate a failed disk/database write after inference. The observation
        // and aggregate cache must either both commit or neither commit.
        await db.customStatement(
          "CREATE TRIGGER reject_screen_save BEFORE INSERT ON plant_observations BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END",
        );
        await expectLater(
          workflow.screenDaBatchPlant(draft.blockId, 20, ids),
          throwsA(isA<Exception>()),
        );
        expect(
          cv.calls,
          expectedCalls,
        ); // Only unfinished photos were evaluated.
        expect(await FieldRepository(db).readPreferenceValue(key), isNull);
        expect(await db.select(db.plantObservations).get(), hasLength(19));
        await db.customStatement('DROP TRIGGER reject_screen_save');
        await workflow.screenDaBatchPlant(draft.blockId, 20, ids);
        expect(
          cv.calls,
          expectedCalls,
        ); // Retry reused all three persisted photo results.
        expect(
          await workflow.daBatchPlantIsScreened(draft.blockId, 20, ids),
          true,
        );
        await workflow.refreshAfterDaBatchImport();
        final plant = (await workflow.loadDaPlantDetails(20)).plant!;
        final note = plant.wholePlantContextNote;
        workflow.dispose();
        await db.close();
        db = AppDatabase(NativeDatabase(databaseFile));
        var detail = (await AssessmentHistoryRepository(
          db,
        ).loadDetail(history.assessment.id))!;
        var sample = DaSampleResults.fromDetail(detail);
        expect(sample.assessablePlants, 20);
        expect(
          sample.screening(sample.plants.last)?.result.classificationLabel,
          'FAW damage',
        );
        // Recover a prior app-version cache-only save, without inference or altering
        // a finalized expert finding. A corrupt cache must not hide the valid note.
        await (db.update(
          db.plantObservations,
        )..where((p) => p.id.equals(plant.id))).write(
          const PlantObservationsCompanion(wholePlantContextNote: Value(null)),
        );
        detail = (await AssessmentHistoryRepository(
          db,
        ).loadDetail(history.assessment.id))!;
        expect(DaSampleResults.fromDetail(detail).assessablePlants, 20);
        await (db.update(
          db.plantObservations,
        )..where((p) => p.id.equals(plant.id))).write(
          PlantObservationsCompanion(wholePlantContextNote: Value(note)),
        );
        await FieldRepository(db).savePreferenceValue(key, '{broken');
        detail = (await AssessmentHistoryRepository(
          db,
        ).loadDetail(history.assessment.id))!;
        final models = await AdvisorModelResultsReader(db).load(
          assessmentId: history.assessment.id,
          stations: detail.stations
              .map((s) => s.station)
              .whereType<StationRecord>()
              .toList(),
          plants: [
            for (final s in detail.stations)
              for (final p in s.plants) p.plant,
          ],
        );
        expect(models.samples.last.availability, 'available');
        await (db.update(
          db.plantObservations,
        )..where((p) => p.id.equals(plant.id))).write(
          const PlantObservationsCompanion(wholePlantContextNote: Value(null)),
        );
        detail = (await AssessmentHistoryRepository(
          db,
        ).loadDetail(history.assessment.id))!;
        expect(DaSampleResults.fromDetail(detail).assessablePlants, 20);
        // Changed evidence cannot reuse either a durable result or a cache.
        await (db.update(
          db.evidenceMedia,
        )..where((m) => m.id.equals(draft.photos.first.id))).write(
          const EvidenceMediaCompanion(sha256Checksum: Value('changed')),
        );
        detail = (await AssessmentHistoryRepository(
          db,
        ).loadDetail(history.assessment.id))!;
        sample = DaSampleResults.fromDetail(detail);
        expect(sample.assessablePlants, 19);
        expect(sample.screening(sample.plants.last), isNull);
        expect(cv.calls, expectedCalls);
        await db.close();
        closed = true;
      },
    );
  }
  test(
    'batch preserves existing plants, retries same photos and completes Plant 20 without fabricated GPS',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('da_batch_workflow_');
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final history = await daResultsFixture(db, recorded: 19);
      final evidence = EvidenceCaptureRepository(db);
      final cv = _Cv();
      ScoutingWorkflowProvider create() => ScoutingWorkflowProvider(
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
        computerVisionService: cv,
        evidenceCoordinator: EvidenceCaptureCoordinator(
          repository: evidence,
          storage: EvidenceStorageService(rootDirectory: () async => dir),
        ),
      );
      var workflow = create();
      await workflow.initialize();
      await workflow.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(await workflow.availableDaBatchPlants(), [20]);
      final existing = (await db.select(db.plantObservations).get())
          .map((p) => p.id)
          .toSet();
      final sources = <String>[];
      for (var i = 0; i < 3; i++) {
        final file = File('${dir.path}/source$i.jpg');
        final image = img.Image(width: 96, height: 96);
        img.fill(image, color: img.ColorRgb8(60 + i * 40, 140, 70));
        await file.writeAsBytes(img.encodeJpg(image));
        sources.add(file.path);
      }
      final store = DaBatchImportStore(db, rootDirectory: () async => dir);
      final draft = await store.create(
        assessmentId: history.assessment.id,
        blockId: workflow.prepared!.run.id,
        plantNumbers: [20],
        paths: sources,
      );
      expect(draft.groups.single.length, 3);
      final views = [
        workflow.primaryEvidenceViewType,
        DatabaseCodes.evidenceViewCloseUp,
        DatabaseCodes.evidenceViewDiagnosticDetail,
      ];
      await workflow.saveDaBatchPhoto(
        blockId: draft.blockId,
        number: 20,
        viewType: views[0],
        photo: draft.photos[0],
      );
      workflow.dispose();
      workflow = create();
      await workflow.initialize();
      await workflow.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      for (var i = 0; i < 3; i++)
        await workflow.saveDaBatchPhoto(
          blockId: draft.blockId,
          number: 20,
          viewType: views[i],
          photo: draft.photos[i],
        );
      for (var i = 0; i < 3; i++)
        expect(
          await workflow.daBatchPhotoIsSaved(
            draft.blockId,
            20,
            views[i],
            draft.photos[i].id,
          ),
          true,
        );
      final photos = await db.select(db.evidenceMedia).get();
      expect(photos.length, 3);
      expect(
        photos.every(
          (p) =>
              p.latitude == null &&
              p.longitude == null &&
              p.capturedAt == null &&
              p.captureSource == 'gallery',
        ),
        true,
      );
      await expectLater(
        workflow.saveDaBatchPhoto(
          blockId: draft.blockId,
          number: 19,
          viewType: views[0],
          photo: draft.photos[0],
        ),
        throwsStateError,
      );
      await expectLater(
        workflow.saveDaBatchPhoto(
          blockId: 'another-block',
          number: 20,
          viewType: views[0],
          photo: draft.photos[0],
        ),
        throwsStateError,
      );
      await workflow.screenDaBatchPlant(
        draft.blockId,
        20,
        draft.photos.map((p) => p.id).toSet(),
      );
      await workflow.refreshAfterDaBatchImport();
      expect(workflow.completedDaPlantCount, 20);
      expect(workflow.state, Station1ViewState.blockReview);
      expect(cv.calls, 3);
      // Previous record numbers are not proof of photo evidence.
      expect(workflow.daEvidencePlantNumbers, {20});
      final activeNumber = workflow.stationNumber;
      final activeState = workflow.state;
      final screeningBefore = (await workflow.loadDaPlantDetails(
        20,
      )).plant!.wholePlantContextNote;
      await workflow.saveDaPlantFieldNotes(19, 'Check again after rain.');
      expect(
        (await workflow.loadDaPlantDetails(19)).plant!.evaluatorNotes,
        'Check again after rain.',
      );
      expect(workflow.stationNumber, activeNumber);
      expect(workflow.state, activeState);
      expect(
        (await workflow.loadDaPlantDetails(20)).plant!.wholePlantContextNote,
        screeningBefore,
      );
      expect(cv.calls, 3);
      final plants = await db.select(db.plantObservations).get();
      expect(plants.length, 20);
      expect(plants.map((p) => p.id).toSet().containsAll(existing), true);
      expect(await workflow.loadDaNaturalEnemies(), null);
      workflow.dispose();
    },
  );
}

class _Cv implements FawComputerVisionService {
  int calls = 0;
  int? failAt;
  int? pauseAt;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool positiveFirst = false;
  @override
  bool get isModelLoaded => true;
  @override
  String get modelIdentifier => 'WormWise-AutoScreen-v1:test';
  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) async {
    calls++;
    if (calls == pauseAt) {
      entered.complete();
      await release.future;
    }
    if (calls == failAt)
      return const PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'Unavailable',
        confidenceScore: 0,
        modelName: 'WormWise-AutoScreen-v1:test',
      );
    return PlantDiagnosisResult(
      isInfested: false,
      pestLabel: 'screen',
      confidenceScore: .9,
      classificationLabel: positiveFirst && calls == 1
          ? 'FAW damage'
          : 'No FAW damage',
      modelName: 'WormWise-AutoScreen-v1:test',
    );
  }
}
