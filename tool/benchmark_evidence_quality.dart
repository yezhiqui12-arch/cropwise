import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:wormwise/services/evidence_technical_quality_service.dart';

void main(List<String> arguments) {
  final cases = arguments.contains('--quick')
      ? const [(1920, 1080)]
      : const [(1920, 1080), (4032, 3024)];
  const service = OnDeviceEvidenceTechnicalQualityService();

  stdout.writeln(
    'QA-A technical benchmark; desktop Dart process; '
    'memory is process RSS, not isolated algorithm allocation.',
  );
  for (final dimensions in cases) {
    final source = _representativeJpeg(dimensions.$1, dimensions.$2);
    final rssBefore = ProcessInfo.currentRss;
    final stopwatch = Stopwatch()..start();
    final result = service.inspect(
      sourceBytes: source,
      view: EvidenceQualityView.whorlNewestLeaves,
    );
    stopwatch.stop();
    final rssAfter = ProcessInfo.currentRss;
    final metrics = result.metrics!;
    stdout.writeln(
      '${dimensions.$1}x${dimensions.$2} '
      'source=${_mib(source.length)}MiB '
      'canonical=${_mib(result.canonical?.byteSize ?? 0)}MiB '
      'elapsed=${stopwatch.elapsedMilliseconds}ms '
      'rss_before=${_mib(rssBefore)}MiB '
      'rss_after=${_mib(rssAfter)}MiB '
      'rss_change=${_signedMib(rssAfter - rssBefore)}MiB '
      'process_max_rss=${_mib(ProcessInfo.maxRss)}MiB '
      'sample=${metrics.sampleWidthPx}x${metrics.sampleHeightPx} '
      'blur=${metrics.blurLaplacianVariance.toStringAsFixed(2)} '
      'mean_luma=${metrics.meanLuminance.toStringAsFixed(2)} '
      'median_luma=${metrics.medianLuminance.toStringAsFixed(2)} '
      'dark_fraction=${metrics.darkPixelFraction.toStringAsFixed(4)} '
      'shadow_clip=${metrics.shadowClippedPixelFraction.toStringAsFixed(4)} '
      'highlight_clip=${metrics.highlightClippedPixelFraction.toStringAsFixed(4)} '
      'max_highlight_region='
      '${metrics.maximumConcentratedHighlightFraction.toStringAsFixed(4)} '
      'warnings=${result.warnings.map((warning) => warning.name).join(',')}',
    );
  }
  _printControlledResults(service);
}

void _printControlledResults(OnDeviceEvidenceTechnicalQualityService service) {
  final sharp = _checkerImage(1024, 1024);
  final controlled = <String, image_lib.Image>{
    'sharp_checker': sharp,
    'blurred_checker': image_lib.gaussianBlur(sharp.clone(), radius: 14),
    'dark': _solidImage(1600, 1000, 14, 18, 12),
    'bright_region': _brightRegionImage(),
  };
  stdout.writeln('Controlled deterministic image results:');
  for (final entry in controlled.entries) {
    final result = service.inspect(
      sourceBytes: Uint8List.fromList(
        image_lib.encodeJpg(entry.value, quality: 92),
      ),
      view: EvidenceQualityView.whorlNewestLeaves,
    );
    final metrics = result.metrics!;
    stdout.writeln(
      '${entry.key} '
      'blur=${metrics.blurLaplacianVariance.toStringAsFixed(2)} '
      'mean_luma=${metrics.meanLuminance.toStringAsFixed(2)} '
      'dark_fraction=${metrics.darkPixelFraction.toStringAsFixed(4)} '
      'highlight_clip=${metrics.highlightClippedPixelFraction.toStringAsFixed(4)} '
      'max_highlight_region='
      '${metrics.maximumConcentratedHighlightFraction.toStringAsFixed(4)} '
      'warnings=${result.warnings.map((warning) => warning.name).join(',')}',
    );
  }
}

Uint8List _representativeJpeg(int width, int height) {
  final image = image_lib.Image(width: width, height: height);
  for (final pixel in image) {
    final row = (pixel.y ~/ 18).isEven;
    final variation = (pixel.x * 7 + pixel.y * 3) % 42;
    pixel
      ..r = (row ? 70 : 105) + variation
      ..g = (row ? 125 : 155) + variation ~/ 2
      ..b = (row ? 45 : 65) + variation ~/ 3;
  }
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 92));
}

image_lib.Image _checkerImage(int width, int height) {
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

image_lib.Image _solidImage(
  int width,
  int height,
  int red,
  int green,
  int blue,
) {
  final image = image_lib.Image(width: width, height: height);
  image_lib.fill(image, color: image_lib.ColorRgb8(red, green, blue));
  return image;
}

image_lib.Image _brightRegionImage() {
  final image = _solidImage(1600, 1000, 120, 145, 90);
  for (var y = 150; y < 850; y++) {
    for (var x = 450; x < 1200; x++) {
      final pixel = image.getPixel(x, y);
      pixel
        ..r = 255
        ..g = 253
        ..b = 250;
    }
  }
  return image;
}

String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

String _signedMib(int bytes) {
  final value = bytes / (1024 * 1024);
  return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';
}
