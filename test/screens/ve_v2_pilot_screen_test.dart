import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/services/atomic_ve_v2_save_service.dart';
import 'package:wormwise/providers/five_station_workflow_provider.dart';
import 'package:wormwise/screens/ve_v2/ve_v2_pilot_steps.dart';
import 'package:wormwise/services/ve_v2_analysis_service.dart';

void main() {
  testWidgets(
    'continuous VE-V2 capture stays camera-first and usable at 200% text scale',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: VeV2ContinuousCaptureStep(
              target: const VeV2CaptureTarget.plantingUnit(1),
              savedUnitCount: 0,
              capturedLivingCount: 0,
              stationId: 'station-1',
              actorPersonId: 'evaluator-1',
              bundle: _emptyBundle(
                scopeType: DatabaseCodes.evidenceScopePlantingUnit,
                scopeKey: 've_v2_unit_01',
                position: 1,
              ),
              isSaving: false,
              resolveFile: (uri) async => File(uri),
              onCapture: (_) async {},
              onInspect: (_) async {},
              onAccept: (_) async {},
              onRetake: (_) async {},
              onRemove: (_) async {},
              onFallback: (_, _, _) async {},
              onSaveUnit: (_) async {},
              onCompleteLivingCapture: (_, _) async {},
            ),
          ),
        ),
      );

      expect(find.text('Seedling 1 of 10'), findsOneWidget);
      expect(find.textContaining('Planting spots'), findsNothing);
      expect(find.textContaining('Living plants'), findsNothing);
      expect(find.byKey(const Key('ve_v2_assess_seedling')), findsOneWidget);
      expect(
        find.byKey(const Key('ve_v2_no_assessable_seedling')),
        findsOneWidget,
      );
      expect(find.text('Injury location'), findsNothing);
      expect(find.text('Main finding'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('row exception records empty without incrementing a seedling', (
    tester,
  ) async {
    VeV2CaptureRoutingSave? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VeV2ContinuousCaptureStep(
            target: const VeV2CaptureTarget.plantingUnit(1),
            savedUnitCount: 0,
            capturedLivingCount: 0,
            stationId: 'station-1',
            actorPersonId: 'evaluator-1',
            bundle: _emptyBundle(
              scopeType: DatabaseCodes.evidenceScopePlantingUnit,
              scopeKey: 've_v2_unit_01',
              position: 1,
            ),
            isSaving: false,
            resolveFile: (uri) async => File(uri),
            onCapture: (_) async {},
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onFallback: (_, _, _) async {},
            onSaveUnit: (value) async => saved = value,
            onCompleteLivingCapture: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ve_v2_no_assessable_seedling')));
    await tester.pumpAndSettle();
    expect(find.text('What is at this position?'), findsOneWidget);
    await tester.tap(find.text('Empty position'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.occupancyStatus, DatabaseCodes.veOccupancyEmpty);
    expect(saved!.observedSeedlingCount, 0);
  });

  testWidgets('living seedling capture starts the camera automatically', (
    tester,
  ) async {
    final capturedViews = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VeV2ContinuousCaptureStep(
            target: const VeV2CaptureTarget.livingSeedling(
              livingSeedlingPosition: 1,
              sourcePlantingUnitId: 'unit-1',
              sourcePlantingUnitSequence: 1,
            ),
            savedUnitCount: 1,
            capturedLivingCount: 0,
            stationId: 'station-1',
            actorPersonId: 'evaluator-1',
            bundle: _emptyBundle(
              scopeType: DatabaseCodes.evidenceScopePlant,
              scopeKey: 'plant_01',
              position: 1,
            ),
            isSaving: false,
            resolveFile: (uri) async => File(uri),
            onCapture: (view) async => capturedViews.add(view),
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onFallback: (_, _, _) async {},
            onSaveUnit: (_) async {},
            onCompleteLivingCapture: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(capturedViews, [DatabaseCodes.evidenceViewWholeSeedling]);
    expect(find.text('Seedling 1 of 10'), findsOneWidget);
    expect(find.text('Seedling physically checked'), findsNothing);
  });

  testWidgets('camera retries after linked-position saving finishes', (
    tester,
  ) async {
    final capturedViews = <String>[];
    final bundle = _emptyBundle(
      scopeType: DatabaseCodes.evidenceScopePlant,
      scopeKey: 'plant_01',
      position: 1,
    );
    Widget app({required bool isSaving}) => MaterialApp(
      home: Scaffold(
        body: VeV2ContinuousCaptureStep(
          target: const VeV2CaptureTarget.livingSeedling(
            livingSeedlingPosition: 1,
            sourcePlantingUnitId: 'unit-1',
            sourcePlantingUnitSequence: 1,
          ),
          savedUnitCount: 1,
          capturedLivingCount: 0,
          stationId: 'station-1',
          actorPersonId: 'evaluator-1',
          bundle: bundle,
          isSaving: isSaving,
          resolveFile: (uri) async => File(uri),
          onCapture: (view) async => capturedViews.add(view),
          onInspect: (_) async {},
          onAccept: (_) async {},
          onRetake: (_) async {},
          onRemove: (_) async {},
          onFallback: (_, _, _) async {},
          onSaveUnit: (_) async {},
          onCompleteLivingCapture: (_, _) async {},
        ),
      ),
    );

    await tester.pumpWidget(app(isSaving: true));
    await tester.pump();
    expect(capturedViews, isEmpty);

    await tester.pumpWidget(app(isSaving: false));
    await tester.pump();
    expect(capturedViews, [DatabaseCodes.evidenceViewWholeSeedling]);
    expect(find.text('Seedling photo'), findsOneWidget);
  });

  testWidgets('accepted VE-V2 photo waits for explicit continue', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VeV2ContinuousCaptureStep(
            target: const VeV2CaptureTarget.livingSeedling(
              livingSeedlingPosition: 1,
              sourcePlantingUnitId: 'unit-1',
              sourcePlantingUnitSequence: 1,
            ),
            savedUnitCount: 1,
            capturedLivingCount: 0,
            stationId: 'station-1',
            actorPersonId: 'evaluator-1',
            bundle: _readySeedlingBundle(),
            isSaving: false,
            resolveFile: (uri) async => File(uri),
            onCapture: (_) async {},
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onFallback: (_, _, _) async {},
            onSaveUnit: (_) async {},
            onCompleteLivingCapture: (_, _) async => completed = true,
          ),
        ),
      ),
    );

    expect(completed, isFalse);
    expect(find.text('Add close-up (optional)'), findsOneWidget);
    final continueAction = find.byKey(const Key('continue_ve_v2_capture'));
    expect(continueAction, findsOneWidget);
    await tester.tap(continueAction);
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('VE-V2 Station setup remains usable at 200% text scale', (
    tester,
  ) async {
    VeV2StationSetupInput? saved;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: VeV2StationSetupStep(
            stationNumber: 2,
            stationId: 'station-2',
            growthStage: 've',
            actorPersonId: 'evaluator-1',
            isSaving: false,
            onSave: (value) async => saved = value,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Station 2'), findsOneWidget);
    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save_ve_v2_station_setup')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(saved, isNull);
  });

  testWidgets('abnormal unit reveals camera before it can be saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: VeV2PlantingUnitStep(
            position: 1,
            stationId: 'station-1',
            actorPersonId: 'evaluator-1',
            bundle: _emptyBundle(
              scopeType: DatabaseCodes.evidenceScopePlantingUnit,
              scopeKey: 've_v2_unit_01',
              position: 1,
            ),
            isSaving: false,
            resolveFile: (uri) async => File(uri),
            onCapture: (_) async {},
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onFallback: (_, _, _) async {},
            onSave: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ve_unit_condition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Damaged').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after condition selection');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after camera reveal');

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Whole seedling'), findsOneWidget);
    expect(find.text('Take photo'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('save_ve_v2_unit')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save_ve_v2_unit')))
          .onPressed,
      isNull,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'after reaching save action',
    );
  });

  testWidgets('living-seedling evidence reveals conditional photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: VeV2LivingSeedlingStep(
            position: 1,
            stationId: 'station-1',
            actorPersonId: 'evaluator-1',
            linkableUnits: const [],
            bundle: _emptyBundle(
              scopeType: DatabaseCodes.evidenceScopePlant,
              scopeKey: 'plant_01',
              position: 1,
            ),
            isSaving: false,
            resolveFile: (uri) async => File(uri),
            onCapture: (_) async {},
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onFallback: (_, _, _) async {},
            onSave: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Windowpanes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Windowpanes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Close-up'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Whole seedling'), findsOneWidget);
    expect(find.text('Close-up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VE-V2 review uses the compact shared station hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? openedPosition;
    final now = DateTime.utc(2026, 8, 21);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: VeV2StationReviewStep(
              stationNumber: 1,
              units: const [],
              plants: const [],
              inspection: VeV2StationInspectionRecord(
                id: 'inspection-1',
                createdAt: now,
                updatedAt: now,
                syncState: DatabaseCodes.localOnly,
                serverVersion: 0,
                stationId: 'station-1',
                plantingUnitSequenceAssessable: true,
                protocolVersion: 'test',
                plantingUnitEntryDurationMs: 0,
                livingSeedlingEntryDurationMs: 0,
                correctionCount: 0,
                repeatedPhysicalCheckCount: 0,
              ),
              acceptedImageCount: 0,
              fallbackCount: 0,
              retakeCount: 0,
              evidenceBundles: const [],
              resolveFile: (uri) async => File(uri),
              onInspect: (_) async {},
              analysisFor: (_) => VeV2AnalysisPresentation.unavailable,
              isSaving: false,
              onEditUnit: (_) async {},
              onEditPlant: (position) async => openedPosition = position,
              onComplete: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Station Evidence Review'), findsOneWidget);
    for (var position = 1; position <= 10; position++) {
      expect(find.byKey(Key('review_position_$position')), findsOneWidget);
    }
    final nextReview = find.byKey(const Key('complete_ve_v2_pilot_station'));
    expect(tester.getSize(nextReview).height, greaterThanOrEqualTo(56));
    await tester.tap(nextReview);
    expect(openedPosition, 1);
    expect(tester.takeException(), isNull);
  });
}

EvidenceCaptureBundle _emptyBundle({
  required String scopeType,
  required String scopeKey,
  required int position,
}) {
  final now = DateTime.utc(2026, 8, 21);
  return EvidenceCaptureBundle(
    session: EvidenceCaptureSessionRecord(
      id: 'session-$scopeKey',
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentId: 'assessment-1',
      stationId: 'station-1',
      scopeType: scopeType,
      scopeKey: scopeKey,
      plantPosition: position,
      requirementsVersion: 'test',
      collectionMode: DatabaseCodes.evidenceCollectionCamera,
      collectionStatus: DatabaseCodes.evidenceSessionInProgress,
      startedAt: now,
    ),
    media: const [],
  );
}

EvidenceCaptureBundle _readySeedlingBundle() {
  final bundle = _emptyBundle(
    scopeType: DatabaseCodes.evidenceScopePlant,
    scopeKey: 'plant_01',
    position: 1,
  );
  final now = DateTime.utc(2026, 8, 21);
  return EvidenceCaptureBundle(
    session: bundle.session,
    media: [
      EvidenceMediaRecord(
        id: 'whole-seedling-1',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        assessmentId: 'assessment-1',
        stationId: 'station-1',
        captureSessionId: bundle.session.id,
        mediaType: 'image',
        viewType: DatabaseCodes.evidenceViewWholeSeedling,
        localUri: 'whole_seedling.jpg',
        thumbnailLocalUri: 'whole_seedling_thumb.jpg',
        mimeType: 'image/jpeg',
        byteSize: 100,
        sha256Checksum: 'whole-seedling-checksum',
        capturedAt: now,
        qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
        captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
        widthPx: 2048,
        heightPx: 1536,
        storageState: DatabaseCodes.evidenceStorageReady,
        uploadState: DatabaseCodes.localOnly,
        isCanonicalEvidence: true,
      ),
    ],
  );
}
