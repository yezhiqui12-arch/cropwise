import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/station1_workflow_repository.dart';
import 'package:wormwise/screens/station1/plant_observation_step.dart';
import 'package:wormwise/screens/station1/evidence_photo_viewer.dart';
import 'package:wormwise/screens/station1/station_context_evidence_step.dart';
import 'package:wormwise/screens/station1/station_review_step.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';

void main() {
  testWidgets('station context remains usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: StationContextEvidenceStep(
              bundle: _bundle(),
              isSaving: false,
              resolveFile: (path) async => File(path),
              onCapture: () async {},
              onInspect: (_) async {},
              onAccept: (_) async {},
              onRetake: (_) async {},
              onRemove: (_) async {},
              onManualFallback: (_, _) async {},
              onContinue: () async {},
            ),
          ),
        ),
      ),
    );

    final camera = find.byKey(
      const Key('capture_${DatabaseCodes.evidenceViewStationContext}'),
    );
    await tester.scrollUntilVisible(
      camera,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera, findsOneWidget);
    expect(tester.getSize(camera).height, greaterThanOrEqualTo(56));

    final fallback = find.byKey(
      const Key('manual_fallback_${DatabaseCodes.evidenceViewStationContext}'),
    );
    await tester.scrollUntilVisible(
      fallback,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(fallback, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual fallback requires and records a documented reason', (
    WidgetTester tester,
  ) async {
    String? savedReason;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationContextEvidenceStep(
            bundle: _bundle(),
            isSaving: false,
            resolveFile: (path) async => File(path),
            onCapture: () async {},
            onInspect: (_) async {},
            onAccept: (_) async {},
            onRetake: (_) async {},
            onRemove: (_) async {},
            onManualFallback: (reason, _) async => savedReason = reason,
            onContinue: () async {},
          ),
        ),
      ),
    );

    final fallback = find.byKey(
      const Key('manual_fallback_${DatabaseCodes.evidenceViewStationContext}'),
    );
    await tester.scrollUntilVisible(
      fallback,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(find.text('Document manual fallback'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save_evidence_fallback')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('evidence_fallback_reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No usable camera').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_evidence_fallback')));
    await tester.pumpAndSettle();

    expect(savedReason, DatabaseCodes.evidenceFallbackNoCamera);
  });

  testWidgets(
    'assessable plant shows camera-first overview and conditional close-up',
    (WidgetTester tester) async {
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
              onSave: (_) async {},
              evidence: _bundle(scopeType: DatabaseCodes.evidenceScopePlant),
              resolveEvidenceFile: (path) async => File(path),
              onCaptureEvidence: (_) async {},
              onInspectEvidence: (_) async {},
              onAcceptEvidence: (_) async {},
              onRetakeEvidence: (_) async {},
              onRemoveEvidence: (_) async {},
              onManualFallback: (_, _, _) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assessable_yes')));
      await tester.pump();
      expect(
        find.byKey(
          const Key(
            'evidence_panel_${DatabaseCodes.evidenceViewWhorlOverview}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('evidence_panel_${DatabaseCodes.evidenceViewCloseUp}'),
        ),
        findsNothing,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('fresh_windowpanes_field')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('fresh_windowpanes_field')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('evidence_panel_${DatabaseCodes.evidenceViewCloseUp}'),
        ),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('evidence_panel_${DatabaseCodes.evidenceViewCloseUp}'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'plant camera action remains reachable at 200 percent text scale',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: PlantObservationStep(
                position: 1,
                savedCount: 0,
                stationId: 'station-1',
                actorPersonId: 'evaluator-1',
                existing: null,
                isSaving: false,
                onSave: (_) async {},
                evidence: _bundle(scopeType: DatabaseCodes.evidenceScopePlant),
                resolveEvidenceFile: (path) async => File(path),
                onCaptureEvidence: (_) async {},
                onInspectEvidence: (_) async {},
                onAcceptEvidence: (_) async {},
                onRetakeEvidence: (_) async {},
                onRemoveEvidence: (_) async {},
                onManualFallback: (_, _, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('assessable_yes')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('assessable_yes')));
      await tester.pump();
      final camera = find.byKey(
        const Key('capture_${DatabaseCodes.evidenceViewWhorlOverview}'),
      );
      await tester.scrollUntilVisible(
        camera,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(camera, findsOneWidget);
      expect(tester.getSize(camera).height, greaterThanOrEqualTo(56));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plant thumbnail opens canonical image and preserves unsaved answers',
    (tester) async {
      late Directory root;
      late File original;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('plant_preview_');
        original = await _writeOnePixelPng(root, 'plant_1.png');
      });
      addTearDown(() => root.delete(recursive: true));
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return Scaffold(
                body: PlantObservationStep(
                  position: 1,
                  savedCount: 0,
                  stationId: 'station-1',
                  actorPersonId: 'evaluator-1',
                  existing: null,
                  isSaving: false,
                  onSave: (_) async {},
                  evidence: _readyPlantBundle(original.path),
                  resolveEvidenceFile: (path) async => File(path),
                  onCaptureEvidence: (_) async {},
                  onInspectEvidence: (media) => Navigator.push<void>(
                    hostContext,
                    MaterialPageRoute(
                      builder: (_) => EvidencePhotoViewer(
                        media: media,
                        scopeLabel: 'Plant 1',
                        resolveFile: (path) async => File(path),
                      ),
                    ),
                  ),
                  onAcceptEvidence: (_) async {},
                  onRetakeEvidence: (_) async {},
                  onRemoveEvidence: (_) async {},
                  onManualFallback: (_, _, _) async {},
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('assessable_yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final inspect = find.byKey(
        const Key(
          'inspect_evidence_${DatabaseCodes.evidenceViewWhorlOverview}',
        ),
      );
      expect(inspect, findsOneWidget);
      await tester.ensureVisible(inspect);
      await tester.pumpAndSettle();
      await tester.tap(inspect);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('evidence_canonical_image')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      final assessableChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('assessable_yes')),
      );
      expect(assessableChip.selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Station 1 review displays documented evidence fallback', (
    WidgetTester tester,
  ) async {
    final bundle = _bundle(waived: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationReviewStep(
            snapshot: _reviewSnapshot(),
            isSaving: false,
            onEdit: (_) {},
            onConfirm: () {},
            evidenceBundles: [bundle],
            resolveEvidenceFile: (path) async => File(path),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('review_evidence_station_context')),
      findsOneWidget,
    );
    expect(find.text('Station context'), findsOneWidget);
    expect(find.text('Manual fallback documented'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Station 1 review displays accepted evidence thumbnails', (
    WidgetTester tester,
  ) async {
    EvidenceMediaRecord? opened;
    String? openedScope;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationReviewStep(
            snapshot: _reviewSnapshot(),
            isSaving: false,
            onEdit: (_) {},
            onConfirm: () {},
            evidenceBundles: [_readyStationBundle()],
            resolveEvidenceFile: (path) async => File(path),
            evidenceThumbnailBuilder: (_) => const ColoredBox(
              key: Key('accepted_evidence_thumbnail'),
              color: Colors.green,
            ),
            onOpenEvidence: (media, scope) async {
              opened = media;
              openedScope = scope;
            },
            pilotWorkloadMetrics: const PilotWorkloadMetrics(
              activeTimeByPlant: {1: Duration(seconds: 48)},
              retakeCount: 2,
              acceptedImageCount: 1,
              manualFallbackCount: 1,
              storageBytes: 1048576,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('accepted_evidence_thumbnail')),
      findsOneWidget,
    );
    expect(find.text('Context'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('review_open_evidence_context-media')),
    );
    await tester.pump();
    expect(opened?.id, 'context-media');
    expect(openedScope, 'Station context');
    await tester.scrollUntilVisible(
      find.byKey(const Key('pilot_workload_metrics')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('1 accepted images'), findsOneWidget);
    expect(find.textContaining('2 retakes'), findsOneWidget);
    expect(find.textContaining('1 manual fallbacks'), findsOneWidget);
    expect(find.textContaining('1.00 MiB'), findsOneWidget);
    expect(find.textContaining('P1: 48s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

EvidenceCaptureBundle _bundle({
  String scopeType = DatabaseCodes.evidenceScopeStationContext,
  bool waived = false,
}) {
  final now = DateTime.utc(2026, 8, 13);
  final plant = scopeType == DatabaseCodes.evidenceScopePlant;
  return EvidenceCaptureBundle(
    session: EvidenceCaptureSessionRecord(
      id: plant ? 'plant-session' : 'station-session',
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentId: 'assessment-1',
      stationId: 'station-1',
      scopeType: scopeType,
      scopeKey: plant ? 'plant_01' : DatabaseCodes.evidenceScopeStationContext,
      plantPosition: plant ? 1 : null,
      requirementsVersion: 'camera_phase_a_v1',
      collectionMode: DatabaseCodes.evidenceCollectionCamera,
      collectionStatus: DatabaseCodes.evidenceSessionInProgress,
      waivedViewTypesJson: waived
          ? jsonEncode([DatabaseCodes.evidenceViewStationContext])
          : null,
      startedAt: now,
    ),
    media: const [],
  );
}

EvidenceCaptureBundle _readyStationBundle() {
  final bundle = _bundle();
  final now = DateTime.utc(2026, 8, 13);
  return EvidenceCaptureBundle(
    session: bundle.session,
    media: [
      EvidenceMediaRecord(
        id: 'context-media',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        assessmentId: 'assessment-1',
        stationId: 'station-1',
        captureSessionId: bundle.session.id,
        mediaType: 'image',
        viewType: DatabaseCodes.evidenceViewStationContext,
        localUri: 'context.jpg',
        thumbnailLocalUri: 'context_thumb.jpg',
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
    ],
  );
}

EvidenceCaptureBundle _readyPlantBundle(String path) {
  final bundle = _bundle(scopeType: DatabaseCodes.evidenceScopePlant);
  final now = DateTime.utc(2026, 8, 13);
  return EvidenceCaptureBundle(
    session: bundle.session,
    media: [
      EvidenceMediaRecord(
        id: 'plant-overview-media',
        createdAt: now,
        updatedAt: now,
        syncState: DatabaseCodes.localOnly,
        serverVersion: 0,
        assessmentId: 'assessment-1',
        stationId: 'station-1',
        captureSessionId: bundle.session.id,
        mediaType: 'image',
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        localUri: path,
        thumbnailLocalUri: path,
        mimeType: 'image/png',
        byteSize: 68,
        sha256Checksum: 'checksum',
        capturedAt: now,
        qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
        captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
        widthPx: 1,
        heightPx: 1,
        storageState: DatabaseCodes.evidenceStorageReady,
        uploadState: DatabaseCodes.localOnly,
        isCanonicalEvidence: true,
      ),
    ],
  );
}

Future<File> _writeOnePixelPng(Directory root, String name) async {
  const bytes =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  return File(
    '${root.path}${Platform.pathSeparator}$name',
  ).writeAsBytes(base64Decode(bytes));
}

Station1Snapshot _reviewSnapshot() {
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
    plants: const [],
    reviewedAt: null,
    reviewIsCurrent: false,
  );
}
