import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/scan/route_preparation_step.dart';
import 'package:wormwise/screens/scan/station_route_guidance_step.dart';
import 'package:wormwise/services/phone_location_service.dart';
import 'package:wormwise/services/scouting_route_generator.dart';

void main() {
  const boundary = [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ];

  testWidgets('offline route guidance never infers arrival from proximity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locations = StreamController<PhoneLocationReading>();
    addTearDown(locations.close);
    var confirmations = 0;
    final plan = _readyPlan();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRouteGuidanceStep(
            blockNumber: 1,
            stationNumber: 1,
            boundary: boundary,
            plan: plan,
            completedStationLocations: const {},
            watchLocation: () async => locations.stream,
            isSaving: false,
            onConfirmReached: () async => confirmations++,
            onAdjustTarget: () async {},
            onEditRoute: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    final target = plan.targetFor(1).location;
    locations.add(
      PhoneLocationReading(
        latitude: target.latitude,
        longitude: target.longitude,
        accuracyMeters: 8,
        capturedAt: DateTime.utc(2026, 8, 14),
      ),
    );
    await tester.pump();

    expect(confirmations, 0);
    expect(find.byType(TileLayer), findsNothing);
    final button = find.byKey(const Key('confirm_station_reached_button'));
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pump();
    expect(confirmations, 1);
  });

  testWidgets('route preparation remains reachable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plan = _readyPlan();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: RoutePreparationStep(
              blockNumber: 1,
              boundary: boundary,
              plan: plan,
              completedStationLocations: const {},
              captureLocation: () async => AveragedPhoneLocation(
                latitude: 17.001,
                longitude: 121.001,
                averageAccuracyMeters: 8,
                worstAccuracyMeters: 10,
                sampleCount: 3,
                capturedAt: DateTime.utc(2026, 8, 14),
              ),
              isSaving: false,
              onSavePreparation: (_) async {},
              onGenerate: () async {},
            ),
          ),
        ),
      ),
    );
    final button = find.byKey(const Key('generate_route_targets_button'));
    final list = find.byKey(const Key('route_preparation_step'));
    expect(list, findsOneWidget);
    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    for (
      var attempt = 0;
      attempt < 12 && button.evaluate().isEmpty;
      attempt++
    ) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(56));
    expect(find.byType(TileLayer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

ScoutingRoutePlan _readyPlan() => ScoutingRouteGenerator.generate(
  draft: ScoutingRoutePlan(
    assessmentId: 'assessment-1',
    blockRunId: 'run-1',
    blockId: 'block-1',
    boundaryVersionId: 'boundary-1',
    pattern: DatabaseCodes.patternW,
    status: ScoutingRouteStatus.draft,
    preparation: const RoutePreparationData(
      entrance: LatLng(17.0002, 121.0002),
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
