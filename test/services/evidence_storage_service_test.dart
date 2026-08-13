import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  test(
    'stores a compressed JPEG and thumbnail under a private relative path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-storage-test-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final source = File(
        '${root.path}${Platform.pathSeparator}phone-cache.jpg',
      );
      final image = image_lib.Image(width: 2600, height: 1800);
      for (final pixel in image) {
        pixel
          ..r = (pixel.x * 13 + pixel.y * 7) % 256
          ..g = (pixel.x * 3 + pixel.y * 17) % 256
          ..b = (pixel.x * 19 + pixel.y * 5) % 256;
      }
      await source.writeAsBytes(
        image_lib.encodeJpg(image, quality: 94),
        flush: true,
      );

      final storage = EvidenceStorageService(rootDirectory: () async => root);
      final stored = await storage.stageCapturedFile(
        sourcePath: source.path,
        assessmentId: 'assessment-1',
        stationId: 'station-1',
        scopeKey: 'plant_01',
        mediaId: 'media-1',
      );
      final storedFile = await storage.resolve(stored.localUri);
      final thumbnail = await storage.resolve(stored.thumbnailLocalUri);
      final bytes = await storedFile.readAsBytes();

      expect(await source.exists(), isFalse);
      expect(
        stored.localUri,
        startsWith('assessment-1/station-1/plant_01/staging/'),
      );
      expect(stored.localUri, isNot(contains(root.path)));
      expect(await storedFile.exists(), isTrue);
      expect(await thumbnail.exists(), isTrue);
      expect(stored.widthPx, 2048);
      expect(stored.heightPx, lessThanOrEqualTo(2048));
      expect(stored.byteSize, bytes.length);
      expect(stored.sha256Checksum, sha256.convert(bytes).toString());

      final ready = await storage.promote(
        localUri: stored.localUri,
        thumbnailLocalUri: stored.thumbnailLocalUri,
      );
      expect(ready.localUri, contains('/ready/'));
      expect(await storage.exists(ready.localUri), isTrue);
      expect(await storage.exists(stored.localUri), isFalse);
    },
  );

  test('rejects traversal in persisted local image paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'wormwise-storage-path-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = EvidenceStorageService(rootDirectory: () async => root);

    await expectLater(storage.resolve('../outside.jpg'), throwsArgumentError);
    await expectLater(
      storage.resolve('folder\\outside.jpg'),
      throwsArgumentError,
    );
  });
}
