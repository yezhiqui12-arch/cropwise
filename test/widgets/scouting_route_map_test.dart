import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/field_imagery_provider.dart';
import 'package:wormwise/services/scouting_route_generator.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/offline_scouting_route_map.dart';

void main() {
  test(
    'DA connections retain all pins and require photo evidence at both ends',
    () {
      final plan = _plan().copyWith(
        targets: [
          for (var n = 1; n <= 5; n++)
            ScoutingStationTarget(
              stationNumber: n,
              location: LatLng(17, 121 + n * .001),
            ),
        ],
      );
      final lines = daPlantConnectionLines(plan, {1, 2, 4, 5});
      expect(lines, hasLength(4));
      expect(lines.first.points, [
        plan.targetFor(1).location,
        plan.targetFor(2).location,
      ]);
      expect(
        lines.first.pattern.runtimeType,
        const StrokePattern.solid().runtimeType,
      );
      expect(
        lines[1].pattern.runtimeType,
        StrokePattern.dashed(segments: const [9, 6]).runtimeType,
      );
      expect(
        lines[2].pattern.runtimeType,
        StrokePattern.dashed(segments: const [9, 6]).runtimeType,
      );
      expect(
        lines.last.pattern.runtimeType,
        const StrokePattern.solid().runtimeType,
      );
    },
  );
  test('pin grouping adapts to screen scale and retains all plant numbers', () {
    final targets = [
      for (var i = 0; i < 20; i++)
        ScoutingStationTarget(
          stationNumber: i + 1,
          location: LatLng(17, 121 + i * .0001),
        ),
    ];
    final close = groupScoutingPlantPins(
      targets,
      (p) => Offset((p.longitude - 121) * 1000, 0),
    );
    expect(close, hasLength(1));
    expect(close.single.targets, hasLength(20));
    final expanded = groupScoutingPlantPins(
      targets,
      (p) => Offset((p.longitude - 121) * 1000000, 0),
    );
    expect(expanded, hasLength(20));
    expect(
      expanded.expand((g) => g.targets).map((t) => t.stationNumber),
      orderedEquals(List.generate(20, (i) => i + 1)),
    );
  });
  testWidgets(
    'DA zoomed-out group is tappable and has one pin per plant without checks',
    (tester) async {
      const outline = [
        LatLng(17, 121),
        LatLng(17, 121.001),
        LatLng(17.001, 121.001),
        LatLng(17.001, 121),
      ];
      final plan = ScoutingRouteGenerator.generate(
        draft: _plan().copyWith(
          pattern: ScoutingSamplingProtocol.daPattern,
          status: ScoutingRouteStatus.draft,
          targets: const [],
        ),
        boundary: outline,
      );
      int? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineScoutingRouteMap(
              boundary: outline,
              plan: plan,
              activeStation: 7,
              completedStationNumbers: const {1, 2, 3, 4, 5, 6},
              completedStationLocations: const {1: LatLng(17.01, 121.01)},
              onTargetTap: (number) => opened = number,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      controller.move(ScoutingRouteGenerator.polygonCenter(outline), 18);
      await tester.pumpAndSettle();
      final saved = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .singleWhere(
            (m) => m.child.key == const Key('route_station_marker_1'),
          );
      expect(saved.point, plan.targetFor(1).location);
      expect(
        find.descendant(
          of: find.byKey(const Key('route_station_marker_1')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('route_station_marker_1')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      opened = null;
      controller.move(ScoutingRouteGenerator.polygonCenter(outline), 12);
      await tester.pumpAndSettle();
      final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      final clusters = layer.markers
          .where((m) => m.child.key.toString().contains('route_plant_cluster_'))
          .toList();
      expect(clusters, hasLength(1));
      await tester.tap(find.byKey(clusters.single.child.key!));
      await tester.pumpAndSettle();
      expect(find.text('20 nearby plants'), findsOneWidget);
      await tester.tap(find.text('Plant 1'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'DA handoff fits visible pins and respects reduced motion: $reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const outline = [
          LatLng(17, 121),
          LatLng(17, 121.001),
          LatLng(17.001, 121.001),
          LatLng(17.001, 121),
        ];
        final plan = ScoutingRouteGenerator.generate(
          draft: _plan().copyWith(
            pattern: ScoutingSamplingProtocol.daPattern,
            status: ScoutingRouteStatus.draft,
            targets: const [],
          ),
          boundary: outline,
        );
        Widget view(int number, {int? from}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: SizedBox(
                height: 600,
                child: OfflineScoutingRouteMap(
                  boundary: outline,
                  plan: plan,
                  activeStation: number,
                  minimalChrome: true,
                  viewportBottomInset: 100,
                  completedStationNumbers: number == 1 ? const {} : const {1},
                  completedStationLocations: number == 1
                      ? const {}
                      : const {1: LatLng(17.05, 121.05)},
                  animateFromCompletedStation: from,
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(view(1));
        await tester.pumpAndSettle();
        await tester.pumpWidget(view(2));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('da_next_plant_leg')), findsNothing);
        await tester.pumpWidget(view(2, from: 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (!reduced)
          expect(
            find.byKey(const Key('da_next_plant_highlight')),
            findsOneWidget,
          );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('da_next_plant_highlight')), findsNothing);
        final line = tester
            .widget<PolylineLayer>(find.byKey(const Key('da_next_plant_leg')))
            .polylines
            .single;
        expect(line.points, [
          plan.targetFor(1).location,
          plan.targetFor(2).location,
        ]);
        final camera = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        for (final n in [1, 2]) {
          final pixel = camera.latLngToScreenOffset(plan.targetFor(n).location);
          expect(pixel.dy, inInclusiveRange(24, 476));
          expect(pixel.dx, inInclusiveRange(24, 316));
        }
        expect(find.byKey(const Key('route_station_marker_1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  const boundary = [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ];

  testWidgets('provider failure automatically shows attributed offline view', (
    tester,
  ) async {
    final plan = _plan();
    await tester.pumpWidget(
      _app(
        plan: plan,
        imageryProvider: _ThrowingProvider(),
        boundary: boundary,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Online map unavailable · Offline field view'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Offline illustrated field view'),
      findsOneWidget,
    );
    for (var station = 1; station <= 5; station++) {
      expect(find.byKey(Key('route_station_marker_$station')), findsOneWidget);
    }
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    for (final target in plan.targets) {
      final marker = markerLayer.markers.singleWhere(
        (item) =>
            item.child.key ==
            Key('route_station_marker_${target.stationNumber}'),
      );
      expect(marker.point, target.location);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('packaged imagery displays its permanent attribution', (
    tester,
  ) async {
    final provider = _FixedProvider(
      FieldImagerySource.packaged(
        kind: FieldImageryKind.approvedHighResolutionPackage,
        displayName: 'DA licensed Piat imagery',
        attribution: 'Department of Agriculture · Licence DA-2026-1',
        licenseReference: 'DA-2026-1',
        resolutionLabel: '0.5 m supplied imagery',
        imageProvider: const AssetImage(
          'assets/images/growth_stages/maize_young_vegetative.jpg',
        ),
        imageBounds: const FieldImageryBounds(
          west: 120.999,
          south: 16.999,
          east: 121.011,
          north: 17.011,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(plan: _plan(), imageryProvider: provider, boundary: boundary),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('DA licensed Piat imagery'), findsOneWidget);
    expect(find.textContaining('Department of Agriculture'), findsOneWidget);
    expect(
      find.text('Online map unavailable · Offline field view'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('map overlays remain usable at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: OfflineScoutingRouteMap(
              boundary: boundary,
              plan: _plan(),
              activeStation: 2,
              completedStationLocations: const {1: LatLng(17.002, 121.002)},
              imageryProvider: _ThrowingProvider(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('offline_scouting_route_map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed station remains checked without recorded GPS', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineScoutingRouteMap(
            boundary: boundary,
            plan: _plan(),
            activeStation: 3,
            completedStationNumbers: const {1, 2},
            imageryProvider: _ThrowingProvider(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final station in [1, 2]) {
      final marker = find.byKey(Key('route_station_marker_$station'));
      expect(marker, findsOneWidget);
      expect(
        find.descendant(of: marker, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
    }
    final active = find.byKey(const Key('route_station_marker_3'));
    expect(
      find.descendant(of: active, matching: find.byIcon(Icons.flag_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('previous station turns green after advancing the route', (
    tester,
  ) async {
    final plan = _plan();
    final unlocked = plan.copyWith(
      targets: [
        for (final target in plan.targets)
          target.copyWith(lockedCompleted: false),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineScoutingRouteMap(
            boundary: boundary,
            plan: unlocked,
            activeStation: 2,
            imageryProvider: _ThrowingProvider(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final previous = find.byKey(const Key('route_station_marker_1'));
    expect(
      find.descendant(of: previous, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    final active = find.byKey(const Key('route_station_marker_2'));
    expect(
      find.descendant(of: active, matching: find.byIcon(Icons.flag_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('completed W-route leg turns green at Station 2', (tester) async {
    final plan = _wPlan();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineScoutingRouteMap(
            boundary: boundary,
            plan: plan,
            activeStation: 2,
            completedStationNumbers: const {1},
            imageryProvider: _ThrowingProvider(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final polylines = tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((layer) => layer.polylines);
    final completedLeg = plan.segments.singleWhere(
      (segment) => segment.stationNumber == 2,
    );
    final activeLeg = plan.segments.singleWhere(
      (segment) => segment.stationNumber == 3,
    );
    expect(
      polylines
          .singleWhere(
            (line) =>
                line.points.first == completedLeg.points.first &&
                line.points.last == completedLeg.points.last,
          )
          .color,
      AppColors.primary,
    );
    expect(
      polylines
          .singleWhere(
            (line) =>
                line.points.first == activeLeg.points.first &&
                line.points.last == activeLeg.points.last,
          )
          .color,
      const Color(0xFFF57C00),
    );
  });

  test('route progress uses color and a distinct status icon', () {
    const completed = ScoutingRouteSegment(
      points: [LatLng(17, 121), LatLng(17.001, 121.001)],
      kind: 'ladder_branch_return',
      drawable: true,
      stationNumber: 1,
    );
    const active = ScoutingRouteSegment(
      points: [LatLng(17.001, 121.001), LatLng(17.002, 121.002)],
      kind: 'ladder_spine_approach',
      drawable: true,
      stationNumber: 2,
    );
    const invalid = ScoutingRouteSegment(
      points: [LatLng(17.002, 121.002), LatLng(17.003, 121.003)],
      kind: 'suggested_orientation_only',
      drawable: false,
      stationNumber: 3,
    );
    const future = ScoutingRouteSegment(
      points: [LatLng(17.003, 121.003), LatLng(17.004, 121.004)],
      kind: 'ladder_spine_approach',
      drawable: true,
      stationNumber: 4,
    );

    final completedState = routeProgressStateFor(
      segment: completed,
      activeStation: 2,
      completedStations: {1},
    );
    final activeState = routeProgressStateFor(
      segment: active,
      activeStation: 2,
      completedStations: {1},
    );
    final invalidState = routeProgressStateFor(
      segment: invalid,
      activeStation: 2,
      completedStations: {1},
    );
    final futureState = routeProgressStateFor(
      segment: future,
      activeStation: 2,
      completedStations: {1},
    );

    expect(completedState, RouteProgressState.completed);
    expect(routeProgressColor(completedState), AppColors.primary);
    expect(routeProgressIcon(completedState), Icons.check_circle);
    expect(activeState, RouteProgressState.active);
    expect(routeProgressColor(activeState), const Color(0xFFF57C00));
    expect(routeProgressIcon(activeState), Icons.arrow_circle_right);
    expect(invalidState, RouteProgressState.invalid);
    expect(routeProgressColor(invalidState), const Color(0xFFB3261E));
    expect(routeProgressIcon(invalidState), Icons.warning);
    expect(futureState, RouteProgressState.future);
    expect(routeProgressColor(futureState), const Color(0xFF60727A));
    expect(routeProgressIcon(futureState), Icons.more_horiz);
  });
}

Widget _app({
  required ScoutingRoutePlan plan,
  required FieldImageryProvider imageryProvider,
  required List<LatLng> boundary,
}) => MaterialApp(
  home: Scaffold(
    body: OfflineScoutingRouteMap(
      boundary: boundary,
      plan: plan,
      activeStation: 2,
      completedStationLocations: const {1: LatLng(17.002, 121.002)},
      imageryProvider: imageryProvider,
    ),
  ),
);

ScoutingRoutePlan _plan() => ScoutingRouteGenerator.generate(
  draft: ScoutingRoutePlan(
    assessmentId: 'assessment-1',
    blockRunId: 'run-1',
    blockId: 'block-1',
    boundaryVersionId: 'boundary-1',
    pattern: DatabaseCodes.patternLadder,
    status: ScoutingRouteStatus.draft,
    preparation: const RoutePreparationData(
      entrance: LatLng(17.0002, 121.0002),
      obstaclesReviewed: true,
    ),
    updatedAt: DateTime.utc(2026, 8, 14),
  ),
  boundary: const [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ],
  completedStations: const {1: LatLng(17.002, 121.002)},
);

ScoutingRoutePlan _wPlan() => ScoutingRouteGenerator.generate(
  draft: ScoutingRoutePlan(
    assessmentId: 'assessment-1',
    blockRunId: 'run-1',
    blockId: 'block-1',
    boundaryVersionId: 'boundary-1',
    pattern: DatabaseCodes.patternW,
    status: ScoutingRouteStatus.draft,
    preparation: const RoutePreparationData(
      entrance: LatLng(17.0002, 121.0002),
      rowBearingDegrees: 0,
      obstaclesReviewed: true,
      wCrossingConfirmed: true,
    ),
    updatedAt: DateTime.utc(2026, 8, 14),
  ),
  boundary: const [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ],
);

class _ThrowingProvider implements FieldImageryProvider {
  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) {
    throw StateError('Offline in test');
  }
}

class _FixedProvider implements FieldImageryProvider {
  const _FixedProvider(this.source);

  final FieldImagerySource source;

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async =>
      source;
}
