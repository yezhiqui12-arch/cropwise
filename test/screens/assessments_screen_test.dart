import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/providers/assessment_workspace_provider.dart';
import 'package:wormwise/providers/field_workspace_provider.dart';
import 'package:wormwise/screens/assess/assessments_screen.dart';
import 'package:wormwise/screens/assess/assessment_details_screen.dart';
import 'package:wormwise/screens/assess/assessment_results_screen.dart';
import 'package:wormwise/screens/assess/assessment_resume_screen.dart';
import 'package:wormwise/screens/assess/plant_details_screen.dart';
import 'package:wormwise/screens/assess/station_details_screen.dart';
import 'package:wormwise/screens/assessment_setup_screen.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';
import 'package:wormwise/theme/app_theme.dart';
import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    db = AppDatabase(NativeDatabase.memory());
  });

  Widget harness(Widget child, {double scale = 1}) => WormWiseDataScope(
    database: db,
    disposeDatabase: false,
    dataMode: const AppDataMode.production(debugFeaturesEnabled: false),
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );

  testWidgets('empty history gives an actionable state', (tester) async {
    await tester.pumpWidget(harness(const AssessmentsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No assessments saved here yet'), findsOneWidget);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets(
    'completed history opens results without changing active selection',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final north = await historyFixture(db, status: 'completed');
      final south = await historyFixture(
        db,
        name: 'South Field',
        daysAgo: 2,
        status: 'completed',
      );
      await FieldRepository(db).savePreferredFieldId(north.field.field.id);
      await tester.pumpWidget(harness(const AssessmentsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All fields').last);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AssessmentsScreen));
      expect(
        context.read<FieldWorkspaceProvider>().activeFieldId,
        north.field.field.id,
      );
      await tester.scrollUntilVisible(
        find.text('View results').last,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('View results').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View results').last);
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentResultsScreen), findsOneWidget);
      expect(find.byType(AssessmentDetailsScreen), findsNothing);
      expect(find.text('South Field'), findsOneWidget);
      expect(find.text('Continue scouting'), findsNothing);
      expect(
        (await db.select(db.assessments).get())
            .firstWhere((r) => r.id == south.assessment.id)
            .status,
        'completed',
      );
      final layoutError = tester.takeException();
      expect(layoutError, isNull, reason: layoutError?.toString());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  testWidgets('unfinished history opens details', (tester) async {
    await historyFixture(db, status: 'in_progress');
    await tester.pumpWidget(harness(const AssessmentsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('active_assessment_details_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentDetailsScreen), findsOneWidget);
    expect(find.byType(AssessmentResultsScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('historical readiness and detail layout support large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await historyFixture(db, status: 'completed');
    await historyStation(db, fixture.field, fixture.assessment);
    await tester.pumpWidget(
      harness(
        AssessmentDetailsScreen(assessmentId: fixture.assessment.id),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Needs verification'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Needs verification'), findsOneWidget);
    expect(find.text('Checks flagged'), findsOneWidget);
    expect(find.text('Required work'), findsNothing);
    expect(find.text('Open Station 2'), findsNothing);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('history layout supports 360px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await historyFixture(
      db,
      name: 'North Maize Field with a longer descriptive name',
    );
    await tester.pumpWidget(harness(const AssessmentsScreen(), scale: 2));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
    await tester.pumpAndSettle();
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('resume opens exact saved draft and closes back to history', (
    tester,
  ) async {
    final north = await historyFixture(db);
    final south = await historyFixture(db, name: 'South Field');
    await FieldRepository(db).savePreferredFieldId(north.field.field.id);
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AssessmentResumeScreen(assessmentId: south.assessment.id),
                ),
              ),
              child: const Text('Resume exact record'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume exact record'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentSetupScreen), findsOneWidget);
    final scope = tester.element(find.byType(AssessmentSetupScreen));
    expect(
      scope.read<AssessmentWorkspaceProvider>().currentAssessment!.id,
      south.assessment.id,
    );
    expect(
      scope.read<FieldWorkspaceProvider>().activeFieldId,
      south.field.field.id,
    );
    Navigator.of(scope).pop();
    await tester.pumpAndSettle();
    expect(find.text('Resume exact record'), findsOneWidget);
    expect(
      await FieldRepository(db).readPreferredFieldId(),
      north.field.field.id,
    );
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('back exits a resumed active assessment without trapping UI', (
    tester,
  ) async {
    final fixture = await historyFixture(db, status: 'in_progress');
    await historyStation(db, fixture.field, fixture.assessment);
    await tester.pumpWidget(
      harness(AssessmentDetailsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_details_resume_button')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('assessment_details_resume_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('station_workflow_back_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('station_workflow_back_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentDetailsScreen), findsOneWidget);
    expect(
      find.byKey(const Key('assessment_details_resume_button')),
      findsOneWidget,
    );
    expect(find.byType(AssessmentResumeScreen), findsNothing);
    await tester.tap(find.byKey(const Key('assessment_details_resume_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('station_workflow_back_button')),
      findsOneWidget,
    );
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('sequential fieldwork does not expose station shortcuts', (
    tester,
  ) async {
    final fixture = await historyFixture(db, status: 'in_progress');
    await historyStation(db, fixture.field, fixture.assessment);
    await tester.pumpWidget(
      harness(AssessmentDetailsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('assessment_details_resume_button')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('assessment_details_resume_button')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Required work'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Required work'), findsOneWidget);
    expect(find.text('Observations needed'), findsWidgets);
    expect(find.text('Fix Station 2'), findsNothing);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets(
    'assessment station and plant history form a read-only drill-down',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await historyFixture(db, status: 'completed');
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      final repository = AssessmentRepository(db);
      final plant = await repository.savePlant(
        stationId: station.id,
        sequenceNumber: 1,
        plantStatus: DatabaseCodes.plantCurrentPositive,
        currentFawEvidence: true,
        oldDamagePresent: false,
        naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
        evaluatorNotes: 'Whorl feeding and fresh frass were recorded.',
      );
      await repository.saveVegetativeObservation(
        plantObservationId: plant.id,
        newestLeavesInspectedCount: 3,
        smallFreshWindowpanes: true,
        freshFrass: true,
        whorlFeedingSign: true,
        daBafsLeafDamageScore: 4,
      );
      await db
          .into(db.evidenceCaptureSessions)
          .insert(
            EvidenceCaptureSessionsCompanion.insert(
              id: 'plant-position-session',
              assessmentId: fixture.assessment.id,
              stationId: station.id,
              scopeType: DatabaseCodes.evidenceScopePlant,
              scopeKey: 'plant:1',
              plantPosition: const drift.Value(1),
            ),
          );
      await db
          .into(db.evidenceMedia)
          .insert(
            EvidenceMediaCompanion.insert(
              id: 'plant-position-photo',
              assessmentId: fixture.assessment.id,
              stationId: drift.Value(station.id),
              captureSessionId: const drift.Value('plant-position-session'),
              mediaType: 'image',
              viewType: const drift.Value(
                DatabaseCodes.evidenceViewWhorlOverview,
              ),
              localUri: 'assessment/station/plant-1.jpg',
              sha256Checksum: 'plant-position-photo-checksum',
              storageState: const drift.Value(
                DatabaseCodes.evidenceStorageReady,
              ),
              isCanonicalEvidence: const drift.Value(true),
            ),
          );

      await tester.pumpWidget(
        harness(
          AssessmentDetailsScreen(assessmentId: fixture.assessment.id),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final stationKey = Key(
        'open_station_${station.assessmentBlockRunId}_${station.stationNumber}',
      );
      await tester.scrollUntilVisible(
        find.byKey(stationKey),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(stationKey));
      await tester.pumpAndSettle();
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('NOT STARTED'), findsWidgets);
      expect(find.text('View field map'), findsNothing);
      expect(find.byKey(const Key('assessment_arcgis_map')), findsNothing);
      await tester.ensureVisible(find.byKey(stationKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(stationKey));
      await tester.pumpAndSettle();

      expect(find.byType(StationDetailsScreen), findsOneWidget);
      expect(
        find.byKey(const Key('station_details_option_b_hero')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('station_details_read_only_notice')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('station_details_read_only_notice')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('station_position_1')),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('station_position_1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('plant_assessment_card_grid')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('station_position_1'))).dx,
        tester.getTopLeft(find.byKey(const Key('station_position_2'))).dx,
      );
      expect(find.text('1 photo available'), findsOneWidget);
      await tester.tap(find.byKey(const Key('station_position_1')));
      await tester.pumpAndSettle();

      expect(find.byType(PlantAssessmentDetailsScreen), findsOneWidget);
      expect(find.text('Current-positive record'), findsWidgets);
      expect(find.byKey(const Key('plant_evidence_hero')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Saved field observation.'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Saved field observation.'), findsOneWidget);
      await tester.drag(
        find.byKey(const PageStorageKey('plant-details-overview')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      expect(find.text('DA-BAFS leaf score'), findsOneWidget);
      expect(find.text('4 of 9'), findsOneWidget);
      expect(find.text('FAW detected'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      final layoutError = tester.takeException();
      expect(layoutError, isNull, reason: layoutError?.toString());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  testWidgets(
    'plant assessments use full-width ribbon tickets at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await historyFixture(db, status: 'completed');
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      final repository = AssessmentRepository(db);
      for (final position in [1, 2]) {
        await repository.savePlant(
          stationId: station.id,
          sequenceNumber: position,
          plantStatus: DatabaseCodes.plantNegative,
          currentFawEvidence: false,
          oldDamagePresent: false,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
        );
      }

      await tester.pumpWidget(
        harness(AssessmentDetailsScreen(assessmentId: fixture.assessment.id)),
      );
      await tester.pumpAndSettle();
      final stationKey = Key(
        'open_station_${station.assessmentBlockRunId}_${station.stationNumber}',
      );
      await tester.scrollUntilVisible(
        find.byKey(stationKey),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(stationKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(stationKey));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('station_position_1')),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final first = tester.getTopLeft(
        find.byKey(const Key('station_position_1')),
      );
      final second = tester.getTopLeft(
        find.byKey(const Key('station_position_2')),
      );
      expect(second.dx, closeTo(first.dx, 1));
      expect(second.dy, greaterThan(first.dy));
      expect(find.text('2 recorded'), findsOneWidget);
      final layoutError = tester.takeException();
      expect(layoutError, isNull, reason: layoutError?.toString());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  testWidgets('seedling grid does not substitute planting-unit records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await historyFixture(db, status: 'completed', stage: 'v2');
    final station = await historyStation(db, fixture.field, fixture.assessment);
    await db
        .into(db.plantingUnitObservations)
        .insert(
          PlantingUnitObservationsCompanion.insert(
            id: 'unit-without-seedling',
            stationId: station.id,
            sequenceNumber: 1,
            primaryCondition: const drift.Value('empty_unexplained'),
          ),
        );

    await tester.pumpWidget(
      harness(AssessmentDetailsScreen(assessmentId: fixture.assessment.id)),
    );
    await tester.pumpAndSettle();
    final stationKey = Key(
      'open_station_${station.assessmentBlockRunId}_${station.stationNumber}',
    );
    await tester.scrollUntilVisible(
      find.byKey(stationKey),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(stationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(stationKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('station_position_1')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Seedling assessments (10)'), findsOneWidget);
    expect(find.text('0 recorded'), findsOneWidget);
    expect(find.text('Seedling 1'), findsOneWidget);
    expect(find.text('No seedling observation is saved.'), findsWidgets);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('active assessment history renders without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await historyFixture(db, status: 'in_progress');
    await historyStation(db, fixture.field, fixture.assessment);
    await tester.pumpWidget(harness(const AssessmentsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Assess'), findsOneWidget);
    expect(
      find.byKey(const Key('active_assessment_option_b_card')),
      findsOneWidget,
    );
    expect(find.text('0 of 5 station reviews current'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });
}
