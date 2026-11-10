import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/plant_action_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/models/da_monitoring.dart';
import 'package:wormwise/models/guided_plant_details.dart';
import 'package:wormwise/models/plant_action_guidance.dart';
import 'package:wormwise/models/sampled_infestation.dart';
import 'package:wormwise/screens/scan/plant_action_guidance_panel.dart';
import 'package:wormwise/screens/scan/plant_action_notice_host.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import '../support/da_results_fixture.dart';

PlantDiagnosisResult model(List<int> ids, {String? label = 'FAW damage'}) =>
    PlantDiagnosisResult(
      isInfested: false,
      pestLabel: 'screen',
      confidenceScore: .92,
      classificationLabel: label,
      classifierStage: 'overlay_complete',
      detectionBoxes: [
        for (final id in ids)
          ModelDetectionBox(
            sourcePath: 'plant.jpg',
            classId: id,
            label: 'class $id',
            confidence: .9,
            left: .1,
            top: .1,
            right: .8,
            bottom: .8,
            imageWidth: 100,
            imageHeight: 100,
          ),
      ],
    );

void main() {
  setUpAll(() async {
    if (Platform.environment['CROPWISE_ACTION_PREVIEW'] != '1') return;
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
  });
  test(
    '20 affected plants offer one expanded guide, without assuming it was read',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = PlantActionRepository(db, 'farmer');
      var expanded = 0;
      for (var number = 1; number <= 20; number++) {
        final offered = await store.firstOffers('assessment', 'block', number, [
          PlantActionGuide.inspectDamage,
        ]);
        if (offered.isNotEmpty) expanded++;
      }
      expect(expanded, 1);
      expect(await store.learnedGuides(), isEmpty);
      expect(
        await store.firstOffers('assessment', 'block', 1, [
          PlantActionGuide.inspectDamage,
        ]),
        {'inspectDamage'},
      );
      expect(
        await store.firstOffers('next-assessment', 'block', 1, [
          PlantActionGuide.inspectDamage,
        ]),
        {'inspectDamage'},
      );
    },
  );
  test('guides deduplicate boxes and prefer removal over frass inspection', () {
    expect(
      PlantActionGuide.resolve(model([2, 2, 1, 0, 3])).map((g) => g.kind),
      [PlantActionKind.larva, PlantActionKind.eggs],
    );
    expect(
      PlantActionGuide.resolve(model([1])).single.kind,
      PlantActionKind.inspectWhorl,
    );
    expect(
      PlantActionGuide.resolve(model([])).single.kind,
      PlantActionKind.inspectDamage,
    );
    expect(
      PlantActionGuide.resolve(model([], label: 'No FAW damage')),
      isEmpty,
    );
    expect(PlantActionGuide.resolve(null), isEmpty);
  });
  test(
    'current manual corrections affect guides without changing model infestation',
    () {
      final result = model([2]);
      final original = result.toJson().toString();
      final corrected = DaPlantFinding.fromModel(result).withCorrections({
        'signature': 'current',
        'overrides': {'larva': false, 'damage': false},
      }, 'current');
      expect(PlantActionGuide.resolve(result, finding: corrected), isEmpty);
      expect(result.toJson().toString(), original);
      expect(modelSampledInfestation(result), true);
      final stale = DaPlantFinding.fromModel(result).withCorrections({
        'signature': 'old',
        'overrides': {'larva': false},
      }, 'current');
      expect(
        PlantActionGuide.resolve(result, finding: stale).first.kind,
        PlantActionKind.larva,
      );
    },
  );
  test(
    'action records survive new instances, remain block/profile scoped and undo',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = PlantActionRepository(db, 'farmer');
      Future<void> record(String block, String signature) => store.record(
        assessment: 'assessment',
        block: block,
        number: 7,
        guide: PlantActionGuide.larva,
        signature: signature,
        imported: false,
      );
      await record('block1', 'photo1');
      final first = (await store.load('assessment', 'block1', 7))['larva']!;
      await record('block1', 'photo2');
      await record('block2', 'photo3');
      final restored = PlantActionRepository(db, 'farmer');
      expect(
        (await restored.load('assessment', 'block1', 7))['larva']!.signature,
        'photo1',
      );
      expect(
        (await restored.load('assessment', 'block1', 7))['larva']!.recordedAt,
        first.recordedAt,
      );
      expect(
        (await restored.load('assessment', 'block2', 7))['larva']!.signature,
        'photo3',
      );
      expect(
        await PlantActionRepository(
          db,
          'another',
        ).load('assessment', 'block1', 7),
        isEmpty,
      );
      expect(await restored.watchSummary('assessment').first, {'larva': 2});
      await restored.record(
        assessment: 'assessment',
        block: 'block1',
        number: 7,
        guide: PlantActionGuide.larva,
        signature: 'photo1',
        imported: false,
        undo: true,
      );
      expect(await restored.load('assessment', 'block1', 7), isEmpty);
      expect(await restored.watchSummary('assessment').first, {'larva': 1});
      await store.rememberCollapsed(PlantActionGuide.larva);
      expect(
        await restored.learnedGuides(),
        contains(PlantActionGuide.larva.preferenceId),
      );
      expect(
        await PlantActionRepository(db, 'another').learnedGuides(),
        isEmpty,
      );
    },
  );

  Future<GuidedPlantDetails> details(AppDatabase db) async {
    final history = await daResultsFixture(db, recorded: 1);
    final snapshot = history.stations.first;
    final bundle = (await EvidenceCaptureRepository(
      db,
    ).loadStationBundles(snapshot.station!.id)).first;
    final now = DateTime.now();
    final photo = EvidenceMediaRecord(
      id: 'photo',
      createdAt: now,
      updatedAt: now,
      syncState: DatabaseCodes.localOnly,
      serverVersion: 0,
      assessmentId: history.assessment.id,
      stationId: snapshot.station!.id,
      captureSessionId: bundle.session.id,
      mediaType: 'image',
      viewType: DatabaseCodes.evidenceViewWhorlOverview,
      localUri: File('assets/images/faw_actions/faw_larva.jpg').absolute.path,
      mimeType: 'image/jpeg',
      byteSize: 0,
      sha256Checksum: 'photo-hash',
      capturedAt: now,
      qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
      captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
      storageState: DatabaseCodes.evidenceStorageReady,
      locationSource: 'unavailable',
      uploadState: DatabaseCodes.localOnly,
      isCanonicalEvidence: true,
    );
    return GuidedPlantDetails(
      snapshot: snapshot,
      evidence: EvidenceCaptureBundle(session: bundle.session, media: [photo]),
      diagnosis: model([2, 2, 1]),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pumpAndSettle();
    }
  }

  // Decode the real JPEG before entering the widget test's fake IO clock.
  Future<void> preparePhoto(WidgetTester tester, String uri) async {
    await tester.runAsync(() async {
      final file = File(uri);
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(file),
        () => _DecodedPhoto(ImageInfo(image: frame.image)),
      );
      codec.dispose();
    });
  }

  Widget screen(
    GuidedPlantDetails data,
    PlantActionRepository store, {
    bool atPlant = true,
    String revision = '',
    double scale = 1,
  }) => MaterialApp(
    theme: ThemeData(
      fontFamily: Platform.environment['CROPWISE_ACTION_PREVIEW'] == '1'
          ? 'Roboto'
          : null,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176327)),
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Plant 1')),
        body: RepaintBoundary(
          key: const Key('action_preview'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlantActionGuidancePanel(
                  repository: store,
                  assessmentId: data.photos.first.assessmentId,
                  blockRunId: data.snapshot.prepared.run.id,
                  number: 1,
                  revision: revision,
                  atPlant: atPlant,
                  loadDetails: () async => data,
                  resolveFile: (uri) async => File(uri),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Save and next plant'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['CROPWISE_ACTION_PREVIEW'] != '1') return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('action_preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('work/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  GuidedPlantDetails live(
    GuidedPlantDetails data,
    PlantDiagnosisResult? result, {
    int number = 1,
    bool reviewed = false,
  }) => GuidedPlantDetails(
    snapshot: StationSnapshot(
      prepared: data.snapshot.prepared,
      stationNumber: number,
      station: data.snapshot.station,
      plants: data.snapshot.plants,
      reviewedAt: reviewed ? DateTime.now() : null,
      reviewIsCurrent: reviewed,
      requiredPlantCount: 1,
    ),
    evidence: data.evidence,
    diagnosis: result,
    monitoring: data.monitoring,
  );

  Widget noticeScreen(
    GuidedPlantDetails data,
    PlantActionRepository store, {
    bool enabled = true,
    String revision = '',
    double scale = 1,
    Future<GuidedPlantDetails> Function()? loader,
  }) => RepaintBoundary(
    key: const Key('notice_preview'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: Platform.environment['CROPWISE_ACTION_PREVIEW'] == '1'
            ? 'Roboto'
            : null,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176327)),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Guided scouting')),
        body: PlantActionNoticeHost(
          repository: store,
          assessmentId: data.photos.first.assessmentId,
          blockRunId: data.snapshot.prepared.run.id,
          number: data.snapshot.stationNumber,
          revision: revision,
          enabled: enabled,
          loadDetails: loader ?? () async => data,
          resolveFile: (uri) async => File(uri),
          child: const Center(child: Text('Map expanded')),
        ),
      ),
    ),
  );

  Future<void> closeNotice(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('plant_action_notice_continue')));
    await settle(tester);
  }

  testWidgets('screening raises a photo notice over the map, once per type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final fixture = (await tester.runAsync(() => details(db)))!;
    final store = PlantActionRepository(db, 'farmer');
    await preparePhoto(tester, fixture.photos.first.localUri);
    await tester.pumpWidget(
      noticeScreen(live(fixture, null), store, enabled: false),
    );
    await settle(tester);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    final damage = live(fixture, model([]));
    await tester.pumpWidget(noticeScreen(damage, store, revision: 'screened'));
    await settle(tester);
    expect(find.text('Damage detected'), findsOneWidget);
    expect(find.text('Your photo'), findsOneWidget);
    expect(find.text('Leaf feeding damage'), findsOneWidget);
    expect(
      find.byKey(const Key('plant_action_notice_continue')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['CROPWISE_ACTION_PREVIEW'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('notice_preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          'work/plant-action-modal.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
    }
    await closeNotice(tester);
    // Dismissing the notice records neither pest removal nor learning.
    expect(
      await tester.runAsync(
        () => store.load(
          damage.photos.first.assessmentId,
          damage.snapshot.prepared.run.id,
          1,
        ),
      ),
      isEmpty,
    );
    expect(await tester.runAsync(store.learnedGuides), isEmpty);
    await tester.pumpWidget(
      noticeScreen(damage, store, revision: 'another-photo'),
    );
    await settle(tester);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    final next = live(fixture, model([]), number: 2);
    await tester.pumpWidget(noticeScreen(next, store, revision: 'next-plant'));
    await settle(tester);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    // A different actionable finding interrupts once, even at the same plant.
    final larva = live(fixture, model([2]), number: 2);
    await tester.pumpWidget(noticeScreen(larva, store, revision: 'new-larva'));
    await settle(tester);
    expect(find.text('Larva detected'), findsOneWidget);
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    await closeNotice(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      noticeScreen(
        larva,
        PlantActionRepository(db, 'farmer'),
        revision: 'resumed',
      ),
    );
    await settle(tester);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'notice keeps Continue reachable on small screens and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final fixture = (await tester.runAsync(() => details(db)))!;
      await preparePhoto(tester, fixture.photos.first.localUri);
      await tester.pumpWidget(
        noticeScreen(
          live(fixture, model([2, 3])),
          PlantActionRepository(db, 'farmer'),
          scale: 2,
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('plant_action_notice')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeNotice(tester);
      expect(find.byKey(const Key('plant_action_notice')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('clear, unavailable, and completed plants do not raise notices', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final fixture = (await tester.runAsync(() => details(db)))!;
    final store = PlantActionRepository(db, 'farmer');
    for (final data in [
      live(fixture, null),
      live(fixture, model([], label: 'No FAW damage')),
      live(fixture, model([2]), reviewed: true),
    ]) {
      await tester.pumpWidget(
        noticeScreen(data, store, revision: identityHashCode(data).toString()),
      );
      await settle(tester);
      expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late screening cannot open a notice for the previous plant', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final fixture = (await tester.runAsync(() => details(db)))!;
    final store = PlantActionRepository(db, 'farmer');
    final delayed = Completer<GuidedPlantDetails>();
    final old = live(fixture, model([2]));
    await tester.pumpWidget(
      noticeScreen(old, store, loader: () => delayed.future),
    );
    await tester.pump();
    await tester.pumpWidget(
      noticeScreen(
        live(fixture, model([], label: 'No FAW damage'), number: 2),
        store,
        revision: 'next-plant',
      ),
    );
    delayed.complete(old);
    await settle(tester);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    expect(
      await tester.runAsync(
        () => store.pendingNotices(old.photos.first.assessmentId, [
          PlantActionGuide.larva,
        ]),
      ),
      [PlantActionGuide.larva],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notice waits for the camera route to close', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final fixture = (await tester.runAsync(() => details(db)))!;
    final store = PlantActionRepository(db, 'farmer');
    await preparePhoto(tester, fixture.photos.first.localUri);
    final data = live(fixture, model([2]));
    await tester.pumpWidget(noticeScreen(data, store, enabled: false));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Camera open'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(noticeScreen(data, store, revision: 'screened'));
    await settle(tester);
    expect(find.text('Camera open'), findsOneWidget);
    expect(find.byKey(const Key('plant_action_notice')), findsNothing);
    navigator.pop();
    await settle(tester);
    expect(find.text('Larva detected'), findsOneWidget);
    await closeNotice(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'first use compares offline photos; later use is compact, optional and undoable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final data = (await tester.runAsync(() => details(db)))!;
      final store = PlantActionRepository(db, 'farmer');
      await preparePhoto(tester, data.photos.first.localUri);
      await tester.pumpWidget(screen(data, store));
      await settle(tester);
      expect(find.text('Your photo'), findsOneWidget);
      expect(find.text('FAW larva'), findsOneWidget);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null)
            .length,
        2,
      );
      expect(find.textContaining('tweezers or small forceps'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Save and next plant'), findsOneWidget);
      await capture(tester, 'plant-action-first-use');
      await tester.tap(find.text('FAW larva'));
      // Tap the image itself to open the zoomable reference.
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plant_action_toggle_larva')));
      await settle(tester);
      expect(find.text('Your photo'), findsNothing);
      await capture(tester, 'plant-action-repeat-use');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        screen(data, PlantActionRepository(db, 'farmer'), revision: 'reopened'),
      );
      await settle(tester);
      expect(find.text('Show less'), findsNothing);
      expect(find.text('How'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plant_action_record_larva')));
      await settle(tester);
      expect(find.text('Removal recorded'), findsOneWidget);
      expect(modelSampledInfestation(data.diagnosis), true);
      await tester.tap(find.byKey(const ValueKey('plant_action_undo_larva')));
      await settle(tester);
      expect(find.text('Removed and destroyed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'historical evidence uses inspection timing and large text does not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final data = (await tester.runAsync(() => details(db)))!;
      await preparePhoto(tester, data.photos.first.localUri);
      await tester.pumpWidget(
        screen(
          data,
          PlantActionRepository(db, 'farmer'),
          atPlant: false,
          scale: 1.7,
        ),
      );
      await settle(tester);
      expect(find.text('When you inspect this plant'), findsOneWidget);
      expect(find.text('At this plant'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DecodedPhoto extends ImageStreamCompleter {
  _DecodedPhoto(ImageInfo image) {
    setImage(image);
  }
}
