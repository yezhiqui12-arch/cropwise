import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

import '../support/da_results_fixture.dart';

void main() {
  test(
    'database failure preserves source and allows the same photo to retry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-save-failure-',
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      await daResultsFixture(db, recorded: 1);
      final session =
          (await db.select(db.evidenceCaptureSessions).get()).single;
      final actor =
          (await db.select(db.assessments).get()).single.evaluatorPersonId;
      final source = File('${root.path}/capture.jpg');
      await source.writeAsBytes(
        image.encodeJpg(image.Image(width: 32, height: 32)),
      );
      final storage = EvidenceStorageService(rootDirectory: () async => root);
      final coordinator = EvidenceCaptureCoordinator(
        repository: EvidenceCaptureRepository(db),
        storage: storage,
      );
      await db.customStatement(
        "CREATE TRIGGER reject_evidence BEFORE INSERT ON evidence_media BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
      Future<EvidenceCaptureBundle> save([String mediaId = 'retry-photo']) =>
          coordinator.stageCapture(
            session: session,
            viewType: DatabaseCodes.evidenceViewWhorlOverview,
            sourcePath: source.path,
            actorPersonId: actor,
            stableMediaId: mediaId,
          );
      await expectLater(save(), throwsA(anything));
      expect(await source.exists(), isTrue);
      expect(await db.select(db.evidenceMedia).get(), isEmpty);
      await db.customStatement('DROP TRIGGER reject_evidence');
      final bundle = await save();
      expect(await source.exists(), isFalse);
      expect(bundle.media.single.sha256Checksum, isNotEmpty);
      final accepted = await coordinator.accept(
        media: bundle.media.single,
        actorPersonId: actor,
      );
      final oldPhoto = accepted.media.single;
      await source.writeAsBytes(
        image.encodeJpg(image.Image(width: 32, height: 32)),
      );
      await db.customStatement(
        "CREATE TRIGGER reject_evidence BEFORE INSERT ON evidence_media BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
      await expectLater(save('replacement-photo'), throwsA(anything));
      expect(await source.exists(), isTrue);
      final retained = await EvidenceCaptureRepository(
        db,
      ).loadBundle(session.id);
      expect(retained.media.single.id, oldPhoto.id);
      expect(
        retained.media.single.storageState,
        DatabaseCodes.evidenceStorageReady,
      );
      expect(await storage.exists(oldPhoto.localUri), isTrue);

      expect(await storage.exists(oldPhoto.localUri), isTrue);
      expect(await storage.exists(oldPhoto.thumbnailLocalUri!), isTrue);
    },
  );

  test('decode failure and destination failure preserve the source', () async {
    final root = await Directory.systemTemp.createTemp(
      'wormwise-stage-failure-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/capture.jpg');
    final storage = EvidenceStorageService(rootDirectory: () async => root);
    Future<StoredEvidenceFile> stage() => storage.stageCapturedFile(
      sourcePath: source.path,
      assessmentId: 'assessment',
      stationId: 'station',
      scopeKey: 'plant',
      mediaId: 'photo',
    );
    await source.writeAsString('corrupt photo');
    await expectLater(stage(), throwsFormatException);
    expect(await source.readAsString(), 'corrupt photo');
    await source.writeAsBytes(
      image.encodeJpg(image.Image(width: 32, height: 32)),
    );
    // Block the destination directory using a regular file.
    await File('${root.path}/assessment').writeAsString('blocked');
    await expectLater(stage(), throwsA(isA<FileSystemException>()));
    expect(await source.exists(), isTrue);
  });
  test(
    'a refresh failure after commit keeps registered evidence files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-refresh-failure-',
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      await daResultsFixture(db, recorded: 1);
      final session =
          (await db.select(db.evidenceCaptureSessions).get()).single;
      final actor =
          (await db.select(db.assessments).get()).single.evaluatorPersonId;
      final source = File('${root.path}/capture.jpg');
      await source.writeAsBytes(
        image.encodeJpg(image.Image(width: 32, height: 32)),
      );
      final storage = EvidenceStorageService(rootDirectory: () async => root);
      final repository = _RefreshFailureRepository(db);
      final coordinator = EvidenceCaptureCoordinator(
        repository: repository,
        storage: storage,
      );
      await expectLater(
        coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: source.path,
          actorPersonId: actor,
        ),
        throwsStateError,
      );
      final record = (await db.select(db.evidenceMedia).get()).single;
      expect(await storage.exists(record.localUri), isTrue);
      expect(await storage.exists(record.thumbnailLocalUri!), isTrue);
      repository.fail = false;
      expect(
        (await repository.loadBundle(session.id)).media.single.id,
        record.id,
      );
    },
  );
}

class _RefreshFailureRepository extends EvidenceCaptureRepository {
  _RefreshFailureRepository(super.database);
  bool fail = true;
  @override
  Future<EvidenceCaptureBundle> loadBundle(String sessionId) async {
    if (fail &&
        (await database.select(database.evidenceMedia).get()).isNotEmpty) {
      throw StateError('simulated refresh failure');
    }
    return super.loadBundle(sessionId);
  }
}
