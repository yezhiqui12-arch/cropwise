import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/models/da_assessment_results.dart';
import 'package:wormwise/models/expert_findings_report.dart';
import 'package:wormwise/screens/assess/expert_findings_export.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/services/expert_findings_pdf_export_service.dart';
import '../support/da_results_fixture.dart';

ExpertReviewCase review(
  String assessmentId, {
  bool finalized = true,
  int scored = 19,
  int insufficient = 1,
}) => ExpertReviewCase(
  id: 'EXAMPLE-CASE',
  assessmentId: assessmentId,
  fieldName: 'Corn plot',
  location: 'Aquib, Piat, Cagayan · EXAMPLE DATA',
  status: 'claimed',
  createdAt: DateTime.utc(2026, 10, 5),
  messages: [],
  expertName: 'Sample agriculturist',
  severitySummary: finalized
      ? ExpertSeveritySummary(
          reviewedPlants: scored + insufficient,
          scoredPlants: scored,
          insufficientPlants: insufficient,
          medianDavisScore: 3,
          finalizedAt: DateTime.utc(2026, 10, 7),
        )
      : null,
);
ExpertPlantRating rating(
  int plant,
  int? score, {
  String? block,
  bool ambiguous = false,
}) => ExpertPlantRating(
  stationNumber: plant,
  plantNumber: 1,
  blockRunId: block,
  davisScore: score,
  outcome: score == null ? 'insufficient_evidence' : 'scored',
  associationAmbiguous: ambiguous,
  note: plant == 7 ? 'Observed leaf damage; saved expert note.' : '',
  photos: [],
  damageFreshness: score == 0 ? null : 'fresh',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  test(
    'finalized review selection never uses a draft or unrelated case, and does not require closing',
    () {
      final finalized = review('a');
      expect(
        finalizedCaseForAssessment('a', [
          review('a', finalized: false),
          review('other'),
          finalized,
        ]),
        same(finalized),
      );
      expect(
        finalizedCaseForAssessment('a', [review('a', finalized: false)]),
        isNull,
      );
    },
  );
  test(
    'report mean includes zero; insufficient evidence is excluded, not scored zero',
    () async {
      final detail = await daResultsFixture(db);
      final r = ExpertFindingsReport(
        detail: detail,
        review: review(detail.assessment.id, scored: 3),
        ratings: [rating(1, 3), rating(2, 4), rating(3, 0), rating(4, null)],
      );
      expect(r.findings.mean, 7 / 3);
      expect(r.distribution[0], 1);
      expect(r.distribution[3], 1);
      expect(r.distribution[4], 1);
      expect(r.damageIncidence, 2 / 3 * 100);
      expect(r.findings.insufficientPlants, 1);
      expect(
        () => ExpertFindingsReport(
          detail: detail,
          review: review(detail.assessment.id, finalized: false),
          ratings: [],
        ),
        throwsStateError,
      );
      expect(
        () => ExpertFindingsReport(
          detail: detail,
          review: review('wrong'),
          ratings: [],
        ),
        throwsStateError,
      );
      expect(
        () => ExpertFindingsReport(
          detail: detail,
          review: review(detail.assessment.id, scored: 1, insufficient: 0),
          ratings: [rating(1, 3, ambiguous: true)],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'all-insufficient finalized findings can export without inventing a mean',
    () async {
      final detail = await daResultsFixture(db);
      final report = ExpertFindingsReport(
        detail: detail,
        review: review(detail.assessment.id, scored: 0, insufficient: 1),
        ratings: [rating(1, null)],
      );
      expect(report.findings.mean, isNull);
      expect(report.damageIncidence, isNull);
      expect(
        (await const ExpertFindingsPdfExportService().build(report)).length,
        greaterThan(1000),
      );
    },
  );
  test(
    'two-block production PDF retains plant identity and all 0–9 grades',
    () async {
      final original = await daResultsFixture(db);
      final second = [
        for (final s in original.stations)
          StationSnapshot(
            prepared: PreparedScoutingRun(
              block: s.prepared.block,
              run: s.prepared.run.copyWith(
                id: 'second-block',
                blockSequence: 2,
              ),
            ),
            stationNumber: s.stationNumber,
            station: s.station,
            plants: s.plants,
            reviewedAt: s.reviewedAt,
            reviewIsCurrent: s.reviewIsCurrent,
            requiredPlantCount: 1,
          ),
      ];
      final detail = AssessmentHistoryDetail(
        assessment: original.assessment,
        workspace: FieldWorkspaceRecord(
          field: original.workspace.field,
          boundary: original.workspace.boundary!.copyWith(areaHectares: 2),
          cropCycle: original.workspace.cropCycle,
        ),
        evaluator: original.evaluator,
        stations: [...original.stations, ...second],
        units: original.units,
        evidence: original.evidence,
        safety: original.safety,
        missingBlocks: 0,
        readiness: original.readiness,
        resultSummary: original.resultSummary,
      );
      final first = original.stations.first.prepared.run.id;
      final ratings = [
        for (var i = 1; i <= 20; i++)
          rating(i, i == 20 ? null : (i - 1) % 10, block: first),
        for (var i = 1; i <= 20; i++)
          rating(
            i,
            i == 20
                ? null
                : i == 7
                ? 8
                : (i - 1) % 10,
            block: 'second-block',
          ),
      ];
      final report = ExpertFindingsReport(
        detail: detail,
        review: review(detail.assessment.id, scored: 38, insufficient: 2),
        ratings: ratings,
      );
      expect(report.sample.expectedPlants, 40);
      expect(report.findings.ratingFor(report.sample.plants[6])!.davisScore, 6);
      expect(
        report.findings.ratingFor(report.sample.plants[26])!.davisScore,
        8,
      );
      final bytes = await const ExpertFindingsPdfExportService().build(report);
      expect(bytes.take(4), [37, 80, 68, 70]);
      final path = Platform.environment['WORMWISE_EXPERT_PDF_PREVIEW'];
      if (path != null) {
        await File(path).parent.create(recursive: true);
        await File(path).writeAsBytes(bytes);
      }
    },
  );
  test(
    'a changed grade cannot export under an older finalized histogram',
    () async {
      final detail = await daResultsFixture(db);
      final stale = ExpertReviewCase(
        id: 'stale',
        assessmentId: detail.assessment.id,
        fieldName: 'Corn plot',
        location: '',
        status: 'claimed',
        createdAt: DateTime.utc(2026, 10, 5),
        messages: [],
        severitySummary: ExpertSeveritySummary(
          reviewedPlants: 1,
          scoredPlants: 1,
          insufficientPlants: 0,
          medianDavisScore: 3,
          finalizedAt: DateTime.utc(2026, 10, 7),
          monitoring: const {
            'score_distribution': [0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
            'reviewer_name': 'Finalizing reviewer',
          },
        ),
      );
      final valid = ExpertFindingsReport(
        detail: detail,
        review: stale,
        ratings: [rating(1, 3)],
      );
      expect(valid.reviewerName, 'Finalizing reviewer');
      expect(
        () => ExpertFindingsReport(
          detail: detail,
          review: stale,
          ratings: [rating(1, 8)],
        ),
        throwsStateError,
      );
    },
  );
  testWidgets('DA and expert export gates are independent', (tester) async {
    var da = 0, expert = 0;
    Future<void> show(bool finished, bool finalized) async => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DaReportExportOptions(
            assessmentFinished: finished,
            expertFinalized: finalized,
            onDaExport: () => da++,
            onExpertExport: () => expert++,
          ),
        ),
      ),
    );
    await show(true, false);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('export_da_pdf_option')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('export_expert_pdf_option')))
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('export_expert_pdf_option')));
    expect(expert, 0);
    await tester.tap(find.byKey(const Key('export_da_pdf_option')));
    expect(da, 1);
    await show(false, true);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('export_da_pdf_option')))
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('export_expert_pdf_option')));
    expect(expert, 1);
  });
  test('unfinished assessment is not eligible for DA export', () async {
    expect(
      DaSampleResults.fromDetail(
        await daResultsFixture(db, recorded: 19),
      ).sampleComplete,
      isFalse,
    );
  });
}
