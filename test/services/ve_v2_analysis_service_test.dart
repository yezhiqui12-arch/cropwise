import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/services/ve_v2_analysis_service.dart';

void main() {
  test(
    'current adapter reports unavailable without fabricated suggestions',
    () async {
      final now = DateTime.utc(2026, 8, 21);
      final bundle = EvidenceCaptureBundle(
        session: EvidenceCaptureSessionRecord(
          id: 'session-1',
          createdAt: now,
          updatedAt: now,
          syncState: DatabaseCodes.localOnly,
          serverVersion: 0,
          assessmentId: 'assessment-1',
          stationId: 'station-1',
          scopeType: DatabaseCodes.evidenceScopePlant,
          scopeKey: 'plant_01',
          plantPosition: 1,
          requirementsVersion:
              DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1,
          collectionMode: DatabaseCodes.evidenceCollectionCamera,
          collectionStatus: DatabaseCodes.evidenceSessionComplete,
          startedAt: now,
        ),
        media: const [],
      );

      final result = await const UnavailableVeV2AnalysisService()
          .presentationFor(bundle);

      expect(result.state, VeV2AnalysisState.unavailable);
      expect(result.suggestedLabels, isEmpty);
    },
  );
}
