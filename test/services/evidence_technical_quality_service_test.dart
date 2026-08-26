import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:wormwise/services/evidence_technical_quality_service.dart';

void main() {
  const service = OnDeviceEvidenceTechnicalQualityService();

  test(
    'records original and canonical facts without enlarging a low-resolution source',
    () {
      final source = _jpeg(_pattern(640, 480));

      final result = service.inspect(
        sourceBytes: source,
        view: EvidenceQualityView.whorlNewestLeaves,
      );

      expect(result.integrityStatus, EvidenceIntegrityStatus.valid);
      expect(result.original?.widthPx, 640);
      expect(result.original?.heightPx, 480);
      expect(result.originalByteSize, source.length);
      expect(result.original?.byteSize, source.length);
      expect(result.canonical?.widthPx, 640);
      expect(result.canonical?.heightPx, 480);
      expect(result.canonical?.byteSize, result.canonicalBytes?.length);
      expect(result.upscalingOccurred, isFalse);
      expect(
        result.warnings,
        contains(EvidenceQualityWarning.lowSourceResolution),
      );
    },
  );

  test(
    'normalizes EXIF orientation before creating and measuring canonical image',
    () {
      final image = _pattern(800, 1200);
      final source = _withExifOrientation(_jpeg(image), 6);

      final result = service.inspect(
        sourceBytes: source,
        view: EvidenceQualityView.plantOverview,
      );

      expect(result.original?.widthPx, 800);
      expect(result.original?.heightPx, 1200);
      expect(result.sourceExifOrientation, 6);
      expect(result.orientationNormalizationApplied, isTrue);
      expect(result.normalizedOrientation, 1);
      expect(result.canonical?.widthPx, 1200);
      expect(result.canonical?.heightPx, 800);
      expect(result.upscalingOccurred, isFalse);
    },
  );

  test('downsizes a large source to the canonical 2048-pixel long edge', () {
    final source = _jpeg(_solid(2600, 1800, 100, 145, 80));

    final result = service.inspect(
      sourceBytes: source,
      view: EvidenceQualityView.stationContext,
    );

    expect(result.original?.widthPx, 2600);
    expect(result.original?.heightPx, 1800);
    expect(result.canonical?.widthPx, 2048);
    expect(result.canonical?.heightPx, 1418);
    expect(result.upscalingOccurred, isFalse);
    expect(result.original?.sha256Checksum, hasLength(64));
    expect(result.canonical?.sha256Checksum, hasLength(64));
  });

  test('sharp controlled image scores above its blurred counterpart', () {
    final sharp = _pattern(1024, 1024);
    final blurred = image_lib.gaussianBlur(sharp.clone(), radius: 14);

    final sharpResult = service.inspect(
      sourceBytes: _jpeg(sharp),
      view: EvidenceQualityView.conditionalCloseUp,
    );
    final blurredResult = service.inspect(
      sourceBytes: _jpeg(blurred),
      view: EvidenceQualityView.conditionalCloseUp,
    );

    expect(
      sharpResult.metrics!.blurLaplacianVariance,
      greaterThan(blurredResult.metrics!.blurLaplacianVariance * 3),
    );
    expect(
      blurredResult.warnings,
      contains(EvidenceQualityWarning.possibleBlur),
    );
  });

  test('dark controlled image records luminance metrics and warns', () {
    final result = service.inspect(
      sourceBytes: _jpeg(_solid(1600, 1000, 14, 18, 12)),
      view: EvidenceQualityView.whorlNewestLeaves,
    );

    expect(result.metrics!.meanLuminance, lessThan(25));
    expect(result.metrics!.darkPixelFraction, greaterThan(0.95));
    expect(result.metrics!.shadowClippedPixelFraction, inInclusiveRange(0, 1));
    expect(result.warnings, contains(EvidenceQualityWarning.tooDark));
  });

  test(
    'bright controlled image uses the combined overexposure-or-glare warning',
    () {
      final image = _solid(1600, 1000, 120, 145, 90);
      for (var y = 150; y < 850; y++) {
        for (var x = 450; x < 1200; x++) {
          final pixel = image.getPixel(x, y);
          pixel
            ..r = 255
            ..g = 253
            ..b = 250;
        }
      }

      final result = service.inspect(
        sourceBytes: _jpeg(image),
        view: EvidenceQualityView.plantOverview,
      );

      expect(result.metrics!.highlightClippedPixelFraction, greaterThan(0.15));
      expect(
        result.metrics!.maximumConcentratedHighlightFraction,
        greaterThan(0.5),
      );
      expect(
        result.warnings,
        contains(EvidenceQualityWarning.possibleOverexposureOrGlare),
      );
    },
  );

  test(
    'unreadable source returns an integrity result without fabricated metrics',
    () {
      final result = service.inspect(
        sourceBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        view: EvidenceQualityView.stationContext,
      );

      expect(
        result.integrityStatus,
        EvidenceIntegrityStatus.sourceDecodeFailed,
      );
      expect(result.hasValidFiles, isFalse);
      expect(result.original, isNull);
      expect(result.canonical, isNull);
      expect(result.metrics, isNull);
      expect(result.canonicalBytes, isNull);
    },
  );

  test('empty source is distinguished from an unsupported or corrupt file', () {
    final result = service.inspect(
      sourceBytes: Uint8List(0),
      view: EvidenceQualityView.stationContext,
    );

    expect(result.integrityStatus, EvidenceIntegrityStatus.emptySource);
    expect(result.originalByteSize, 0);
  });

  test('every evidence view has a distinct provisional configuration', () {
    final configurations = EvidenceQualityView.values
        .map(ProvisionalEvidenceQualityConfigurations.forView)
        .toList();

    expect(configurations.map((item) => item.view).toSet(), {
      ...EvidenceQualityView.values,
    });
    expect(
      configurations.map((item) => item.version).toSet(),
      hasLength(EvidenceQualityView.values.length),
    );
    expect(
      configurations.map((item) => item.blurVarianceWarningBelow).toSet(),
      hasLength(EvidenceQualityView.values.length),
    );
  });

  test('raw metrics are deterministic for the same canonical input', () {
    final source = _jpeg(_pattern(1600, 1000));
    final first = service.inspect(
      sourceBytes: source,
      view: EvidenceQualityView.plantOverview,
    );
    final second = service.inspect(
      sourceBytes: source,
      view: EvidenceQualityView.plantOverview,
    );

    expect(first.canonical?.sha256Checksum, second.canonical?.sha256Checksum);
    expect(
      first.metrics!.blurLaplacianVariance,
      second.metrics!.blurLaplacianVariance,
    );
    expect(first.metrics!.meanLuminance, second.metrics!.meanLuminance);
    expect(first.warnings, second.warnings);
  });
}

