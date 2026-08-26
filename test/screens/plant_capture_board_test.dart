import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/screens/station1/plant_capture_board_step.dart';
import 'package:wormwise/services/station_evidence_policy.dart';

EvidenceCaptureBundle _mockPlantBundle({
  required int position,
  bool completed = false,
}) {
  final now = DateTime.utc(2026, 8, 13);
  final sessionId = 'plant-session-$position';
  return EvidenceCaptureBundle(
    session: EvidenceCaptureSessionRecord(
      id: sessionId,
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentId: 'assessment-1',
      stationId: 'station-1',
      scopeType: DatabaseCodes.evidenceScopePlant,
      scopeKey: 'plant_$position',
      plantPosition: position,
      requirementsVersion:
          DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
      collectionMode: DatabaseCodes.evidenceCollectionCamera,
      collectionStatus: completed
          ? DatabaseCodes.completed
          : DatabaseCodes.inProgress,
      waivedViewTypesJson: null,
      startedAt: now,
      completedAt: completed ? now : null,
    ),
    media: completed
        ? [
            EvidenceMediaRecord(
              id: 'media-$position',
              createdAt: now,
              updatedAt: now,
              syncState: DatabaseCodes.localOnly,
              serverVersion: 0,
              assessmentId: 'assessment-1',
              stationId: 'station-1',
              captureSessionId: sessionId,
              mediaType: 'image',
              viewType: DatabaseCodes.evidenceViewWhorlOverview,
              localUri: 'plant$position.jpg',
              thumbnailLocalUri: 'plant$position.jpg',
              mimeType: 'image/jpeg',
              byteSize: 100,
              sha256Checksum: 'checksum',
              capturedAt: now,
              qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
              captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
              widthPx: 32,
              heightPx: 24,
              storageState: DatabaseCodes.evidenceStorageReady,
              uploadState: DatabaseCodes.localOnly,
              isCanonicalEvidence: true,
            ),
          ]
        : const [],
  );
}

