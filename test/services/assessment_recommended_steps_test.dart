import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/assessment_recommended_steps.dart';

void main() {
  Map<String, dynamic> facts() => {
    'growth_stage': 'v3_v6',
    'remaining_plants': 0,
    'sampling_complete': true,
    'sampled_infestation': {'unavailable_count': 0, 'percent': 5},
    'plants': [
      {
        'reference': 'B2-S7',
        'damage_screen': 'FAW damage',
        'model_suggestions': {'larvae': true, 'eggs': true, 'frass': false},
      },
      {
        'reference': 'B2-S8',
        'damage_screen': 'Unavailable',
        'model_suggestions': {},
      },
    ],
  };
  test('sign checks use the actual plant identity and stay provisional', () {
    final steps = recommendedAssessmentChecks(facts(), entryBlocked: false);
    final larvae = steps.singleWhere(
      (s) => s.title == 'Verify potential larvae',
    );
    expect(larvae.references, ['B2-S7']);
    expect(steps.any((s) => s.title == 'Verify potential frass'), false);
    expect(
      steps.any((s) => s.title == 'Check unavailable plant evidence'),
      true,
    );
    expect(readableAssessmentReferences('B2-S7'), 'Block 2 · Plant 7');
  });
  test('finalized expert findings supersede model sign follow-ups', () {
    final data = facts()
      ..['finalized_expert_findings'] = {
        'mean_davis_score': 0,
        'insufficient_plants': 0,
      }
      ..['sampled_infestation'] = {'unavailable_count': 0, 'percent': 0};
    final steps = recommendedAssessmentChecks(data, entryBlocked: false);
    expect(steps.any((s) => s.title.startsWith('Verify potential')), false);
    expect(
      steps.any((s) => s.title == 'Compare screening with the expert review'),
      true,
    );
  });
  test('pending expert review keeps screening-based steps available', () {
    final data = facts()
      ..['finalized_expert_findings'] = null
      ..['expert_review'] = {
        'cases': [
          {'status': 'awaiting_review', 'severity': null},
        ],
      };
    final steps = recommendedAssessmentChecks(data, entryBlocked: false);
    expect(
      steps.any((s) => s.title == 'Review the damage flagged by the app'),
      true,
    );
    expect(steps.any((s) => s.title == 'Verify potential larvae'), true);
    expect(
      steps.any((s) => s.title == 'Check your expert review and messages'),
      true,
    );
  });
  test('missing photos remain visible when a screening result was saved', () {
    final data = facts();
    (data['plants'] as List).first['photo_count'] = 0;
    final steps = recommendedAssessmentChecks(data, entryBlocked: false);
    final missing = steps.singleWhere(
      (s) => s.title == 'Check missing plant photos',
    );
    expect(missing.references, ['B2-S7']);
    expect(missing.description, contains('new capture date'));
  });
  test(
    'unconfirmed entry safety permits saved-photo checks but no field visit',
    () {
      final steps = recommendedAssessmentChecks(facts(), entryBlocked: true);
      expect(steps.first.type, 'safety_review');
      expect(steps.any((s) => s.type == 'field_monitoring'), false);
      expect(steps.any((s) => s.type == 'review_evidence'), true);
    },
  );
  test(
    'completed zero-damage sample still has useful baseline and review steps',
    () {
      final data = facts()..['plants'] = [];
      final steps = recommendedAssessmentChecks(data, entryBlocked: false);
      expect(
        steps.map((s) => s.type),
        containsAll(['expert_review', 'field_monitoring']),
      );
      expect(steps.last.description, contains('newest leaves and whorl'));
    },
  );
}
