import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/station1/guided_camera_screen.dart';
import 'package:wormwise/services/evidence_camera_service.dart';
import 'package:wormwise/services/phone_location_service.dart';

void main() {
  testWidgets('plant photo session stays in camera for optional views', (
    tester,
  ) async {
    final savedViewIndices = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => GuidedCameraScreen(
                  title: 'Plant photo',
                  viewLabel: 'Overview',
                  instruction: 'Frame the plant.',
                  cameraFactory: _LifecycleCameraFactory(),
                  captureLocation: () async => AveragedPhoneLocation(
                    latitude: 17,
                    longitude: 121,
                    averageAccuracyMeters: 6,
                    worstAccuracyMeters: 8,
                    sampleCount: 1,
                    capturedAt: DateTime.now(),
                  ),
                  sessionViews: const [
                    GuidedCameraView(
                      title: 'Plant photo',
                      viewLabel: 'Overview',
                      instruction: 'Frame the plant.',
                    ),
                    GuidedCameraView(
                      title: 'Close-up',
                      viewLabel: 'Close-up',
                      instruction: 'Move closer.',
                    ),
                    GuidedCameraView(
                      title: 'Detail',
                      viewLabel: 'Detail',
                      instruction: 'Frame the sign.',
                    ),
                  ],
                  onSessionCapture: (_, index) async {
                    savedViewIndices.add(index);
                    return true;
                  },
                ),
              ),
            ),
            child: const Text('Open camera'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Plant photo'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('camera_shutter_button')));
    await tester.tap(find.byKey(const Key('camera_shutter_button')));
    await tester.pumpAndSettle();
    expect(savedViewIndices, [0]);
    expect(find.widgetWithText(AppBar, 'Close-up'), findsOneWidget);
    expect(find.byKey(const Key('finish_plant_photos')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('camera_shutter_button')));
    await tester.tap(find.byKey(const Key('camera_shutter_button')));
    await tester.pumpAndSettle();
    expect(savedViewIndices, [0, 1]);
    expect(find.widgetWithText(AppBar, 'Detail'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('camera_shutter_button')));
    await tester.tap(find.byKey(const Key('camera_shutter_button')));
    await tester.pumpAndSettle();
    expect(savedViewIndices, [0, 1, 2]);
    expect(find.text('Open camera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['fresh', 'failed', 'stale']) {
    testWidgets('photo returns safely with $mode GPS', (tester) async {
      GuidedCameraResult? result;
      var gpsCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<GuidedCameraResult>(
                  MaterialPageRoute(
                    builder: (_) => GuidedCameraScreen(
                      title: 'Plant',
                      viewLabel: 'Plant',
                      instruction: 'Capture plant',
                      cameraFactory: _LifecycleCameraFactory(),
                      captureLocation: () async {
                        gpsCalls++;
                        if (mode == 'failed') {
                          throw Exception('GPS unavailable');
                        }
                        return AveragedPhoneLocation(
                          latitude: 17,
                          longitude: 121,
                          averageAccuracyMeters: 6,
                          worstAccuracyMeters: 8,
                          sampleCount: 3,
                          capturedAt: DateTime.now().subtract(
                            Duration(minutes: mode == 'stale' ? 10 : 0),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open camera'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      expect(gpsCalls, 0);
      await tester.ensureVisible(
        find.byKey(const Key('camera_shutter_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera_shutter_button')));
      await tester.pumpAndSettle();
      expect(gpsCalls, 1);
      expect(result?.sourcePath, 'fake-camera-file.jpg');
      expect(result?.location?.latitude, mode == 'fresh' ? 17 : null);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'permission failure offers retry and documented manual fallback',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GuidedCameraScreen(
            title: 'Whorl overview',
            viewLabel: 'Whorl and newest leaves',
            instruction: 'Expose the newest leaves.',
            cameraFactory: _DeniedCameraFactory(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('camera_error_message')), findsOneWidget);
      expect(find.textContaining('permission was denied'), findsOneWidget);
      expect(find.byKey(const Key('retry_camera_button')), findsOneWidget);
      expect(
        find.byKey(const Key('camera_manual_fallback_button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera resources release and reinitialize across lifecycle changes',
    (WidgetTester tester) async {
      final factory = _LifecycleCameraFactory();
      await tester.pumpWidget(
        MaterialApp(
          home: GuidedCameraScreen(
            title: 'Station context',
            viewLabel: 'Station context',
            instruction: 'Frame the maize row.',
            cameraFactory: factory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(factory.sessions.length, 1);
      expect(factory.sessions.first.initializeCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(factory.sessions.first.disposeCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(factory.sessions.length, 2);
      expect(factory.sessions.last.initializeCount, 1);
      expect(find.byKey(const Key('camera_shutter_button')), findsOneWidget);
    },
  );

  testWidgets('permission dialog does not cancel initial camera preview', (
    tester,
  ) async {
    final factory = _PermissionDialogCameraFactory();
    await tester.pumpWidget(
      MaterialApp(
        home: GuidedCameraScreen(
          title: 'Plant photo',
          viewLabel: 'Overview',
          instruction: 'Frame the plant.',
          cameraFactory: factory,
        ),
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    factory.session.ready.complete();
    await tester.pumpAndSettle();
    expect(factory.session.disposeCount, 0);
    expect(find.byKey(const Key('live_camera_preview')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, isNot(Colors.black));
    expect(tester.takeException(), isNull);
  });

  testWidgets('guided camera remains usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final factory = _LifecycleCameraFactory();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: GuidedCameraScreen(
            title: 'Whorl overview',
            viewLabel: 'Whorl and newest leaves',
            instruction:
                'Gently expose and frame the newest three or four leaves and whorl.',
            cameraFactory: factory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shutter = find.byKey(const Key('camera_shutter_button'));
    await tester.scrollUntilVisible(
      shutter,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(shutter, findsOneWidget);
    expect(
      find.byKey(const Key('camera_manual_fallback_button')),
      findsOneWidget,
    );
    expect(tester.getSize(shutter).height, greaterThanOrEqualTo(64));
    expect(tester.takeException(), isNull);
  });
}

class _DeniedCameraFactory implements EvidenceCameraFactory {
  const _DeniedCameraFactory();

  @override
  Future<EvidenceCameraSession> createRearCamera() {
    throw const EvidenceCameraException(
      reasonCode: DatabaseCodes.evidenceFallbackPermissionDenied,
      message:
          'Camera permission was denied. You can retry or use documented manual fallback.',
    );
  }
}

class _LifecycleCameraFactory implements EvidenceCameraFactory {
  final sessions = <_FakeCameraSession>[];

  @override
  Future<EvidenceCameraSession> createRearCamera() async {
    final session = _FakeCameraSession();
    sessions.add(session);
    return session;
  }
}

class _FakeCameraSession implements EvidenceCameraSession {
  int initializeCount = 0;
  int disposeCount = 0;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose() async {
    disposeCount++;
    _initialized = false;
  }

  @override
  Future<void> initialize() async {
    initializeCount++;
    _initialized = true;
  }

  @override
  Future<String> takePicture() async => 'fake-camera-file.jpg';
}

class _PermissionDialogCameraFactory implements EvidenceCameraFactory {
  final session = _PermissionDialogCameraSession();
  @override
  Future<EvidenceCameraSession> createRearCamera() async => session;
}

class _PermissionDialogCameraSession extends _FakeCameraSession {
  final ready = Completer<void>();
  @override
  Future<void> initialize() async {
    await ready.future;
    await super.initialize();
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('live_camera_preview'), color: Colors.green);
}