void main() {
  testWidgets('PlantCaptureBoardStep displays 10 plant tiles and progresses', (
    WidgetTester tester,
  ) async {
    int selectedPos = 1;
    bool completedStation = false;
    final completedBundle1 = _mockPlantBundle(position: 1, completed: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return PlantCaptureBoardStep(
                blockNumber: 1,
                stationNumber: 1,
                evidencePolicy:
                    StationEvidencePolicy.cameraFirstOverviewConditional,
                selectedPosition: selectedPos,
                capturedPlantCount: 1,
                stationBundles: [completedBundle1],
                isSaving: false,
                resolveFile: (path) async => File(path),
                onSelectPlant: (pos) {
                  setState(() => selectedPos = pos);
                },
                onCapture: (pos, view) async => null,
                onInspect: (_) async => null,
                onAccept: (_) async => true,
                onRetake: (_) async => null,
                onRemove: (_) async {},
                onManualFallback: (pos, view, reason, note) async => true,
                onCompleteStationCapture: () {
                  completedStation = true;
                },
                onCannotAssess: (_, _) async {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Board Header
    expect(find.textContaining('Capture Plants 1'), findsOneWidget);
    expect(find.text('1/10 Captured'), findsOneWidget);

    // Verify Plant 1 is complete
    expect(find.text('Overview ✓ · Close-up optional'), findsOneWidget);

    // Verify Plant 2 is displayed as Overview needed
    expect(find.text('Plant 2'), findsOneWidget);
    expect(find.text('Overview needed'), findsWidgets);

    // Tap Plant 2 to select it
    await tester.tap(find.text('Plant 2'));
    await tester.pumpAndSettle();

    expect(selectedPos, 2);
    expect(find.text('Capture Plant 2'), findsOneWidget);
    expect(find.byKey(const Key('capture_cannot_assess')), findsOneWidget);
    expect(completedStation, isFalse);

    // Tap Plant 2 again to close/collapse it
    await tester.tap(find.text('Plant 2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_cannot_assess')), findsNothing);

    // Tap Plant 2 again to reopen it
    await tester.tap(find.text('Plant 2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_cannot_assess')), findsOneWidget);
  });

  testWidgets(
    'PlantCaptureBoardStep adapts to VE-V2 growth stage with Seedlings 1-10',
    (WidgetTester tester) async {
      int selectedPos = 1;
      final veBundle1 = EvidenceCaptureBundle(
        session: EvidenceCaptureSessionRecord(
          id: 've-session-1',
          createdAt: DateTime.utc(2026, 8, 13),
          updatedAt: DateTime.utc(2026, 8, 13),
          syncState: DatabaseCodes.localOnly,
          serverVersion: 0,
          assessmentId: 'assessment-1',
          stationId: 'station-1',
          scopeType: DatabaseCodes.evidenceScopePlant,
          scopeKey: 'plant_1',
          plantPosition: 1,
          requirementsVersion:
              DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1,
          collectionMode: DatabaseCodes.evidenceCollectionCamera,
          collectionStatus: DatabaseCodes.completed,
          waivedViewTypesJson: null,
          startedAt: DateTime.utc(2026, 8, 13),
          completedAt: DateTime.utc(2026, 8, 13),
        ),
        media: [
          EvidenceMediaRecord(
            id: 've-media-1',
            createdAt: DateTime.utc(2026, 8, 13),
            updatedAt: DateTime.utc(2026, 8, 13),
            syncState: DatabaseCodes.localOnly,
            serverVersion: 0,
            assessmentId: 'assessment-1',
            stationId: 'station-1',
            captureSessionId: 've-session-1',
            mediaType: 'image',
            viewType: DatabaseCodes.evidenceViewWholeSeedling,
            localUri: 'seedling1.jpg',
            thumbnailLocalUri: 'seedling1.jpg',
            mimeType: 'image/jpeg',
            byteSize: 100,
            sha256Checksum: 'checksum',
            capturedAt: DateTime.utc(2026, 8, 13),
            qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
            captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
            widthPx: 32,
            heightPx: 24,
            storageState: DatabaseCodes.evidenceStorageReady,
            uploadState: DatabaseCodes.localOnly,
            isCanonicalEvidence: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PlantCaptureBoardStep(
                  blockNumber: 1,
                  stationNumber: 1,
                  isVeV2: true,
                  evidencePolicy:
                      StationEvidencePolicy.cameraFirstOverviewConditional,
                  selectedPosition: selectedPos,
                  capturedPlantCount: 1,
                  stationBundles: [veBundle1],
                  isSaving: false,
                  resolveFile: (path) async => File(path),
                  onSelectPlant: (pos) {
                    setState(() => selectedPos = pos);
                  },
                  onCapture: (pos, view) async => null,
                  onInspect: (_) async => null,
                  onAccept: (_) async => true,
                  onRetake: (_) async => null,
                  onRemove: (_) async {},
                  onManualFallback: (pos, view, reason, note) async => true,
                  onCompleteStationCapture: () {},
                  onCannotAssess: (_, _) async {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify VE-V2 Board Header & Seedling Labeling
      expect(find.textContaining('Capture Seedlings 1'), findsOneWidget);
      expect(find.text('Seedling 1'), findsOneWidget);
      expect(find.text('Seedling 2'), findsOneWidget);

      // Verify Seedling 1 status is satisfied
      expect(find.text('Seedling ✓ · Close-up optional'), findsOneWidget);

      // Verify Seedling 2 prompts for Whole Seedling
      expect(find.text('Seedling needed'), findsWidgets);

      // Select Seedling 2 and check action button
      await tester.tap(find.text('Seedling 2'));
      await tester.pumpAndSettle();

      expect(find.text('Capture Seedling 2'), findsOneWidget);
      expect(find.text('Add Seedling'), findsOneWidget);
    },
  );
}
