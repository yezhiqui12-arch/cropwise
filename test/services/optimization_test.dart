import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/cloud/wormwise_account_backup_service.dart';
import 'package:wormwise/services/startup/app_startup.dart';

import '../support/assessment_history_fixture.dart';
import '../support/da_results_fixture.dart';

void main() {
  test(
    'background snapshot encoding preserves payload and fingerprint',
    () async {
      final payload = <String, dynamic>{
        'format_version': 2,
        'owner_id': 'owner',
        'tables': {
          'fields': [
            {'id': 'field', 'name': 'Mais 🌽', 'area': 1.25},
          ],
        },
        'media_complete': false,
      };
      final encoded = await compute(compressSnapshot, payload);
      expect(jsonDecode(utf8.decode(gzip.decode(encoded))), payload);
      expect(
        await compute(snapshotFingerprint, payload),
        sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
      );
    },
  );

  test(
    'startup only selects assessments with unresolved media transitions',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await daResultsFixture(db, recorded: 1);
      final assessment = (await db.select(db.assessments).get()).single;
      await db.customStatement(
        'INSERT INTO evidence_media '
        '(id, created_at, updated_at, assessment_id, media_type, local_uri, sha256_checksum) '
        "VALUES ('photo', 0, 0, ?, 'image', 'photo.jpg', 'checksum')",
        [assessment.id],
      );
      await historyFixture(db, name: 'No photographs');
      await db.customStatement(
        "UPDATE evidence_media SET storage_state='ready'",
      );
      expect(await assessmentsNeedingEvidenceRecovery(db), isEmpty);
      for (final state in [
        'staged',
        'missing',
        'deletion_pending',
        'unknown',
      ]) {
        await db.customStatement('UPDATE evidence_media SET storage_state=?', [
          state,
        ]);
        final pending = await assessmentsNeedingEvidenceRecovery(db);
        expect(pending, hasLength(1));
        expect(
          pending.single.id,
          (await db.select(db.evidenceMedia).get()).first.assessmentId,
        );
      }
      await db.customStatement(
        "UPDATE evidence_media SET storage_state='deleted'",
      );
      expect(await assessmentsNeedingEvidenceRecovery(db), isEmpty);
    },
  );

  test(
    'v8 upgrade preserves records and indexes accelerate evidence lookup',
    () async {
      final dir = await Directory.systemTemp.createTemp('wormwise-index-');
      final file = File('${dir.path}/records.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final fixture = await historyFixture(db);
        // Simulate the v8 schema: identical tables, without the v9 indexes.
        final indexes = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='index' AND sql LIKE 'CREATE INDEX%'",
            )
            .get();
        for (final index in indexes) {
          await db.customStatement(
            'DROP INDEX "${index.read<String>('name')}"',
          );
        }
        await db.customStatement('PRAGMA user_version=8');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await db.select(db.assessments).get()).single.id,
          fixture.assessment.id,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          9,
        );
        final plan = await db
            .customSelect(
              "EXPLAIN QUERY PLAN SELECT * FROM evidence_media WHERE assessment_id='a' AND storage_state='ready' AND deleted_at IS NULL",
            )
            .get();
        expect(
          plan.map((r) => r.data.toString()).join(),
          contains('evidence_assessment_state_idx'),
        );
        final freshPlan = await db
            .customSelect(
          "EXPLAIN QUERY PLAN SELECT assessment_id FROM evidence_media INDEXED BY evidence_pending_recovery_idx WHERE storage_state NOT IN ('ready','deleted')",
            )
            .get();
        expect(
          freshPlan.map((r) => r.data.toString()).join(),
          contains('evidence_pending_recovery_idx'),
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
