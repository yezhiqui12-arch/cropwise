import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/station1/evidence_photo_viewer.dart';

void main() {
  testWidgets(
    'staged original supports pinch zoom, clear labels, and capture actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory root;
      late File original;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('evidence_viewer_');
        original = File('${root.path}${Platform.pathSeparator}plant_1.png');
        await original.writeAsBytes(base64Decode(_onePixelPng));
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
                          localUri: original.path,
                          storageState: DatabaseCodes.evidenceStorageStaged,
                        ),
                        scopeLabel: 'Plant 1',
                        resolveFile: (path) async => File(path),
                        allowActions: true,
                        allowAddCloseUp: true,
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
      expect(find.byKey(const Key('evidence_original_image')), findsOneWidget);
      expect(find.byKey(const Key('viewer_use_photo')), findsOneWidget);
      expect(find.byKey(const Key('viewer_retake')), findsOneWidget);
      expect(find.byKey(const Key('viewer_add_close_up')), findsOneWidget);
      expect(find.byKey(const Key('viewer_remove')), findsOneWidget);

      final viewer = find.byKey(const Key('evidence_interactive_viewer'));
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
    widthPx: 1,
    heightPx: 1,
    storageState: storageState,
    uploadState: DatabaseCodes.localOnly,
    isOriginal: true,
  );
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
