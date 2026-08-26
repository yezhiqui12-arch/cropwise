import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_lib;

const evidenceTechnicalQualityAlgorithmVersion =
    'laplacian_luminance_canonical_v1';

enum EvidenceQualityView {
  stationContext,
  plantOverview,
  whorlNewestLeaves,
  conditionalCloseUp,
}

enum EvidenceIntegrityStatus {
  valid,
  emptySource,
  sourceDecodeFailed,
  canonicalDecodeFailed,
}

enum EvidenceQualityWarning {
  lowSourceResolution,
  unexpectedUpscaling,
  possibleBlur,
  tooDark,
  possibleOverexposureOrGlare,
}

class EvidenceQualityConfiguration {
  const EvidenceQualityConfiguration({
    required this.view,
    required this.version,
    required this.minimumSourceLongEdgePx,
    required this.minimumSourceShortEdgePx,
    required this.analysisLongEdgePx,
    required this.blurVarianceWarningBelow,
    required this.darkLuminanceCutoff,
    required this.meanLuminanceWarningBelow,
    required this.darkPixelFractionWarningAbove,
    required this.highlightLuminanceCutoff,
    required this.highlightPixelFractionWarningAbove,
    required this.concentratedHighlightFractionWarningAbove,
  });

  final EvidenceQualityView view;
  final String version;
  final int minimumSourceLongEdgePx;
  final int minimumSourceShortEdgePx;
  final int analysisLongEdgePx;
  final double blurVarianceWarningBelow;
  final int darkLuminanceCutoff;
  final double meanLuminanceWarningBelow;
  final double darkPixelFractionWarningAbove;
  final int highlightLuminanceCutoff;
  final double highlightPixelFractionWarningAbove;
  final double concentratedHighlightFractionWarningAbove;
}

/// Provisional technical configurations for QA-A only.
///
/// These values have not been calibrated with real maize photographs or the
/// supported phone matrix. A result is never evidence of pest presence,
/// absence, identity, or assessment correctness.
class ProvisionalEvidenceQualityConfigurations {
  const ProvisionalEvidenceQualityConfigurations._();

  static EvidenceQualityConfiguration forView(
    EvidenceQualityView view,
  ) => switch (view) {
    EvidenceQualityView.stationContext => const EvidenceQualityConfiguration(
      view: EvidenceQualityView.stationContext,
      version: 'qa_a_station_context_provisional_v1',
      minimumSourceLongEdgePx: 1280,
      minimumSourceShortEdgePx: 720,
      analysisLongEdgePx: 512,
      blurVarianceWarningBelow: 45,
      darkLuminanceCutoff: 36,
      meanLuminanceWarningBelow: 42,
      darkPixelFractionWarningAbove: 0.68,
      highlightLuminanceCutoff: 245,
      highlightPixelFractionWarningAbove: 0.25,
      concentratedHighlightFractionWarningAbove: 0.70,
    ),
    EvidenceQualityView.plantOverview => const EvidenceQualityConfiguration(
      view: EvidenceQualityView.plantOverview,
      version: 'qa_a_plant_overview_provisional_v1',
      minimumSourceLongEdgePx: 1600,
      minimumSourceShortEdgePx: 900,
      analysisLongEdgePx: 512,
      blurVarianceWarningBelow: 60,
      darkLuminanceCutoff: 36,
      meanLuminanceWarningBelow: 45,
      darkPixelFractionWarningAbove: 0.62,
      highlightLuminanceCutoff: 245,
      highlightPixelFractionWarningAbove: 0.18,
      concentratedHighlightFractionWarningAbove: 0.60,
    ),
    EvidenceQualityView.whorlNewestLeaves => const EvidenceQualityConfiguration(
      view: EvidenceQualityView.whorlNewestLeaves,
      version: 'qa_a_whorl_newest_leaves_provisional_v1',
      minimumSourceLongEdgePx: 1600,
      minimumSourceShortEdgePx: 1000,
      analysisLongEdgePx: 640,
      blurVarianceWarningBelow: 75,
      darkLuminanceCutoff: 38,
      meanLuminanceWarningBelow: 48,
      darkPixelFractionWarningAbove: 0.58,
      highlightLuminanceCutoff: 245,
      highlightPixelFractionWarningAbove: 0.15,
      concentratedHighlightFractionWarningAbove: 0.55,
    ),
    EvidenceQualityView.conditionalCloseUp =>
      const EvidenceQualityConfiguration(
        view: EvidenceQualityView.conditionalCloseUp,
        version: 'qa_a_conditional_close_up_provisional_v1',
        minimumSourceLongEdgePx: 1600,
        minimumSourceShortEdgePx: 1000,
        analysisLongEdgePx: 768,
        blurVarianceWarningBelow: 90,
        darkLuminanceCutoff: 40,
        meanLuminanceWarningBelow: 50,
        darkPixelFractionWarningAbove: 0.55,
        highlightLuminanceCutoff: 245,
        highlightPixelFractionWarningAbove: 0.13,
        concentratedHighlightFractionWarningAbove: 0.50,
      ),
  };
}

