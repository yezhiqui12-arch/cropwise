import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  test(
    'creates inspectable canonical evidence fixtures from supplied maize photos',
    () async {
      final paths = Platform.environment['WORMWISE_QA_IMAGE_PATHS']
          ?.split(';')
          .where((path) => path.trim().isNotEmpty)
          .toList(growable: false);
      final outputPath = Platform.environment['WORMWISE_QA_OUTPUT_PATH'];
      if (paths == null || paths.isEmpty || outputPath == null) {
        fail(
          'Set WORMWISE_QA_IMAGE_PATHS and WORMWISE_QA_OUTPUT_PATH to run this manual visual QA tool.',
        );
      }

      final output = Directory(outputPath);
      await output.create(recursive: true);
      final storage = EvidenceStorageService(rootDirectory: () async => output);
      var totalBytes = 0;

      for (var index = 0; index < paths.length; index++) {
        final source = File(paths[index]);
        expect(await source.exists(), isTrue, reason: source.path);
        final staged = await storage.stageCapturedFile(
          sourcePath: source.path,
          assessmentId: 'real-maize-qa',
          stationId: 'station-1',
          scopeKey: 'reference_${index + 1}',
          mediaId: 'reference-${index + 1}',
          deleteSourceAfterCopy: false,
        );
        final ready = await storage.promote(
          localUri: staged.localUri,
          thumbnailLocalUri: staged.thumbnailLocalUri,
        );
        final canonical = await storage.resolve(ready.localUri);
        final thumbnail = await storage.resolve(ready.thumbnailLocalUri);
        totalBytes += await canonical.length() + await thumbnail.length();
        // ignore: avoid_print
        print(
          'CANONICAL_EVIDENCE_QA source=${source.path} '
          'canonical=${canonical.path} thumbnail=${thumbnail.path} '
          'dimensions=${staged.widthPx}x${staged.heightPx} '
          'canonical_bytes=${await canonical.length()} '
          'checksum=${staged.sha256Checksum}',
        );
        expect(staged.widthPx, lessThanOrEqualTo(2048));
        expect(staged.heightPx, lessThanOrEqualTo(2048));
        expect(staged.sha256Checksum, isNotEmpty);
      }

      // ignore: avoid_print
      print(
        'CANONICAL_EVIDENCE_QA_TOTAL images=${paths.length} bytes=$totalBytes '
        'output=${output.path}',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
