import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/advisor_context_repository.dart';
import 'package:wormwise/data/repositories/da_monitoring_repository.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/services/advisor/advisor_assessment_contract.dart';
import 'package:wormwise/services/advisor/assessment_result_ai_context.dart';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';
import 'package:wormwise/services/cloud/expert_damage_monitoring.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';
import '../support/da_results_fixture.dart';

Map<String, dynamic> finalized({
  bool ambiguous = false,
  bool freshness = true,
}) => {
  'cases': [
    {
      'status': 'reviewed',
      'severity': {
        ...expertDamageMonitoringFacts({
          'association_status': ambiguous ? 'ambiguous' : 'matched',
          'monitoring_version': freshness ? 2 : 1,
          'reviewed_plants': 20,
          'scored_plants': 20,
          'insufficient_plants': 0,
          'positive_plants': 5,
          'zero_damage_plants': 15,
          'fresh_plants': 2,
          'old_only_plants': 3,
          'score_distribution': [15, 0, 0, 5, 0, 0, 0, 0, 0, 0],
          'median_davis_score': 0,
        }),
        'finalized_at': '2026-10-07T10:00:00Z',
      },
    },
  ],
};

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'DA report corrections and natural enemies are supplied separately from CV output',
    () async {
      final detail = await daResultsFixture(
        db,
        positives: 4,
        infestationDetections: true,
      );
      final block = detail.stations.first.prepared.run.id;
      final monitoring = DaMonitoringRepository(db);
      await monitoring.saveEnemies(detail.assessment.id, block, ['predators']);
      await monitoring.saveCorrection(detail.assessment.id, block, 1, '', {
        'larva': false,
      });
      final reloaded = (await AssessmentHistoryRepository(
        db,
      ).loadDetail(detail.assessment.id))!;
      final facts = assessmentResultAiContext(reloaded);
      final plant = (facts['plants'] as List).first as Map;
      expect((plant['model_suggestions'] as Map)['larvae'], true);
      expect(
        ((plant['da_monitoring_observations'] as Map)['presence']
            as Map)['larva'],
        false,
      );
      expect((facts['sampled_infestation'] as Map)['infested_count'], 4);
      expect((facts['natural_enemies'] as List).single['observations'], [
        'predators',
      ]);
    },
  );

  test(
    'polling availability changes do not invalidate otherwise identical cached facts',
    () {
      final one = {
        'damage_screen': {'percent': 20},
        'expert_review': {'availability': 'loading'},
      };
      final two = {
        'damage_screen': {'percent': 20},
        'expert_review': {'availability': 'cached'},
      };
      expect(
        AdvisorAssessmentContract.stableFacts(one),
        AdvisorAssessmentContract.stableFacts(two),
      );
    },
  );

  test(
    'both AI contexts use DA plant numbering and separate screening from infestation',
    () async {
      final detail = await daResultsFixture(
        db,
        positives: 4,
        infestationDetections: true,
      );
      final result = assessmentResultAiContext(detail);
      final advisor = await AdvisorContextRepository(db)
          .read('get_assessment', {
            'field_id': detail.workspace.field.id,
            'assessment_id': detail.assessment.id,
          });
      expect((result['sampling'] as Map)['planned_plants'], 20);
      expect((advisor['sampling'] as Map)['planned_plants'], 20);
      expect((result['damage_screen'] as Map)['percent'], 20);
      expect((result['sampled_infestation'] as Map)['percent'], 20);
      expect(advisor['sampled_infestation'], result['sampled_infestation']);
      final plants = result['plants'] as List;
      expect(plants.last['plant_number'], 20);
      expect(plants.last['label'], 'Block 1 · Plant 20');
      final samples = await AdvisorContextRepository(
        db,
      ).read('get_assessment_samples', {'field_id': detail.workspace.field.id});
      expect((samples['plants'] as List).last['plant_number'], 20);
      expect((samples['plants'] as List).last['block_run_id'], isNotNull);
    },
  );

  test(
    'valid damage remains available when optional detection did not run',
    () async {
      final detail = await daResultsFixture(db, positives: 4);
      final facts = assessmentResultAiContext(detail);
      expect((facts['damage_screen'] as Map)['percent'], 20);
      expect((facts['sampled_infestation'] as Map)['percent'], isNull);
      expect(
        (facts['sampled_infestation'] as Map)['case_label'],
        'Unavailable',
      );
      expect((facts['sampled_infestation'] as Map)['unavailable_count'], 20);
      final plant = (facts['plants'] as List).first as Map;
      expect((plant['model_suggestions'] as Map)['larvae'], isNull);
    },
  );

  test(
    'partial sampling preserves actual denominator and unfinished planned coverage',
    () async {
      final detail = await daResultsFixture(
        db,
        recorded: 7,
        positives: 2,
        unavailable: 2,
        infestationDetections: true,
      );
      final facts = assessmentResultAiContext(detail);
      expect(facts['recorded_plants'], 7);
      expect((facts['damage_screen'] as Map)['eligible_count'], 5);
      expect((facts['damage_screen'] as Map)['percent'], 40);
      expect((facts['sampled_infestation'] as Map)['eligible_count'], 5);
      expect((facts['sampled_infestation'] as Map)['unavailable_count'], 15);
    },
  );

  test(
    'finalized expert overrides CV, uses mean including zeros rather than median',
    () async {
      final detail = await daResultsFixture(
        db,
        positives: 4,
        infestationDetections: true,
      );
      final review = finalized();
      final result = assessmentResultAiContext(detail, expertReview: review);
      final advisor = await AdvisorContextRepository(
        db,
        readExpertReview: (_) => review,
      ).read('get_assessment', {'field_id': detail.workspace.field.id});
      expect((result['model_sampled_infestation'] as Map)['percent'], 20);
      expect((result['sampled_infestation'] as Map)['percent'], 10);
      expect((result['sampled_infestation'] as Map)['provisional'], false);
      expect(
        (result['finalized_expert_findings'] as Map)['mean_davis_score'],
        .75,
      );
      expect(
        (result['finalized_expert_findings'] as Map)['median_davis_score'],
        0,
      );
      expect(advisor['sampled_infestation'], result['sampled_infestation']);
      final prompt = buildAssessmentResultAiPrompt(result);
      expect(prompt, contains('finalized_expert_findings'));
      expect(prompt, contains('mean_davis_score'));
      expect(prompt, isNot(contains('Frass, larvae and eggs: not assessed')));
    },
  );

  test(
    'missing or ambiguous finalized freshness never falls back to CV infestation',
    () async {
      final detail = await daResultsFixture(db, infestationDetections: true);
      for (final review in [
        finalized(freshness: false),
        finalized(ambiguous: true),
      ]) {
        final facts = assessmentResultAiContext(detail, expertReview: review);
        final infestation = facts['sampled_infestation'] as Map;
        expect(infestation['source'], 'finalized_expert_findings');
        expect(infestation['case_label'], 'Unavailable');
        expect(infestation['percent'], isNull);
      }
    },
  );

  test('latest finalized review wins over a later unfinished case', () {
    final review = finalized();
    (review['cases'] as List).add({
      'status': 'pending',
      'created_at': '2026-10-08',
    });
    expect(
      AdvisorAssessmentContract.finalized(review)!['mean_davis_score'],
      .75,
    );
  });

  test(
    'no scored grades cannot produce Davis zero from a median or empty distribution',
    () {
      final review = {
        'cases': [
          {
            'severity': {
              'scored_plants': 0,
              'median_davis_score': 0,
              'mean_davis_score': 0,
              'score_distribution': List.filled(10, 0),
              'finalized_at': '2026-10-07T10:00:00Z',
            },
          },
        ],
      };
      expect(
        AdvisorAssessmentContract.finalized(review)!['mean_davis_score'],
        isNull,
      );
    },
  );

  test(
    'current operational references are eligible for AI and contain no obsolete sampling instructions',
    () {
      final chunk = AdvisorRagService.chunks.firstWhere(
        (c) => c.id == 'scout-field',
      );
      expect(AdvisorRagService.isAiEligible(chunk), true);
      final prompt = buildAssessmentResultAiPrompt({
        'sampling': AdvisorAssessmentContract.sampling(
          ScoutingSamplingProtocol.daVersion,
          2,
        ),
      });
      expect(prompt, contains('20 different plants'));
      expect(prompt, contains('"planned_plants":40'));
      expect(jsonEncode(chunk.body), isNot(contains('five stations')));
      expect(jsonEncode(chunk.body), isNot(contains('ten consecutive')));
    },
  );
}
