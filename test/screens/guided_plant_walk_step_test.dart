import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/screens/scan/guided_plant_walk_step.dart';
import 'package:wormwise/services/scouting_route_generator.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';
import 'package:wormwise/services/phone_location_service.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/offline_scouting_route_map.dart';

void main() {
  final capturePreview =
      Platform.environment['WORMWISE_CAPTURE_PREVIEW'] == '1';
  setUpAll(() async {
    if (!capturePreview) return;
    final fontDirectory =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$fontDirectory/${font.value}',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  const boundary = [
    LatLng(17, 121),
    LatLng(17, 121.00094),
    LatLng(17.0009, 121.00094),
    LatLng(17.0009, 121),
  ];
  final plan = ScoutingRouteGenerator.generate(
    draft: ScoutingRoutePlan(
      assessmentId: 'a',
      blockRunId: 'r',
      blockId: 'b',
      boundaryVersionId: 'v',
      pattern: ScoutingSamplingProtocol.daPattern,
      status: ScoutingRouteStatus.draft,
      preparation: const RoutePreparationData(),
      updatedAt: DateTime.now(),
    ),
    boundary: boundary,
  );
  Widget screen({
    bool arrived = false,
    int plantNumber = 7,
    bool reduceMotion = false,
    int count = 0,
    String? resultLabel,
    double? resultConfidence,
    Future<Stream<PhoneLocationReading>> Function()? watch,
    Future<void> Function()? onArrive,
    Future<void> Function()? onContinue,
    Future<void> Function()? onImport,
    Future<void> Function()? onImportSample,
    Future<void> Function(int)? onOpenPlant,
    Key? boundaryKey,
    double scale = 1,
  }) {
    final now = DateTime.now();
    return MaterialApp(
      theme: ThemeData(
        fontFamily: capturePreview ? 'Roboto' : null,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Guided scouting'),
              leading: const Icon(Icons.arrow_back),
              actions: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Icon(Icons.help_outline),
                ),
              ],
            ),
            body: GuidedPlantWalkStep(
              fieldName: 'Corn plot',
              areaHectares: 1,
              plantNumber: plantNumber,
              completedPlants: plantNumber - 1,
              boundary: boundary,
              plan: plan,
              completedLocations: const {},
              completedNumbers: {for (var i = 1; i < plantNumber; i++) i},
              watchLocation: watch ?? () async => const Stream.empty(),
              arrived: arrived,
              isSaving: false,
              resultLabel: resultLabel,
              resultConfidence: resultConfidence,
              onArrive: onArrive ?? () async {},
              onCapture: () async {},
              onImport: onImport ?? () async {},
              onImportSample: onImportSample,
              onContinue: onContinue ?? () async {},
              onReview: () async {},
              onOpenPlant: onOpenPlant,
              onAdjust: () async {},
              resolveFile: (uri) async => File(uri),
              photos: [
                for (var i = 0; i < count; i++)
                  EvidenceMediaRecord(
                    id: 'p$i',
                    createdAt: now,
                    updatedAt: now,
                    syncState: DatabaseCodes.localOnly,
                    serverVersion: 0,
                    assessmentId: 'a',
                    stationId: 's',
                    captureSessionId: 'c',
                    mediaType: 'image',
                    viewType: i == 0
                        ? DatabaseCodes.evidenceViewWhorlOverview
                        : DatabaseCodes.evidenceViewCloseUp,
                    localUri: 'missing$i.jpg',
                    mimeType: 'image/jpeg',
                    byteSize: 0,
                    sha256Checksum: 'hash',
                    capturedAt: now,
                    qualityStatus:
                        DatabaseCodes.evidenceQualityEvaluatorConfirmed,
                    captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
                    storageState: DatabaseCodes.evidenceStorageReady,
                    locationSource: 'unavailable',
                    uploadState: DatabaseCodes.localOnly,
                    isCanonicalEvidence: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'manual arrival remains available without GPS and renders the approved sheet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      const imageKey = Key('walk_preview');
      await tester.pumpWidget(
        screen(
          onArrive: () async {
            calls++;
          },
          boundaryKey: imageKey,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plant 7'), findsOneWidget);
      expect(find.text('GPS unavailable'), findsOneWidget);
      expect(find.text('7 of 20'), findsOneWidget);
      expect(find.text('View all'), findsNothing);
      expect(find.text('Keep at least 3 m from the field edge.'), findsNothing);
      await tester.tap(find.byKey(const Key('guided_walk_arrive')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      if (Platform.environment['WORMWISE_CAPTURE_PREVIEW'] == '1')
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(imageKey),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'C:/Users/marka/Documents/Codex/2026-10-02/an/outputs/guided-scouting-redesign/widget-details.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    },
  );
  testWidgets('advancing a saved plant reveals the map before the DA handoff', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen(arrived: true, count: 1));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byKey(const Key('guided_walk_draggable_sheet')),
    );
    sheet.controller!.jumpTo(1);
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(plantNumber: 8));
    await tester.pumpAndSettle();
    expect(find.text('Plant 8'), findsOneWidget);
    expect(sheet.controller!.size, closeTo(sheet.minChildSize, .01));
    final map = tester.widget<OfflineScoutingRouteMap>(
      find.byType(OfflineScoutingRouteMap),
    );
    expect(map.animateFromCompletedStation, 7);
    expect(find.byKey(const Key('da_next_plant_leg')), findsOneWidget);
    expect(find.byKey(const Key('da_next_plant_highlight')), findsNothing);
    expect(find.byKey(const Key('route_station_marker_7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cached GPS does not display a fabricated live distance', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        watch: () async => Stream.value(
          PhoneLocationReading(
            latitude: 17,
            longitude: 121,
            accuracyMeters: 5,
            capturedAt: DateTime.now(),
            isCached: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GPS unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'save needs no leaf count and completed photos hide extra photo controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saved = false;
      await tester.pumpWidget(
        screen(
          arrived: true,
          count: 3,
          onContinue: () async {
            saved = true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('guided_walk_primary_action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Leaves inspected:'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('guided_walk_primary_action')),
      );
      await tester.tap(find.byKey(const Key('guided_walk_primary_action')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(find.byKey(const Key('guided_walk_import')), findsNothing);
      expect(find.byKey(const Key('guided_walk_add_photo')), findsNothing);
      expect(find.text('Edit field notes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('expand icon keeps the header and pull-up sheet restores details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const imageKey = Key('expanded_map_preview');
    await tester.pumpWidget(screen(boundaryKey: imageKey));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byKey(const Key('guided_walk_draggable_sheet')),
    );
    expect(sheet.controller!.size, closeTo(.48, .01));
    await tester.tap(find.byKey(const Key('guided_walk_expand_map')));
    await tester.pumpAndSettle();
    expect(sheet.controller!.size, closeTo(sheet.minChildSize, .01));
    expect(find.text('1.00 ha · Sampling block'), findsOneWidget);
    expect(find.byTooltip('Show plant details'), findsOneWidget);
    final handle = find.byKey(const Key('guided_walk_sheet_handle'));
    final plant = find.text('Plant 7');
    expect(tester.getRect(plant).bottom, lessThan(844));
    if (capturePreview) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(imageKey),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'C:/Users/marka/Documents/Codex/2026-10-02/an/outputs/guided-scouting-redesign/widget-expanded-map.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.drag(handle, const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(sheet.controller!.size, closeTo(.48, .01));
    await tester.tap(find.byTooltip('Expand plant details'));
    await tester.pumpAndSettle();
    expect(sheet.controller!.size, closeTo(1, .01));
    await tester.ensureVisible(find.byKey(const Key('guided_walk_arrive')));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'sheet handle follows the finger and releases into existing snap heights',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byKey(const Key('guided_walk_draggable_sheet')),
      );
      final controller = sheet.controller!;
      final handle = find.byKey(const Key('guided_walk_sheet_handle'));
      var gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      final height = controller.sizeToPixels(controller.size);
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump();
      expect(controller.sizeToPixels(controller.size) - height, closeTo(70, 1));
      final releaseExtent = controller.size;
      expect(releaseExtent, greaterThan(.48));
      expect(releaseExtent, lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      final stops = [sheet.minChildSize, .48, 1.0]
        ..sort(
          (a, b) =>
              (a - releaseExtent).abs().compareTo((b - releaseExtent).abs()),
        );
      expect(controller.size, closeTo(stops.first, .001));

      controller.jumpTo(1);
      await tester.pumpAndSettle();
      gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      final fullHeight = controller.sizeToPixels(controller.size);
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(
        fullHeight - controller.sizeToPixels(controller.size),
        closeTo(80, 1),
      );
      await gesture.moveBy(const Offset(0, 1000));
      await tester.pump();
      expect(controller.size, closeTo(sheet.minChildSize, .001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(sheet.minChildSize, .001));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('model results opens directly for the current captured plant', (
    tester,
  ) async {
    int? opened;
    await tester.pumpWidget(
      screen(
        arrived: true,
        count: 1,
        onOpenPlant: (number) async {
          opened = number;
        },
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('guided_walk_model_results'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, 7);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'screening result is visible before saving or opening model results',
    (tester) async {
      await tester.pumpWidget(
        screen(
          arrived: true,
          count: 1,
          resultLabel: 'Damage detected',
          resultConfidence: .92,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('guided_walk_screening_status')),
        findsOneWidget,
      );
      expect(find.text('Damage detected · 92% confidence'), findsOneWidget);
      expect(find.textContaining('expert'), findsNothing);
      expect(find.textContaining('Suggested'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'fit field collapses the panel and fits plants in the visible map',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byKey(const Key('guided_walk_draggable_sheet')),
      );
      sheet.controller!.jumpTo(.92);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show map'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guided_walk_fit_field')));
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(sheet.minChildSize, .01));
      final camera = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera;
      final visibleHeight = camera.nonRotatedSize.height * .82;
      for (final plant in plan.targets) {
        final pixel = camera.latLngToScreenOffset(plant.location);
        expect(pixel.dy, greaterThan(0));
        expect(pixel.dy, lessThan(visibleHeight));
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small screen keeps arrival focused and exposes import after arrival',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen(scale: 1.5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guided_walk_arrive')));
      expect(find.byKey(const Key('guided_walk_import')), findsNothing);
      await tester.pumpWidget(screen(scale: 1.5, arrived: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guided_walk_import')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('single plant import and batch import call different actions', (
    tester,
  ) async {
    var plantImports = 0, batches = 0;
    await tester.pumpWidget(
      screen(
        arrived: true,
        onImport: () async => plantImports++,
        onImportSample: () async => batches++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guided_walk_import')));
    await tester.tap(find.byKey(const Key('guided_walk_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guided_import_this_plant')));
    await tester.pumpAndSettle();
    expect(plantImports, 1);
    expect(batches, 0);
    await tester.tap(find.byKey(const Key('guided_walk_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guided_import_batch')));
    await tester.pumpAndSettle();
    expect(plantImports, 1);
    expect(batches, 1);
    expect(tester.takeException(), isNull);
  });
}
