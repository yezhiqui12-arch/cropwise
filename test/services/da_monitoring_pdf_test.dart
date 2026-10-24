import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/advisor_model_results_reader.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/models/da_monitoring.dart';
import 'package:wormwise/services/da_monitoring_pdf_export_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/data/local/database_codes.dart';
import '../support/da_results_fixture.dart';
import '../models/da_monitoring_test.dart' show daTestModel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'evidence appendix groups views and retains missing-photo placeholders',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final original = await daResultsFixture(db);
      final folder = await Directory.systemTemp.createTemp('da-pdf-evidence-');
      addTearDown(() => folder.delete(recursive: true));
      await File(
        'assets/images/faw_actions/faw_leaf_damage.jpg',
      ).copy('${folder.path}/evidence.jpg');
      final now = DateTime.utc(2026, 10, 8, 2);
      EvidenceMediaRecord media(
        int n, {
        String? assessmentId,
        DateTime? deletedAt,
      }) => EvidenceMediaRecord(
        id: 'photo-$n',
        createdAt: now,
        updatedAt: now,
        deletedAt: deletedAt,
        syncState: 'local',
        serverVersion: 0,
        assessmentId: assessmentId ?? original.assessment.id,
        stationId: original.stations[n == 4 ? 1 : 0].station!.id,
        mediaType: 'image',
        localUri: n == 3 ? 'missing.jpg' : 'evidence.jpg',
        sha256Checksum: 'fixture',
        capturedAt: now,
        locationSource: 'not_recorded',
        qualityStatus: 'accepted',
        storageState: DatabaseCodes.evidenceStorageReady,
        uploadState: 'pending',
        isCanonicalEvidence: true,
      );
      AssessmentEvidenceEntry entry(EvidenceMediaRecord m) =>
          AssessmentEvidenceEntry(
            m,
            'Whorl overview',
            stationId: m.stationId,
            plantPosition: 1,
          );
      final photos = [for (var i = 0; i < 5; i++) entry(media(i))];
      final detail = AssessmentHistoryDetail(
        assessment: original.assessment,
        workspace: original.workspace,
        evaluator: original.evaluator,
        stations: original.stations,
        units: original.units,
        evidence: [
          ...photos,
          photos.first,
          entry(media(90, assessmentId: 'different-assessment')),
          entry(media(91, deletedAt: now)),
        ],
        safety: original.safety,
        missingBlocks: 0,
        readiness: original.readiness,
        resultSummary: original.resultSummary,
      );
      final bytes = await const DaMonitoringPdfExportService().build(
        detail: detail,
        record: DaMonitoringRecord(data: {}),
        models: const AdvisorModelResults([]),
        evidenceStorage: EvidenceStorageService(
          rootDirectory: () async => folder,
        ),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      final output = Platform.environment['WORMWISE_DA_EVIDENCE_PREVIEW'];
      if (output != null) await File(output).writeAsBytes(bytes);
    },
  );
  test(
    'DA PDF contains independent 20-plant blocks without expert review',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final original = await daResultsFixture(db);
      final second = original.stations
          .map(
            (s) => StationSnapshot(
              prepared: PreparedScoutingRun(
                block: s.prepared.block,
                run: s.prepared.run.copyWith(
                  id: 'second-block',
                  blockSequence: 2,
                ),
              ),
              stationNumber: s.stationNumber,
              station: s.station!.copyWith(
                id: 'second-${s.station!.id}',
                assessmentBlockRunId: 'second-block',
              ),
              plants: s.plants,
              reviewedAt: s.reviewedAt,
              reviewIsCurrent: s.reviewIsCurrent,
              requiredPlantCount: 1,
            ),
          )
          .toList();
      final detail = AssessmentHistoryDetail(
        assessment: original.assessment.copyWith(
          weatherContext: const Value(
            'open_meteo_precipitation_last_48h_mm=4.25;weather_period_end_utc=2026-10-07T00:00:00Z',
          ),
        ),
        workspace: original.workspace,
        evaluator: original.evaluator,
        stations: [...original.stations, ...second],
        units: original.units,
        evidence: original.evidence,
        safety: original.safety,
        missingBlocks: 0,
        readiness: original.readiness,
        resultSummary: original.resultSummary,
      );
      final firstBlock = detail.stations.first.prepared.run.id;
      final record = DaMonitoringRecord(
        data: {
          'fields': {
            'farmer': 'SAMPLE FARMER',
            'collector': 'Sample collector',
            'region': 'II',
            'province': 'Cagayan',
            'municipality': 'Piat',
            'barangay': 'Aquib',
            'field_id': 'SAMPLE-001',
            'land_tenure': 'Owner',
            'topography': 'Flat',
            'soil_texture': 'Not recorded',
            'previous_crop': 'Corn',
            'adjacent_crop': 'Corn',
            'planting_pattern': 'Rows',
            'planting_date': '01 Sep 2026',
            'planting_material_source': 'Sample seed supplier',
            'corn_type': 'Grain corn',
            'variety': 'Sample variety',
            'spacing': '25 cm x 75 cm',
            'fertilizer': 'Not recorded',
            'remarks': 'EXAMPLE DATA - not an actual field report.',
            'week': 3,
          },
          'blocks': {
            firstBlock: {
              'natural_enemies': ['predators'],
            },
            'second-block': {
              'natural_enemies': ['none'],
            },
          },
          'plants': {
            '$firstBlock:7': {
              'signature': '',
              'overrides': {'damage': true, 'pupa': false},
            },
            'second-block:7': {
              'signature': '',
              'overrides': {'damage': false, 'larva': false},
            },
          },
        },
      );
      final models = AdvisorModelResults([
        for (final s in detail.stations)
          AdvisorModelSample(
            stationId: s.station!.id,
            position: 1,
            images: const [],
            availability: s.stationNumber == 20 ? 'stale' : 'available',
            result: daTestModel(
              label: s.stationNumber <= 4 ? 'FAW damage' : 'No FAW damage',
              stage: s.stationNumber <= 4 ? 'overlay_complete' : 'overlay_off',
              boxes: s.stationNumber == 1
                  ? [3]
                  : s.stationNumber == 2
                  ? [2]
                  : [],
            ),
          ),
      ]);
      final bytes = await const DaMonitoringPdfExportService().build(
        detail: detail,
        record: record,
        models: models,
        includeCoordinates: true,
      );
      expect(bytes.length, greaterThan(3000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final path = Platform.environment['WORMWISE_DA_PDF_PREVIEW'];
      if (path != null) {
        await File(path).parent.create(recursive: true);
        await File(path).writeAsBytes(bytes);
      }
    },
  );
}
