import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import 'scouting_sampling_protocol.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/people_repository.dart';

const _debugPolygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.00085,17.0],'
    '[121.00085,17.00080],[121.0,17.00080],[121.0,17.0]]]}';

class DebugTestDataService {
  DebugTestDataService(this.database);

  final AppDatabase database;

  Future<void> ensureTestAssessment() async {
    _requireDebugBuild();
    final existing = await database.select(database.assessments).get();
    if (existing.isNotEmpty) return;
    final evaluator = await PeopleRepository(
      database,
    ).findOrCreateEvaluator('[TEST DATA] Evaluator');
    final field = await FieldRepository(database)
        .createFieldWithBoundaryAndCycle(
          name: '[TEST DATA] DA maize field',
          geometryGeojson: _debugPolygon,
          areaHectares: 0.8,
          boundarySourceMethod: 'debug_synthetic_outline',
          boundaryConfirmationStatus: 'user_confirmed',
          ownerPersonId: evaluator.id,
          actorPersonId: evaluator.id,
        );
    final assessments = AssessmentRepository(database);
    final draft = await assessments.createDraft(
      cropCycleId: field.cropCycle.id,
      boundaryVersionId: field.boundary!.id,
      evaluatorPersonId: evaluator.id,
      assessmentMode: DatabaseCodes.modeVeV6,
      scoutingPattern: ScoutingSamplingProtocol.daPattern,
      growthStage: 'v3_v6',
      protocolVersion: ScoutingSamplingProtocol.daVersion,
      formulaVersion: 'debug-test-data-v1',
      preferredLanguage: 'en',
    );
    await assessments.recordSafetyCheck(
      assessmentId: draft.id,
      checkedByPersonId: evaluator.id,
      resultStatus: DatabaseCodes.noRecentTreatment,
      notes: '[TEST DATA] Synthetic safety record.',
    );
    await assessments.startAssessment(draft.id);
  }

  Future<void> clear({Directory? evidenceRoot}) async {
    _requireDebugBuild();
    await database.transaction(() async {
      await database.delete(database.syncOutbox).go();
      await database.delete(database.auditLogs).go();
      await database.delete(database.metricResults).go();
      await database.delete(database.evidenceMedia).go();
      await database.delete(database.evidenceCaptureSessions).go();
      await database.delete(database.earObservations).go();
      await database.delete(database.reproductiveObservations).go();
      await database.delete(database.vegetativeObservations).go();
      await database.delete(database.plantObservations).go();
      await database.delete(database.plantingUnitObservations).go();
      await database.delete(database.stations).go();
      await database.delete(database.assessmentBlockRuns).go();
      await database.delete(database.fieldBlocks).go();
      await database.delete(database.safetyChecks).go();
      await database.delete(database.assessments).go();
      await database.delete(database.interventionAreas).go();
      await database.delete(database.interventionInputs).go();
      await database.delete(database.interventions).go();
      await database.delete(database.cropCycles).go();
      await database.delete(database.fieldBoundaryVersions).go();
      await database.delete(database.fields).go();
      await database.delete(database.people).go();
      await database.delete(database.appPreferences).go();
    });
    if (evidenceRoot != null && await evidenceRoot.exists()) {
      await evidenceRoot.delete(recursive: true);
    }
  }

  void _requireDebugBuild() {
    if (!kDebugMode) {
      throw StateError('Test-data tools are unavailable in release builds.');
    }
  }
}
