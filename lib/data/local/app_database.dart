import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'database_codes.dart';

part 'app_database.g.dart';

abstract class SyncableTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant(DatabaseCodes.localOnly))();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PersonRecord')
class People extends SyncableTable {
  TextColumn get displayName => text()();
  TextColumn get roleLabel => text().nullable()();
  TextColumn get organization => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get privacyConsentStatus =>
      text().withDefault(const Constant('not_recorded'))();
}

@DataClassName('FieldRecord')
class Fields extends SyncableTable {
  TextColumn get ownerPersonId => text().nullable().references(People, #id)();
  TextColumn get name => text()();
  TextColumn get fieldCode => text().nullable()();
  TextColumn get barangay => text().nullable()();
  TextColumn get municipalityCity => text().nullable()();
  TextColumn get province => text().nullable()();
  TextColumn get locationDescription => text().nullable()();
  TextColumn get activeBoundaryVersionId => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

@DataClassName('BoundaryRecord')
class FieldBoundaryVersions extends SyncableTable {
  TextColumn get fieldId => text().references(Fields, #id)();
  IntColumn get versionNumber => integer()();
  TextColumn get geometryGeojson => text()();
  TextColumn get sourceMethod => text()();
  RealColumn get areaHectares => real()();
  RealColumn get centroidLatitude => real().nullable()();
  RealColumn get centroidLongitude => real().nullable()();
  RealColumn get averageAccuracyM => real().nullable()();
  RealColumn get worstAccuracyM => real().nullable()();
  TextColumn get confidenceCode => text().nullable()();
  TextColumn get confirmationStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get confirmedByPersonId =>
      text().nullable().references(People, #id)();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {fieldId, versionNumber},
  ];
}

@DataClassName('CropCycleRecord')
class CropCycles extends SyncableTable {
  TextColumn get fieldId => text().references(Fields, #id)();
  TextColumn get cycleLabel => text().nullable()();
  TextColumn get cropCode => text().withDefault(const Constant('maize'))();
  TextColumn get varietyName => text().nullable()();
  TextColumn get intendedUse => text().nullable()();
  DateTimeColumn get plantingDate => dateTime().nullable()();
  TextColumn get plantingDatePrecision =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get plantingArrangement => text().nullable()();
  RealColumn get intendedWithinRowSpacingCm => real().nullable()();
  IntColumn get intendedSeedlingsPerPosition => integer().nullable()();
  TextColumn get waterRegime => text().nullable()();
  TextColumn get intercroppingDescription => text().nullable()();
  TextColumn get seasonConditions => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
}

@DataClassName('FieldBlockRecord')
class FieldBlocks extends SyncableTable {
  TextColumn get cropCycleId => text().references(CropCycles, #id)();
  TextColumn get boundaryVersionId =>
      text().references(FieldBoundaryVersions, #id)();
  IntColumn get blockNumber => integer()();
  TextColumn get geometryGeojson => text()();
  RealColumn get areaHectares => real()();
  TextColumn get separationReason => text().nullable()();
  BoolColumn get isProvisional => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {cropCycleId, blockNumber},
  ];
}

@DataClassName('InterventionRecord')
class Interventions extends SyncableTable {
  TextColumn get cropCycleId => text().references(CropCycles, #id)();
  TextColumn get interventionType => text()();
  TextColumn get statedPurpose => text().nullable()();
  TextColumn get targetPestOrCondition => text().nullable()();
  DateTimeColumn get occurredStartAt => dateTime().nullable()();
  DateTimeColumn get occurredEndAt => dateTime().nullable()();
  TextColumn get timePrecision =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get applicationMethod => text().nullable()();
  TextColumn get equipmentDescription => text().nullable()();
  BoolColumn get equipmentCalibrated => boolean().nullable()();
  @ReferenceName('interventionsAppliedBy')
  TextColumn get applicatorPersonId =>
      text().nullable().references(People, #id)();
  @ReferenceName('interventionsAdvisedBy')
  TextColumn get adviserPersonId => text().nullable().references(People, #id)();
  TextColumn get weatherDescription => text().nullable()();
  TextColumn get windDescription => text().nullable()();
  TextColumn get rainfallAfterDescription => text().nullable()();
  TextColumn get ppeReported => text().nullable()();
  TextColumn get incidentDescription => text().nullable()();
  TextColumn get disposalDescription => text().nullable()();
  @ReferenceName('interventionsReportedBy')
  TextColumn get reporterPersonId =>
      text().nullable().references(People, #id)();
  TextColumn get overallProvenanceState =>
      text().withDefault(const Constant('reported'))();
  TextColumn get notes => text().nullable()();
}

@DataClassName('InterventionInputRecord')
class InterventionInputs extends SyncableTable {
  TextColumn get interventionId => text().references(Interventions, #id)();
  TextColumn get reportedProductName => text().nullable()();
  TextColumn get reportedActiveIngredientOrAgent => text().nullable()();
  TextColumn get reportedConcentrationFormulation => text().nullable()();
  TextColumn get reportedRegistrationNumber => text().nullable()();
  TextColumn get reportedCrop => text().nullable()();
  TextColumn get reportedTarget => text().nullable()();
  RealColumn get amountUsedValue => real().nullable()();
  TextColumn get amountUsedUnit => text().nullable()();
  RealColumn get waterVolumeValue => real().nullable()();
  TextColumn get waterVolumeUnit => text().nullable()();
  TextColumn get reportedRateText => text().nullable()();
  TextColumn get labelRateText => text().nullable()();
  TextColumn get releaseQuantityText => text().nullable()();
  TextColumn get phiText => text().nullable()();
  TextColumn get reiText => text().nullable()();
  TextColumn get modeOfActionGroup => text().nullable()();
  TextColumn get registrationStatus =>
      text().withDefault(const Constant('not_checked'))();
  TextColumn get provenanceState =>
      text().withDefault(const Constant('reported'))();
}

@DataClassName('InterventionAreaRecord')
class InterventionAreas extends SyncableTable {
  TextColumn get interventionId => text().references(Interventions, #id)();
  TextColumn get fieldBlockId =>
      text().nullable().references(FieldBlocks, #id)();
  TextColumn get coverageType => text()();
  TextColumn get geometryGeojson => text().nullable()();
  RealColumn get areaHectares => real().nullable()();
}

@DataClassName('AssessmentRecord')
class Assessments extends SyncableTable {
  TextColumn get cropCycleId => text().references(CropCycles, #id)();
  TextColumn get boundaryVersionId =>
      text().references(FieldBoundaryVersions, #id)();
  TextColumn get evaluatorPersonId => text().references(People, #id)();
  TextColumn get assessmentType =>
      text().withDefault(const Constant(DatabaseCodes.formal))();
  TextColumn get status =>
      text().withDefault(const Constant(DatabaseCodes.draft))();
  TextColumn get assessmentMode => text()();
  TextColumn get scoutingPattern => text()();
  TextColumn get patternReason => text().nullable()();
  TextColumn get growthStage => text()();
  TextColumn get growthStageBestEstimate => text().nullable()();
  BoolColumn get growthStageUncertain =>
      boolean().withDefault(const Constant(false))();
  TextColumn get preferredLanguage =>
      text().withDefault(const Constant('en'))();
  TextColumn get protocolVersion => text()();
  TextColumn get formulaVersion => text()();
  TextColumn get interventionHistoryStatus =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get safetySummaryStatus => text().withDefault(
    const Constant(DatabaseCodes.treatmentHistoryUnknown),
  )();
  TextColumn get previousAssessmentId => text().nullable()();
  TextColumn get weatherContext => text().nullable()();
  DateTimeColumn get recentHeavyRainAt => dateTime().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get localUtcOffsetMinutes => integer().nullable()();
  TextColumn get validationStatus =>
      text().withDefault(const Constant('unreviewed'))();
  TextColumn get completionNote => text().nullable()();
}

@DataClassName('SafetyCheckRecord')
class SafetyChecks extends SyncableTable {
  TextColumn get assessmentId => text().references(Assessments, #id)();
  TextColumn get interventionId =>
      text().nullable().references(Interventions, #id)();
  TextColumn get checkedByPersonId => text().references(People, #id)();
  DateTimeColumn get checkedAt => dateTime()();
  DateTimeColumn get applicationEndAtUsed => dateTime().nullable()();
  TextColumn get reiTextUsed => text().nullable()();
  TextColumn get reiSource => text().nullable()();
  TextColumn get phiTextUsed => text().nullable()();
  TextColumn get phiSource => text().nullable()();
  TextColumn get resultStatus => text()();
  DateTimeColumn get calculatedSafeEntryAt => dateTime().nullable()();
  BoolColumn get calculationInputsVerified =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get warningAcknowledged =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
}

@DataClassName('AssessmentBlockRunRecord')
class AssessmentBlockRuns extends SyncableTable {
  TextColumn get assessmentId => text().references(Assessments, #id)();
  TextColumn get fieldBlockId => text().references(FieldBlocks, #id)();
  IntColumn get blockSequence => integer()();
  TextColumn get scoutingPattern => text()();
  TextColumn get patternReason => text().nullable()();
  TextColumn get routeGeojson => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  BoolColumn get edgeBiasWarning =>
      boolean().withDefault(const Constant(false))();
  TextColumn get accessibilityNotes => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {assessmentId, fieldBlockId},
    {assessmentId, blockSequence},
  ];
}

@DataClassName('StationRecord')
class Stations extends SyncableTable {
  TextColumn get assessmentBlockRunId =>
      text().references(AssessmentBlockRuns, #id)();
  IntColumn get stationNumber => integer()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get gpsAccuracyM => real().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  TextColumn get notLocatedReason => text().nullable()();
  TextColumn get accessibilityNotes => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {assessmentBlockRunId, stationNumber},
  ];
}

@DataClassName('PlantingUnitObservationRecord')
class PlantingUnitObservations extends SyncableTable {
  TextColumn get stationId => text().references(Stations, #id)();
  IntColumn get sequenceNumber => integer()();
  BoolColumn get assessable => boolean().withDefault(const Constant(true))();
  TextColumn get notAssessableReason => text().nullable()();
  TextColumn get occupancyStatus => text().nullable()();
  IntColumn get observedSeedlingCount => integer().nullable()();
  IntColumn get intendedSeedlingCount => integer().nullable()();
  BoolColumn get visibleCutting => boolean().nullable()();
  BoolColumn get visibleSeedlingInjury => boolean().nullable()();
  BoolColumn get confirmedFawPresent => boolean().nullable()();
  BoolColumn get injuryConsistentWithFaw => boolean().nullable()();
  TextColumn get alternativeCauseCode => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {stationId, sequenceNumber},
  ];
}

@DataClassName('PlantObservationRecord')
class PlantObservations extends SyncableTable {
  TextColumn get stationId => text().references(Stations, #id)();
  IntColumn get sequenceNumber => integer()();
  TextColumn get persistentPlantIdentifier => text().nullable()();
  BoolColumn get assessable => boolean().withDefault(const Constant(true))();
  TextColumn get notAssessableReason => text().nullable()();
  TextColumn get plantStatus => text()();
  BoolColumn get currentFawEvidence => boolean().nullable()();
  BoolColumn get oldDamagePresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get naturalEnemyQuickStatus => text()();
  TextColumn get wholePlantContextNote => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get gpsAccuracyM => real().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  TextColumn get evaluatorNotes => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {stationId, sequenceNumber},
  ];
}

@DataClassName('VegetativeObservationRecord')
class VegetativeObservations extends Table {
  TextColumn get plantObservationId =>
      text().references(PlantObservations, #id)();
  IntColumn get newestLeavesInspectedCount => integer().nullable()();
  BoolColumn get smallFreshWindowpanes =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get infestedWhorl =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get scraping => boolean().withDefault(const Constant(false))();
  BoolColumn get cuttingOrTearing =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get freshFrass => boolean().withDefault(const Constant(false))();
  BoolColumn get whorlFeedingSign =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get larvaVisible => boolean().withDefault(const Constant(false))();
  TextColumn get larvalSize =>
      text().withDefault(const Constant('none_seen'))();
  IntColumn get larvaCount => integer().nullable()();
  IntColumn get daBafsLeafDamageScore => integer().nullable()();
  BoolColumn get damageScoreUncertain =>
      boolean().withDefault(const Constant(false))();
  TextColumn get damageScoreReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {plantObservationId};
}

@DataClassName('ReproductiveObservationRecord')
class ReproductiveObservations extends Table {
  TextColumn get plantObservationId =>
      text().references(PlantObservations, #id)();
  BoolColumn get tasselExamined =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get earBaseExamined =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get upperAxilExamined =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get lowerAxilExamined =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get freshFeedingPresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get larvaPresent => boolean().withDefault(const Constant(false))();
  IntColumn get larvaCount => integer().nullable()();
  BoolColumn get percentInfestedPositive =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {plantObservationId};
}

@DataClassName('EarObservationRecord')
class EarObservations extends SyncableTable {
  TextColumn get plantObservationId =>
      text().references(PlantObservations, #id)();
  IntColumn get earSequence => integer().withDefault(const Constant(1))();
  BoolColumn get externallyAssessable =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get externalDamagePresent => boolean().nullable()();
  BoolColumn get activeInfestationPresent => boolean().nullable()();
  BoolColumn get silkDamagePresent => boolean().nullable()();
  BoolColumn get huskDamagePresent => boolean().nullable()();
  BoolColumn get entryHolePresent => boolean().nullable()();
  BoolColumn get frassPresent => boolean().nullable()();
  BoolColumn get larvaPresent => boolean().nullable()();
  TextColumn get openingPermission =>
      text().withDefault(const Constant('not_requested'))();
  BoolColumn get opened => boolean().withDefault(const Constant(false))();
  BoolColumn get internalDamagePresent => boolean().nullable()();
  IntColumn get totalKernelsCounted => integer().nullable()();
  IntColumn get damagedKernelsCounted => integer().nullable()();
  TextColumn get kernelCountMethod => text().nullable()();
  BoolColumn get earRotPresent => boolean().nullable()();
  TextColumn get earRotSuspectedType => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {plantObservationId, earSequence},
  ];
}

@DataClassName('EvidenceMediaRecord')
class EvidenceMedia extends SyncableTable {
  TextColumn get assessmentId => text().references(Assessments, #id)();
  TextColumn get stationId => text().nullable().references(Stations, #id)();
  TextColumn get plantingUnitObservationId =>
      text().nullable().references(PlantingUnitObservations, #id)();
  TextColumn get plantObservationId =>
      text().nullable().references(PlantObservations, #id)();
  TextColumn get earObservationId =>
      text().nullable().references(EarObservations, #id)();
  TextColumn get interventionId =>
      text().nullable().references(Interventions, #id)();
  TextColumn get safetyCheckId =>
      text().nullable().references(SafetyChecks, #id)();
  TextColumn get mediaType => text()();
  TextColumn get viewType => text().nullable()();
  TextColumn get localUri => text()();
  TextColumn get remoteUri => text().nullable()();
  TextColumn get thumbnailLocalUri => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get byteSize => integer().nullable()();
  TextColumn get sha256Checksum => text()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get gpsAccuracyM => real().nullable()();
  TextColumn get qualityStatus =>
      text().withDefault(const Constant('unchecked'))();
  TextColumn get uploadState =>
      text().withDefault(const Constant(DatabaseCodes.localOnly))();
  BoolColumn get isOriginal => boolean().withDefault(const Constant(true))();
}

@DataClassName('MetricResultRecord')
class MetricResults extends SyncableTable {
  TextColumn get assessmentId => text().references(Assessments, #id)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text().nullable()();
  TextColumn get metricCode => text()();
  RealColumn get numerator => real().nullable()();
  RealColumn get denominator => real().nullable()();
  RealColumn get value => real().nullable()();
  TextColumn get unit => text()();
  TextColumn get distributionJson => text().nullable()();
  TextColumn get formulaVersion => text()();
  TextColumn get validationStatus =>
      text().withDefault(const Constant('provisional'))();
  TextColumn get warningCode => text().nullable()();
  DateTimeColumn get calculatedAt => dateTime()();
}

@DataClassName('SyncOutboxRecord')
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get dependencyIdsJson => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AuditLogRecord')
class AuditLogs extends Table {
  @override
  String get tableName => 'audit_log';

  TextColumn get id => text()();
  TextColumn get actorPersonId => text().nullable().references(People, #id)();
  TextColumn get deviceId => text().nullable()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get syncState =>
      text().withDefault(const Constant(DatabaseCodes.localOnly))();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppPreferenceRecord')
class AppPreferences extends Table {
  TextColumn get preferenceKey => text()();
  TextColumn get preferenceValue => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {preferenceKey};
}

@DriftDatabase(
  tables: [
    People,
    Fields,
    FieldBoundaryVersions,
    CropCycles,
    FieldBlocks,
    Interventions,
    InterventionInputs,
    InterventionAreas,
    Assessments,
    SafetyChecks,
    AssessmentBlockRuns,
    Stations,
    PlantingUnitObservations,
    PlantObservations,
    VegetativeObservations,
    ReproductiveObservations,
    EarObservations,
    EvidenceMedia,
    MetricResults,
    SyncOutbox,
    AuditLogs,
    AppPreferences,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(appPreferences);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'wormwise',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
