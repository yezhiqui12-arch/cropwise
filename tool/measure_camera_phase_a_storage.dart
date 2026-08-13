import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  test(
    'measures capture-first Station 1 context plus twenty required plant images',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-ten-plant-measurement-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final image = image_lib.Image(width: 2304, height: 1728);
      for (final pixel in image) {
        final texture =
            (pixel.x * 31 + pixel.y * 17 + (pixel.x ^ pixel.y)) % 256;
        pixel
          ..r = texture
          ..g = (texture + pixel.x ~/ 9) % 256
          ..b = (texture + pixel.y ~/ 7) % 256;
      }
      final phoneJpeg = image_lib.encodeJpg(image, quality: 94);
      final storage = EvidenceStorageService(rootDirectory: () async => root);
      var mainBytes = 0;
      var thumbnailBytes = 0;

      for (var index = 0; index < 21; index++) {
        final source = File(
          '${root.path}${Platform.pathSeparator}source_$index.jpg',
        );
        await source.writeAsBytes(phoneJpeg, flush: true);
        final plantPosition = index == 0 ? null : ((index - 1) ~/ 2) + 1;
        final view = index == 0
            ? 'context'
            : index.isOdd
            ? 'overview'
            : 'whorl_detail';
        final scopeKey = index == 0
            ? 'station_context'
            : 'plant_${plantPosition!.toString().padLeft(2, '0')}_$view';
        final staged = await storage.stageCapturedFile(
          sourcePath: source.path,
          assessmentId: 'measurement-assessment',
          stationId: 'measurement-station',
          scopeKey: scopeKey,
          mediaId: 'measurement-$index',
        );
        final ready = await storage.promote(
          localUri: staged.localUri,
          thumbnailLocalUri: staged.thumbnailLocalUri,
        );
        mainBytes += await (await storage.resolve(ready.localUri)).length();
        thumbnailBytes += await (await storage.resolve(
          ready.thumbnailLocalUri,
        )).length();
      }

      final totalBytes = mainBytes + thumbnailBytes;
      // ignore: avoid_print
      print(
        'CAPTURE_FIRST_10_PLANT_MEASUREMENT '
        'fixture=2304x1728_high_detail input=${phoneJpeg.length}B_each '
        'main=${mainBytes}B thumbnails=${thumbnailBytes}B '
        'total=${totalBytes}B images=21',
      );
      // ignore: avoid_print
      print(
        'This reproducible stress fixture is not a claim about every phone or '
        'field scene. Repeat the measurement with real maize images on the '
        'target phone.',
      );
      expect(totalBytes, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
