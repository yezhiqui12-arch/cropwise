import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/screens/assess/assessment_results_screen.dart';
import 'package:wormwise/screens/assess/da_findings_overview.dart';
import 'package:wormwise/models/da_assessment_results.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';
import '../support/da_results_fixture.dart';

void main() {
  final output = Platform.environment['CROPWISE_RESULTS_PREVIEW'];
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (output == null) return;
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              'C:/src/flutter/bin/cache/artifacts/material_fonts/${font.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (output == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('results_capture')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tapInViewport(WidgetTester tester, Finder target) async {
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView).first)
        .controller!;
    for (var i = 0; i < 25; i++) {
      final y = tester.getCenter(target).dy;
      if (y >= 260 && y <= 680) break;
      controller.jumpTo(
        (controller.offset + (y > 680 ? 80 : -80)).clamp(
          0,
          controller.position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'actual DA results and recommended steps at text scale $scale',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(() => db.close()));
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
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
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: output == null ? null : 'Roboto',
                colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
                scaffoldBackgroundColor: AppColors.background,
              ),
              builder: (context, child) => RepaintBoundary(
                key: const Key('results_capture'),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: AssessmentResultsScreen(assessmentId: detail.assessment.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('da_findings_overview')), findsOneWidget);
        expect(find.text('20.0%'), findsWidgets);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'app-results-${scale == 1 ? 'phone' : 'large-text'}',
        );
        await tester.tap(find.text('Recommendations'));
        await tester.pumpAndSettle();
        expect(find.text('More steps'), findsNothing);
        expect(
          find.byKey(const Key('assessment_interpretation_panel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('field_interpretation_details')),
          findsNothing,
        );
        expect(find.text('4 plants flagged for damage'), findsOneWidget);
        await capture(
          tester,
          'app-recommendations-${scale == 1 ? 'phone' : 'large-text'}',
        );
        expect(find.byType(ExpansionTile), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('view_interpretation_results')),
          150,
        );
        await tapInViewport(
          tester,
          find.byKey(const Key('view_interpretation_results')),
        );
        expect(
          find.byKey(const Key('assessment_action_modal')),
          findsOneWidget,
        );
        expect(find.text('Provisional sampled infestation'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        final damageStep = find.text('Review the damage flagged by the app');
        await tester.scrollUntilVisible(find.text('Recommended steps'), 150);
        expect(find.text('Recommended steps'), findsOneWidget);
        await capture(
          tester,
          'app-compact-steps-${scale == 1 ? 'phone' : 'large-text'}',
        );
        await tester.scrollUntilVisible(damageStep, 150);
        expect(
          find.textContaining(
            'Open these plant photos and check the visible injury',
          ),
          findsNothing,
        );
        await tapInViewport(tester, damageStep);
        expect(
          find.textContaining(
            'Open these plant photos and check the visible injury',
          ),
          findsOneWidget,
        );
        expect(find.text('View plant evidence'), findsOneWidget);
        expect(
          find.byKey(const Key('assessment_action_modal')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'app-recommendation-modal-${scale == 1 ? 'phone' : 'large-text'}',
        );
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assessment_action_modal')), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Verify potential larvae'),
          200,
        );
        expect(
          find.textContaining('Block 1 · Plants 1, 2, 3, 4'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'app-recommended-plant-checks-${scale == 1 ? 'phone' : 'large-text'}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }
  testWidgets(
    'finalized report separates expert severity, infestation and screening',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = (await tester.runAsync(
        () => daResultsFixture(db, infestationDetections: true),
      ))!;
      final sample = DaSampleResults.fromDetail(detail);
      final expert = DaExpertResults.fromRatings(
        sample: sample,
        summary: ExpertSeveritySummary(
          reviewedPlants: 20,
          scoredPlants: 20,
          insufficientPlants: 0,
          medianDavisScore: 3,
          finalizedAt: DateTime(2026, 10, 11),
        ),
        ratings: [
          for (final plant in sample.plants)
            ExpertPlantRating(
              stationNumber: plant.stationNumber,
              plantNumber: 1,
              blockRunId: plant.prepared.run.id,
              outcome: 'scored',
              davisScore: 3,
              damageFreshness: plant.stationNumber <= 10 ? 'fresh' : 'old_only',
              note: '',
              photos: const [],
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: output == null ? null : 'Roboto'),
          home: RepaintBoundary(
            key: const Key('results_capture'),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DaFindingsOverview(
                  sample: sample,
                  expert: expert,
                  finalized: true,
                  loading: false,
                  failed: false,
                  onReview: () {},
                  onExplain: () {},
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3.00 / 9'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
      expect(find.text('Current sampled infestation'), findsOneWidget);
      expect(find.text('Original app damage screening'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'app-results-expert-finalized');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => db.close());
    },
  );
}
