import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/services/field_retention_service.dart';

void main() {
  test('expired deleted field removes files and retains tombstones', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final fields = FieldRepository(database);
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Temporary Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.8,
      boundarySourceMethod: 'draw',
      boundaryConfirmationStatus: 'user_confirmed',
    );
    final person = await PeopleRepository(
      database,
    ).findOrCreateEvaluator('Tester');
    final assessments = AssessmentRepository(database);
    final assessment = await assessments.createDraft(
      cropCycleId: created.cropCycle.id,
      boundaryVersionId: created.boundary.id,
      evaluatorPersonId: person.id,
      assessmentMode: DatabaseCodes.modeVeV6,
      scoutingPattern: DatabaseCodes.patternW,
      growthStage: 'v3_v6',
      protocolVersion: 'test',
      formulaVersion: 'test',
    );
    final block = await fields.addBlock(
      cropCycleId: created.cropCycle.id,
      boundaryVersionId: created.boundary.id,
      blockNumber: 1,
      geometryGeojson: created.boundary.geometryGeojson,
      areaHectares: 0.8,
    );
    final run = await assessments.addBlockRun(
      assessmentId: assessment.id,
      fieldBlockId: block.id,
      blockSequence: 1,
      scoutingPattern: DatabaseCodes.patternW,
    );
    final station = await assessments.addStation(
      assessmentBlockRunId: run.id,
      stationNumber: 1,
    );
    final session = await EvidenceCaptureRepository(database)
        .ensureStationContextSession(
          assessmentId: assessment.id,
          stationId: station.id,
          actorPersonId: person.id,
        );

    final root = await Directory.systemTemp.createTemp('wormwise_retention_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      await database.close();
    });
    const localUri = 'assessment/station/context/ready/photo.jpg';
    const thumbUri = 'assessment/station/context/ready/photo_thumb.jpg';
    for (final uri in [localUri, thumbUri]) {
      final file = _file(root, uri);
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
    }
    await database
        .into(database.evidenceMedia)
        .insert(
          EvidenceMediaCompanion.insert(
            id: 'media-1',
            assessmentId: assessment.id,
            stationId: Value(station.id),
            captureSessionId: Value(session.id),
            mediaType: 'image/jpeg',
            viewType: const Value(DatabaseCodes.evidenceViewStationContext),
            localUri: localUri,
            thumbnailLocalUri: const Value(thumbUri),
            sha256Checksum: 'checksum-kept-for-audit',
            storageState: const Value(DatabaseCodes.evidenceStorageReady),
          ),
        );

    await fields.setFieldArchived(fieldId: created.field.id, archived: true);
    final now = DateTime.utc(2026, 8, 26);
    await (database.update(
      database.fields,
    )..where((row) => row.id.equals(created.field.id))).write(
      FieldsCompanion(updatedAt: Value(now.subtract(const Duration(days: 31)))),
    );

    final purged = await FieldRetentionService(
      fields,
      evidenceStorage: EvidenceStorageService(rootDirectory: () async => root),
    ).purgeExpired(nowUtc: now);

    expect(purged, 1);
    expect(await _file(root, localUri).exists(), isFalse);
    final field = await (database.select(
      database.fields,
    )..where((row) => row.id.equals(created.field.id))).getSingle();
    expect(field.deletedAt, isNotNull);
    final media = await database.select(database.evidenceMedia).getSingle();
    expect(media.deletedAt, isNotNull);
    expect(media.sha256Checksum, 'checksum-kept-for-audit');
  });
}

File _file(Directory root, String relative) => File(
  '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
);
