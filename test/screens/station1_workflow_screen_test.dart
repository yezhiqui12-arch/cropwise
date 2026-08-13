import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/screens/station1/plant_observation_step.dart';
import 'package:wormwise/screens/station1/station_location_step.dart';
import 'package:wormwise/services/phone_location_service.dart';

void main() {
  testWidgets('plant entry remains scrollable and usable at 200 percent text', (
    WidgetTester tester,
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
            body: PlantObservationStep(
              position: 1,
              savedCount: 0,
              stationId: 'station-1',
              actorPersonId: 'evaluator-1',
              existing: null,
              isSaving: false,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );

    final save = find.byKey(const Key('save_plant_button'));
    await tester.scrollUntilVisible(
      save,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(save, findsOneWidget);
    expect(tester.getSize(save).height, greaterThanOrEqualTo(56));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mixed evidence is shown and does not preselect an interpretation',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantObservationStep(
              position: 1,
              savedCount: 0,
              stationId: 'station-1',
              actorPersonId: 'evaluator-1',
              existing: null,
              isSaving: false,
              onSave: (_) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assessable_yes')));
      await tester.pump();
      await _tapVisible(tester, find.byKey(const Key('leaves_inspected_3')));
      await _tapVisible(
        tester,
        find.byKey(const Key('fresh_windowpanes_field')),
      );
      await _tapVisible(tester, find.byKey(const Key('visible_larva_no')));
      await _tapVisible(
        tester,
        find.byKey(const Key('egg_mass_not_collected')),
      );
      await _tapVisible(tester, find.byKey(const Key('old_damage_no')));
      await _tapVisible(tester, find.byKey(const Key('possible_non_faw_yes')));
      await _tapVisible(
        tester,
        find.byKey(const Key('uncertain_evidence_yes')),
      );

      expect(find.byKey(const Key('mixed_evidence_notice')), findsOneWidget);

      final save = find.byKey(const Key('save_plant_button'));
      await tester.scrollUntilVisible(
        save,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();

      expect(
        find.text(
          'Confirm the primary interpretation. WormWise will not select it automatically.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'fresh signs require an explicit answer and preserve explicit all-false raw values',
    (tester) async {
      VegetativePlantSave? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantObservationStep(
              position: 1,
              savedCount: 0,
              stationId: 'station-1',
              actorPersonId: 'evaluator-1',
              existing: null,
              isSaving: false,
              onSave: (input) async => saved = input,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assessable_yes')));
      await tester.pump();
      await _tapVisible(tester, find.byKey(const Key('leaves_inspected_3')));
      await tester.tap(find.byKey(const Key('save_plant_button')));
      await tester.pump();
      expect(
        find.text(
          'Select each fresh feeding sign observed, or explicitly select no listed fresh signs.',
        ),
        findsOneWidget,
      );
      expect(saved, isNull);

      await _tapVisible(tester, find.byKey(const Key('no_fresh_signs_field')));
      await _tapVisible(tester, find.byKey(const Key('visible_larva_no')));
      expect(find.byKey(const Key('larval_size_field')), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const Key('egg_mass_not_collected')),
      );
      await _tapVisible(tester, find.byKey(const Key('old_damage_no')));
      await _tapVisible(tester, find.byKey(const Key('possible_non_faw_no')));
      await _tapVisible(tester, find.byKey(const Key('uncertain_evidence_no')));
      await _tapVisible(tester, find.byKey(const Key('plant_status_negative')));
      await tester.tap(find.byKey(const Key('save_plant_button')));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.smallFreshWindowpanes, isFalse);
      expect(saved!.scraping, isFalse);
      expect(saved!.cuttingOrTearing, isFalse);
      expect(saved!.freshFrass, isFalse);
      expect(saved!.whorlFeedingSign, isFalse);
      expect(saved!.larvaVisible, isFalse);
    },
  );

  testWidgets('station GPS displays accuracy without blocking a coarse fix', (
    WidgetTester tester,
  ) async {
    AveragedPhoneLocation? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationLocationStep(
            captureLocation: () async => AveragedPhoneLocation(
              latitude: 17.1,
              longitude: 121.2,
              averageAccuracyMeters: 245,
              worstAccuracyMeters: 280,
              sampleCount: 2,
              capturedAt: DateTime.utc(2026, 8, 12),
            ),
            isSaving: false,
            onUseLocation: (value) async => saved = value,
            onSaveUnavailable: ({required reason, note}) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('capture_station_gps_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('245.0 m'), findsOneWidget);
    expect(find.textContaining('does not block this station'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_station_gps_button')));
    await tester.pump();
    expect(saved?.averageAccuracyMeters, 245);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
