import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/models/automatic_screening.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  const pipeline = 'WormWise-AutoScreen-v1:test';
  PlantDiagnosisResult result({
    String? stage = 'overlay_complete',
    String? label = 'FAW damage',
  }) => PlantDiagnosisResult(
    isInfested: false,
    pestLabel: 'screen',
    confidenceScore: .9,
    modelName: pipeline,
    classifierStage: stage,
    classificationLabel: label,
  );
  String cache(PlantDiagnosisResult r, {String signature = 'photos'}) =>
      jsonEncode({
        'signature': signature,
        'pipelineVersion': pipeline,
        'result': r.toJson(),
      });

  test('valid durable result survives a malformed or stale cache', () {
    final note = AutomaticScreening(
      result(),
      evidenceSignature: 'photos',
    ).encode();
    for (final value in ['{bad', cache(result(), signature: 'old')]) {
      final saved = AutomaticScreening.resolveSaved(
        note: note,
        cache: value,
        signature: 'photos',
        hasEvidence: true,
      );
      expect(saved?.screeningSucceeded, true);
      expect(saved?.result.classificationLabel, 'FAW damage');
    }
  });
  test('cache-only save recovers exact photos, not replacement photos', () {
    final value = cache(result());
    expect(
      AutomaticScreening.resolveSaved(
        note: null,
        cache: value,
        signature: 'photos',
        hasEvidence: true,
      )?.screeningSucceeded,
      true,
    );
    expect(
      AutomaticScreening.resolveSaved(
        note: null,
        cache: value,
        signature: 'changed',
        hasEvidence: true,
      ),
      isNull,
    );
    expect(
      AutomaticScreening.resolveSaved(
        note: null,
        cache: value,
        signature: 'photos',
        hasEvidence: false,
      ),
      isNull,
    );
  });
  test(
    'failure is not a reusable success; detector skipped is a saved screening',
    () {
      expect(AutomaticScreening(result(label: null)).processingComplete, false);
      expect(
        AutomaticScreening(
          result(stage: 'overlay_unavailable'),
        ).processingComplete,
        false,
      );
      expect(
        AutomaticScreening(result(stage: 'overlay_off')).processingComplete,
        true,
      );
      expect(
        AutomaticScreening(
          result(
            stage: 'Stage 1 (No FAW damage - Stage 2 not run)',
            label: 'No FAW damage',
          ),
        ).processingComplete,
        true,
      );
    },
  );
  test('multi-photo merge preserves detector failure for retry', () {
    final merged = PlantDiagnosisResult.merge([
      result(),
      result(stage: 'overlay_unavailable'),
    ]);
    expect(merged.classificationLabel, 'FAW damage');
    expect(merged.classifierStage, 'overlay_partial');
    expect(AutomaticScreening(merged).screeningSucceeded, true);
    expect(AutomaticScreening(merged).processingComplete, false);
  });
  test(
    'a legacy unsigned result is displayable but cannot validate a batch marker',
    () {
      final note = AutomaticScreening(result()).encode();
      expect(
        AutomaticScreening.resolveSaved(
          note: note,
          cache: null,
          signature: '',
          hasEvidence: false,
        ),
        isNotNull,
      );
      expect(
        AutomaticScreening.resolveSaved(
          note: note,
          cache: null,
          signature: 'photos',
          hasEvidence: true,
          allowLegacy: false,
        ),
        isNull,
      );
    },
  );
}
