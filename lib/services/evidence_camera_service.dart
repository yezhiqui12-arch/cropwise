import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../data/local/database_codes.dart';

class EvidenceCameraException implements Exception {
  const EvidenceCameraException({
    required this.reasonCode,
    required this.message,
  });

  final String reasonCode;
  final String message;

  @override
  String toString() => message;
}

abstract interface class EvidenceCameraSession {
  bool get isInitialized;
  Widget buildPreview();
  Future<void> initialize();
  Future<String> takePicture();
  Future<void> dispose();
}

abstract interface class EvidenceCameraFactory {
  Future<EvidenceCameraSession> createRearCamera();
}

class PluginEvidenceCameraFactory implements EvidenceCameraFactory {
  const PluginEvidenceCameraFactory();

  @override
  Future<EvidenceCameraSession> createRearCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const EvidenceCameraException(
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          message: 'No camera is available on this phone.',
        );
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      return PluginEvidenceCameraSession(description);
    } on CameraException catch (error) {
      throw _mappedCameraException(error);
    }
  }
}

class PluginEvidenceCameraSession implements EvidenceCameraSession {
  PluginEvidenceCameraSession(CameraDescription description)
    : _controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

  final CameraController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize();
    } on CameraException catch (error) {
      throw _mappedCameraException(error);
    }
  }

  @override
  Future<String> takePicture() async {
    try {
      final image = await _controller.takePicture();
      return image.path;
    } on CameraException catch (error) {
      throw _mappedCameraException(error, capture: true);
    }
  }

  @override
  Future<void> dispose() => _controller.dispose();
}

EvidenceCameraException _mappedCameraException(
  CameraException error, {
  bool capture = false,
}) {
  final code = error.code;
  if (code == 'CameraAccessDenied') {
    return const EvidenceCameraException(
      reasonCode: DatabaseCodes.evidenceFallbackPermissionDenied,
      message:
          'Camera permission was denied. You can retry or use documented manual fallback.',
    );
  }
  if (code == 'CameraAccessDeniedWithoutPrompt' ||
      code == 'CameraAccessRestricted') {
    return const EvidenceCameraException(
      reasonCode: DatabaseCodes.evidenceFallbackPermissionBlocked,
      message:
          'Camera access is blocked in phone settings. You can use documented manual fallback.',
    );
  }
  return EvidenceCameraException(
    reasonCode: DatabaseCodes.evidenceFallbackCaptureFailure,
    message: capture
        ? 'The phone could not save this photo. Retry or use documented manual fallback.'
        : 'The camera could not start. Retry or use documented manual fallback.',
  );
}
