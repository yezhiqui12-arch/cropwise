import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wormwise/services/cloud/case_message_service.dart';
import 'package:wormwise/services/cloud/wormwise_identity_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late CaseMessageService service;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('wormwise-message-');
    service = CaseMessageService(
      WormWiseIdentityService.localOnly(),
      files: EvidenceStorageService(rootDirectory: () async => root),
    );
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'draft restores stable retry ID, request link, captions and staged photo',
    () async {
      final original = File('${root.path}/original.jpg');
      final sourceImage = img.Image(width: 24, height: 32);
      sourceImage.exif.imageIfd.make = 'Private camera metadata';
      await original.writeAsBytes(img.encodeJpg(sourceImage));
      final draft = CaseMessageDraft(
        body: 'Here is a clearer photo',
        requestId: 'request-1',
      );
      final photo = await service.stagePhoto(
        'case-1',
        draft,
        original.path,
        station: 2,
        plant: 4,
      );
      photo.caption = 'Whorl today';
      draft.photos.add(photo);
      draft.attempted = true;
      await service.saveDraft('owner-1', 'case-1', draft);
      final restored = await service.loadDraft('owner-1', 'case-1');
      expect(restored.id, draft.id);
      expect(restored.attempted, isTrue);
      expect(restored.requestId, 'request-1');
      expect(restored.photos.single.caption, 'Whorl today');
      expect(restored.photos.single.station, 2);
      expect(restored.photos.single.plant, 4);
      final bytes = await (await service.files.resolve(
        restored.photos.single.localUri,
      )).readAsBytes();
      expect(img.decodeJpg(bytes), isNotNull);
      expect(img.decodeJpg(bytes)!.exif.isEmpty, isTrue);
      expect(await original.exists(), isTrue);
      expect(
        (await service.loadDraft('different-owner', 'case-1')).photos,
        isEmpty,
      );
    },
  );
  test(
    'discard removes draft copies without removing assessment source photos',
    () async {
      final original = File('${root.path}/assessment-photo.png');
      await original.writeAsBytes(
        img.encodePng(img.Image(width: 32, height: 32)),
      );
      final draft = CaseMessageDraft();
      draft.photos.add(
        await service.stagePhoto('case-1', draft, original.path),
      );
      final staged = await service.files.resolve(draft.photos.single.localUri);
      await service.saveDraft('owner-1', 'case-1', draft);
      await service.discard('owner-1', 'case-1', draft);
      expect(await original.exists(), isTrue);
      expect(await staged.exists(), isFalse);
      expect((await service.loadDraft('owner-1', 'case-1')).photos, isEmpty);
    },
  );
  test('oversized images are rejected before staging', () async {
    final file = File('${root.path}/too-large.jpg');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(CaseMessageService.maxBytes + 1);
    await handle.close();
    await expectLater(
      service.stagePhoto('case-1', CaseMessageDraft(), file.path),
      throwsStateError,
    );
  });
  test(
    'replacement draft preserves inherited identity and quality provenance',
    () async {
      final file = File('${root.path}/replacement.png');
      await file.writeAsBytes(img.encodePng(img.Image(width: 32, height: 32)));
      final draft = CaseMessageDraft(
        requestId: 'request-2',
        targetPlant: 8,
        targetBlockId: 'block-2',
        targetBlockSequence: 2,
        requestedViews: ['whole_plant', 'whorl'],
        samePlantConfirmed: true,
      );
      final photo = await service.stagePhoto(
        'case-1',
        draft,
        file.path,
        captureSource: 'gallery',
      );
      draft.photos.add(photo);
      await service.saveDraft('owner-1', 'case-1', draft);
      final restored = await service.loadDraft('owner-1', 'case-1');
      expect(restored.targetPlant, 8);
      expect(restored.targetBlockSequence, 2);
      expect(restored.samePlantConfirmed, isTrue);
      expect(restored.requestedViews, ['whole_plant', 'whorl']);
      expect(restored.photos.single.station, 8);
      expect(restored.photos.single.plant, 1);
      expect(restored.photos.single.blockRunId, 'block-2');
      expect(restored.photos.single.captureSource, 'gallery');
      expect(restored.photos.single.capturedAt, isNull);
      expect(
        restored.photos.single.qualityWarnings,
        contains('lowSourceResolution'),
      );
    },
  );
  test('unreadable replacement is rejected before staging', () async {
    final file = File('${root.path}/invalid.jpg');
    await file.writeAsString('not an image');
    await expectLater(
      service.stagePhoto('case-1', CaseMessageDraft(), file.path),
      throwsStateError,
    );
  });
}
