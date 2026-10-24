import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/advisor_context_repository.dart';
import 'package:wormwise/services/advisor/advisor_assessment_explanation_service.dart';

void main() {
  const service = AdvisorAssessmentExplanationService();

  test(
    'completed explanation uses CV denominator and excludes legacy manual metrics',
    () {
      final answer = service.explainAssessment(_context(completed: true));
      final content = [answer.summary, ...answer.details].join(' ');

      expect(answer.title, 'Latest completed assessment');
      expect(content, contains('25 of 50 successfully screened plants'));
      expect(content, isNot(contains('Current infestation observations')));
      expect(content, contains('not a treatment recommendation'));
      expect(content, isNot(contains('old damage')));
      expect(content, contains('Recorded weather context'));
      expect(answer.source.version, contains('formula-v1'));
    },
  );

  test('incomplete explanation does not present progress as final results', () {
    final answer = service.explainAssessment(_context(completed: false));

    expect(answer.title, 'Assessment in progress');
    expect(answer.summary, contains('must not be interpreted as final'));
    expect(answer.nextAction, contains('complete'));
  });

  test('no selected field produces a safe setup response', () {
    final answer = service.explainAssessment(null);

    expect(answer.title, 'No maize field is selected');
    expect(answer.nextAction, contains('add or select'));
  });
}

AdvisorFieldContextSnapshot _context({required bool completed}) {
  return AdvisorFieldContextSnapshot(
    fieldId: 'field-1',
    fieldName: 'North Field',
    plantingDate: DateTime.utc(2026, 8, 1),
    hasConfirmedOutline: true,
    hasSeparateModelFindingProvenance: false,
    assessment: AdvisorAssessmentSnapshot(
      id: 'assessment-1',
      status: completed ? DatabaseCodes.completed : DatabaseCodes.inProgress,
      growthStage: 'v3_v6',
      growthStageUncertain: false,
      scoutingPattern: 'w_pattern',
      protocolVersion: 'protocol-v1',
      formulaVersion: 'formula-v1',
      totalBlocks: 1,
      completedBlocks: completed ? 1 : 0,
      stationRecords: completed ? 5 : 2,
      plantRecords: completed ? 50 : 17,
      assessablePlants: completed ? 50 : 17,
      evidencePhotoCount: 8,
      findingSummary: const {
        'automatic_damage_screen': {
          'positive_count': 25,
          'eligible_count': 50,
          'missing_result_count': 0,
          'stale_result_count': 0,
        },
      },
      weatherContext: 'No recent heavy rain reported.',
      metrics: [
        AdvisorMetricSnapshot(
          code: DatabaseCodes.vegetativeCurrentInfestationPercent,
          label: 'Current infestation observations',
          unit: 'percent',
          value: 50,
          numerator: 25,
          denominator: 50,
          formulaVersion: 'formula-v1',
          validationStatus: 'provisional',
          calculatedAt: DateTime.utc(2026, 9, 3),
          blockSequence: 1,
        ),
      ],
    ),
  );
}
