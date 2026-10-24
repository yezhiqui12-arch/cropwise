import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/station1/evidence_photo_viewer.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/screens/station1/model_detection_image.dart';

void main() {
  testWidgets(
    'staged canonical evidence supports constrained zoom and capture actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory root;
      late File canonicalEvidence;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('evidence_viewer_');
        canonicalEvidence = File(
          '${root.path}${Platform.pathSeparator}plant_1.png',
        );
        await canonicalEvidence.writeAsBytes(base64Decode(_onePixelPng));
      });
      addTearDown(() => root.delete(recursive: true));
      final controller = TransformationController();
      addTearDown(controller.dispose);
      EvidencePhotoAction? result;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Builder(
              builder: (context) => FilledButton(
                key: const Key('open_viewer'),
                onPressed: () async {
                  result = await Navigator.push<EvidencePhotoAction>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EvidencePhotoViewer(
                        media: _media(
                          localUri: canonicalEvidence.path,
                          storageState: DatabaseCodes.evidenceStorageStaged,
                        ),
                        scopeLabel: 'Plant 1',
                        resolveFile: (path) async => File(path),
                        allowActions: true,
                        allowAddCloseUp: true,
                        allowAddDiagnosticDetail: true,
                        transformationController: controller,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open_viewer')));
      await tester.pumpAndSettle();

      expect(find.text('Plant 1'), findsOneWidget);
      expect(find.text('Whorl and newest-leaves overview'), findsOneWidget);
      expect(find.byKey(const Key('evidence_canonical_image')), findsOneWidget);
      expect(find.byKey(const Key('viewer_use_photo')), findsOneWidget);
      expect(find.byKey(const Key('viewer_retake')), findsOneWidget);
      expect(find.byKey(const Key('viewer_add_close_up')), findsOneWidget);
      expect(
        find.byKey(const Key('viewer_add_diagnostic_detail')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('viewer_remove')), findsOneWidget);

      final viewer = find.byKey(const Key('evidence_interactive_viewer'));
      final interactiveViewer = tester.widget<InteractiveViewer>(viewer);
      expect(interactiveViewer.minScale, 1);
      expect(interactiveViewer.maxScale, 5);
      expect(interactiveViewer.boundaryMargin, EdgeInsets.zero);
      expect(interactiveViewer.clipBehavior, Clip.hardEdge);
      final center = tester.getCenter(viewer);
      final first = await tester.startGesture(center - const Offset(25, 0));
      final second = await tester.startGesture(center + const Offset(25, 0));
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await first.up();
      await second.up();
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

      await tester.tap(find.byKey(const Key('viewer_use_photo')));
      await tester.pumpAndSettle();
      expect(result, EvidencePhotoAction.usePhoto);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scouting photo uses the available screen, preserves evidence and switches overlays',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final file = File('assets/images/empty_map_field_indicator.png');
      final originalBytes = await tester.runAsync(() => file.readAsBytes());
      final transform = TransformationController();
      addTearDown(transform.dispose);
      final model = PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'screen',
        confidenceScore: .9,
        detectionBoxes: [
          ModelDetectionBox(
            sourcePath: file.path,
            classId: 2,
            label: 'Larva',
            confidence: .9,
            left: .1,
            top: .1,
            right: .8,
            bottom: .8,
            imageWidth: 1,
            imageHeight: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EvidencePhotoViewer(
            media: _media(
              localUri: file.path,
              storageState: DatabaseCodes.evidenceStorageReady,
            ),
            scopeLabel: 'Plant 2',
            resolveFile: (p) async => File(p),
            scoutingStyle: true,
            cvDiagnosis: model,
            transformationController: transform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const Key('evidence_interactive_viewer')))
            .height,
        greaterThan(600),
      );
      expect(
        tester
            .widget<ModelDetectionImage>(find.byType(ModelDetectionImage))
            .boxes,
        hasLength(1),
      );
      await tester.tap(find.byKey(const Key('scout_photo_false')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ModelDetectionImage>(find.byType(ModelDetectionImage))
            .boxes,
        isEmpty,
      );
      expect(model.detectionBoxes, hasLength(1));
      transform.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
      await tester.tap(find.byKey(const Key('viewer_reset_view')));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), 1);
      await tester.tap(find.byTooltip('Photo information'));
      await tester.pumpAndSettle();
      expect(find.text('Location not recorded'), findsOneWidget);
      expect(find.byKey(const Key('viewer_remove')), findsNothing);
      expect(tester.takeException(), isNull);
      expect(await tester.runAsync(() => file.readAsBytes()), originalBytes);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await FileImage(file).evict();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );
}

EvidenceMediaRecord _media({
  required String localUri,
  required String storageState,
}) {
  final now = DateTime.utc(2026, 8, 13);
  return EvidenceMediaRecord(
    id: 'media-1',
    createdAt: now,
    updatedAt: now,
    syncState: DatabaseCodes.localOnly,
    serverVersion: 0,
    assessmentId: 'assessment-1',
    stationId: 'station-1',
    captureSessionId: 'plant-session-1',
    mediaType: 'image',
    viewType: DatabaseCodes.evidenceViewWhorlOverview,
    localUri: localUri,
    thumbnailLocalUri: localUri,
    mimeType: 'image/png',
    byteSize: 68,
    sha256Checksum: 'checksum',
    capturedAt: now,
    qualityStatus: 'unchecked',
    captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
    locationSource: 'unavailable',
    widthPx: 1,
    heightPx: 1,
    storageState: storageState,
    uploadState: DatabaseCodes.localOnly,
    isCanonicalEvidence: true,
  );
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