Uint8List _jpeg(image_lib.Image image) =>
    Uint8List.fromList(image_lib.encodeJpg(image, quality: 92));

Uint8List _withExifOrientation(Uint8List jpeg, int orientation) {
  if (jpeg.length < 2 || jpeg[0] != 0xff || jpeg[1] != 0xd8) {
    throw ArgumentError('Expected JPEG source bytes.');
  }
  final app1 = <int>[
    0xff,
    0xe1,
    0x00,
    0x22,
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    0x49,
    0x49,
    0x2a,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x12,
    0x01,
    0x03,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    orientation,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ];
  return Uint8List.fromList([jpeg[0], jpeg[1], ...app1, ...jpeg.skip(2)]);
}

image_lib.Image _solid(int width, int height, int red, int green, int blue) {
  final image = image_lib.Image(width: width, height: height);
  image_lib.fill(image, color: image_lib.ColorRgb8(red, green, blue));
  return image;
}

image_lib.Image _pattern(int width, int height) {
  final image = image_lib.Image(width: width, height: height);
  for (final pixel in image) {
    final checker = ((pixel.x ~/ 12) + (pixel.y ~/ 12)).isEven;
    pixel
      ..r = checker ? 35 : 215
      ..g = checker ? 125 : 185
      ..b = checker ? 45 : 75;
  }
  return image;
}
