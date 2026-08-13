import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/station1/guided_camera_screen.dart';
import 'package:wormwise/services/evidence_camera_service.dart';

void main() {
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
