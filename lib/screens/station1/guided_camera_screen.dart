import '../../services/phone_location_service.dart';
import 'dart:async';
import 'dart:io';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../services/evidence_camera_service.dart';

class GuidedCameraResult {
  const GuidedCameraResult.captured(this.sourcePath, {this.location})
    : fallbackReasonCode = null;
  const GuidedCameraResult.manualFallback([this.fallbackReasonCode])
    : sourcePath = null,
      location = null;

  final AveragedPhoneLocation? location;
  final String? sourcePath;
  final String? fallbackReasonCode;
}

class GuidedCameraView {
  const GuidedCameraView({
    required this.title,
    required this.viewLabel,
    required this.instruction,
  });

  final String title;
  final String viewLabel;
  final String instruction;
}

class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({
    super.key,
    required this.title,
    required this.instruction,
    required this.viewLabel,
    this.cameraFactory = const PluginEvidenceCameraFactory(),
    this.captureLocation,
    this.sessionViews = const [],
    this.onSessionCapture,
    this.initialPhotoCount = 0,
    this.minimumSessionCaptures = 1,
  });

  final Future<AveragedPhoneLocation> Function()? captureLocation;
  final String title;
  final String instruction;
  final String viewLabel;
  final EvidenceCameraFactory cameraFactory;

  /// When supplied, accepted photos stay in this camera route until the
  /// evaluator finishes or the three-view limit is reached.
  final List<GuidedCameraView> sessionViews;
  final Future<bool> Function(GuidedCameraResult result, int viewIndex)?
  onSessionCapture;
  final int initialPhotoCount;
  final int minimumSessionCaptures;

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen>
    with WidgetsBindingObserver {
  EvidenceCameraSession? _session;
  EvidenceCameraException? _error;
  bool _initializing = true;
  bool _takingPicture = false;
  StreamSubscription<PhoneLocationReading>? _locationSubscription;
  PhoneLocationReading? _recentLocation;
  String? _pendingPhotoPath;
  int _initializationGeneration = 0;
  int _sessionCaptureCount = 0;
  Future<void>? _cameraRelease;
  bool _warmingLocation = false;

  bool get _isPhotoSession => widget.onSessionCapture != null;
  bool get _sessionComplete =>
      _isPhotoSession && _sessionCaptureCount >= widget.sessionViews.length;
  GuidedCameraView get _currentView => _isPhotoSession && !_sessionComplete
      ? widget.sessionViews[_sessionCaptureCount]
      : GuidedCameraView(
          title: widget.title,
          viewLabel: widget.viewLabel,
          instruction: widget.instruction,
        );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _warmLocation() async {
    if (_warmingLocation || _locationSubscription != null) return;
    _warmingLocation = true;
    try {
      final stream = await const PhoneLocationService().watchPosition();
      if (!mounted) return;
      _locationSubscription = stream.listen((reading) {
        if (!reading.isCached && mounted) _recentLocation = reading;
      }, onError: (Object _) {});
    } catch (_) {
      // Photo capture remains available without location permission or GPS.
    } finally {
      _warmingLocation = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Android permission dialog temporarily makes the app inactive.
    // Let initialization finish instead of cancelling the preview underneath it.
    if (state == AppLifecycleState.inactive && _initializing) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseCamera());
    } else if (state == AppLifecycleState.resumed &&
        _session == null &&
        !_initializing) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }
    EvidenceCameraSession? session;
    try {
      await _cameraRelease;
      if (!mounted || generation != _initializationGeneration) return;
      session = await widget.cameraFactory.createRearCamera();
      await session.initialize();
      if (!mounted || generation != _initializationGeneration) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _initializing = false;
      });
      // Ask for GPS only after the live preview is ready, so permission prompts
      // cannot race camera startup.
      if (_locationSubscription == null) unawaited(_warmLocation());
    } on EvidenceCameraException catch (error) {
      await session?.dispose();
      if (!mounted || generation != _initializationGeneration) return;
      setState(() {
        _session = null;
        _error = error;
        _initializing = false;
      });
    } catch (_) {
      await session?.dispose();
      if (!mounted || generation != _initializationGeneration) return;
      setState(() {
        _session = null;
        _error = const EvidenceCameraException(
          reasonCode: DatabaseCodes.evidenceFallbackCaptureFailure,
          message:
              'The camera could not start. Retry or use documented manual fallback.',
        );
        _initializing = false;
      });
    }
  }

  Future<void> _releaseCamera() async {
    _initializationGeneration++;
    final session = _session;
    _session = null;
    _initializing = false;
    if (mounted) setState(() {});
    final release = session?.dispose();
    if (release != null) _cameraRelease = release;
    await release;
  }

  Future<AveragedPhoneLocation?> _capturePhotoLocation() async {
    final cameraReading = _recentLocation;
    final recent =
        cameraReading != null &&
            DateTime.now().toUtc().difference(
                  cameraReading.capturedAt.toUtc(),
                ) <=
                const Duration(seconds: 15)
        ? cameraReading
        : const PhoneLocationService().recentLiveReading();
    if (recent != null &&
        DateTime.now().toUtc().difference(recent.capturedAt.toUtc()) <=
            const Duration(seconds: 15)) {
      return AveragedPhoneLocation(
        latitude: recent.latitude,
        longitude: recent.longitude,
        averageAccuracyMeters: recent.accuracyMeters,
        worstAccuracyMeters: recent.accuracyMeters,
        sampleCount: 1,
        capturedAt: recent.capturedAt,
      );
    }
    final capture =
        widget.captureLocation ??
        () => const PhoneLocationService().captureAverage(
          targetSamples: 1,
          maximumWait: Duration(seconds: 8),
          maximumAcceptedAccuracyMeters: null,
          fallbackToCurrentPosition: false,
        );
    final started = DateTime.now().toUtc();
    try {
      final value = await capture().timeout(const Duration(seconds: 9));
      if (!value.latitude.isFinite ||
          !value.longitude.isFinite ||
          value.latitude.abs() > 90 ||
          value.longitude.abs() > 180 ||
          !value.averageAccuracyMeters.isFinite ||
          value.averageAccuracyMeters < 0 ||
          value.capturedAt.toUtc().isBefore(
            started.subtract(const Duration(seconds: 5)),
          )) {
        return null;
      }
      return value;
    } catch (_) {
      // A photo can still be retained explicitly without a usable GPS fix.
      return null;
    }
  }

  Future<void> _takePicture() async {
    final session = _session;
    if (_takingPicture ||
        (_pendingPhotoPath == null &&
            (session == null || !session.isInitialized))) {
      return;
    }
    setState(() => _takingPicture = true);
    try {
      var path = _pendingPhotoPath;
      // Start locating at the shutter press, but do not hold the shutter
      // behind GPS. A failed fix can be retried with the same captured image.
      final locationFuture = _capturePhotoLocation();
      if (path == null) {
        final activeSession = _session;
        if (activeSession == null || !activeSession.isInitialized) return;
        path = await activeSession.takePicture();
        if (!mounted) {
          unawaited(_deleteTemporaryPhoto(path));
          return;
        }
        setState(() => _pendingPhotoPath = path);
      }
      final location = await locationFuture;
      if (!mounted) return;
      // No GPS fix: keep the photo and mark its location unavailable.
      await _completePhoto(
        GuidedCameraResult.captured(path, location: location),
      );
    } on EvidenceCameraException catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<void> _completePhoto(GuidedCameraResult result) async {
    if (!_isPhotoSession) {
      _pendingPhotoPath = null;
      Navigator.pop(context, result);
      return;
    }
    final saved = await widget.onSessionCapture!(result, _sessionCaptureCount);
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Photo was not saved. Retry saving this photo.'),
        ),
      );
      return;
    }
    setState(() {
      _pendingPhotoPath = null;
      _sessionCaptureCount++;
    });
    if (_sessionComplete) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_locationSubscription?.cancel());
    _initializationGeneration++;
    final session = _session;
    _session = null;
    final pendingPath = _pendingPhotoPath;
    if (pendingPath != null) {
      unawaited(_deleteTemporaryPhoto(pendingPath));
    }
    unawaited(session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canShoot =
        (_pendingPhotoPath != null || _session?.isInitialized == true) &&
        !_takingPicture;
    final canFinish =
        _isPhotoSession &&
        _sessionCaptureCount >= widget.minimumSessionCaptures &&
        _pendingPhotoPath == null &&
        !_takingPicture;
    return Scaffold(
      appBar: AppBar(title: AppText(_currentView.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('guided_camera_scroll_view'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isPhotoSession)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: _SessionSteps(
                    key: const Key('camera_session_progress'),
                    views: widget.sessionViews,
                    initialCount: widget.initialPhotoCount,
                    current: _sessionCaptureCount,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      _currentView.viewLabel.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF176B3A),
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppText(
                      _currentView.instruction,
                      style: const TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
              AspectRatio(aspectRatio: 3 / 4, child: _cameraBody()),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const Key('camera_shutter_button'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 64),
                        backgroundColor: const Color(0xFF176B3A),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: canShoot ? _takePicture : null,
                      icon: Icon(
                        _pendingPhotoPath == null
                            ? Icons.camera_alt_outlined
                            : Icons.refresh,
                      ),
                      label: AppText(
                        _takingPicture
                            ? 'Saving photo…'
                            : _pendingPhotoPath != null
                            ? 'Retry saving photo'
                            : 'Take photo',
                      ),
                    ),
                    if (canFinish)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          key: const Key('finish_plant_photos'),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check, size: 18),
                          label: const AppText('Done'),
                        ),
                      ),
                    TextButton(
                      key: const Key('camera_manual_fallback_button'),
                      onPressed: _takingPicture
                          ? null
                          : () => Navigator.pop(
                              context,
                              GuidedCameraResult.manualFallback(
                                _error?.reasonCode,
                              ),
                            ),
                      child: const AppText('Camera unavailable?'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraBody() {
    final pendingPath = _pendingPhotoPath;
    if (pendingPath != null) {
      return ColoredBox(
        color: const Color(0xFF111111),
        child: Image.file(File(pendingPath), fit: BoxFit.contain),
      );
    }
    if (_initializing) {
      return const ColoredBox(
        color: Color(0xFFF3F6F2),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null && _session == null) {
      return ColoredBox(
        color: const Color(0xFFF3F6F2),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  size: 48,
                  color: Colors.black54,
                ),
                const SizedBox(height: 12),
                AppText(
                  error.message,
                  key: const Key('camera_error_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const Key('retry_camera_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF176B3A),
                  ),
                  onPressed: _initialize,
                  child: const AppText('Retry camera'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final session = _session;
    if (session == null) {
      return ColoredBox(
        color: const Color(0xFFF3F6F2),
        child: Center(
          child: TextButton(
            key: const Key('retry_camera_button'),
            onPressed: _initialize,
            child: const AppText('Start camera'),
          ),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: session.buildPreview()),
          const IgnorePointer(child: _FrameCorners()),
        ],
      ),
    );
  }

  Future<void> _deleteTemporaryPhoto(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // The camera plugin may already have cleaned up its temporary file.
    }
  }
}

/// "1 Overview — 2 Close-up — 3 Detail" progress for a 3-photo plant session.
class _SessionSteps extends StatelessWidget {
  const _SessionSteps({
    super.key,
    required this.views,
    required this.initialCount,
    required this.current,
  });

  final List<GuidedCameraView> views;
  final int initialCount;
  final int current;

  String _short(String label) => label == 'Whole seedling' ? 'Seedling' : label;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B3A);
    return Row(
      children: [
        for (var i = 0; i < views.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= current ? green : const Color(0xFFD8E3D7),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: i < current
                    ? green
                    : i == current
                    ? const Color(0xFFE3F2E1)
                    : const Color(0xFFECEFEB),
                child: i < current
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : Text(
                        '${initialCount + i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: i == current ? green : Colors.black54,
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              AppText(
                _short(views[i].viewLabel),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: i == current ? green : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FrameCorners extends StatelessWidget {
  const _FrameCorners();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: CustomPaint(painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, len)
      ..lineTo(0, 0)
      ..lineTo(len, 0)
      ..moveTo(w - len, 0)
      ..lineTo(w, 0)
      ..lineTo(w, len)
      ..moveTo(w, h - len)
      ..lineTo(w, h)
      ..lineTo(w - len, h)
      ..moveTo(len, h)
      ..lineTo(0, h)
      ..lineTo(0, h - len);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
