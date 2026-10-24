import 'dart:convert';
import 'dart:ui' show Offset, Rect;
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/models/assessment_map_data.dart';
import '../support/da_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  AssessmentHistoryDetail replace(
    AssessmentHistoryDetail d,
    List<StationSnapshot> stations,
  ) => AssessmentHistoryDetail(
    assessment: d.assessment,
    workspace: d.workspace,
    evaluator: d.evaluator,
    stations: stations,
    units: d.units,
    evidence: d.evidence,
    safety: d.safety,
    missingBlocks: d.missingBlocks,
    readiness: d.readiness,
    resultSummary: d.resultSummary,
  );
  StationSnapshot position(
    StationSnapshot s, {
    double? plantLat,
    double? stationLat,
    String? runId,
    int? block,
  }) => StationSnapshot(
    prepared: PreparedScoutingRun(
      block: s.prepared.block,
      run: s.prepared.run.copyWith(
        id: runId,
        blockSequence: block,
        routeGeojson: Value(
          jsonEncode({
            'features': [
              {
                'properties': {
                  'feature_type': 'station_target',
                  'station_number': s.stationNumber,
                },
                'geometry': {
                  'coordinates': [121.0005, 17.0005],
                },
              },
            ],
          }),
        ),
      ),
    ),
    stationNumber: s.stationNumber,
    station: s.station!.copyWith(
      locationSource: 'phone_gps',
      latitude: Value(stationLat),
      longitude: const Value(121.0003),
    ),
    plants: [
      StationPlantRecord(
        plant: s.plants.single.plant.copyWith(
          locationSource: 'phone_gps',
          latitude: Value(plantLat),
          longitude: const Value(121.0004),
        ),
        vegetative: s.plants.single.vegetativeOrNull,
      ),
    ],
    reviewedAt: s.reviewedAt,
    reviewIsCurrent: s.reviewIsCurrent,
    requiredPlantCount: s.requiredPlantCount,
  );
  test('scouting pin stays fixed despite plant or station photo GPS', () async {
    final detail = await daResultsFixture(db);
    final first = detail.stations.first;
    var data = AssessmentMapData(
      replace(detail, [
        position(first, plantLat: 17.0004, stationLat: 17.0003),
      ]),
    );
    expect(data.points.single.location, const LatLng(17.0005, 121.0005));
    expect(data.points.single.locationLabel, 'Scouting pin');
    data = AssessmentMapData(
      replace(detail, [position(first, plantLat: 99, stationLat: 17.0003)]),
    );
    expect(data.points.single.location, const LatLng(17.0005, 121.0005));
    data = AssessmentMapData(
      replace(detail, [position(first, plantLat: 99, stationLat: 99)]),
    );
    expect(data.points.single.location, data.points.single.planned);
    expect(data.points.single.planned, isNotNull);
  });
  test('missing scouting pin never falls back to valid photo GPS', () async {
    final detail = await daResultsFixture(db);
    final original = position(
      detail.stations.first,
      plantLat: 17.0004,
      stationLat: 17.0003,
    );
    final withoutRoute = StationSnapshot(
      prepared: PreparedScoutingRun(
        block: original.prepared.block,
        run: original.prepared.run.copyWith(routeGeojson: const Value(null)),
      ),
      stationNumber: original.stationNumber,
      station: original.station,
      plants: original.plants,
      reviewedAt: original.reviewedAt,
      reviewIsCurrent: original.reviewIsCurrent,
      requiredPlantCount: original.requiredPlantCount,
    );
    final data = AssessmentMapData(replace(detail, [withoutRoute]));
    expect(data.points.single.location, isNull);
    expect(data.mappedCount, 0);
    expect(data.unlocatedCount, 1);
  });
  test(
    'same plant number in different blocks stays distinct and overlap grouping preserves coordinates',
    () async {
      final detail = await daResultsFixture(db);
      final first = detail.stations.first;
      final data = AssessmentMapData(
        replace(detail, [
          position(first, plantLat: 17.0004, stationLat: 17.0003),
          position(
            first,
            plantLat: 17.0004,
            stationLat: 17.0003,
            runId: 'second',
            block: 2,
          ),
        ]),
      );
      expect(data.points.map((p) => p.id).toSet(), hasLength(2));
      expect(data.points.last.label, 'Block 2 · Plant 1');
      final locations = data.points.map((p) => p.location).toList();
      final grouped = groupAssessmentMapPoints(data.points, (_) => Offset.zero);
      expect(grouped, hasLength(1));
      expect(grouped.single, hasLength(2));
      expect(data.points.map((p) => p.location), locations);
    },
  );
  test('malformed or out-of-range route data never creates a map point', () {
    expect(AssessmentMapData.samplingTarget('{bad', 1), isNull);
    final route = jsonEncode({
      'features': [
        {
          'properties': {'feature_type': 'station_target', 'station_number': 1},
          'geometry': {
            'coordinates': [181, 17],
          },
        },
      ],
    });
    expect(AssessmentMapData.samplingTarget(route, 1), isNull);
  });

  test('a chain of nearby locations stays in compact groups', () async {
    final detail = await daResultsFixture(db);
    final points = [
      for (var i = 0; i < 3; i++)
        AssessmentMapPoint(
          station: detail.stations[i],
          record: null,
          planned: LatLng(17, 121 + i * .001),
          damage: null,
        ),
    ];
    final groups = groupAssessmentMapPoints(
      points,
      (location) => Offset((location.longitude - 121) * 40000, 0),
    );
    expect(groups.map((g) => g.length), [2, 1]);
  });
  test(
    'overview separates identical GPS labels and keeps them in the viewport',
    () {
      final anchors = List.filled(20, const Offset(28, 220));
      const bounds = Rect.fromLTRB(20, 112, 340, 460);
      final labels = layoutAssessmentMapPins(anchors, bounds);
      expect(labels, hasLength(20));
      expect(anchors.every((p) => p == const Offset(28, 220)), isTrue);
      for (var i = 0; i < labels.length; i++) {
        expect(labels[i].dx, inInclusiveRange(bounds.left, bounds.right));
        expect(labels[i].dy, inInclusiveRange(bounds.top, bounds.bottom));
        for (var j = i + 1; j < labels.length; j++) {
          expect(
            (labels[i].dx - labels[j].dx).abs() >= 33.99 ||
                (labels[i].dy - labels[j].dy).abs() >= 37.99,
            isTrue,
          );
        }
      }
      expect(layoutAssessmentMapPins(anchors, bounds), labels);
    },
  );
}
