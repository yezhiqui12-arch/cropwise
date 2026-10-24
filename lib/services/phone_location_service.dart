import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class AveragedPhoneLocation {
  const AveragedPhoneLocation({
    required this.latitude,
    required this.longitude,
    required this.averageAccuracyMeters,
    required this.worstAccuracyMeters,
    required this.sampleCount,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double averageAccuracyMeters;
  final double worstAccuracyMeters;
  final int sampleCount;
  final DateTime capturedAt;

  String get confidenceCode {
    if (sampleCount >= 3 && averageAccuracyMeters <= 5) {
      return 'high_phone_gnss';
    }
    if (averageAccuracyMeters <= 10) return 'moderate_phone_gnss';
    return 'low_phone_gnss';
  }
}

class PhoneLocationReading {
  const PhoneLocationReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    this.isCached = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final bool isCached;
}

class PhoneLocationException implements Exception {
  const PhoneLocationException(
    this.message, {
    this.code = PhoneLocationFailureCode.deviceError,
  });

  final String message;
  final PhoneLocationFailureCode code;

  @override
  String toString() => message;
}

enum PhoneLocationFailureCode {
  servicesDisabled,
  permissionDenied,
  permissionBlocked,
  noCurrentFix,
  deviceError,
}

class PhoneLocationService {
  const PhoneLocationService();

  static PhoneLocationReading? _latestLiveReading;

  /// A recent device reading shared by route guidance and photo capture.
  /// Never use a last-known cached fix as a photo location.
  PhoneLocationReading? recentLiveReading({
    Duration maximumAge = const Duration(seconds: 15),
  }) {
    final reading = _latestLiveReading;
    if (reading == null) return null;
    final age = DateTime.now().toUtc().difference(reading.capturedAt.toUtc());
    if (age.isNegative || age > maximumAge) return null;
    return reading;
  }

  Future<Stream<PhoneLocationReading>> watchPosition() async {
    await _ensurePermission();
    final controller = StreamController<PhoneLocationReading>();
    StreamSubscription<Position>? subscription;
    var closed = false;

    controller.onListen = () async {
      try {
        final initial = await Geolocator.getLastKnownPosition();
        if (!closed &&
            initial != null &&
            _isUsable(initial, maximumAcceptedAccuracyMeters: null)) {
          controller.add(_toReading(initial, isCached: true));
        }

        if (closed) return;

        subscription =
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.best,
                distanceFilter: 0,
              ),
            ).listen((position) {
              if (!closed &&
                  _isUsable(position, maximumAcceptedAccuracyMeters: null)) {
                final reading = _toReading(position);
                _latestLiveReading = reading;
                controller.add(reading);
              }
            }, onError: controller.addError);
      } catch (error, stackTrace) {
        if (!closed) controller.addError(error, stackTrace);
      }
    };
    controller.onCancel = () async {
      closed = true;
      await subscription?.cancel();
    };
    return controller.stream;
  }

  PhoneLocationReading _toReading(Position position, {bool isCached = false}) =>
      PhoneLocationReading(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
        isCached: isCached,
      );

  Future<AveragedPhoneLocation> captureAverage({
    int targetSamples = 5,
    Duration maximumWait = const Duration(seconds: 12),
    double? maximumAcceptedAccuracyMeters = 100,
    bool fallbackToCurrentPosition = true,
  }) async {
    if (targetSamples < 1) {
      throw ArgumentError.value(
        targetSamples,
        'targetSamples',
        'Must be positive',
      );
    }

    await _ensurePermission();

    final captureStarted = DateTime.now().toUtc();
    bool isFresh(Position position) => !position.timestamp.toUtc().isBefore(
      captureStarted.subtract(const Duration(seconds: 5)),
    );
    final samples = <Position>[];
    final completion = Completer<void>();
    Object? streamError;
    late final StreamSubscription<Position> subscription;
    final timer = Timer(maximumWait, () {
      if (!completion.isCompleted) completion.complete();
    });

    subscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            if (isFresh(position) &&
                _isUsable(
                  position,
                  maximumAcceptedAccuracyMeters: maximumAcceptedAccuracyMeters,
                )) {
              samples.add(position);
            }
            if (samples.length >= targetSamples && !completion.isCompleted) {
              completion.complete();
            }
          },
          onError: (Object error) {
            streamError = error;
            if (!completion.isCompleted) completion.complete();
          },
        );

    await completion.future;
    timer.cancel();
    await subscription.cancel();

    if (samples.isEmpty && fallbackToCurrentPosition) {
      try {
        final single = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (isFresh(single) &&
            _isUsable(
              single,
              maximumAcceptedAccuracyMeters: maximumAcceptedAccuracyMeters,
            )) {
          samples.add(single);
        }
      } on TimeoutException {
        throw const PhoneLocationException(
          'No GPS reading was received. Move outdoors and try again.',
          code: PhoneLocationFailureCode.noCurrentFix,
        );
      } catch (error) {
        throw PhoneLocationException(
          'Could not read the phone location${streamError == null ? '' : ': $streamError'}.',
        );
      }
    }

    if (samples.isEmpty) {
      throw const PhoneLocationException(
        'The available GPS reading was not usable. Move outdoors and retry.',
        code: PhoneLocationFailureCode.noCurrentFix,
      );
    }

    return _average(samples);
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PhoneLocationException(
        'Location is turned off. Enable phone location and try again.',
        code: PhoneLocationFailureCode.servicesDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const PhoneLocationException(
        'Location permission was denied. Allow location to record this station.',
        code: PhoneLocationFailureCode.permissionDenied,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const PhoneLocationException(
        'Location permission is blocked. Enable it in the phone settings to record GPS.',
        code: PhoneLocationFailureCode.permissionBlocked,
      );
    }
  }

  bool _isUsable(
    Position position, {
    double? maximumAcceptedAccuracyMeters = 100,
  }) {
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        (maximumAcceptedAccuracyMeters == null ||
            position.accuracy <= maximumAcceptedAccuracyMeters);
  }

  AveragedPhoneLocation _average(List<Position> samples) {
    var weightedLatitude = 0.0;
    var weightedLongitude = 0.0;
    var totalWeight = 0.0;
    var accuracyTotal = 0.0;
    var worstAccuracy = 0.0;

    for (final sample in samples) {
      final effectiveAccuracy = math.max(sample.accuracy, 1.0);
      final weight = 1 / (effectiveAccuracy * effectiveAccuracy);
      weightedLatitude += sample.latitude * weight;
      weightedLongitude += sample.longitude * weight;
      totalWeight += weight;
      accuracyTotal += sample.accuracy;
      worstAccuracy = math.max(worstAccuracy, sample.accuracy);
    }

    return AveragedPhoneLocation(
      latitude: weightedLatitude / totalWeight,
      longitude: weightedLongitude / totalWeight,
      averageAccuracyMeters: accuracyTotal / samples.length,
      worstAccuracyMeters: worstAccuracy,
      sampleCount: samples.length,
      capturedAt: samples
          .map((sample) => sample.timestamp.toUtc())
          .reduce((latest, value) => value.isAfter(latest) ? value : latest),
    );
  }
}