class EvidenceImageFacts {
  const EvidenceImageFacts({
    required this.widthPx,
    required this.heightPx,
    required this.byteSize,
    required this.sha256Checksum,
  });

  final int widthPx;
  final int heightPx;
  final int byteSize;
  final String sha256Checksum;

  int get longEdgePx => math.max(widthPx, heightPx);
  int get shortEdgePx => math.min(widthPx, heightPx);
}

class EvidenceTechnicalMetrics {
  const EvidenceTechnicalMetrics({
    required this.sampleWidthPx,
    required this.sampleHeightPx,
    required this.blurLaplacianVariance,
    required this.meanLuminance,
    required this.medianLuminance,
    required this.darkPixelFraction,
    required this.shadowClippedPixelFraction,
    required this.highlightClippedPixelFraction,
    required this.maximumConcentratedHighlightFraction,
  });

  final int sampleWidthPx;
  final int sampleHeightPx;
  final double blurLaplacianVariance;
  final double meanLuminance;
  final double medianLuminance;
  final double darkPixelFraction;
  final double shadowClippedPixelFraction;
  final double highlightClippedPixelFraction;
  final double maximumConcentratedHighlightFraction;
}

class EvidenceTechnicalQualityResult {
  const EvidenceTechnicalQualityResult({
    required this.view,
    required this.algorithmVersion,
    required this.configurationVersion,
    required this.integrityStatus,
    required this.originalByteSize,
    required this.originalSha256Checksum,
    required this.sourceExifOrientation,
    required this.orientationNormalizationApplied,
    required this.normalizedOrientation,
    required this.upscalingOccurred,
    required this.warnings,
    this.original,
    this.canonical,
    this.metrics,
    this.canonicalBytes,
  });

  final EvidenceQualityView view;
  final String algorithmVersion;
  final String configurationVersion;
  final EvidenceIntegrityStatus integrityStatus;
  final int originalByteSize;
  final String originalSha256Checksum;
  final int? sourceExifOrientation;
  final bool orientationNormalizationApplied;
  final int? normalizedOrientation;
  final bool upscalingOccurred;
  final Set<EvidenceQualityWarning> warnings;
  final EvidenceImageFacts? original;
  final EvidenceImageFacts? canonical;
  final EvidenceTechnicalMetrics? metrics;

  /// QA-B can persist these canonical bytes instead of decoding the source a
  /// second time. QA-A does not attach them to evidence or write them to disk.
  final Uint8List? canonicalBytes;

  bool get hasValidFiles => integrityStatus == EvidenceIntegrityStatus.valid;
}

abstract interface class EvidenceTechnicalQualityService {
  EvidenceTechnicalQualityResult inspect({
    required Uint8List sourceBytes,
    required EvidenceQualityView view,
  });
}

