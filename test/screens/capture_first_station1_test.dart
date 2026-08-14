import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/station1_workflow_repository.dart';
import 'package:wormwise/screens/station1/continuous_plant_capture_step.dart';
import 'package:wormwise/screens/station1/plant_selection_step.dart';
import 'package:wormwise/screens/station1/station_review_step.dart';
import 'package:wormwise/screens/station1/station1_workflow_screen.dart';
import 'package:wormwise/services/station_evidence_policy.dart';

void main() {
  testWidgets(
    'camera-first guidance is explicit and reachable at 200 percent text scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: PlantSelectionStep(
                blockNumber: 1,
                stationNumber: 3,
                evidencePolicy:
                    StationEvidencePolicy.cameraFirstOverviewConditional,
                onBegin: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('BLOCK 1 · STATION 3'), findsOneWidget);
      final policyNotice = find.byKey(const Key('camera_first_policy_notice'));
      await tester.scrollUntilVisible(
        policyNotice,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Camera-first pilot'), findsOneWidget);
      final action = find.byKey(const Key('begin_ten_plants_button'));
      await tester.scrollUntilVisible(
        action,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Use documented fallback'), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(56));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Station guidance explains one overview, conditional close-up, and honest no-model review',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantSelectionStep(
              evidencePolicy:
                  StationEvidencePolicy.cameraFirstOverviewConditional,
              onBegin: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('ten consecutive plants'), findsOneWidget);
      expect(find.textContaining('one guided overview'), findsOneWidget);
      expect(find.textContaining('Add a close-up only when'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('begin_ten_plants_button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no validated image model'), findsOneWidget);
      expect(
        find.textContaining('confirm every plant manually'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'continuous capture advances after one overview without a manual form',
    (tester) async {
      var bundle = _bundle();
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ContinuousPlantCaptureStep(
                  evidencePolicy:
                      StationEvidencePolicy.cameraFirstOverviewConditional,
                  position: 1,
                  capturedPlantCount: 0,
                  initialLeavesInspectedCount: null,
                  bundle: bundle,
                  isSaving: false,
                  resolveFile: (path) async => File(path),
                  onCapture: (viewType) async => viewType,
                  onInspect: (media) async => media.viewType,
                  onAccept: (_) async => true,
                  onRetake: (media) async => media.viewType,
                  onRemove: (_) async {},
                  onManualFallback: (_, _, _) async => true,
                  onLeavesInspected: (_) async {},
                  onCompletePlant: (_, _) async => completed = true,
                  onCannotAssess: (_, _) async {},
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Required view 1 · Overview'), findsNothing);
      await tester.tap(find.byKey(const Key('capture_assessable_yes')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('capture_leaves_3')));
      await tester.pump();
      expect(
        find.byKey(Key('capture_${DatabaseCodes.evidenceViewWhorlOverview}')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(
        find.byKey(Key('capture_${DatabaseCodes.evidenceViewWhorlOverview}')),
      );
      await tester.pump();
      expect(completed, isTrue);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'continuous capture remains reachable at 200 percent text scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: ContinuousPlantCaptureStep(
                evidencePolicy:
                    StationEvidencePolicy.cameraFirstOverviewConditional,
                position: 4,
                capturedPlantCount: 3,
                initialLeavesInspectedCount: 4,
                bundle: _bundle(
                  waivedViews: {DatabaseCodes.evidenceViewWhorlOverview},
                ),
                isSaving: false,
                resolveFile: (path) async => File(path),
                onCapture: (viewType) async => viewType,
                onInspect: (media) async => media.viewType,
                onAccept: (_) async => true,
                onRetake: (media) async => media.viewType,
                onRemove: (_) async {},
                onManualFallback: (_, _, _) async => true,
                onLeavesInspected: (_) async {},
                onCompletePlant: (_, _) async {},
                onCannotAssess: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      final leaves = find.byKey(const Key('capture_leaves_4'));
      expect(tester.widget<ChoiceChip>(leaves).selected, isTrue);
      await tester.scrollUntilVisible(
        leaves,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(leaves);
      await tester.pumpAndSettle();
      await tester.tap(leaves);
      await tester.pump();
      final next = find.byKey(const Key('next_plant_after_capture'));
      await tester.scrollUntilVisible(
        next,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(next, findsOneWidget);
      expect(tester.getSize(next).height, greaterThanOrEqualTo(56));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Station Evidence Review exposes ten separate no-model confirmations',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? openedPosition;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: StationReviewStep(
                snapshot: _snapshot(),
                evidencePolicy:
                    StationEvidencePolicy.cameraFirstOverviewConditional,
                isSaving: false,
                onEdit: (position) => openedPosition = position,
                onConfirm: () {},
                evidenceBundles: [
                  _bundle(scopeType: DatabaseCodes.evidenceScopeStationContext),
                  for (var position = 1; position <= 10; position++)
                    _bundle(
                      position: position,
                      waivedViews: {
                        DatabaseCodes.evidenceViewWhorlOverview,
                        DatabaseCodes.evidenceViewCloseUp,
                      },
                    ),
                ],
                resolveEvidenceFile: (path) async => File(path),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Automated analysis unavailable'), findsOneWidget);
      expect(
        find.textContaining('No image result has been generated'),
        findsOneWidget,
      );
      expect(find.text('Confirm All'), findsNothing);
      final pendingPlant = find.byKey(const Key('pending_manual_plant_1'));
      await tester.scrollUntilVisible(
        pendingPlant,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(pendingPlant, findsOneWidget);
      await tester.tap(find.byKey(const Key('manual_confirm_plant_1_button')));
      expect(openedPosition, 1);
      final completeFinder = find.byKey(
        const Key('confirm_station_review_button'),
      );
      await tester.scrollUntilVisible(
        completeFinder,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final complete = tester.widget<FilledButton>(completeFinder);
      expect(complete.onPressed, isNull);
      expect(
        find.byKey(const Key('complete_test_station_from_review_button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'TEST DATA review exposes a reachable synthetic station bypass at 200 percent text scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: StationReviewStep(
                snapshot: _snapshot(),
                evidencePolicy:
                    StationEvidencePolicy.cameraFirstOverviewConditional,
                isSaving: false,
                onEdit: (_) {},
                onConfirm: () {},
                onCompleteTestStation: () => completed = true,
              ),
            ),
          ),
        ),
      );

      final shortcut = find.byKey(
        const Key('complete_test_station_from_review_button'),
      );
      await tester.scrollUntilVisible(
        shortcut,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(shortcut, findsOneWidget);
      expect(tester.getSize(shortcut).height, greaterThanOrEqualTo(56));
      await tester.tap(shortcut);
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'persistent TEST DATA actions bypass one or all stations without capture',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var currentCalls = 0;
      var allCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: TestDataWorkflowActions(
                stationNumber: 3,
                isSaving: false,
                onCompleteCurrent: () => currentCalls++,
                onCompleteAll: () => allCalls++,
              ),
            ),
          ),
        ),
      );

      final all = find.byKey(
        const Key('complete_all_test_stations_persistent_button'),
      );
      final current = find.byKey(
        const Key('complete_current_test_station_persistent_button'),
      );
      expect(
        find.textContaining('No photos or manual documentation'),
        findsOneWidget,
      );
      expect(tester.getSize(all).height, greaterThanOrEqualTo(56));
      await tester.tap(all);
      await tester.tap(current);
      expect(allCalls, 1);
      expect(currentCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Station Evidence Review renders every required evidence state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationReviewStep(
            snapshot: _snapshot(plants: [_notAssessablePlant(6)]),
            evidencePolicy:
                StationEvidencePolicy.cameraFirstOverviewConditional,
            isSaving: false,
            onEdit: (_) {},
            onConfirm: () {},
            evidenceBundles: [
              _bundle(
                position: 2,
                waivedViews: {DatabaseCodes.evidenceViewWhorlOverview},
              ),
              _bundle(
                position: 3,
                readyViews: {DatabaseCodes.evidenceViewWhorlOverview},
              ),
              _bundle(
                position: 4,
                readyViews: {DatabaseCodes.evidenceViewWhorlOverview},
              ),
              _bundle(
                position: 5,
                readyViews: {
                  DatabaseCodes.evidenceViewWhorlOverview,
                  DatabaseCodes.evidenceViewCloseUp,
                },
              ),
            ],
            evidenceReviews: const {
              4: PlantEvidenceReview(
                sessionId: 'plant-4',
                plantPosition: 4,
                status: DatabaseCodes.evidenceReviewInsufficient,
                isCurrent: true,
              ),
              5: PlantEvidenceReview(
                sessionId: 'plant-5',
                plantPosition: 5,
                status: DatabaseCodes.evidenceReviewSufficient,
                isCurrent: true,
              ),
            },
            resolveEvidenceFile: (path) async => File(path),
            evidenceThumbnailBuilder: (_) =>
                const SizedBox.square(dimension: 72),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Missing'), findsWidgets);
    expect(find.text('Fallback'), findsWidgets);
    expect(find.text('Not reviewed'), findsOneWidget);
    expect(find.text('Insufficient'), findsOneWidget);
    expect(find.text('Sufficient'), findsOneWidget);
    expect(find.text('Not assessable'), findsWidgets);
    expect(find.text('Close-up'), findsWidgets);
    expect(
      find.textContaining('Structured observations incomplete'),
      findsWidgets,
    );
    final complete = tester.widget<FilledButton>(
      find.byKey(const Key('confirm_station_review_button')),
    );
    expect(complete.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

EvidenceCaptureBundle _bundle({
  String scopeType = DatabaseCodes.evidenceScopePlant,
  int position = 1,
  Set<String> waivedViews = const {},
  Set<String> readyViews = const {},
}) {
  final now = DateTime.utc(2026, 8, 13);
  final plant = scopeType == DatabaseCodes.evidenceScopePlant;
  return EvidenceCaptureBundle(
    session: EvidenceCaptureSessionRecord(
      id: plant ? 'plant-$position' : 'station-context',
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentId: 'assessment-1',
      stationId: 'station-1',
      scopeType: scopeType,
      scopeKey: plant
          ? 'plant_${position.toString().padLeft(2, '0')}'
          : DatabaseCodes.evidenceScopeStationContext,
      plantPosition: plant ? position : null,
      requirementsVersion: plant
          ? 'capture_first_station1_v1'
          : 'camera_phase_a_v1',
      collectionMode: waivedViews.isEmpty
          ? DatabaseCodes.evidenceCollectionCamera
          : DatabaseCodes.evidenceCollectionCameraWithFallback,
      collectionStatus: DatabaseCodes.evidenceSessionInProgress,
      waivedViewTypesJson: waivedViews.isEmpty
          ? null
          : jsonEncode(waivedViews.toList()),
      startedAt: now,
    ),
    media: [
      for (final viewType in readyViews)
        _readyMedia(
          id: 'plant-$position-$viewType',
          sessionId: 'plant-$position',
          position: position,
          viewType: viewType,
        ),
    ],
  );
}

EvidenceMediaRecord _readyMedia({
  required String id,
  required String sessionId,
  required int position,
  required String viewType,
}) {
  final now = DateTime.utc(2026, 8, 13);
  return EvidenceMediaRecord(
    id: id,
    createdAt: now,
    updatedAt: now,
    syncState: DatabaseCodes.localOnly,
    serverVersion: 0,
    assessmentId: 'assessment-1',
    stationId: 'station-1',
    captureSessionId: sessionId,
    mediaType: 'image',
    viewType: viewType,
    localUri: 'plant_${position}_$viewType.jpg',
    thumbnailLocalUri: 'plant_${position}_${viewType}_thumb.jpg',
    mimeType: 'image/jpeg',
    byteSize: 100,
    sha256Checksum: 'checksum-$id',
    capturedAt: now,
    qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
    captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
    widthPx: 2048,
    heightPx: 1536,
    storageState: DatabaseCodes.evidenceStorageReady,
    uploadState: DatabaseCodes.localOnly,
    isCanonicalEvidence: true,
  );
}

Station1PlantRecord _notAssessablePlant(int position) {
  final now = DateTime.utc(2026, 8, 13);
  final id = 'plant-record-$position';
  return Station1PlantRecord(
    plant: PlantObservationRecord(
      id: id,
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      stationId: 'station-1',
      sequenceNumber: position,
      assessable: false,
      notAssessableReason: 'Plant missing at this position',
      plantStatus: DatabaseCodes.plantNotAssessable,
      oldDamagePresent: false,
      naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNotCollected,
    ),
    vegetative: VegetativeObservationRecord(
      plantObservationId: id,
      smallFreshWindowpanes: false,
      infestedWhorl: false,
      scraping: false,
      cuttingOrTearing: false,
      freshFrass: false,
      whorlFeedingSign: false,
      larvaVisible: false,
      larvalSize: 'none_seen',
      damageScoreUncertain: false,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Station1Snapshot _snapshot({List<Station1PlantRecord> plants = const []}) {
  final now = DateTime.utc(2026, 8, 13);
  return Station1Snapshot(
    prepared: PreparedStation1Run(
      block: FieldBlockRecord(
        id: 'block-1',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        cropCycleId: 'cycle-1',
        boundaryVersionId: 'boundary-1',
        blockNumber: 1,
        geometryGeojson: '{}',
        areaHectares: 0.8,
        isProvisional: false,
      ),
      run: AssessmentBlockRunRecord(
        id: 'run-1',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        assessmentId: 'assessment-1',
        fieldBlockId: 'block-1',
        blockSequence: 1,
        scoutingPattern: DatabaseCodes.patternW,
        status: DatabaseCodes.inProgress,
        edgeBiasWarning: false,
      ),
    ),
    station: StationRecord(
      id: 'station-1',
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentBlockRunId: 'run-1',
      stationNumber: 1,
      notLocatedReason: DatabaseCodes.stationNoCurrentFix,
    ),
    plants: plants,
    reviewedAt: null,
    reviewIsCurrent: false,
  );
}
