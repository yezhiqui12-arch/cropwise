import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/station1_workflow_repository.dart';
import 'package:wormwise/screens/station1/continuous_plant_capture_step.dart';
import 'package:wormwise/screens/station1/station_review_step.dart';

void main() {
  setUpAll(() async {
    final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final bytes = await File('$windowsRoot\\Fonts\\segoeui.ttf').readAsBytes();
    await (FontLoader(
      'ScreenshotSans',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('render continuous plant capture', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF176B3A),
          fontFamily: 'ScreenshotSans',
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Station 1 capture')),
          body: ContinuousPlantCaptureStep(
            position: 4,
            capturedPlantCount: 3,
            initialLeavesInspectedCount: 4,
            bundle: _bundle(position: 4),
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
    );
    await tester.tap(find.byKey(const Key('capture_assessable_yes')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../artifacts/continuous_capture.png'),
    );
  });

  testWidgets('render Station Evidence Review', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF176B3A),
          fontFamily: 'ScreenshotSans',
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Station 1')),
          body: StationReviewStep(
            snapshot: _snapshot(),
            isSaving: false,
            onEdit: (_) {},
            onConfirm: () {},
            evidenceBundles: [
              _bundle(
                scopeType: DatabaseCodes.evidenceScopeStationContext,
                waivedViews: {DatabaseCodes.evidenceViewStationContext},
              ),
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
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../artifacts/station_evidence_review.png'),
    );
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

EvidenceCaptureBundle _bundle({
  String scopeType = DatabaseCodes.evidenceScopePlant,
  int position = 1,
  Set<String> waivedViews = const {},
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
    media: const [],
  );
}

Station1Snapshot _snapshot() {
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
