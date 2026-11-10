import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/screens/assess/assessment_results_screen.dart';
import 'package:wormwise/screens/assess/da_assessment_results_section.dart';
import 'package:wormwise/screens/advisor/guidelines_redesign.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';
import '../support/da_results_fixture.dart';
import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase db;
  final previewPath = Platform.environment['CROPWISE_RESULTS_PREVIEW'];
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (previewPath == null) return;
    final directory =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$directory/${entry.value}',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  const previewKey = Key('da_results_preview');
  Future<void> capture(WidgetTester tester, String suffix) async {
    if (previewPath == null) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(previewKey),
      );
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        previewPath.replaceFirst('.png', '-$suffix.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  Widget harness(Widget child, {double scale = 1}) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: previewPath == null ? null : 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: RepaintBoundary(
      key: previewKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Assessment results')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  ExpertReviewCase review(String id, {int count = 3}) => ExpertReviewCase(
    id: id,
    assessmentId: 'unused',
    fieldName: 'Corn plot',
    location: '',
    status: 'reviewed',
    createdAt: DateTime.utc(2026, 10, 6),
    messages: const [],
    severitySummary: ExpertSeveritySummary(
      reviewedPlants: count,
      scoredPlants: count,
      insufficientPlants: 0,
      medianDavisScore: 3,
      finalizedAt: DateTime.utc(2026, 10, 6),
    ),
  );
  final ratings = [
    for (var i = 0; i < 3; i++)
      ExpertPlantRating(
        stationNumber: i + 1,
        plantNumber: 1,
        outcome: 'scored',
        davisScore: [3, 4, 0][i],
        note: '',
        photos: const [],
      ),
  ];
  Widget view(
    AssessmentHistoryDetail detail, {
    ExpertReviewCase? expert,
    Future<List<ExpertPlantRating>> Function()? load,
    VoidCallback? submit,
    VoidCallback? recommendations,
    EvidenceStorageService? storage,
  }) => DaAssessmentResultsView(
    detail: detail,
    storage: storage ?? EvidenceStorageService(),
    reportStatus: 0,
    onSubmit: submit ?? () {},
    onRecommendations: recommendations ?? () {},
    reviewCase: expert,
    loadRatings: load,
  );

  testWidgets(
    'sample view switches between two-column tiles and full-width rows',
    (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await tester.pumpWidget(harness(view(detail)));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('da_sampled_plants'))),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const Key('da_plant_card_1_1'));
      final second = find.byKey(const Key('da_plant_card_1_2'));
      final third = find.byKey(const Key('da_plant_card_1_3'));
      expect(find.byKey(const Key('da_plant_grid_1')), findsOneWidget);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(second).dx,
        greaterThan(tester.getTopLeft(first).dx),
      );
      expect(
        tester.getTopLeft(third).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(tester.getSize(first), tester.getSize(second));
      await tester.ensureVisible(find.byKey(const Key('da_plant_view_list')));
      await tester.tap(find.byKey(const Key('da_plant_view_list')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('da_plant_grid_1')), findsNothing);
      expect(find.byKey(const Key('da_plant_list_1')), findsOneWidget);
      expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getBottomLeft(first).dy),
      );
      expect(tester.getSize(first).width, 328);
      await tester.ensureVisible(
        find.byKey(const Key('da_plant_filter_infested')),
      );
      await tester.tap(find.byKey(const Key('da_plant_filter_infested')));
      await tester.pumpAndSettle();
      expect(find.text('Plant 4'), findsOneWidget);
      expect(find.text('Plant 5'), findsNothing);
      expect(find.byKey(const Key('da_plant_list_1')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('da_plant_view_grid')));
      await tester.tap(find.byKey(const Key('da_plant_view_grid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('da_plant_grid_1')), findsOneWidget);
      expect(find.text('Plant 4'), findsOneWidget);
      expect(find.text('Plant 5'), findsNothing);
      await capture(tester, 'grid-phone');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small phone keeps grid columns at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = (await tester.runAsync(
      () => daResultsFixture(db, infestationDetections: true),
    ))!;
    await tester.pumpWidget(
      harness(
        view(detail, expert: review('grid-expert'), load: () async => ratings),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('da_sampled_plants'))),
      alignment: 0,
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const Key('da_plant_card_1_1'));
    final second = find.byKey(const Key('da_plant_card_1_2'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(
      tester.getTopLeft(second).dx,
      greaterThan(tester.getTopLeft(first).dx),
    );
    expect(find.text('Davis 0/9'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('da_plant_view_list')));
    await tester.tap(find.byKey(const Key('da_plant_view_list')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(second).dy,
      greaterThan(tester.getBottomLeft(first).dy),
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'list-large-text');
  });

  testWidgets(
    'twenty plants, rate, pending expert state, filters, and submit action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      var submissions = 0;
      await tester.pumpWidget(
        harness(view(detail, submit: () => submissions++)),
      );
      await tester.pumpAndSettle();
      expect(find.text('20 of 20 plants recorded'), findsOneWidget);
      expect(find.text('Sample completion'), findsNothing);
      expect(find.text('View recommendations'), findsNothing);
      expect(find.text('Sample details'), findsOneWidget);
      expect(find.text('20.0%'), findsNWidgets(2));
      expect(
        find.text('4 of 20 assessable plants show damage'),
        findsOneWidget,
      );
      expect(find.text('Awaiting expert review'), findsOneWidget);
      expect(find.text('Plant 20'), findsOneWidget);
      if (previewPath != null)
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(previewKey),
          );
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      await tester.ensureVisible(find.text('Submit assessment'));
      await tester.tap(find.text('Submit assessment'));
      expect(submissions, 1);
      final positiveFilter = find.byKey(const Key('da_plant_filter_infested'));
      await tester.ensureVisible(positiveFilter);
      if (previewPath != null) {
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('da_sampled_plants'))),
          alignment: 0,
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(previewKey),
          );
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            previewPath.replaceFirst('.png', '-plants.png'),
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('da_sampled_plants')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
      await tester.tap(positiveFilter);
      await tester.pumpAndSettle();
      expect(find.text('Plant 4'), findsOneWidget);
      expect(find.text('Plant 5'), findsNothing);
      expect(
        find.descendant(of: positiveFilter, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      final unavailableFilter = find.byKey(
        const Key('da_plant_filter_unavailable'),
      );
      await tester.tap(unavailableFilter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('da_plants_empty')), findsOneWidget);
      expect(find.text('All recorded plants have results'), findsOneWidget);
      await tester.tap(find.byKey(const Key('da_plant_filter_all')));
      await tester.pumpAndSettle();
      expect(find.text('Plant 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'finalized old-only damage replaces detector infestation in phone results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await tester.pumpWidget(harness(view(detail)));
      await tester.pumpAndSettle();
      expect(find.text('4 of 20 assessable plants infested'), findsOneWidget);
      final oldOnly = [
        for (var i = 1; i <= 20; i++)
          ExpertPlantRating(
            stationNumber: i,
            plantNumber: 1,
            outcome: 'scored',
            davisScore: i <= 4 ? 3 : 0,
            damageFreshness: i <= 4 ? 'old_only' : null,
            note: '',
            photos: const [],
          ),
      ];
      await tester.pumpWidget(
        harness(
          view(
            detail,
            expert: review('final', count: 20),
            load: () async => oldOnly,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expert findings'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('20 Not infested'), findsOneWidget);
      expect(find.text('4 of 20 assessable plants infested'), findsNothing);
      expect(
        find.text('4 of 20 assessable plants show damage'),
        findsOneWidget,
      );
      await capture(tester, 'expert-old-only');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'finalized average and zero score appear with partial review coverage',
    (tester) async {
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await tester.pumpWidget(
        harness(view(detail, expert: review('one'), load: () async => ratings)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.33 / 9'), findsOneWidget);
      expect(
        find.text('3 of 20 sampled plants scored · 0 insufficient evidence'),
        findsOneWidget,
      );
      expect(find.textContaining('Davis 0/9'), findsOneWidget);
      expect(find.text('Submit assessment'), findsNothing);
      expect(find.text('Open expert review'), findsOneWidget);
      await capture(tester, 'finalized');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed rating fetch offers retry without a fabricated score', (
    tester,
  ) async {
    final detail = (await tester.runAsync(
      () => daResultsFixture(db, infestationDetections: true),
    ))!;
    var calls = 0;
    await tester.pumpWidget(
      harness(
        view(
          detail,
          expert: review('one'),
          load: () async {
            calls++;
            if (calls == 1) throw StateError('Offline');
            return ratings;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expert review unavailable'), findsOneWidget);
    expect(find.text('0.00 / 9'), findsNothing);
    await tester.ensureVisible(find.text('Retry ratings'));
    await tester.tap(find.text('Retry ratings'));
    await tester.pumpAndSettle();
    expect(find.text('2.33 / 9'), findsOneWidget);
  });
  testWidgets(
    'a changed finalized review does not display the old average while loading',
    (tester) async {
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await tester.pumpWidget(
        harness(view(detail, expert: review('one'), load: () async => ratings)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.33 / 9'), findsOneWidget);
      final pending = Completer<List<ExpertPlantRating>>();
      await tester.pumpWidget(
        harness(
          view(detail, expert: review('two'), load: () => pending.future),
        ),
      );
      await tester.pump();
      expect(find.text('2.33 / 9'), findsNothing);
      expect(find.text('Checking expert review…'), findsOneWidget);
      pending.complete(ratings);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'small screen and 200 percent text keep preliminary results usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(
          db,
          recorded: 10,
          positives: 4,
          unavailable: 2,
          infestationDetections: true,
        ),
      ))!;
      await tester.pumpWidget(harness(view(detail), scale: 2));
      await tester.pumpAndSettle();
      expect(find.text('50.0%'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('4 no damage detected. 2 screening unavailable.'),
        findsOneWidget,
      );
      await capture(tester, 'large-text');
      await tester.ensureVisible(find.text('Continue scouting'));
      await tester.ensureVisible(
        find.byKey(const Key('da_plant_filter_unavailable')),
      );
      await tester.tap(find.byKey(const Key('da_plant_filter_unavailable')));
      await tester.pumpAndSettle();
      expect(find.text('Plant 9'), findsOneWidget);
      expect(find.text('Plant 8'), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('da_sampled_plants'))),
        alignment: 0,
      );
      await capture(tester, 'unavailable-large-text');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy results retain the Stations tab and original results section',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = (await tester.runAsync(() async {
        final fixture = await historyFixture(db, status: 'completed');
        await historyStation(db, fixture.field, fixture.assessment);
        return fixture.assessment.id;
      }))!;
      await tester.pumpWidget(
        WormWiseDataScope(
          database: db,
          disposeDatabase: false,
          dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
          child: MaterialApp(home: AssessmentResultsScreen(assessmentId: id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stations'), findsOneWidget);
      expect(find.text('Plants'), findsNothing);
      expect(find.byType(DaAssessmentResultsSection), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => db.close());
    },
  );
  testWidgets(
    'actual results destination shows Results and recommendations link to Guidelines',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      await tester.pumpWidget(
        WormWiseDataScope(
          database: db,
          disposeDatabase: false,
          dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
          child: RepaintBoundary(
            key: previewKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: previewPath == null ? null : 'Roboto',
                scaffoldBackgroundColor: AppColors.background,
                colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
              ),
              home: AssessmentResultsScreen(assessmentId: detail.assessment.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Plants'), findsNothing);
      expect(find.text('Stations'), findsNothing);
      await capture(tester, 'actual-overview');
      await tester.scrollUntilVisible(
        find.byKey(const Key('da_damage_screening')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('4 of 20 assessable plants show damage'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('da_sampled_plants')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('da_sampled_plants'))),
        alignment: 0,
      );
      await capture(tester, 'actual-plants');
      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();
      expect(find.text('Assessment submission'), findsNothing);
      expect(find.text('Field management'), findsNothing);
      expect(find.byKey(const Key('queue_report_button')), findsNothing);
      await capture(tester, 'actual-recommendations');
      await tester.tap(find.byTooltip('Step details').first);
      await tester.pumpAndSettle();
      expect(find.text('Close'), findsOneWidget);
      await capture(tester, 'recommendation-details');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('assessment_guidelines_link')),
        250,
      );
      expect(find.text('Guidelines'), findsOneWidget);
      final interpretation = find.byKey(
        const PageStorageKey('results_disclosure_Field interpretation'),
      );
      await tester.scrollUntilVisible(interpretation, 250);
      await Scrollable.ensureVisible(
        tester.element(find.text('Field interpretation')),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Field interpretation'));
      // Expanding can reveal an unrelated in-flight advice spinner. Check the
      // disclosure after its animation without waiting for that service.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Use AI advice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('assessment_guidelines_link')),
        -250,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('assessment_guidelines_link'))),
        alignment: .3,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('assessment_guidelines_link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AdvisorOfflineGuidesScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AssessmentResultsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => db.close());
    },
  );
  testWidgets('DA results tabs and actions remain usable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = (await tester.runAsync(
      () => daResultsFixture(db, recorded: 10),
    ))!;
    await tester.pumpWidget(
      WormWiseDataScope(
        database: db,
        disposeDatabase: false,
        dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
        child: RepaintBoundary(
          key: previewKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: previewPath == null ? null : 'Roboto',
              scaffoldBackgroundColor: AppColors.background,
              colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AssessmentResultsScreen(assessmentId: detail.assessment.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'actual-large-text');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    await capture(tester, 'recommendations-large-text');
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_guidelines_link')),
      250,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('assessment_guidelines_link'))),
      alignment: .3,
    );
    await capture(tester, 'guidelines-large-text');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue scouting'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => db.close());
  });
  testWidgets('photo cards show real evidence and open the selected plant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = (await tester.runAsync(
      () => daResultsFixture(db, recorded: 4),
    ))!;
    final now = DateTime.now();
    final detail = AssessmentHistoryDetail(
      assessment: source.assessment,
      workspace: source.workspace,
      evaluator: source.evaluator,
      stations: source.stations,
      units: source.units,
      safety: source.safety,
      missingBlocks: source.missingBlocks,
      readiness: source.readiness,
      resultSummary: source.resultSummary,
      metrics: source.metrics,
      evidence: [
        for (final plant in source.stations.take(4))
          AssessmentEvidenceEntry(
            EvidenceMediaRecord(
              id: 'preview_${plant.stationNumber}',
              createdAt: now,
              updatedAt: now,
              syncState: DatabaseCodes.localOnly,
              serverVersion: 0,
              assessmentId: source.assessment.id,
              stationId: plant.station!.id,
              captureSessionId: 'preview',
              mediaType: 'image',
              viewType: DatabaseCodes.evidenceViewWhorlOverview,
              localUri: plant.stationNumber.isOdd
                  ? 'assets/images/growth_stages/maize_young_vegetative.jpg'
                  : 'assets/images/growth_stages/maize_tall_vegetative.jpg',
              mimeType: 'image/jpeg',
              byteSize: 0,
              sha256Checksum: 'preview',
              capturedAt: now,
              qualityStatus: DatabaseCodes.evidenceQualityEvaluatorConfirmed,
              captureSource: DatabaseCodes.evidenceCaptureSourceCamera,
              storageState: DatabaseCodes.evidenceStorageReady,
              locationSource: 'unavailable',
              uploadState: DatabaseCodes.localOnly,
              isCanonicalEvidence: true,
            ),
            'Plant ${plant.stationNumber}',
            stationId: plant.station!.id,
            plantObservationId: plant.plants.first.plant.id,
            plantPosition: 1,
            scopeType: DatabaseCodes.evidenceScopePlant,
          ),
      ],
    );
    final storage = EvidenceStorageService(
      rootDirectory: () async => Directory.current,
    );
    await tester.runAsync(() async {
      for (final uri in detail.evidence.map((e) => e.media.localUri).toSet()) {
        final file = await storage.resolve(uri);
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        final frame = await codec.getNextFrame();
        PaintingBinding.instance.imageCache.putIfAbsent(
          FileImage(file),
          () => _DecodedPhoto(ImageInfo(image: frame.image)),
        );
        codec.dispose();
      }
    });
    await tester.pumpWidget(harness(view(detail, storage: storage)));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('da_sampled_plants'))),
      alignment: 0,
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await capture(tester, 'photo-cards');
    await tester.ensureVisible(find.byKey(const Key('da_plant_view_list')));
    await tester.tap(find.byKey(const Key('da_plant_view_list')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('da_sampled_plants'))),
      alignment: 0,
    );
    await capture(tester, 'photo-list');
    await tester.ensureVisible(find.byKey(const Key('da_plant_view_grid')));
    await tester.tap(find.byKey(const Key('da_plant_view_grid')));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('da_plant_card_1_1'));
    expect(
      find.descendant(of: card, matching: find.byType(Image)),
      findsOneWidget,
    );
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Plant 1 details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DecodedPhoto extends ImageStreamCompleter {
  _DecodedPhoto(ImageInfo image) {
    setImage(image);
  }
}
