import 'dart:convert';
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
  test('prepared capture replays once after reopening the database', () async {
    final root = await Directory.systemTemp.createTemp('wormwise-journal-');
    final dbFile = File('${root.path}/records.sqlite');
    var db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    await daResultsFixture(db, recorded: 1);
    final session = (await db.select(db.evidenceCaptureSessions).get()).single;
    final actor =
        (await db.select(db.assessments).get()).single.evaluatorPersonId;
    final source = File('${root.path}/capture.jpg');
    await source.writeAsBytes(
      image.encodeJpg(image.Image(width: 32, height: 32)),
    );
    final storage = EvidenceStorageService(
      rootDirectory: () async => Directory('${root.path}/private'),
    );
    EvidenceCaptureCoordinator coordinator() => EvidenceCaptureCoordinator(
      repository: EvidenceCaptureRepository(db),
      storage: storage,
    );
    await db.customStatement(
      "CREATE TRIGGER reject_evidence BEFORE INSERT ON evidence_media BEGIN SELECT RAISE(ABORT, 'simulated crash window'); END",
    );
    await expectLater(
      coordinator().stageCapture(
        session: session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        sourcePath: source.path,
        actorPersonId: actor,
        stableMediaId: 'pending-photo',
      ),
      throwsA(anything),
    );
    expect(await storage.pendingCaptureJournals(null), hasLength(1));
    await db.close();
    db = AppDatabase(NativeDatabase(dbFile));
    await db.customStatement('DROP TRIGGER reject_evidence');
    final recovery = coordinator();
    expect(await recovery.recoverPreparedCaptures(), 0);
    expect(await recovery.recoverPreparedCaptures(), 0);
    expect(await db.select(db.evidenceMedia).get(), hasLength(1));
    expect(await storage.pendingCaptureJournals(null), isEmpty);
    var media = (await db.select(db.evidenceMedia).get()).single;
    expect(media.storageState, DatabaseCodes.evidenceStorageStaged);
    // Crash after moving just the main file, before moving its thumbnail and DB update.
    final staged = await storage.resolve(media.localUri);
    final ready = await storage.resolve(storage.readyUriFor(media.localUri));
    await ready.parent.create(recursive: true);
    await staged.rename(ready.path);
    await recovery.reconcileAssessment(
      assessmentId: session.assessmentId,
      actorPersonId: actor,
    );
    media = (await db.select(db.evidenceMedia).get()).single;
    expect(media.storageState, DatabaseCodes.evidenceStorageReady);
    expect(await storage.exists(media.thumbnailLocalUri!), isTrue);
    // Thumbnail loss can be repaired repeatedly from the canonical image.
    await (await storage.resolve(media.thumbnailLocalUri!)).delete();
    await recovery.reconcileAssessment(
      assessmentId: session.assessmentId,
      actorPersonId: actor,
    );
    expect(await storage.exists(media.thumbnailLocalUri!), isTrue);
  });
  test('another account database cannot claim a pending capture', () async {
    final root = await Directory.systemTemp.createTemp(
      'wormwise-journal-isolation-',
    );
    final db = AppDatabase(NativeDatabase.memory());
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await other.close();
      await root.delete(recursive: true);
    });
    await daResultsFixture(db, recorded: 1);
    final session = (await db.select(db.evidenceCaptureSessions).get()).single;
    final actor =
        (await db.select(db.assessments).get()).single.evaluatorPersonId;
    final source = File('${root.path}/capture.jpg');
    await source.writeAsBytes(
      image.encodeJpg(image.Image(width: 32, height: 32)),
    );
    final storage = EvidenceStorageService(rootDirectory: () async => root);
    await db.customStatement(
      "CREATE TRIGGER reject_evidence BEFORE INSERT ON evidence_media BEGIN SELECT RAISE(ABORT, 'simulated crash'); END",
    );
    await expectLater(
      EvidenceCaptureCoordinator(
        repository: EvidenceCaptureRepository(db),
        storage: storage,
      ).stageCapture(
        session: session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        sourcePath: source.path,
        actorPersonId: actor,
      ),
      throwsA(anything),
    );
    final otherCoordinator = EvidenceCaptureCoordinator(
      repository: EvidenceCaptureRepository(other),
      storage: storage,
    );
    expect(await otherCoordinator.recoverPreparedCaptures(), 0);
    expect(await other.select(other.evidenceMedia).get(), isEmpty);
    expect(await storage.pendingCaptureJournals(null), hasLength(1));
    final journal = (await storage.pendingCaptureJournals(null)).single;
    final metadata =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    metadata['assessment_id'] = 'mismatched-assessment';
    await journal.writeAsString(jsonEncode(metadata));
    final originalCoordinator = EvidenceCaptureCoordinator(
      repository: EvidenceCaptureRepository(db),
      storage: storage,
    );
    expect(await originalCoordinator.recoverPreparedCaptures(), 1);
    expect(await db.select(db.evidenceMedia).get(), isEmpty);
    expect(await journal.exists(), isTrue);
  });
}