class OnDeviceEvidenceTechnicalQualityService
    implements EvidenceTechnicalQualityService {
  const OnDeviceEvidenceTechnicalQualityService({
    this.configurationForView =
        ProvisionalEvidenceQualityConfigurations.forView,
  });

  static const canonicalLongEdgePx = 2048;
  static const canonicalJpegQuality = 82;

  final EvidenceQualityConfiguration Function(EvidenceQualityView view)
  configurationForView;

  @override
  EvidenceTechnicalQualityResult inspect({
    required Uint8List sourceBytes,
    required EvidenceQualityView view,
  }) {
    final configuration = configurationForView(view);
    final sourceChecksum = sha256.convert(sourceBytes).toString();
    if (sourceBytes.isEmpty) {
      return _integrityFailure(
        view: view,
        configuration: configuration,
        status: EvidenceIntegrityStatus.emptySource,
        sourceBytes: sourceBytes,
        sourceChecksum: sourceChecksum,
      );
    }

    final sourceInfo = _readSourceInfoSafely(sourceBytes);
    final sourceExifOrientation = _readJpegExifOrientation(sourceBytes);
    final decodedSource = _decodeImageSafely(sourceBytes);
    if (decodedSource == null) {
      return _integrityFailure(
        view: view,
        configuration: configuration,
        status: EvidenceIntegrityStatus.sourceDecodeFailed,
        sourceBytes: sourceBytes,
        sourceChecksum: sourceChecksum,
      );
    }

    final original = EvidenceImageFacts(
      widthPx: sourceInfo?.width ?? decodedSource.width,
      heightPx: sourceInfo?.height ?? decodedSource.height,
      byteSize: sourceBytes.length,
      sha256Checksum: sourceChecksum,
    );
    final normalizationApplied =
        sourceExifOrientation != null && sourceExifOrientation != 1;
    var normalized = image_lib.bakeOrientation(decodedSource);
    final normalizedWidth = normalized.width;
    final normalizedHeight = normalized.height;
    final normalizedLongEdge = math.max(normalizedWidth, normalizedHeight);
    if (normalizedLongEdge > canonicalLongEdgePx) {
      normalized = normalizedWidth >= normalizedHeight
          ? image_lib.copyResize(
              normalized,
              width: canonicalLongEdgePx,
              interpolation: image_lib.Interpolation.average,
            )
          : image_lib.copyResize(
              normalized,
              height: canonicalLongEdgePx,
              interpolation: image_lib.Interpolation.average,
            );
    }

    final canonicalBytes = Uint8List.fromList(
      image_lib.encodeJpg(normalized, quality: canonicalJpegQuality),
    );
    final decodedCanonical = _decodeJpegSafely(canonicalBytes);
    if (decodedCanonical == null) {
      return EvidenceTechnicalQualityResult(
        view: view,
        algorithmVersion: evidenceTechnicalQualityAlgorithmVersion,
        configurationVersion: configuration.version,
        integrityStatus: EvidenceIntegrityStatus.canonicalDecodeFailed,
        originalByteSize: sourceBytes.length,
        originalSha256Checksum: sourceChecksum,
        original: original,
        sourceExifOrientation: sourceExifOrientation,
        orientationNormalizationApplied: normalizationApplied,
        normalizedOrientation: 1,
        upscalingOccurred: false,
        warnings: const {},
      );
    }

    final canonical = EvidenceImageFacts(
      widthPx: decodedCanonical.width,
      heightPx: decodedCanonical.height,
      byteSize: canonicalBytes.length,
      sha256Checksum: sha256.convert(canonicalBytes).toString(),
    );
    final upscalingOccurred =
        canonical.widthPx > normalizedWidth ||
        canonical.heightPx > normalizedHeight;
    final metrics = _calculateMetrics(decodedCanonical, configuration);
    final warnings = _warningsFor(
      original: original,
      upscalingOccurred: upscalingOccurred,
      metrics: metrics,
      configuration: configuration,
    );

    return EvidenceTechnicalQualityResult(
      view: view,
      algorithmVersion: evidenceTechnicalQualityAlgorithmVersion,
      configurationVersion: configuration.version,
      integrityStatus: EvidenceIntegrityStatus.valid,
      originalByteSize: sourceBytes.length,
      originalSha256Checksum: sourceChecksum,
      original: original,
      canonical: canonical,
      sourceExifOrientation: sourceExifOrientation,
      orientationNormalizationApplied: normalizationApplied,
      normalizedOrientation: 1,
      upscalingOccurred: upscalingOccurred,
      metrics: metrics,
      warnings: warnings,
      canonicalBytes: canonicalBytes,
    );
  }

  static EvidenceTechnicalQualityResult _integrityFailure({
    required EvidenceQualityView view,
    required EvidenceQualityConfiguration configuration,
    required EvidenceIntegrityStatus status,
    required Uint8List sourceBytes,
    required String sourceChecksum,
  }) => EvidenceTechnicalQualityResult(
    view: view,
    algorithmVersion: evidenceTechnicalQualityAlgorithmVersion,
    configurationVersion: configuration.version,
    integrityStatus: status,
    originalByteSize: sourceBytes.length,
    originalSha256Checksum: sourceChecksum,
    sourceExifOrientation: null,
    orientationNormalizationApplied: false,
    normalizedOrientation: null,
    upscalingOccurred: false,
    warnings: const {},
  );

  static image_lib.Image? _decodeImageSafely(Uint8List bytes) {
    try {
      return image_lib.decodeImage(bytes);
    } on Object {
      return null;
    }
  }

  static image_lib.DecodeInfo? _readSourceInfoSafely(Uint8List bytes) {
    try {
      return image_lib.findDecoderForData(bytes)?.startDecode(bytes);
    } on Object {
      return null;
    }
  }

  static image_lib.Image? _decodeJpegSafely(Uint8List bytes) {
    try {
      return image_lib.decodeJpg(bytes);
    } on Object {
      return null;
    }
  }

  static int? _readJpegExifOrientation(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 0xff) return null;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 0xd9 || marker == 0xda) return null;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset + 2 > bytes.length) return null;
      final segmentLength = _readUint16(bytes, offset, bigEndian: true);
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return null;
      }
      final payload = offset + 2;
      final payloadLength = segmentLength - 2;
      if (marker == 0xe1 &&
          payloadLength >= 14 &&
          bytes[payload] == 0x45 &&
          bytes[payload + 1] == 0x78 &&
          bytes[payload + 2] == 0x69 &&
          bytes[payload + 3] == 0x66 &&
          bytes[payload + 4] == 0 &&
          bytes[payload + 5] == 0) {
        final orientation = _readTiffOrientation(
          bytes,
          payload + 6,
          payloadLength - 6,
        );
        if (orientation != null) return orientation;
      }
      offset += segmentLength;
    }
    return null;
  }

  static int? _readTiffOrientation(
    Uint8List bytes,
    int tiffStart,
    int tiffLength,
  ) {
    if (tiffLength < 8 || tiffStart + tiffLength > bytes.length) return null;
    final littleEndian =
        bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final bigEndian = bytes[tiffStart] == 0x4d && bytes[tiffStart + 1] == 0x4d;
    if (!littleEndian && !bigEndian) return null;
    if (_readUint16(bytes, tiffStart + 2, bigEndian: bigEndian) != 42) {
      return null;
    }
    final ifdOffset = _readUint32(bytes, tiffStart + 4, bigEndian: bigEndian);
    final ifdStart = tiffStart + ifdOffset;
    final tiffEnd = tiffStart + tiffLength;
    if (ifdStart < tiffStart || ifdStart + 2 > tiffEnd) return null;
    final entryCount = _readUint16(bytes, ifdStart, bigEndian: bigEndian);
    for (var index = 0; index < entryCount; index++) {
      final entry = ifdStart + 2 + index * 12;
      if (entry + 12 > tiffEnd) return null;
      final tag = _readUint16(bytes, entry, bigEndian: bigEndian);
      if (tag != 0x0112) continue;
      final type = _readUint16(bytes, entry + 2, bigEndian: bigEndian);
      final count = _readUint32(bytes, entry + 4, bigEndian: bigEndian);
      if (type != 3 || count != 1) return null;
      final orientation = _readUint16(bytes, entry + 8, bigEndian: bigEndian);
      return orientation >= 1 && orientation <= 8 ? orientation : null;
    }
    return null;
  }

  static int _readUint16(
    Uint8List bytes,
    int offset, {
    required bool bigEndian,
  }) => bigEndian
      ? (bytes[offset] << 8) | bytes[offset + 1]
      : bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint32(
    Uint8List bytes,
    int offset, {
    required bool bigEndian,
  }) => bigEndian
      ? (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3]
      : bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24);

  static Set<EvidenceQualityWarning> _warningsFor({
    required EvidenceImageFacts original,
    required bool upscalingOccurred,
    required EvidenceTechnicalMetrics metrics,
    required EvidenceQualityConfiguration configuration,
  }) {
    final warnings = <EvidenceQualityWarning>{};
    if (original.longEdgePx < configuration.minimumSourceLongEdgePx ||
        original.shortEdgePx < configuration.minimumSourceShortEdgePx) {
      warnings.add(EvidenceQualityWarning.lowSourceResolution);
    }
    if (upscalingOccurred) {
      warnings.add(EvidenceQualityWarning.unexpectedUpscaling);
    }
    if (metrics.blurLaplacianVariance <
        configuration.blurVarianceWarningBelow) {
      warnings.add(EvidenceQualityWarning.possibleBlur);
    }
    if (metrics.meanLuminance < configuration.meanLuminanceWarningBelow ||
        metrics.darkPixelFraction >
            configuration.darkPixelFractionWarningAbove) {
      warnings.add(EvidenceQualityWarning.tooDark);
    }
    if (metrics.highlightClippedPixelFraction >
            configuration.highlightPixelFractionWarningAbove ||
        metrics.maximumConcentratedHighlightFraction >
            configuration.concentratedHighlightFractionWarningAbove) {
      warnings.add(EvidenceQualityWarning.possibleOverexposureOrGlare);
    }
    return Set.unmodifiable(warnings);
  }

  static EvidenceTechnicalMetrics _calculateMetrics(
    image_lib.Image canonical,
    EvidenceQualityConfiguration configuration,
  ) {
    final sample = _analysisSample(canonical, configuration.analysisLongEdgePx);
    final width = sample.width;
    final height = sample.height;
    final luminance = Float64List(width * height);
    final histogram = List<int>.filled(256, 0);
    final gridColumns = math.min(8, width);
    final gridRows = math.min(8, height);
    final gridBright = List<int>.filled(gridColumns * gridRows, 0);
    final gridTotals = List<int>.filled(gridColumns * gridRows, 0);
    var sum = 0.0;
    var darkPixels = 0;
    var shadowClippedPixels = 0;
    var highlightPixels = 0;

    for (final pixel in sample) {
      final value =
          0.2126 * pixel.r.toDouble() +
          0.7152 * pixel.g.toDouble() +
          0.0722 * pixel.b.toDouble();
      final rounded = value.round().clamp(0, 255);
      luminance[pixel.y * width + pixel.x] = value;
      histogram[rounded]++;
      sum += value;
      if (value <= configuration.darkLuminanceCutoff) darkPixels++;
      if (value <= 5) shadowClippedPixels++;
      final highlighted = value >= configuration.highlightLuminanceCutoff;
      if (highlighted) highlightPixels++;
      final gridX = math.min(gridColumns - 1, pixel.x * gridColumns ~/ width);
      final gridY = math.min(gridRows - 1, pixel.y * gridRows ~/ height);
      final gridIndex = gridY * gridColumns + gridX;
      gridTotals[gridIndex]++;
      if (highlighted) gridBright[gridIndex]++;
    }

    final pixelCount = width * height;
    var cumulative = 0;
    var median = 0;
    final medianTarget = (pixelCount + 1) ~/ 2;
    for (var value = 0; value < histogram.length; value++) {
      cumulative += histogram[value];
      if (cumulative >= medianTarget) {
        median = value;
        break;
      }
    }
    var maximumConcentratedHighlight = 0.0;
    for (var index = 0; index < gridTotals.length; index++) {
      if (gridTotals[index] == 0) continue;
      maximumConcentratedHighlight = math.max(
        maximumConcentratedHighlight,
        gridBright[index] / gridTotals[index],
      );
    }

    return EvidenceTechnicalMetrics(
      sampleWidthPx: width,
      sampleHeightPx: height,
      blurLaplacianVariance: _laplacianVariance(luminance, width, height),
      meanLuminance: sum / pixelCount,
      medianLuminance: median.toDouble(),
      darkPixelFraction: darkPixels / pixelCount,
      shadowClippedPixelFraction: shadowClippedPixels / pixelCount,
      highlightClippedPixelFraction: highlightPixels / pixelCount,
      maximumConcentratedHighlightFraction: maximumConcentratedHighlight,
    );
  }

  static image_lib.Image _analysisSample(
    image_lib.Image canonical,
    int maximumLongEdge,
  ) {
    final longEdge = math.max(canonical.width, canonical.height);
    if (longEdge <= maximumLongEdge) return canonical;
    return canonical.width >= canonical.height
        ? image_lib.copyResize(
            canonical,
            width: maximumLongEdge,
            interpolation: image_lib.Interpolation.average,
          )
        : image_lib.copyResize(
            canonical,
            height: maximumLongEdge,
            interpolation: image_lib.Interpolation.average,
          );
  }

  static double _laplacianVariance(
    Float64List luminance,
    int width,
    int height,
  ) {
    if (width < 3 || height < 3) return 0;
    var sum = 0.0;
    var sumSquared = 0.0;
    var count = 0;
    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        final index = row + x;
        final response =
            luminance[index - width] +
            luminance[index + width] +
            luminance[index - 1] +
            luminance[index + 1] -
            4 * luminance[index];
        sum += response;
        sumSquared += response * response;
        count++;
      }
    }
    final mean = sum / count;
    return math.max(0, sumSquared / count - mean * mean);
  }
}
