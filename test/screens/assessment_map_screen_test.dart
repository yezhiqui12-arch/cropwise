import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/models/assessment_map_data.dart';
import 'package:wormwise/screens/assess/assessment_map_screen.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import '../support/da_results_fixture.dart';

void main() {
  late AppDatabase db;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  ExpertReviewCase review(
    AssessmentHistoryDetail detail, {
    String id = 'review',
  }) => ExpertReviewCase(
    id: id,
    assessmentId: detail.assessment.id,
    fieldName: 'Corn plot',
    location: '',
    status: 'reviewed',
    createdAt: DateTime.utc(2026, 10, 7),
    messages: const [],
    severitySummary: ExpertSeveritySummary(
      reviewedPlants: 3,
      scoredPlants: 3,
      insufficientPlants: 0,
      medianDavisScore: 3,
      finalizedAt: DateTime.utc(2026, 10, 7),
    ),
  );
  List<ExpertPlantRating> ratings(AssessmentHistoryDetail detail) => [
    for (var i = 0; i < 3; i++)
      ExpertPlantRating(
        blockRunId: detail.stations.first.prepared.run.id,
        stationNumber: i + 1,
        plantNumber: 1,
        outcome: 'scored',
        davisScore: [3, 4, 0][i],
        damageFreshness: i == 0 ? 'fresh' : 'old_only',
        note: '',
        photos: const [],
      ),
  ];
  Future<void> open(
    WidgetTester tester,
    AssessmentHistoryDetail detail, {
    double scale = 1,
    ExpertReviewCase? expert,
    Future<List<ExpertPlantRating>> Function()? load,
  }) async {
    tester.view.physicalSize = const Size(360, 804);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AssessmentMapScreen(
          detail: detail,
          storage: EvidenceStorageService(),
          showMapTiles: false,
          reviewCase: expert,
          loadRatings: load,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> layer(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('assessment_map_layers')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('map_layer_$name')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(ValueKey('map_layer_$name')));
    await tester.scrollUntilVisible(
      find.text('Done'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  PreparedScoutingRun withPin(
    StationSnapshot station,
    double lat,
    double lon,
  ) => PreparedScoutingRun(
    block: station.prepared.block,
    run: station.prepared.run.copyWith(
      routeGeojson: Value(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': {
                'feature_type': 'station_target',
                'station_number': station.stationNumber,
              },
              'geometry': {
                'type': 'Point',
                'coordinates': [lon, lat],
              },
            },
          ],
        }),
      ),
    ),
  );

  testWidgets(
    'layers use saved screening and model signs and expose their meaning',
    (tester) async {
      final d = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await open(tester, d);
      expect(find.text('20.0%'), findsOneWidget);
      await layer(tester, 'infestation');
      expect(
        find.textContaining('4 of 20 assessable plants infested'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('About this layer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('frass or larvae detected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'finalized expert layer defaults to mean with zero and overrides CV infestation',
    (tester) async {
      final d = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await open(tester, d, expert: review(d), load: () async => ratings(d));
      expect(find.text('2.33 / 9'), findsOneWidget);
      await layer(tester, 'infestation');
      expect(find.text('33.3%'), findsOneWidget);
      expect(
        find.textContaining('1 of 3 assessable plants infested'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'map fits the field above collapsed panel and selected sample remains tappable',
    (tester) async {
      final d = (await tester.runAsync(() => daResultsFixture(db)))!;
      await open(tester, d);
      final located = AssessmentHistoryDetail(
        assessment: d.assessment,
        workspace: d.workspace,
        evaluator: d.evaluator,
        stations: [
          for (final s in d.stations)
            StationSnapshot(
              prepared: withPin(
                s,
                17.0001 + s.stationNumber * .00003,
                121.0001 + s.stationNumber * .00003,
              ),
              stationNumber: s.stationNumber,
              station: s.station!.copyWith(
                locationSource: 'phone_gps',
                latitude: const Value(18.5),
                longitude: const Value(123.5),
              ),
              plants: s.plants,
              reviewedAt: s.reviewedAt,
              reviewIsCurrent: s.reviewIsCurrent,
              requiredPlantCount: s.requiredPlantCount,
            ),
        ],
        units: d.units,
        evidence: d.evidence,
        safety: d.safety,
        missingBlocks: d.missingBlocks,
        readiness: d.readiness,
        resultSummary: d.resultSummary,
      );
      await open(tester, located);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final mapTop = tester.getTopLeft(find.byType(FlutterMap)).dy;
      final sheetTop = tester
          .getTopLeft(
            find
                .descendant(
                  of: find.byKey(const Key('assessment_map_panel')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .dy;
      for (final point in AssessmentMapData(
        located,
      ).points.where((p) => p.location != null)) {
        final screen = map.mapController!.camera.latLngToScreenOffset(
          point.location!,
        );
        expect(screen.dy + mapTop, lessThan(sheetTop));
      }
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        located.stations.length,
      );
      await tester.tap(find.byKey(const Key('assessment_map_expand')));
      await tester.pumpAndSettle();
      final id = AssessmentMapData(d).points.first.id;
      final row = find.byKey(ValueKey('map_sample_$id'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('assessment_map_sample_details')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('map_pin_$id')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'center fits scouting pins, ignores distant photo GPS and groups only after zoom out',
    (tester) async {
      final d = (await tester.runAsync(() => daResultsFixture(db)))!;
      final located = AssessmentHistoryDetail(
        assessment: d.assessment,
        workspace: d.workspace,
        evaluator: d.evaluator,
        stations: [
          for (final s in d.stations)
            StationSnapshot(
              prepared: withPin(
                s,
                s.stationNumber == 20
                    ? 17.0015
                    : 17.0004 + s.stationNumber * .000005,
                s.stationNumber == 20
                    ? 121.0015
                    : 121.0004 + s.stationNumber * .000005,
              ),
              stationNumber: s.stationNumber,
              station: s.station!.copyWith(
                locationSource: 'phone_gps',
                latitude: const Value(18.5),
                longitude: const Value(123.5),
              ),
              plants: s.plants,
              reviewedAt: s.reviewedAt,
              reviewIsCurrent: s.reviewIsCurrent,
              requiredPlantCount: s.requiredPlantCount,
            ),
        ],
        units: d.units,
        evidence: d.evidence,
        safety: d.safety,
        missingBlocks: d.missingBlocks,
        readiness: d.readiness,
        resultSummary: d.resultSummary,
      );
      await open(tester, located);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final camera = map.mapController!;
      final fittedZoom = camera.camera.zoom;
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        20,
      );
      final pinScreens = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .map((pin) => camera.camera.latLngToScreenOffset(pin.point))
          .toList();
      for (var i = 0; i < pinScreens.length; i++) {
        for (var j = i + 1; j < pinScreens.length; j++) {
          expect(
            (pinScreens[i].dx - pinScreens[j].dx).abs() >= 33.9 ||
                (pinScreens[i].dy - pinScreens[j].dy).abs() >= 37.9,
            isTrue,
          );
        }
      }
      final top = tester.getTopLeft(find.byType(FlutterMap)).dy;
      final sheetTop = tester
          .getTopLeft(find.byKey(const Key('assessment_map_expand')))
          .dy;
      for (final p in AssessmentMapData(located).points) {
        final offset = camera.camera.latLngToScreenOffset(p.location!);
        expect(offset.dx, inInclusiveRange(15, 345));
        expect(offset.dy + top, inInclusiveRange(top + 15, sheetTop - 17));
      }
      // Two-finger zoom out enables overlap groups; panning alone did not.
      final center = Offset(180, top + 220);
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(80, 0));
      await second.down(center + const Offset(80, 0));
      await tester.pump();
      for (var n = 1; n <= 5; n++) {
        await first.moveTo(center - Offset(80 - n * 10, 0));
        await second.moveTo(center + Offset(80 - n * 10, 0));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(camera.camera.zoom, lessThan(fittedZoom - .15));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        lessThan(20),
      );
      await tester.tap(find.byKey(const Key('assessment_map_expand')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit field'));
      await tester.pumpAndSettle();
      expect(camera.camera.zoom, closeTo(fittedZoom, .001));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        20,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large text can scroll layers and sample details without overflow',
    (tester) async {
      final d = (await tester.runAsync(() => daResultsFixture(db)))!;
      await open(tester, d, scale: 2);
      await layer(tester, 'infestation');
      await tester.tap(find.byKey(const Key('assessment_map_expand')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new finalized case never reuses previous findings while loading',
    (tester) async {
      final d = (await tester.runAsync(() => daResultsFixture(db)))!;
      await open(tester, d, expert: review(d), load: () async => ratings(d));
      expect(find.text('2.33 / 9'), findsOneWidget);
      final pending = Completer<List<ExpertPlantRating>>();
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentMapScreen(
            detail: d,
            storage: EvidenceStorageService(),
            showMapTiles: false,
            reviewCase: review(d, id: 'new'),
            loadRatings: () => pending.future,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2.33 / 9'), findsNothing);
      pending.complete(ratings(d));
      await tester.pumpAndSettle();
      expect(find.text('2.33 / 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed finalized ratings stay unavailable and can be retried', (
    tester,
  ) async {
    final d = (await tester.runAsync(
      () => daResultsFixture(db, infestationDetections: true),
    ))!;
    var attempts = 0;
    await open(
      tester,
      d,
      expert: review(d),
      load: () async {
        if (++attempts == 1) throw StateError('offline');
        return ratings(d);
      },
    );
    await layer(tester, 'expert');
    expect(find.text('Unavailable'), findsWidgets);
    await tester.tap(find.byKey(const Key('assessment_map_expand')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('assessment_map_retry_expert')),
    );
    await tester.tap(find.byKey(const Key('assessment_map_retry_expert')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('2.33 / 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
