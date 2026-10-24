import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/cloud/wormwise_account_backup_service.dart';

void main() {
  test(
    'explicit save copies guest fields into account and keeps guest view',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon-key');
      final directory = await Directory.systemTemp.createTemp(
        'wormwise-transfer-',
      );
      try {
        final backup = WormWiseAccountBackupService(
          database,
          client,
          localViewDirectory: directory,
        );
        await database.customStatement(
          'INSERT INTO fields (id, name) VALUES (?, ?)',
          ['guest-field', 'Guest field'],
        );
        await database.customStatement(
          'INSERT INTO people (id, display_name) VALUES (?, ?)',
          ['guest-person', 'Guest farmer'],
        );
        await database.customStatement(
          'INSERT INTO crop_cycles (id, field_id) VALUES (?, ?)',
          ['guest-cycle', 'guest-field'],
        );
        await database.customStatement(
          'INSERT INTO field_boundary_versions (id, field_id, version_number, geometry_geojson, source_method, area_hectares) VALUES (?, ?, ?, ?, ?, ?)',
          ['guest-boundary', 'guest-field', 1, '{}', 'reported_area_only', 1.0],
        );
        await database.customStatement(
          'INSERT INTO assessments (id, crop_cycle_id, boundary_version_id, evaluator_person_id, assessment_mode, scouting_pattern, growth_stage, protocol_version, formula_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'guest-assessment',
            'guest-cycle',
            'guest-boundary',
            'guest-person',
            'formal',
            'five_station',
            'vegetative',
            '1',
            '1',
          ],
        );

        await backup.beginGuestTransfer();
        await backup.prepareAccountView('saved-account');
        expect(
          (await database.select(database.fields).get()).single.id,
          'guest-field',
        );
        expect(
          (await database.select(database.assessments).get()).single.id,
          'guest-assessment',
        );
        await backup.prepareGuestView();
        expect(
          (await database.select(database.fields).get()).single.id,
          'guest-field',
        );
        expect(
          (await database.select(database.assessments).get()).single.id,
          'guest-assessment',
        );
      } finally {
        await database.close();
        client.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'new account stays empty and guest records return on guest switch',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon-key');
      final directory = await Directory.systemTemp.createTemp(
        'wormwise-views-',
      );
      try {
        final backup = WormWiseAccountBackupService(
          database,
          client,
          localViewDirectory: directory,
        );
        await database.customStatement(
          'INSERT INTO fields (id, name) VALUES (?, ?)',
          ['guest-field', 'Guest field'],
        );

        await backup.prepareAccountView('new-account');
        expect(await database.select(database.fields).get(), isEmpty);
        await database.customStatement(
          'INSERT INTO fields (id, name) VALUES (?, ?)',
          ['account-field', 'Account field'],
        );

        await backup.prepareGuestView();
        expect(
          (await database.select(database.fields).get()).single.id,
          'guest-field',
        );
        await backup.prepareAccountView('new-account');
        expect(
          (await database.select(database.fields).get()).single.id,
          'account-field',
        );
      } finally {
        await database.close();
        client.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'account snapshot restores guest field records on another database',
    () async {
      final source = AppDatabase(NativeDatabase.memory());
      final destination = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon-key');
      try {
        await source.customStatement(
          'INSERT INTO people (id, display_name) VALUES (?, ?)',
          ['guest-person', 'Guest farmer'],
        );
        await source.customStatement(
          'INSERT INTO fields (id, owner_person_id, name) VALUES (?, ?, ?)',
          ['guest-field', 'guest-person', 'North field'],
        );
        final sourceBackup = WormWiseAccountBackupService(source, client);
        final destinationBackup = WormWiseAccountBackupService(
          destination,
          client,
        );
        final snapshot =
            jsonDecode(
                  utf8.decode(
                    gzip.decode(
                      gzip.encode(
                        utf8.encode(
                          jsonEncode(await sourceBackup.exportLocalTables()),
                        ),
                      ),
                    ),
                  ),
                )
                as Map;

        await destinationBackup.restoreLocalTables(snapshot);
        await destinationBackup.restoreLocalTables(snapshot);

        final people = await destination.select(destination.people).get();
        final fields = await destination.select(destination.fields).get();
        expect(people, hasLength(1));
        expect(fields, hasLength(1));
        expect(fields.single.ownerPersonId, 'guest-person');
        expect(fields.single.name, 'North field');
      } finally {
        await source.close();
        await destination.close();
        client.dispose();
      }
    },
  );

  test(
    'linked guest cloud rows rebuild the field and assessment graph',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon-key');
      try {
        final backup = WormWiseAccountBackupService(database, client);
        await backup.restoreLinkedGuestCloudRecords([
          {
            'guest_id': 'guest-id',
            'fields': [
              {
                'id': 'field-id',
                'name': 'Recovered field',
                'status': 'active',
                'created_at': '2026-09-20T00:00:00Z',
                'updated_at': '2026-09-20T00:00:00Z',
              },
            ],
            'boundaries': [
              {
                'id': 'boundary-id',
                'field_id': 'field-id',
                'version_number': 1,
                'geometry_geojson': {'type': 'Polygon', 'coordinates': []},
                'area_hectares': 1.0,
                'source_method': 'draw',
                'created_at': '2026-09-20T00:00:00Z',
                'updated_at': '2026-09-20T00:00:00Z',
              },
            ],
            'assessments': [
              {
                'id': 'assessment-id',
                'field_id': 'field-id',
                'boundary_id': 'boundary-id',
                'status': 'completed',
                'growth_stage': 'vegetative',
                'protocol_version': 'v1',
                'formula_version': 'v1',
                'created_at': '2026-09-20T00:00:00Z',
                'updated_at': '2026-09-20T00:00:00Z',
              },
            ],
            'stations': [
              {
                'id': 'station-id',
                'assessment_id': 'assessment-id',
                'station_number': 1,
              },
            ],
            'evidence': <Map<String, dynamic>>[],
          },
        ]);
        expect(await database.select(database.fields).get(), hasLength(1));
        expect(await database.select(database.assessments).get(), hasLength(1));
        expect(await database.select(database.stations).get(), hasLength(1));
        final activeField =
            await (database.select(database.appPreferences)
                  ..where((row) => row.preferenceKey.equals('active_field_id')))
                .getSingle();
        expect(activeField.preferenceValue, 'field-id');
      } finally {
        await database.close();
        client.dispose();
      }
    },
  );
}
