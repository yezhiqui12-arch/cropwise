import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/screens/advisor/advisor_screen.dart';
import 'package:wormwise/screens/advisor/guidelines_redesign.dart';
import 'package:wormwise/screens/assess/assessment_assistant_screen.dart';
import 'package:wormwise/screens/assess/assessment_details_screen.dart';
import 'package:wormwise/screens/assess/assessment_results_screen.dart';
import 'package:wormwise/theme/app_theme.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';

import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Widget harness(
    Widget child, {
    double textScale = 1,
    AppDataMode dataMode = const AppDataMode.production(
      debugFeaturesEnabled: false,
    ),
  }) => WormWiseDataScope(
    database: database,
    disposeDatabase: false,
    dataMode: dataMode,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    ),
  );

  testWidgets('assessment details opens the results destination', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'in_progress');

    await tester.pumpWidget(
      harness(AssessmentDetailsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assessment_results_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_results_empty')),
      300,
    );
    expect(find.text('No current metrics available'), findsOneWidget);
    expect(find.text('PRELIMINARY SAVED METRICS'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('vegetative metric shows its exact saved denominator', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.vegetativeCurrentInfestationPercent,
      numerator: 8,
      denominator: 50,
      value: 16,
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsOneWidget);
    expect(
      find.byKey(const Key('results_verification_warning')),
      findsOneWidget,
    );
    expect(find.text('Current infestation'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('primary_metric_card')),
        matching: find.byIcon(Icons.eco_rounded),
      ),
      findsNothing,
    );
    expect(
      find.text('This is field data, not a treatment recommendation.'),
      findsNothing,
    );
    expect(find.text('16%'), findsOneWidget);
    expect(find.text('8 of 50 assessable plants'), findsOneWidget);
    expect(
      find.text('Based on saved assessment data. Not a live reading.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_sampling_quality')),
      220,
    );
    expect(
      find.byKey(const Key('assessment_sampling_quality')),
      findsOneWidget,
    );
    await _disposeHarness(tester);
  });

  testWidgets('VE-V2 labels the living-seedling denominator explicitly', (
    tester,
  ) async {
    final fixture = await historyFixture(
      database,
      status: 'completed',
      stage: 'v2',
    );
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.vegetativeCurrentInfestationPercent,
      numerator: 4,
      denominator: 42,
      value: 9.5,
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 of 42 assessable seedlings'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('V7-V12 displays the saved DA-BAFS score distribution', (
    tester,
  ) async {
    final fixture = await historyFixture(
      database,
      status: 'completed',
      stage: 'v7_v12',
    );
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.daBafsMedianScore,
      numerator: 50,
      denominator: 50,
      value: 3,
      unit: 'ordinal_score',
      distribution:
          '{"counts":{"1":10,"3":30,"5":10},"minimum":1,"maximum":5,"uncertain_count":2}',
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('DA-BAFS median leaf-damage score'), findsWidgets);
    expect(find.text('Observed score range 1–5 · 2 uncertain'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('VT-R2 uses its separate infested-plant result', (tester) async {
    final fixture = await historyFixture(
      database,
      status: 'completed',
      stage: 'vt_r2',
    );
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.vtR2InfestedPlantPercent,
      numerator: 10,
      denominator: 50,
      value: 20,
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('VT-R2 infested plants'), findsOneWidget);
    expect(find.text('10 of 50 assessable plants'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('zero denominator is unavailable rather than zero', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.openedEarInternalDamagePercent,
      numerator: 0,
      denominator: 0,
      value: null,
      warning: 'zero_denominator',
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('The combined denominator is zero.'), findsOneWidget);
    expect(find.textContaining('No partial result is shown'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    await _disposeHarness(tester);
  });

  testWidgets('R3-R6 explains opened-ear and yield boundaries', (tester) async {
    _setLargeViewport(tester);
    final fixture = await historyFixture(
      database,
      status: 'completed',
      stage: 'r3_r6',
    );
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.pooledDamagedKernelPercent,
      numerator: 180,
      denominator: 2400,
      value: 7.5,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.externalEarDamagePercent,
      numerator: 18,
      denominator: 50,
      value: 36,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.openedEarInternalDamagePercent,
      numerator: 4,
      denominator: 10,
      value: 40,
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('results_interpretation_boundary')),
      300,
    );
    expect(find.textContaining('opened subsample'), findsWidgets);
    expect(find.textContaining('not estimated yield loss'), findsWidgets);
    final blockFinder = find.byKey(
      PageStorageKey('block_results_${station.assessmentBlockRunId}'),
    );
    await tester.scrollUntilVisible(blockFinder, 300);
    await tester.ensureVisible(blockFinder);
    await tester.tap(blockFinder);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'result_metric_${DatabaseCodes.externalEarDamagePercent}_${station.assessmentBlockRunId}',
        ),
      ),
      300,
    );
    expect(find.text('18 of 50 externally assessable ears'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'result_metric_${DatabaseCodes.openedEarInternalDamagePercent}_${station.assessmentBlockRunId}',
        ),
      ),
      300,
    );
    expect(find.text('4 of 10 opened ears'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'result_metric_${DatabaseCodes.pooledDamagedKernelPercent}_${station.assessmentBlockRunId}',
        ),
      ),
      300,
    );
    expect(find.text('7.5%'), findsOneWidget);
    expect(
      find.text('180 of 2400 assessable kernels in opened ears'),
      findsOneWidget,
    );
    await _disposeHarness(tester);
  });

  testWidgets('metrics from another formula version are not presented', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    final station = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: station.assessmentBlockRunId,
      code: DatabaseCodes.vegetativeCurrentInfestationPercent,
      numerator: 10,
      denominator: 50,
      value: 20,
      formulaVersion: 'obsolete-formula',
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_results_empty')),
      300,
    );
    expect(find.text('No current metrics available'), findsOneWidget);
    expect(find.text('20%'), findsNothing);
    await _disposeHarness(tester);
  });

  testWidgets('whole result weights exact counts and keeps block detail', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    final firstStation = await historyStation(
      database,
      fixture.field,
      fixture.assessment,
    );
    final secondBlock = await database
        .into(database.fieldBlocks)
        .insertReturning(
          FieldBlocksCompanion.insert(
            id: 'results-block-2',
            cropCycleId: fixture.field.cropCycle.id,
            boundaryVersionId: fixture.field.boundary!.id,
            blockNumber: 2,
            geometryGeojson: historyPolygon,
            areaHectares: .4,
          ),
        );
    final secondRun = await database
        .into(database.assessmentBlockRuns)
        .insertReturning(
          AssessmentBlockRunsCompanion.insert(
            id: 'results-run-2',
            assessmentId: fixture.assessment.id,
            fieldBlockId: secondBlock.id,
            blockSequence: 2,
            scoutingPattern: DatabaseCodes.patternW,
          ),
        );
    await AssessmentRepository(database).addStation(
      assessmentBlockRunId: secondRun.id,
      stationNumber: 1,
      latitude: 17.0005,
      longitude: 121.0005,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: firstStation.assessmentBlockRunId,
      code: DatabaseCodes.vegetativeCurrentInfestationPercent,
      numerator: 5,
      denominator: 50,
      value: 10,
    );
    await _metric(
      database,
      assessment: fixture.assessment,
      blockRunId: secondRun.id,
      code: DatabaseCodes.vegetativeCurrentInfestationPercent,
      numerator: 20,
      denominator: 50,
      value: 40,
    );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('25 of 100 assessable plants'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(
        PageStorageKey('block_results_${firstStation.assessmentBlockRunId}'),
      ),
      300,
    );
    expect(find.text('Block 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Block 2'), 300);
    expect(find.text('Block 2'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PageStorageKey('block_results_${secondRun.id}')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'result_metric_${DatabaseCodes.vegetativeCurrentInfestationPercent}_${secondRun.id}',
        ),
      ),
      300,
    );
    expect(find.text('40%'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('results support a narrow screen and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await historyFixture(database, status: 'completed');

    await tester.pumpWidget(
      harness(
        AssessmentResultsScreen(assessmentId: fixture.assessment.id),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assessment_results_hero')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeHarness(tester);
  });

  testWidgets('test mode preserves [TEST DATA] and shows test data banner', (
    tester,
  ) async {
    final fixture = await historyFixture(
      database,
      name: '[TEST DATA] Five-station maize field',
      status: 'completed',
    );

    await tester.pumpWidget(
      harness(
        AssessmentResultsScreen(assessmentId: fixture.assessment.id),
        dataMode: const AppDataMode(isTestMode: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permanent_test_data_indicator')),
      findsOneWidget,
    );
    expect(
      find.text('TEST DATA · Separate from farmer records'),
      findsOneWidget,
    );
    expect(find.text('[TEST DATA] Five-station maize field'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets(
    'normal mode strips [TEST DATA] from field name and hides banner',
    (tester) async {
      final fixture = await historyFixture(
        database,
        name: '[TEST DATA] Normal Farm Field',
        status: 'completed',
      );

      await tester.pumpWidget(
        harness(
          AssessmentResultsScreen(assessmentId: fixture.assessment.id),
          dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permanent_test_data_indicator')),
        findsNothing,
      );
      expect(find.text('Normal Farm Field'), findsOneWidget);
      expect(find.textContaining('[TEST DATA]'), findsNothing);
      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'AssessmentResultsScreen directly presents Stations and Recommendations tabs without intermediate button',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AssessmentResultsScreen), findsOneWidget);
      // Verify direct tabs are present
      expect(find.text('Stations'), findsOneWidget);
      expect(find.text('Recommendations'), findsOneWidget);

      // Verify no intermediate "View Details" button exists
      expect(
        find.byKey(const Key('results_view_details_button')),
        findsNothing,
      );

      // Verify Stations tab elements
      expect(
        find.byKey(const Key('recorded_evidence_4_across')),
        findsOneWidget,
      );
      expect(find.text('Evidence categories'), findsOneWidget);
      expect(find.text('Sampling stations'), findsOneWidget);

      // Switch directly to Recommendations tab
      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(find.text('Field interpretation'), findsOneWidget);
      expect(find.text('Recommended Next Steps'), findsOneWidget);
      expect(find.text('Send to an Expert'), findsOneWidget);
      expect(find.text('Management Guidance'), findsOneWidget);
      expect(find.text('Ask WormWise About This Assessment'), findsOneWidget);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'strict conditional egg filtering: eggCount == 0 produces NO egg next steps',
    (tester) async {
      final fixture = await historyFixture(database, status: 'completed');
      final station = await historyStation(
        database,
        fixture.field,
        fixture.assessment,
      );
      await _addVegetativePlant(
        database,
        stationId: station.id,
        position: 1,
        damage: true,
        larva: true,
        egg: false,
      );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(find.text('Recommended Next Steps'), findsOneWidget);
      expect(find.text('Recheck egg-positive locations'), findsNothing);
      expect(find.text('Review larval-positive observations'), findsOneWidget);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'strict conditional larva filtering: larvaCount == 0 produces NO larva next steps',
    (tester) async {
      final fixture = await historyFixture(database, status: 'completed');
      final station = await historyStation(
        database,
        fixture.field,
        fixture.assessment,
      );
      await _addVegetativePlant(
        database,
        stationId: station.id,
        position: 1,
        damage: true,
        larva: false,
        egg: true,
      );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(find.text('Recommended Next Steps'), findsOneWidget);
      expect(find.text('Review larval-positive observations'), findsNothing);
      expect(find.text('Recheck egg-positive locations'), findsOneWidget);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'station revisit next step tags the station with the highest recorded evidence count',
    (tester) async {
      final fixture = await historyFixture(database, status: 'completed');
      final station = await historyStation(
        database,
        fixture.field,
        fixture.assessment,
      );
      for (var i = 1; i <= 10; i++) {
        await _addVegetativePlant(
          database,
          stationId: station.id,
          position: i,
          damage: i <= 2,
          larva: i <= 2,
        );
      }

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(find.text('Revisit affected stations'), findsOneWidget);
      expect(find.text('Stn 1'), findsOneWidget);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'interpretation shows source footer and regenerate without photo findings badge',
    (tester) async {
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline guidance'), findsOneWidget);
      expect(find.text('Photo findings (Gemini)'), findsNothing);
      expect(
        find.byKey(const Key('regenerate_ai_interpretation_button')),
        findsOneWidget,
      );

      await _disposeHarness(tester);
    },
  );

  testWidgets('recommendations header fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await historyFixture(database, status: 'completed');
    await historyStation(database, fixture.field, fixture.assessment);

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();

    expect(find.text('Field interpretation'), findsOneWidget);
    expect(find.text('Photo findings (Gemini)'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeHarness(tester);
  });

  testWidgets(
    'cached AI results in AppPreferences are reused on screen reload',
    (tester) async {
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      final cacheKey = 'ai_assessment_result_v2_${fixture.assessment.id}';
      final cachedJson = jsonEncode({
        'interpretation': 'Pre-cached custom AI interpretation text.',
        'recommendations': [
          {
            'title': 'Pre-cached custom action',
            'description': 'Follow up on pre-cached inspection.',
            'type': 'monitoring',
            'stationNumbers': [1],
          },
        ],
        'isOffline': false,
        'generatedAt': '2026-09-12T08:00:00.000Z',
      });

      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              preferenceKey: cacheKey,
              preferenceValue: cachedJson,
              updatedAt: Value(DateTime.now()),
            ),
          );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pre-cached custom AI interpretation text.'),
        findsOneWidget,
      );
      expect(find.text('Pre-cached custom action'), findsOneWidget);
      expect(find.text('AI Analysis (Gemini)'), findsOneWidget);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'report submission stays on the results tab and opens its send dialog',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = (await tester.runAsync(() async {
        final fixture = await historyFixture(database, status: 'completed');
        await historyStation(database, fixture.field, fixture.assessment);
        return fixture;
      }))!;

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('queue_report_button')),
        300,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('queue_report_button'))),
        alignment: .3,
      );
      await tester.tap(find.byKey(const Key('queue_report_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Send to an expert'), findsOneWidget);
      expect(find.text('Farmer name'), findsOneWidget);
      expect(find.text('Share field location'), findsOneWidget);
      expect(find.text('Send securely'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Recommendations'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('queue_report_button')), findsNothing);

      await _disposeHarness(tester);
    },
  );

  testWidgets('recommendations open the Guidelines library', (tester) async {
    _setLargeViewport(tester);
    final fixture = (await tester.runAsync(() async {
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);
      return fixture;
    }))!;

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recommendations'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('queue_report_button')), findsNothing);
    expect(find.text('Management Guidance'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_guidelines_link')),
      300,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('assessment_guidelines_link'))),
      alignment: .3,
    );
    await tester.tap(find.byKey(const Key('assessment_guidelines_link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AdvisorOfflineGuidesScreen), findsOneWidget);
    expect(find.byType(AdvisorScreen), findsNothing);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AssessmentResultsScreen), findsOneWidget);

    await _disposeHarness(tester);
  });

  testWidgets('result tabs stay visible while station cards scroll', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    await historyStation(database, fixture.field, fixture.assessment);
    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sampling stations'), 300);
    expect(find.byKey(const Key('results_pinned_tabs')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('results_pinned_tabs'))).dy,
      lessThan(160),
    );
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Field interpretation'), 250);
    expect(find.text('Field interpretation'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets('tapping a next step sends it in the assessment assistant', (
    tester,
  ) async {
    final fixture = await historyFixture(database, status: 'completed');
    await historyStation(database, fixture.field, fixture.assessment);
    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('recommended_step_1')),
      260,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('recommended_step_1'))),
      alignment: 0.4,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recommended_step_1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(AssessmentAssistantScreen), findsOneWidget);
    expect(find.byType(AdvisorScreen), findsNothing);
    final row =
        await (database.select(database.appPreferences)..where(
              (tbl) => tbl.preferenceKey.equals(
                'assessment_assistant_thread_${fixture.assessment.id}',
              ),
            ))
            .getSingleOrNull();
    expect(row, isNotNull);
    expect(
      row!.preferenceValue,
      contains('Explain this recommended next step'),
    );
    await _disposeHarness(tester);
  });

  testWidgets(
    'Ask WormWise card opens the assessment-specific assistant instead of AdvisorScreen',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();

      expect(
        tester
            .getTopLeft(find.byKey(const Key('ask_wormwise_assessment_card')))
            .dy,
        lessThan(tester.getTopLeft(find.text('Field interpretation')).dy),
      );

      await tester.scrollUntilVisible(
        find.text('Ask WormWise About This Assessment'),
        300,
      );
      await tester.tap(find.text('Ask WormWise About This Assessment'));
      await tester.pumpAndSettle();

      expect(find.byType(AssessmentAssistantScreen), findsOneWidget);
      expect(find.byType(AdvisorScreen), findsNothing);

      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'station cards omit View Photos and do not overflow at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fixture = await historyFixture(database, status: 'completed');
      final station = await historyStation(
        database,
        fixture.field,
        fixture.assessment,
      );
      await _addVegetativePlant(
        database,
        stationId: station.id,
        position: 1,
        damage: true,
        frass: true,
        larva: true,
      );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sampling stations'), 300);

      expect(find.textContaining('View Photos'), findsNothing);
      expect(find.text('Station 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'recorded evidence is four across and bottom actions persist on both tabs',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recorded_evidence_4_across')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('persistent_results_action_bar')),
        findsOneWidget,
      );
      expect(find.text('View Map'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);

      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('persistent_results_action_bar')),
        findsOneWidget,
      );
      expect(find.text('View Map'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      await _disposeHarness(tester);
    },
  );

  testWidgets('management guidance cards use equal height', (tester) async {
    _setLargeViewport(tester);
    final fixture = await historyFixture(database, status: 'completed');
    await historyStation(database, fixture.field, fixture.assessment);

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('guidance_cultural_card')),
      300,
    );

    final cultural = tester.getSize(
      find.byKey(const Key('guidance_cultural_card')),
    );
    final predators = tester.getSize(
      find.byKey(const Key('guidance_predators_card')),
    );
    expect(cultural.height, predators.height);
    await _disposeHarness(tester);
  });

  testWidgets(
    'Ask WormWise remains collapsed when user exits without sending a message',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ask WormWise About This Assessment'),
        300,
      );
      await tester.tap(find.text('Ask WormWise About This Assessment'));
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentAssistantScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Continue conversation'), findsNothing);
      expect(
        find.text('Get insights and field guidance based on your results.'),
        findsOneWidget,
      );
      await _disposeHarness(tester);
    },
  );

  testWidgets(
    'Ask WormWise card expands only when the assessment has saved conversation',
    (tester) async {
      _setLargeViewport(tester);
      final fixture = await historyFixture(database, status: 'completed');
      await historyStation(database, fixture.field, fixture.assessment);
      final thread = jsonEncode({
        'assessmentId': fixture.assessment.id,
        'messages': [
          {
            'role': 'user',
            'text': 'Why did this station stand out?',
            'createdAt': '2026-09-12T08:00:00.000Z',
          },
          {
            'role': 'assistant',
            'text':
                'It has the highest recorded evidence count in this assessment.',
            'createdAt': '2026-09-12T08:00:01.000Z',
          },
        ],
      });
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              preferenceKey:
                  'assessment_assistant_thread_${fixture.assessment.id}',
              preferenceValue: thread,
              updatedAt: Value(DateTime.now()),
            ),
          );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recommendations'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Continue conversation'), 300);

      expect(find.text('Continue conversation'), findsOneWidget);
      expect(
        find.textContaining('Why did this station stand out?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('highest recorded evidence count'),
        findsOneWidget,
      );
      await _disposeHarness(tester);
    },
  );

  testWidgets('queued report state is restored when results reopen', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final fixture = await historyFixture(database, status: 'completed');
    await historyStation(database, fixture.field, fixture.assessment);
    await database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: 'report_assessment_${fixture.assessment.id}',
            entityType: 'assessment_report',
            entityId: fixture.assessment.id,
            operation: 'lgu_report_sync',
            payloadJson: const Value('{"schemaVersion":1}'),
            status: const Value('queued'),
          ),
        );

    await tester.pumpWidget(
      harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Queued locally'), 300);

    expect(find.text('Queued locally'), findsOneWidget);
    await _disposeHarness(tester);
  });

  testWidgets(
    'kernel-based primary metric keeps kernel denominator semantics',
    (tester) async {
      final fixture = await historyFixture(
        database,
        status: 'completed',
        stage: 'r3_r6',
      );
      final station = await historyStation(
        database,
        fixture.field,
        fixture.assessment,
      );
      await _metric(
        database,
        assessment: fixture.assessment,
        blockRunId: station.assessmentBlockRunId,
        code: DatabaseCodes.pooledDamagedKernelPercent,
        numerator: 180,
        denominator: 2400,
        value: 7.5,
      );

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pooled damaged kernels'), findsWidgets);
      expect(
        find.text('180 of 2400 assessable kernels in opened ears'),
        findsOneWidget,
      );
      await _disposeHarness(tester);
    },
  );

  testWidgets('results use the shared app bar and a responsive record card', (
    tester,
  ) async {
    final fixture = await historyFixture(
      database,
      name:
          'Very Long Field Plot Name Located in Remote Barangay Northern Extension',
      status: 'completed',
      stage: 'v3_v6',
    );
    await historyStation(database, fixture.field, fixture.assessment);

    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        harness(AssessmentResultsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();

      // Hero is present
      expect(find.byKey(const Key('assessment_results_hero')), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Assessment results'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      final fieldImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('assessment_results_hero')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (fieldImage.image as AssetImage).assetName,
        'assets/images/assessment_results_field.png',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('assessment_results_hero')),
          matching: find.byType(FlutterMap),
        ),
        findsNothing,
      );
      // Verify large leaf icon tile is NOT present in hero
      expect(
        find.descendant(
          of: find.byKey(const Key('assessment_results_hero')),
          matching: find.byIcon(Icons.eco_rounded),
        ),
        findsNothing,
      );
      // Compact chips are present
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('V3–V6'), findsOneWidget);
      expect(find.textContaining('Station'), findsWidgets);
      // Segmented tabs are present
      expect(find.text('Stations'), findsOneWidget);
      expect(find.text('Recommendations'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recorded_evidence_4_across')),
        260,
      );
      expect(
        find.byKey(const Key('recorded_evidence_4_across')),
        findsOneWidget,
      );
      // Zero layout overflow exceptions
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    await _disposeHarness(tester);
  });
}

