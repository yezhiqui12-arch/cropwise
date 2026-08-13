import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../services/evidence_camera_service.dart';

class GuidedCameraResult {
  const GuidedCameraResult.captured(this.sourcePath)
    : fallbackReasonCode = null;
  const GuidedCameraResult.manualFallback([this.fallbackReasonCode])
    : sourcePath = null;

  final String? sourcePath;
  final String? fallbackReasonCode;
}

class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({
    super.key,
    required this.title,
    required this.instruction,
    required this.viewLabel,
    this.cameraFactory = const PluginEvidenceCameraFactory(),
  });

  final String title;
  final String instruction;
  final String viewLabel;
  final EvidenceCameraFactory cameraFactory;

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen>
    with WidgetsBindingObserver {
  EvidenceCameraSession? _session;
  EvidenceCameraException? _error;
  bool _initializing = true;
  bool _takingPicture = false;
  int _initializationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseCamera());
    } else if (state == AppLifecycleState.resumed && _session == null) {
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
    if (mounted) setState(() {});
    await session?.dispose();
  }

  Future<void> _takePicture() async {
    final session = _session;
    if (session == null || !session.isInitialized || _takingPicture) return;
    setState(() => _takingPicture = true);
    try {
      final path = await session.takePicture();
      if (!mounted) return;
      Navigator.pop(context, GuidedCameraResult.captured(path));
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationGeneration++;
    final session = _session;
    _session = null;
    unawaited(session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('guided_camera_scroll_view'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.viewLabel.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF176B3A),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.instruction,
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You—not the camera—confirm that the target is visible and framed usefully.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              AspectRatio(aspectRatio: 3 / 4, child: _cameraBody()),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: FilledButton.icon(
                        key: const Key('camera_shutter_button'),
                        onPressed:
                            _session?.isInitialized == true && !_takingPicture
                            ? _takePicture
                            : null,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _takingPicture ? 'Saving photo…' : 'Take photo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('camera_manual_fallback_button'),
                      onPressed: () => Navigator.pop(
                        context,
                        GuidedCameraResult.manualFallback(_error?.reasonCode),
                      ),
                      child: const Text(
                        'Camera unavailable? Use manual fallback',
                      ),
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
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && _session == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.no_photography_outlined, size: 54),
              const SizedBox(height: 12),
              Text(
                error.message,
                key: const Key('camera_error_message'),
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('retry_camera_button'),
                onPressed: _initialize,
                child: const Text('Retry camera'),
              ),
            ],
          ),
        ),
      );
    }
    final session = _session;
    if (session == null) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: session.buildPreview()),
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
