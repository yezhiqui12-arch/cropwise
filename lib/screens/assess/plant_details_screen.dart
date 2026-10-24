import '../../models/automatic_screening.dart';
import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../services/evidence_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../station1/evidence_photo_viewer.dart';
import 'plant_evidence_support.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/da_monitoring_repository.dart';
import '../../data/repositories/plant_action_repository.dart';
import '../../models/guided_plant_details.dart';
import '../scan/plant_action_guidance_panel.dart';

class PlantAssessmentDetailsScreen extends StatelessWidget {
  const PlantAssessmentDetailsScreen({
    super.key,
    required this.detail,
    required this.station,
    required this.record,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final StationPlantRecord record;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    final plant = record.plant;
    final evidenceRecords = assessmentEvidenceForPlant(
      detail: detail,
      station: station,
      plantObservationId: plant.id,
      plantPosition: plant.sequenceNumber,
    );
    final evidence = evidenceRecords
        .where(
          (entry) =>
              entry.media.storageState == DatabaseCodes.evidenceStorageReady,
        )
        .toList(growable: false);
    final missingEvidenceCount = evidenceRecords.length - evidence.length;
    final subject = _isSeedling(detail.assessment.growthStage)
        ? 'Seedling'
        : 'Plant';
    final displayPosition = station.requiredPlantCount == 1
        ? station.stationNumber
        : plant.sequenceNumber;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: AppText('$subject $displayPosition details'),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.workflowMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppText(
                              '$subject $displayPosition',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            PlantObservationStatusBadge(
                              status: plant.plantStatus,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        AppText(
                          'Block ${station.prepared.run.blockSequence} · ${station.requiredPlantCount == 1 ? 'Plant' : 'Station'} ${station.stationNumber} · ${detail.workspace.field.name}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Photos'),
                      Tab(text: 'Notes'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _PlantOverview(
                          detail: detail,
                          station: station,
                          record: record,
                          evidence: evidence,
                          missingEvidenceCount: missingEvidenceCount,
                          storage: storage,
                        ),
                        _PlantPhotos(
                          detail: detail,
                          station: station,
                          plant: plant,
                          evidence: evidence,
                          missingEvidenceCount: missingEvidenceCount,
                          storage: storage,
                        ),
                        _PlantNotes(plant: plant),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlantOverview extends StatelessWidget {
  const _PlantOverview({
    required this.detail,
    required this.station,
    required this.record,
    required this.evidence,
    required this.missingEvidenceCount,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final StationPlantRecord record;
  final List<AssessmentEvidenceEntry> evidence;
  final int missingEvidenceCount;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    final plant = record.plant;
    final facts = _observationFacts(
      record,
      screening: detail.screeningFor(record),
    );
    final stationRecord = station.station;
    final hasPlantLocation =
        plant.locationSource == 'phone_gps' &&
        plant.latitude != null &&
        plant.longitude != null;
    final hasStationLocation =
        stationRecord?.latitude != null && stationRecord?.longitude != null;
    final locationLabel = hasPlantLocation
        ? 'Plant location'
        : hasStationLocation
        ? 'Station reference (plant GPS not recorded)'
        : 'Plant location';
    final locationValue = hasPlantLocation
        ? '${plant.latitude!.toStringAsFixed(5)}, ${plant.longitude!.toStringAsFixed(5)}'
        : hasStationLocation
        ? '${stationRecord!.latitude!.toStringAsFixed(5)}, ${stationRecord.longitude!.toStringAsFixed(5)}'
        : 'Not recorded';
    final database = context.read<AppDatabase?>();
    return ListView(
      key: const PageStorageKey('plant-details-overview'),
      padding: const EdgeInsets.all(16),
      children: [
        if (evidence.isNotEmpty)
          _EvidenceHero(
            entry: evidence.first,
            storage: storage,
            onTap: () => _openEvidence(
              context,
              detail: detail,
              station: station,
              plant: plant,
              entries: evidence,
              index: 0,
              storage: storage,
            ),
          )
        else
          const _NoEvidenceHero(),
        if (missingEvidenceCount > 0) ...[
          const SizedBox(height: 10),
          _MissingEvidenceNotice(count: missingEvidenceCount),
        ],
        const SizedBox(height: 12),
        const _ProvenanceNotice(),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Observation results',
          child: Column(
            children: [
              for (var index = 0; index < facts.length; index++) ...[
                _FactRow(fact: facts[index]),
                if (index < facts.length - 1) const Divider(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Plant information',
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.tag_outlined,
                label: 'Plant number',
                value: '${plant.sequenceNumber} of 10',
              ),
              const Divider(height: 12),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: locationLabel,
                value: locationValue,
              ),
              const Divider(height: 12),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Date and time',
                value: plant.capturedAt == null
                    ? 'Not recorded'
                    : DateFormat.yMMMd().add_jm().format(
                        plant.capturedAt!.toLocal(),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (database != null &&
            station.requiredPlantCount == 1 &&
            evidence.isNotEmpty)
          PlantActionGuidancePanel(
            repository: PlantActionRepository(
              database,
              detail.assessment.evaluatorPersonId,
            ),
            assessmentId: detail.assessment.id,
            blockRunId: station.prepared.run.id,
            number: station.stationNumber,
            resolveFile: storage.resolve,
            loadDetails: () async {
              final bundles =
                  (await EvidenceCaptureRepository(
                        database,
                      ).loadStationBundles(station.station!.id))
                      .where(
                        (b) =>
                            b.session.scopeType ==
                                DatabaseCodes.evidenceScopePlant &&
                            b.session.plantPosition == 1,
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          b.session.updatedAt.compareTo(a.session.updatedAt),
                    );
              final bundle = bundles.firstOrNull;
              final checksums =
                  bundle?.media
                      .where(
                        (m) =>
                            m.deletedAt == null &&
                            m.storageState ==
                                DatabaseCodes.evidenceStorageReady,
                      )
                      .map((m) => m.sha256Checksum)
                      .toList() ??
                  <String>[];
              checksums.sort();
              final screening = detail.screeningFor(record);
              return GuidedPlantDetails(
                snapshot: station,
                evidence: bundle,
                diagnosis: screening?.evidenceSignature == checksums.join(':')
                    ? screening?.result
                    : null,
                monitoring: await DaMonitoringRepository(
                  database,
                ).load(detail.assessment.id),
              );
            },
          ),
        _EvidencePreviewStrip(
          detail: detail,
          station: station,
          plant: plant,
          entries: evidence,
          storage: storage,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          label: const AppText('Back to station'),
        ),
      ],
    );
  }
}

class _PlantPhotos extends StatelessWidget {
  const _PlantPhotos({
    required this.detail,
    required this.station,
    required this.plant,
    required this.evidence,
    required this.missingEvidenceCount,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final PlantObservationRecord plant;
  final List<AssessmentEvidenceEntry> evidence;
  final int missingEvidenceCount;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    if (evidence.isEmpty) {
      return _EmptyTab(
        icon: Icons.photo_library_outlined,
        title: 'No available plant photos',
        message: missingEvidenceCount > 0
            ? '$missingEvidenceCount saved evidence ${missingEvidenceCount == 1 ? 'file is' : 'files are'} missing from this device.'
            : 'No canonical evidence is associated with this saved plant record.',
      );
    }
    return GridView.builder(
      key: const PageStorageKey('plant-details-photos'),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 190,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: evidence.length,
      itemBuilder: (context, index) => _EvidenceGridTile(
        entry: evidence[index],
        storage: storage,
        onTap: () => _openEvidence(
          context,
          detail: detail,
          station: station,
          plant: plant,
          entries: evidence,
          index: index,
          storage: storage,
        ),
      ),
    );
  }
}

class _PlantNotes extends StatelessWidget {
  const _PlantNotes({required this.plant});

  final PlantObservationRecord plant;

  @override
  Widget build(BuildContext context) {
    final contextNote = plant.wholePlantContextNote?.trim();
    final evaluatorNote = plant.evaluatorNotes?.trim();
    if ((contextNote == null || contextNote.isEmpty) &&
        (evaluatorNote == null || evaluatorNote.isEmpty)) {
      return const _EmptyTab(
        icon: Icons.notes_outlined,
        title: 'No notes recorded',
        message: 'This read-only record has no saved evaluator notes.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (contextNote != null && contextNote.isNotEmpty)
          _SectionCard(title: 'Whole-plant context', child: Text(contextNote)),
        if (contextNote != null &&
            contextNote.isNotEmpty &&
            evaluatorNote != null &&
            evaluatorNote.isNotEmpty)
          const SizedBox(height: 12),
        if (evaluatorNote != null && evaluatorNote.isNotEmpty)
          _SectionCard(title: 'Evaluator notes', child: Text(evaluatorNote)),
        const SizedBox(height: 12),
        const _ProvenanceNotice(),
      ],
    );
  }
}

class _EvidenceHero extends StatelessWidget {
  const _EvidenceHero({
    required this.entry,
    required this.storage,
    required this.onTap,
  });

  final AssessmentEvidenceEntry entry;
  final EvidenceStorageService storage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black,
    borderRadius: AppRadii.cardBorder,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const Key('plant_evidence_hero'),
      onTap: onTap,
      child: SizedBox(
        height: 220,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SavedEvidenceThumbnail(
              entry: entry,
              storage: storage,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x77000000)],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      evidenceViewLabel(entry.media.viewType),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.open_in_full, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoEvidenceHero extends StatelessWidget {
  const _NoEvidenceHero();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 150),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 34),
        SizedBox(height: 8),
        AppText('No available evidence photo'),
      ],
    ),
  );
}

class _EvidencePreviewStrip extends StatelessWidget {
  const _EvidencePreviewStrip({
    required this.detail,
    required this.station,
    required this.plant,
    required this.entries,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final PlantObservationRecord plant;
  final List<AssessmentEvidenceEntry> entries;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: AppText(
              'Evidence photos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          AppText(
            '${entries.length} available',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (entries.isEmpty)
        const AppText('No available photos are associated with this plant.')
      else
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => SizedBox(
              width: 104,
              child: _EvidenceGridTile(
                entry: entries[index],
                storage: storage,
                compact: true,
                onTap: () => _openEvidence(
                  context,
                  detail: detail,
                  station: station,
                  plant: plant,
                  entries: entries,
                  index: index,
                  storage: storage,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _EvidenceGridTile extends StatelessWidget {
  const _EvidenceGridTile({
    required this.entry,
    required this.storage,
    required this.onTap,
    this.compact = false,
  });

  final AssessmentEvidenceEntry entry;
  final EvidenceStorageService storage;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceCard,
    borderRadius: AppRadii.controlBorder,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SavedEvidenceThumbnail(
              entry: entry,
              storage: storage,
              fit: BoxFit.cover,
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                evidenceViewLabel(entry.media.viewType),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProvenanceNotice extends StatelessWidget {
  const _ProvenanceNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: AppRadii.controlBorder,
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 20, color: AppColors.primary),
        SizedBox(width: 9),
        Expanded(
          child: AppText(
            'Saved field observation. This historical record does not separately identify automated suggestions and manual entries, so no model certainty is claimed here.',
          ),
        ),
      ],
    ),
  );
}

class _MissingEvidenceNotice extends StatelessWidget {
  const _MissingEvidenceNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4DC),
      borderRadius: AppRadii.controlBorder,
      border: Border.all(color: const Color(0xFFF0C66A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: Color(0xFF755100),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: AppText(
            '$count saved evidence ${count == 1 ? 'file is' : 'files are'} missing from this device.',
          ),
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final _ObservationFact fact;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(fact.icon, size: 19, color: AppColors.primary),
      const SizedBox(width: 10),
      Expanded(child: AppText(fact.label)),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          fact.value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: AppColors.primary),
      const SizedBox(width: 10),
      Expanded(child: AppText(label)),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 12),
          AppText(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          AppText(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class PlantObservationStatusBadge extends StatelessWidget {
  const PlantObservationStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final presentation = _statusPresentation(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: presentation.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AppText(
        presentation.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: presentation.foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

List<_ObservationFact> _observationFacts(
  StationPlantRecord record, {
  AutomaticScreening? screening,
}) {
  final plant = record.plant;
  final screen = screening;
  if (screen != null)
    return [
      _ObservationFact(Icons.image_search, 'Damage screening', screen.label),
      for (final entry in <int, String>{
        1: 'Frass suggestions',
        2: 'Larva suggestions',
        3: 'Egg suggestions',
      }.entries)
        _ObservationFact(
          Icons.center_focus_strong,
          entry.value,
          !screen.highlighted
              ? 'Not assessed'
              : screen.suggested(entry.key)
              ? 'Suggested'
              : 'None highlighted',
        ),
    ];

  if (!plant.assessable) {
    return [
      const _ObservationFact(
        Icons.do_not_disturb_alt_outlined,
        'Saved status',
        'Not assessable',
      ),
      _ObservationFact(
        Icons.notes_outlined,
        'Reason',
        _codeLabel(plant.notAssessableReason),
      ),
    ];
  }
  final facts = <_ObservationFact>[
    _ObservationFact(
      Icons.fact_check_outlined,
      'Saved status',
      _statusPresentation(plant.plantStatus).label,
    ),
    if (plant.currentFawEvidence != null)
      _ObservationFact(
        Icons.bug_report_outlined,
        'Protocol-derived current-evidence indicator',
        _yesNo(plant.currentFawEvidence),
      ),
    if (plant.possibleNonFawEvidence != null)
      _ObservationFact(
        Icons.help_outline,
        'Possible non-FAW evidence',
        _yesNo(plant.possibleNonFawEvidence),
      ),
    if (plant.uncertainEvidence != null)
      _ObservationFact(
        Icons.help_center_outlined,
        'Uncertain evidence',
        _yesNo(plant.uncertainEvidence),
      ),
    _ObservationFact(
      Icons.history_outlined,
      'Old damage present',
      _yesNo(plant.oldDamagePresent),
    ),
  ];
  final vegetative = record.vegetativeOrNull;
  if (vegetative != null) {
    if (vegetative.daBafsLeafDamageScore != null) {
      facts.add(
        _ObservationFact(
          Icons.analytics_outlined,
          'DA-BAFS leaf score',
          '${vegetative.daBafsLeafDamageScore} of 9',
        ),
      );
    }
    if (vegetative.damageAttribution != null) {
      facts.add(
        _ObservationFact(
          Icons.account_tree_outlined,
          'Damage attribution',
          _codeLabel(vegetative.damageAttribution),
        ),
      );
    }
    if (vegetative.damageFreshness != null) {
      facts.add(
        _ObservationFact(
          Icons.update_outlined,
          'Damage freshness',
          _codeLabel(vegetative.damageFreshness),
        ),
      );
    }
    facts.addAll([
      _ObservationFact(
        Icons.grass_outlined,
        'Whorl-feeding sign',
        _yesNo(vegetative.whorlFeedingSign),
      ),
      _ObservationFact(
        Icons.bubble_chart_outlined,
        'Fresh frass',
        _yesNo(vegetative.freshFrass),
      ),
      _ObservationFact(
        Icons.bug_report_outlined,
        'Larva visible',
        _yesNo(vegetative.larvaVisible),
      ),
    ]);
    if (vegetative.larvaVisible) {
      facts.add(
        _ObservationFact(
          Icons.straighten_outlined,
          'Recorded larval size',
          _codeLabel(vegetative.larvalSize),
        ),
      );
    }
  }
  final reproductive = record.reproductive;
  if (reproductive != null) {
    if (reproductive.classification != null) {
      facts.add(
        _ObservationFact(
          Icons.fact_check_outlined,
          'Evaluator classification',
          _codeLabel(reproductive.classification),
        ),
      );
    }
    facts.addAll([
      _ObservationFact(
        Icons.check_circle_outline_rounded,
        'Fresh feeding present',
        _yesNo(reproductive.freshFeedingPresent),
      ),
      _ObservationFact(
        Icons.bug_report_outlined,
        'Larva present',
        _yesNo(reproductive.larvaPresent),
      ),
      _ObservationFact(
        Icons.bubble_chart_outlined,
        'Frass present',
        _yesNo(reproductive.frassPresent),
      ),
    ]);
  }
  final ear = record.ear;
  if (ear != null) {
    if (ear.externalClassification != null) {
      facts.add(
        _ObservationFact(
          Icons.fact_check_outlined,
          'External-ear classification',
          _codeLabel(ear.externalClassification),
        ),
      );
    }
    facts.addAll([
      if (ear.externalDamagePresent != null)
        _ObservationFact(
          Icons.warning_amber_outlined,
          'External damage present',
          _yesNo(ear.externalDamagePresent),
        ),
      if (ear.activeInfestationPresent != null)
        _ObservationFact(
          Icons.bug_report_outlined,
          'Active infestation evidence',
          _yesNo(ear.activeInfestationPresent),
        ),
      if (ear.moldRotLikeSymptoms != null)
        _ObservationFact(
          Icons.coronavirus_outlined,
          'Mold- or rot-like symptoms',
          _yesNo(ear.moldRotLikeSymptoms),
        ),
    ]);
  }
  return facts;
}

Future<void> _openEvidence(
  BuildContext context, {
  required AssessmentHistoryDetail detail,
  required StationSnapshot station,
  required PlantObservationRecord plant,
  required List<AssessmentEvidenceEntry> entries,
  required int index,
  required EvidenceStorageService storage,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => EvidencePhotoViewer(
      media: entries[index].media,
      scopeLabel: entries[index].scope,
      resolveFile: storage.resolve,
      allowActions: false,
      fieldName: detail.workspace.field.name,
      stationLabel:
          'Block ${station.prepared.run.blockSequence} · Station ${station.stationNumber}',
      photoIndex: index + 1,
      photoCount: entries.length,
      observationSummary:
          'Saved status: ${_statusPresentation(plant.plantStatus).label}',
    ),
  ),
);

bool _isSeedling(String stage) => const {'ve', 'v1', 'v2'}.contains(stage);

String _yesNo(bool? value) => value == null
    ? 'Not recorded'
    : value
    ? 'Yes'
    : 'No';

String _codeLabel(String? value) {
  if (value == null || value.trim().isEmpty) return 'Not recorded';
  final words = value.replaceAll('_', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

({String label, Color background, Color foreground}) _statusPresentation(
  String status,
) => switch (status) {
  AutomaticScreening.positiveStatus => (
    label: 'Damage detected',
    background: const Color(0xFFFDE8E8),
    foreground: const Color(0xFFB3261E),
  ),
  AutomaticScreening.negativeStatus => (
    label: 'No damage detected',
    background: const Color(0xFFEAF6EE),
    foreground: const Color(0xFF176B3A),
  ),
  AutomaticScreening.unavailableStatus => (
    label: 'Not assessed',
    background: const Color(0xFFF1F5F9),
    foreground: const Color(0xFF64748B),
  ),

  'current_positive' => (
    label: 'Current-positive record',
    background: const Color(0xFFFFD9DE),
    foreground: const Color(0xFF8B1E2D),
  ),
  'negative' => (
    label: 'No current signs recorded',
    background: const Color(0xFFDDF1DB),
    foreground: AppColors.highContrastGreen,
  ),
  'old_damage_only' => (
    label: 'Old damage only',
    background: const Color(0xFFFFE8B8),
    foreground: const Color(0xFF755100),
  ),
  'possible_non_faw' => (
    label: 'Possible non-FAW',
    background: const Color(0xFFFFE8B8),
    foreground: const Color(0xFF755100),
  ),
  'uncertain' => (
    label: 'Uncertain',
    background: const Color(0xFFE6E7EB),
    foreground: const Color(0xFF42464D),
  ),
  'not_assessable' => (
    label: 'Not assessable',
    background: const Color(0xFFE6E7EB),
    foreground: const Color(0xFF42464D),
  ),
  _ => (
    label: _codeLabel(status),
    background: AppColors.primaryLight,
    foreground: AppColors.highContrastGreen,
  ),
};

class _ObservationFact {
  const _ObservationFact(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}
