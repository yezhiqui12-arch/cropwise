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

void main() {
  testWidgets(
    'Station guidance explains two views and honest no-model review',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlantSelectionStep(onBegin: () {})),
        ),
      );

      expect(find.textContaining('ten consecutive plants'), findsOneWidget);
      expect(
        find.textContaining('one overview and one closer'),
        findsOneWidget,
      );
      expect(find.textContaining('no validated image model'), findsOneWidget);
      expect(
        find.textContaining('confirm every plant manually'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'continuous capture advances from two required views without a manual form',
    (tester) async {
      var bundle = _bundle();
      var completed = false;
      late StateSetter hostSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return ContinuousPlantCaptureStep(
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
      expect(find.text('Required view 1 · Overview'), findsOneWidget);
      expect(find.text('Required view 2 · Whorl detail'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      hostSetState(() {
        bundle = _bundle(
          waivedViews: {DatabaseCodes.evidenceViewWhorlOverview},
        );
      });
      await tester.pump();
      expect(find.text('Required view 2 · Whorl detail'), findsOneWidget);
      await tester.tap(
        find.byKey(Key('capture_${DatabaseCodes.evidenceViewCloseUp}')),
      );
      await tester.pump();
      expect(completed, isTrue);
      completed = false;

      hostSetState(() {
        bundle = _bundle(
          waivedViews: {
            DatabaseCodes.evidenceViewWhorlOverview,
            DatabaseCodes.evidenceViewCloseUp,
          },
        );
      });
      await tester.pump();
      expect(
        find.byKey(const Key('conditional_detail_choice')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const Key('next_plant_after_capture')));
      await tester.pump();
      expect(completed, isTrue);
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
                position: 4,
                capturedPlantCount: 3,
                initialLeavesInspectedCount: 4,
                bundle: _bundle(
                  waivedViews: {
                    DatabaseCodes.evidenceViewWhorlOverview,
                    DatabaseCodes.evidenceViewCloseUp,
                  },
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
    },
  );
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
