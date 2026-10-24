import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/models/da_assessment_results.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import '../support/da_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  List<ExpertPlantRating> ratings(List<int> scores) => [
    for (var i = 0; i < scores.length; i++)
      ExpertPlantRating(
        stationNumber: i + 1,
        plantNumber: 1,
        outcome: 'scored',
        davisScore: scores[i],
        note: '',
        photos: const [],
      ),
  ];
  ExpertSeveritySummary summary(
    int count, {
    Map<String, dynamic> monitoring = const {},
  }) => ExpertSeveritySummary(
    reviewedPlants: count,
    scoredPlants: count,
    insufficientPlants: 0,
    medianDavisScore: 4,
    finalizedAt: DateTime.utc(2026, 10, 6),
    monitoring: monitoring,
  );

  Future<DaSampleResults> twoBlockSample() async {
    final detail = await daResultsFixture(db);
    final second = detail.stations
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
            station: s.station,
            plants: s.plants,
            reviewedAt: s.reviewedAt,
            reviewIsCurrent: s.reviewIsCurrent,
            requiredPlantCount: s.requiredPlantCount,
          ),
        )
        .toList();
    return DaSampleResults.fromDetail(
      AssessmentHistoryDetail(
        assessment: detail.assessment,
        workspace: FieldWorkspaceRecord(
          field: detail.workspace.field,
          boundary: detail.workspace.boundary!.copyWith(areaHectares: 2),
          cropCycle: detail.workspace.cropCycle,
        ),
        evaluator: detail.evaluator,
        stations: [...detail.stations, ...second],
        units: detail.units,
        evidence: detail.evidence,
        safety: detail.safety,
        missingBlocks: detail.missingBlocks,
        readiness: detail.readiness,
        resultSummary: detail.resultSummary,
      ),
    );
  }

  ExpertPlantRating blockRating(String block, int score) => ExpertPlantRating(
    stationNumber: 7,
    plantNumber: 1,
    blockRunId: block,
    outcome: 'scored',
    davisScore: score,
    note: '',
    photos: const [],
  );

  test(
    'same plant number in two blocks keeps its own score and counts once',
    () async {
      final sample = await twoBlockSample();
      final firstBlock = sample.plants.first.prepared.run.id;
      final expert = DaExpertResults.fromRatings(
        sample: sample,
        summary: summary(2),
        ratings: [blockRating(firstBlock, 3), blockRating('second-block', 8)],
      );
      expect(sample.expectedPlants, 40);
      expect(sample.plants, hasLength(40));
      expect(expert.available, isTrue);
      expect(expert.mean, 5.5);
      expect(expert.ratingFor(sample.plants[6])!.davisScore, 3);
      expect(expert.ratingFor(sample.plants[26])!.davisScore, 8);
    },
  );

  test(
    'unscoped, wrong-block and duplicate block ratings cannot publish a mean',
    () async {
      final sample = await twoBlockSample();
      final block = sample.plants.first.prepared.run.id;
      for (final invalid in [
        [
          const ExpertPlantRating(
            stationNumber: 7,
            plantNumber: 1,
            outcome: 'scored',
            davisScore: 3,
            note: '',
            photos: [],
          ),
          blockRating('second-block', 8),
        ],
        [blockRating('wrong-block', 3), blockRating('second-block', 8)],
        [blockRating(block, 3), blockRating(block, 8)],
      ]) {
        final expert = DaExpertResults.fromRatings(
          sample: sample,
          summary: summary(2),
          ratings: invalid,
        );
        expect(expert.available, isFalse);
        expect(expert.mean, isNull);
        expect(expert.byLocation, isEmpty);
      }
    },
  );

  test('four positive plants out of twenty are 20 percent', () async {
    final sample = DaSampleResults.fromDetail(await daResultsFixture(db));
    expect(sample.expectedPlants, 20);
    expect(sample.recordedPlants, 20);
    expect(sample.savedPlants, 20);
    expect(sample.sampleComplete, isTrue);
    expect(sample.screeningPercent, 20);
  });
  test(
    'three photos of one plant do not inflate plant counts and missing files are excluded from photos',
    () async {
      final detail = await daResultsFixture(db);
      final first = detail.stations.first;
      for (var i = 0; i < 5; i++) {
        await db
            .into(db.evidenceMedia)
            .insert(
              EvidenceMediaCompanion.insert(
                id: 'photo-$i',
                assessmentId: detail.assessment.id,
                stationId: Value(first.station!.id),
                plantObservationId: Value(first.plants.single.plant.id),
                mediaType: 'image',
                localUri: 'unused-$i.jpg',
                sha256Checksum: 'test-$i',
                storageState: Value(i == 3 ? 'missing' : 'ready'),
                deletedAt: Value(i == 4 ? DateTime.now().toUtc() : null),
              ),
            );
      }
      final sample = DaSampleResults.fromDetail(
        (await AssessmentHistoryRepository(
          db,
        ).loadDetail(detail.assessment.id))!,
      );
      expect(sample.photos(sample.plants.first), hasLength(3));
      expect(sample.recordedPlants, 20);
      expect(sample.positivePlants, 4);
      expect(sample.screeningPercent, 20);
    },
  );
  test(
    'unavailable screens are excluded and missing plants are not negative',
    () async {
      final sample = DaSampleResults.fromDetail(
        await daResultsFixture(db, recorded: 10, positives: 4, unavailable: 2),
      );
      expect(sample.assessablePlants, 8);
      expect(sample.unavailablePlants, 2);
      expect(sample.remainingPlants, 10);
      expect(sample.screeningPercent, 50);
      expect(sample.sampleComplete, isFalse);
    },
  );
  test(
    'all unavailable results produce no rate rather than zero percent',
    () async {
      final sample = DaSampleResults.fromDetail(
        await daResultsFixture(db, positives: 0, unavailable: 20),
      );
      expect(sample.screeningPercent, isNull);
      expect(sample.unavailablePlants, 20);
    },
  );
  test(
    'Davis average includes zero and uses actual ratings rather than saved median',
    () async {
      final sample = DaSampleResults.fromDetail(await daResultsFixture(db));
      final expert = DaExpertResults.fromRatings(
        sample: sample,
        summary: summary(3),
        ratings: ratings([3, 4, 0]),
      );
      expect(expert.available, isTrue);
      expect(expert.mean, closeTo(7 / 3, .0001));
      expect(expert.scoredPlants, 3);
      expect(expert.ratingFor(sample.plants[2])!.davisScore, 0);
    },
  );
  test(
    'incomplete, invalid, duplicate, or ambiguous finalized ratings have no average',
    () async {
      final sample = DaSampleResults.fromDetail(await daResultsFixture(db));
      for (final invalid in [
        ratings([3, 4]),
        ratings([3, 4, 10]),
        [
          ratings([3]).single,
          ratings([4]).single,
          ratings([0]).single,
        ],
      ]) {
        expect(
          DaExpertResults.fromRatings(
            sample: sample,
            summary: summary(3),
            ratings: invalid,
          ).mean,
          isNull,
        );
      }
      expect(
        DaExpertResults.fromRatings(
          sample: sample,
          summary: summary(3, monitoring: {'association_status': 'ambiguous'}),
          ratings: ratings([3, 4, 0]),
        ).available,
        isFalse,
      );
    },
  );
  test(
    'insufficient evidence is excluded while zero-rated plants still contribute',
    () async {
      final sample = DaSampleResults.fromDetail(await daResultsFixture(db));
      final expert = DaExpertResults.fromRatings(
        sample: sample,
        summary: ExpertSeveritySummary(
          reviewedPlants: 4,
          scoredPlants: 3,
          insufficientPlants: 1,
          medianDavisScore: 3,
          finalizedAt: DateTime.now().toUtc(),
        ),
        ratings: [
          ...ratings([3, 4, 0]),
          const ExpertPlantRating(
            stationNumber: 4,
            plantNumber: 1,
            outcome: 'insufficient_evidence',
            davisScore: null,
            note: '',
            photos: [],
          ),
        ],
      );
      expect(expert.available, isTrue);
      expect(expert.mean, closeTo(7 / 3, .0001));
      expect(expert.insufficientPlants, 1);
    },
  );
}