Future<void> _addVegetativePlant(
  AppDatabase db, {
  required String stationId,
  required int position,
  bool damage = false,
  bool frass = false,
  bool larva = false,
  bool egg = false,
}) async {
  await AtomicPlantSaveService(db).saveVegetativePlant(
    VegetativePlantSave(
      stationId: stationId,
      plantPosition: position,
      plantStatus: (damage || frass || larva || egg)
          ? DatabaseCodes.plantCurrentPositive
          : DatabaseCodes.plantNegative,
      assessable: true,
      newestLeavesInspectedCount: 4,
      smallFreshWindowpanes: damage,
      scraping: false,
      cuttingOrTearing: false,
      freshFrass: frass,
      whorlFeedingSign: damage,
      larvaVisible: larva,
      larvalSize: larva ? 'small' : 'none_seen',
      eggMassVisible: egg,
      oldDamagePresent: false,
      possibleNonFawEvidence: false,
      uncertainEvidence: false,
      damageAttribution: (damage || frass || larva || egg)
          ? DatabaseCodes.damageAttributionFawConsistent
          : null,
    ),
  );
}

Future<void> _disposeHarness(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _metric(
  AppDatabase database, {
  required AssessmentRecord assessment,
  required String blockRunId,
  required String code,
  required double numerator,
  required double denominator,
  required double? value,
  String? warning,
  String? formulaVersion,
  String unit = 'percent',
  String? distribution,
}) => database
    .into(database.metricResults)
    .insert(
      MetricResultsCompanion.insert(
        id: 'metric-$blockRunId-$code',
        assessmentId: assessment.id,
        scopeType: 'block',
        scopeId: Value(blockRunId),
        metricCode: code,
        numerator: Value(numerator),
        denominator: Value(denominator),
        value: Value(value),
        unit: unit,
        distributionJson: Value(distribution),
        formulaVersion: formulaVersion ?? assessment.formulaVersion,
        warningCode: Value(warning),
        calculatedAt: DateTime.utc(2026, 9, 9, 10),
      ),
    );
