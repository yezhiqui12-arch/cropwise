import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/models/guided_plant_details.dart';
import 'package:wormwise/screens/scan/guided_plant_details_sheet.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import '../support/da_results_fixture.dart';

void main() {
  testWidgets(
    'pin details shows saved evidence and screening without station review',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final history = (await tester.runAsync(
        () => daResultsFixture(db, recorded: 1),
      ))!;
      final snapshot = history.stations.first;
      final bundle = (await tester.runAsync(
        () => EvidenceCaptureRepository(
          db,
        ).loadStationBundles(snapshot.station!.id),
      ))!.first;
      final now = DateTime.now();
      final photo = EvidenceMediaRecord(
        id: 'photo',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        assessmentId: history.assessment.id,
        stationId: snapshot.station!.id,
        captureSessionId: bundle.session.id,
        mediaType: 'image',
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        localUri: 'missing.jpg',
        mimeType: 'image/jpeg',
        byteSize: 0,
        sha256Checksum: 'hash',
        capturedAt: now,
        qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
        captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
        storageState: DatabaseCodes.evidenceStorageReady,
        locationSource: 'unavailable',
        uploadState: DatabaseCodes.localOnly,
        isCanonicalEvidence: true,
      );
      final details = GuidedPlantDetails(
        snapshot: snapshot,
        evidence: EvidenceCaptureBundle(
          session: bundle.session,
          media: [photo],
        ),
        diagnosis: const PlantDiagnosisResult(
          isInfested: false,
          pestLabel: 'screen',
          confidenceScore: .92,
          classificationLabel: 'FAW damage',
          modelName: 'WormWise-AutoScreen-v1:test',
        ),
      );
      Map<String, bool?>? corrections;
      String? savedNotes;
      Widget screen(Future<GuidedPlantDetails> Function() load) => MaterialApp(
        home: Scaffold(
          body: GuidedPlantDetailsSheet(
            number: 1,
            blockNumber: 1,
            growthStage: 'v3_v6',
            loadDetails: load,
            resolveFile: (uri) async => File(uri),
            onSaveCorrection: (values) async => corrections = values,
            onSaveNotes: (notes) async => savedNotes = notes,
          ),
        ),
      );
      await tester.pumpWidget(screen(() async => details));
      await tester.pumpAndSettle();
      expect(find.text('Plant 1'), findsOneWidget);
      expect(find.text('Sampled · 1 photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guided_details_notes')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('guided_details_notes_input')),
        'Recheck this sample.',
      );
      await tester.tap(find.byKey(const Key('guided_details_save_notes')));
      await tester.pumpAndSettle();
      expect(savedNotes, 'Recheck this sample.');
      expect(find.byKey(const Key('guided_details_notes_input')), findsNothing);
      expect(find.textContaining('Suggested point:'), findsNothing);
      expect(find.textContaining('expert review'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('plant_details_screening_status')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Damage detected'), findsOneWidget);
      expect(find.text('92% confidence'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Capture location'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Capture location'));
      await tester.pumpAndSettle();
      expect(find.text('Not recorded'), findsOneWidget);
      await tester.tap(find.byKey(const Key('da_open_correction')));
      await tester.pumpAndSettle();
      expect(find.text('Correct observations'), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.byKey(const Key('da_correct_damage_no')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('da_correct_damage_no')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('da_save_correction')));
      await tester.pumpAndSettle();
      expect(corrections?['damage'], false);
      expect(find.text('Saved'), findsOneWidget);
      expect(details.diagnosis!.classificationLabel, 'FAW damage');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => db.close());
    },
  );
}
