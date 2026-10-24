import '../../models/automatic_screening.dart';
import 'dart:io';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../services/evidence_capture_coordinator.dart';
import '../../services/station_evidence_policy.dart';
import '../../theme/app_colors.dart';
import 'field_workflow_components.dart';
import 'station_review_components.dart';

class StationReviewStep extends StatelessWidget {
  const StationReviewStep({
    super.key,
    required this.snapshot,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.evidencePolicy = StationEvidencePolicy.station1TwoView,
    required this.isSaving,
    required this.onEdit,
    required this.onConfirm,
    this.onCompleteWithoutManualConfirmation,
    this.onCompleteTestStation,
    this.onMarkInsufficient,
    this.evidenceReviews = const {},
    this.evidenceBundles = const [],
    this.resolveEvidenceFile,
    this.evidenceThumbnailBuilder,
    this.onOpenEvidence,
    this.pilotWorkloadMetrics = PilotWorkloadMetrics.empty,
    this.growthStage = 'v3_v6',
  });

  final Station1Snapshot snapshot;
  final int blockNumber;
  final int stationNumber;
  final String growthStage;
  final StationEvidencePolicy evidencePolicy;
  final bool isSaving;
  final ValueChanged<int> onEdit;
  final VoidCallback onConfirm;
  final VoidCallback? onCompleteWithoutManualConfirmation;
  final VoidCallback? onCompleteTestStation;
  final ValueChanged<int>? onMarkInsufficient;
  final Map<int, PlantEvidenceReview> evidenceReviews;
  final List<EvidenceCaptureBundle> evidenceBundles;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? evidenceThumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;
  final PilotWorkloadMetrics pilotWorkloadMetrics;

  @override
  Widget build(BuildContext context) {
    final station = snapshot.station!;
    final savedByPosition = {
      for (final item in snapshot.plants) item.plant.sequenceNumber: item,
    };
    final pendingPositions = [
      for (var position = 1; position <= 10; position++)
        if (!savedByPosition.containsKey(position)) position,
    ];
    final confirmedPositions = [
      for (var position = 1; position <= 10; position++)
        if (savedByPosition.containsKey(position)) position,
    ];
    final manualComplete = pendingPositions.isEmpty;
    final unresolvedEvidence = <int>[
      for (final item in snapshot.plants)
        if (item.plant.assessable &&
            (evidenceReviews[item.plant.sequenceNumber]?.isCurrent != true ||
                evidenceReviews[item.plant.sequenceNumber]?.status !=
                    DatabaseCodes.evidenceReviewSufficient))
          item.plant.sequenceNumber,
    ];
    final stationReady = manualComplete && unresolvedEvidence.isEmpty;
    final attentionPositions =
        <int>{...pendingPositions, ...unresolvedEvidence}.toList()
          ..sort((a, b) {
            final aState = _positionState(
              saved: savedByPosition[a],
              evidence: _bundleForPlant(evidenceBundles, a),
              review: evidenceReviews[a],
            );
            final bState = _positionState(
              saved: savedByPosition[b],
              evidence: _bundleForPlant(evidenceBundles, b),
              review: evidenceReviews[b],
            );
            return _reviewPriority(aState).compareTo(_reviewPriority(bState));
          });
    final readyPositions = [
      for (final position in confirmedPositions)
        if (!attentionPositions.contains(position)) position,
    ];
    final states = {
      for (var position = 1; position <= 10; position++)
        position: _positionState(
          saved: savedByPosition[position],
          evidence: _bundleForPlant(evidenceBundles, position),
          review: evidenceReviews[position],
        ),
    };
    final screeningMode = snapshot.plants.any(
      (p) => AutomaticScreening.parse(p.plant.wholePlantContextNote) != null,
    );
    final healthyCount = snapshot.plants
        .where(
          (p) =>
              (p.plant.plantStatus ==
              (screeningMode
                  ? AutomaticScreening.negativeStatus
                  : DatabaseCodes.plantNegative)),
        )
        .length;
    final infestedCount = snapshot.plants
        .where(
          (p) =>
              (p.plant.plantStatus ==
              (screeningMode
                  ? AutomaticScreening.positiveStatus
                  : DatabaseCodes.plantCurrentPositive)),
        )
        .length;
    final notAssessableCount = snapshot.plants
        .where((p) => !p.plant.assessable)
        .length;
    final davisScores = snapshot.plants
        .map((p) => p.vegetativeOrNull?.daBafsLeafDamageScore)
        .where((s) => s != null && s > 0)
        .cast<int>()
        .toList();
    final avgDavisGrade = davisScores.isNotEmpty
        ? davisScores.reduce((a, b) => a + b) / davisScores.length
        : null;
    final larvaeCount = snapshot.plants
        .where(
          (p) =>
              p.vegetativeOrNull?.larvaVisible == true ||
              p.reproductive?.larvaPresent == true,
        )
        .length;
    final frassCount = snapshot.plants
        .where(
          (p) =>
              p.vegetativeOrNull?.freshFrass == true ||
              p.reproductive?.frassPresent == true,
        )
        .length;
    final whorlDamageCount = snapshot.plants
        .where(
          (p) =>
              p.vegetativeOrNull?.whorlFeedingSign == true ||
              p.vegetativeOrNull?.smallFreshWindowpanes == true ||
              (p.vegetativeOrNull?.daBafsLeafDamageScore != null &&
                  p.vegetativeOrNull!.daBafsLeafDamageScore! > 1),
        )
        .length;
    final cutSeedlingCount = snapshot.plants
        .where(
          (p) =>
              p.vegetativeOrNull?.cuttingOrTearing == true ||
              p.plant.notAssessableReason?.toLowerCase().contains('cut') ==
                  true ||
              p.plant.evaluatorNotes?.toLowerCase().contains('cut') == true,
        )
        .length;
    final emptySpotCount = snapshot.plants
        .where(
          (p) =>
              p.plant.notAssessableReason == DatabaseCodes.veOccupancyEmpty ||
              p.plant.notAssessableReason?.toLowerCase().contains('empty') ==
                  true,
        )
        .length;

    final nextPosition = attentionPositions.firstOrNull;

    return FieldWorkflowShell(
      scrollKey: const Key('station_review_step'),
      bottomBar: StationReviewBottomBar(
        message: stationReady
            ? 'All required observations and evidence reviews are complete.'
            : 'Review observations or complete station.',
        actionLabel: stationReady
            ? 'Complete Station $stationNumber'
            : 'Complete Station $stationNumber',
        actionKey: const Key('confirm_station_review_button'),
        isSaving: isSaving,
        onPressed: onConfirm,
      ),
      children: [
        StationReviewHeader(
          blockNumber: blockNumber,
          stageLabel: growthStageLabel(growthStage),
          stationNumber: stationNumber,
          confirmedCount: snapshot.plants.length,
          itemLabel: 'plants',
          needsAttentionCount: 0,
          healthyCount: healthyCount,
          infestedCount: infestedCount,
        ),
        const WorkflowSectionHeader(
          title: 'Agronomic summary',
          subtitle: 'Observations recorded at this station.',
        ),
        StationAgronomicThreatCard(
          screeningMode: screeningMode,
          growthStage: growthStage,
          totalPlants: screeningMode
              ? snapshot.plants
                    .where(
                      (p) =>
                          AutomaticScreening.parse(
                            p.plant.wholePlantContextNote,
                          )?.available ==
                          true,
                    )
                    .length
              : 10,
          infestedCount: infestedCount,
          healthyCount: healthyCount,
          notAssessableCount: notAssessableCount,
          avgDavisGrade: avgDavisGrade,
          larvaeCount: larvaeCount,
          frassCount: frassCount,
          whorlDamageCount: whorlDamageCount,
          cutSeedlingCount: cutSeedlingCount,
          emptySpotCount: emptySpotCount,
        ),
        const SizedBox(height: 14),
        const WorkflowSectionHeader(
          title: 'Plant assessments',
          subtitle: 'Tap any plant to inspect observations or photos.',
        ),
        for (var position = 1; position <= 10; position++)
          _buildCompactPlantTile(
            context: context,
            position: position,
            item: savedByPosition[position],
            evidence: _bundleForPlant(evidenceBundles, position),
            resolveEvidenceFile: resolveEvidenceFile,
            onEdit: onEdit,
          ),
        const SizedBox(height: 14),
        StationDetailsFooterStrip(
          gpsAccuracyM: station.gpsAccuracyM,
          notLocatedReason: station.notLocatedReason,
          durationLabel: pilotWorkloadMetrics.acceptedImageCount > 0
              ? '${pilotWorkloadMetrics.acceptedImageCount} photos · ${pilotWorkloadMetrics.manualFallbackCount} fallbacks'
              : null,
        ),
        if (onCompleteTestStation != null) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('test_data_station_bypass_card'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'TEST DATA SHORTCUT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.severeSeverityRing,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('complete_test_station_from_review_button'),
                    onPressed: isSaving ? null : onCompleteTestStation,
                    child: AppText(
                      'Bypass Station $stationNumber with test data',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactPlantTile({
    required BuildContext context,
    required int position,
    required Station1PlantRecord? item,
    required EvidenceCaptureBundle? evidence,
    required Future<File> Function(String localUri)? resolveEvidenceFile,
    required ValueChanged<int> onEdit,
  }) {
    if (item == null) {
      return CompactPlantAuditTile(
        position: position,
        statusLabel: 'Not recorded',
        statusColor: const Color(0xFF7A4A00),
        statusBgColor: const Color(0xFFFFEBC4),
        symptomsSummary: 'Tap to record observation',
        isUnassessed: true,
        onTap: () => onEdit(position),
      );
    }
    final plant = item.plant;
    if (!plant.assessable) {
      return CompactPlantAuditTile(
        position: position,
        statusLabel: 'Not assessable',
        statusColor: const Color(0xFF5A5A5A),
        statusBgColor: const Color(0xFFE8EAEB),
        symptomsSummary: plant.notAssessableReason ?? 'Cannot assess',
        onTap: () => onEdit(position),
      );
    }

    final screen = AutomaticScreening.parse(plant.wholePlantContextNote);
    final isInfested =
        screen?.positive ??
        (plant.plantStatus == DatabaseCodes.plantCurrentPositive);
    final isOldDamage = plant.plantStatus == DatabaseCodes.plantOldDamageOnly;
    final isNonFaw = plant.plantStatus == DatabaseCodes.plantPossibleNonFaw;

    final String statusLabel;
    final Color statusColor;
    final Color statusBgColor;

    if (isInfested) {
      statusLabel = screen?.label ?? 'FAW Infested';
      statusColor = AppColors.severeSeverityRing;
      statusBgColor = AppColors.severeSeverityBg;
    } else if (isOldDamage) {
      statusLabel = 'Old damage';
      statusColor = const Color(0xFFB57400);
      statusBgColor = const Color(0xFFFFF3D6);
    } else if (isNonFaw) {
      statusLabel = 'Non-FAW sign';
      statusColor = const Color(0xFF24547A);
      statusBgColor = const Color(0xFFE3EDF7);
    } else {
      statusLabel = screen?.label ?? 'Clean';
      statusColor = AppColors.highContrastGreen;
      statusBgColor = const Color(0xFFDDF1E2);
    }

    final symptoms = <String>[
      if (item.vegetative.larvaVisible)
        'Larva visible (${item.vegetative.larvalSize})',
      if (item.vegetative.freshFrass) 'Fresh frass',
      if (item.vegetative.whorlFeedingSign) 'Whorl feeding',
      if (item.vegetative.daBafsLeafDamageScore != null &&
          item.vegetative.daBafsLeafDamageScore! > 1)
        'Davis Grade ${item.vegetative.daBafsLeafDamageScore}',
      if (item.vegetative.smallFreshWindowpanes) 'Windowpanes',
      if (item.vegetative.scraping) 'Scraping',
      if (item.vegetative.cuttingOrTearing) 'Cutting/Tearing',
    ];

    final summary = screen != null
        ? screen.label
        : symptoms.isNotEmpty
        ? symptoms.join(' · ')
        : 'Healthy · No signs of fall armyworm';

    final readyMedia = evidence?.media
        .where(
          (m) =>
              m.deletedAt == null &&
              (m.storageState == DatabaseCodes.evidenceStorageReady ||
                  m.storageState == DatabaseCodes.evidenceStorageStaged),
        )
        .firstOrNull;

    if (readyMedia != null && resolveEvidenceFile != null) {
      return FutureBuilder<File>(
        future: resolveEvidenceFile(readyMedia.localUri),
        builder: (context, snapshot) {
          return CompactPlantAuditTile(
            position: position,
            statusLabel: statusLabel,
            statusColor: statusColor,
            statusBgColor: statusBgColor,
            symptomsSummary: summary,
            thumbnailFile: snapshot.data,
            onTap: () => onEdit(position),
          );
        },
      );
    }

    return CompactPlantAuditTile(
      position: position,
      statusLabel: statusLabel,
      statusColor: statusColor,
      statusBgColor: statusBgColor,
      symptomsSummary: summary,
      onTap: () => onEdit(position),
    );
  }
}

class _PendingPlantReviewCard extends StatelessWidget {
  const _PendingPlantReviewCard({
    required this.position,
    required this.onEdit,
    this.evidence,
    this.evidenceReview,
    this.resolveEvidenceFile,
    this.evidenceThumbnailBuilder,
    this.onOpenEvidence,
    this.onMarkInsufficient,
  });

  final int position;
  final ValueChanged<int> onEdit;
  final EvidenceCaptureBundle? evidence;
  final PlantEvidenceReview? evidenceReview;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? evidenceThumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;
  final ValueChanged<int>? onMarkInsufficient;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('pending_manual_plant_$position'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFFD54F)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppText(
                    'Plant $position',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                _StatusPill(
                  label: _evidenceStateLabel(
                    evidence: evidence,
                    review: evidenceReview,
                  ),
                  icon: _evidenceStateIcon(
                    evidence: evidence,
                    review: evidenceReview,
                  ),
                ),
              ],
            ),
            if (_evidenceStateLabel(
                  evidence: evidence,
                  review: evidenceReview,
                ) ==
                'Not reviewed') ...[
              const SizedBox(height: 4),
              const AppText(
                'Needs confirmation',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            if (resolveEvidenceFile != null) ...[
              const SizedBox(height: 8),
              _ReviewEvidence(
                label: 'Plant $position evidence',
                bundle: evidence,
                showPlantViews: true,
                showLabel: false,
                resolveEvidenceFile: resolveEvidenceFile!,
                thumbnailBuilder: evidenceThumbnailBuilder,
                onOpenEvidence: onOpenEvidence,
              ),
            ],
            const SizedBox(height: 10),
            if (onMarkInsufficient != null) ...[
              OutlinedButton.icon(
                key: Key('mark_plant_${position}_insufficient'),
                onPressed: () => onMarkInsufficient!(position),
                icon: const Icon(Icons.report_outlined),
                label: const AppText('Mark evidence insufficient'),
              ),
              const SizedBox(height: 8),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                key: Key('manual_confirm_plant_${position}_button'),
                onPressed: () => onEdit(position),
                icon: const Icon(Icons.fact_check_outlined),
                label: AppText('Review Plant $position'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (label) {
      'Sufficient' => (const Color(0xFFDDF1E2), const Color(0xFF176B3A)),
      'Missing' ||
      'Insufficient' => (const Color(0xFFFFE3DE), const Color(0xFF9F2D20)),
      'Fallback' => (const Color(0xFFE3EDF7), const Color(0xFF24547A)),
      'Not assessable' => (const Color(0xFFE8EAEB), const Color(0xFF4E585C)),
      _ => (const Color(0xFFFFEBC4), const Color(0xFF7A4A00)),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantReviewCard extends StatelessWidget {
  const _PlantReviewCard({
    required this.item,
    required this.evidencePolicy,
    required this.onEdit,
    this.evidence,
    this.evidenceReview,
    this.resolveEvidenceFile,
    this.evidenceThumbnailBuilder,
    this.onOpenEvidence,
    this.onMarkInsufficient,
  });

  final Station1PlantRecord item;
  final StationEvidencePolicy evidencePolicy;
  final ValueChanged<int> onEdit;
  final EvidenceCaptureBundle? evidence;
  final PlantEvidenceReview? evidenceReview;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? evidenceThumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;
  final ValueChanged<int>? onMarkInsufficient;

  @override
  Widget build(BuildContext context) {
    final plant = item.plant;
    final isPositive = plant.plantStatus == DatabaseCodes.plantCurrentPositive;
    final isNegative = plant.plantStatus == DatabaseCodes.plantNegative;
    final raw = <String>[
      if (item.vegetative.smallFreshWindowpanes) 'Windowpanes',
      if (item.vegetative.scraping) 'Scraping',
      if (item.vegetative.cuttingOrTearing) 'Cutting/Tearing',
      if (item.vegetative.freshFrass) 'Frass',
      if (item.vegetative.whorlFeedingSign) 'Whorl feeding',
      if (item.vegetative.larvaVisible) 'Larva: ${item.vegetative.larvalSize}',
      if (item.vegetative.eggMassVisible == true) 'Egg mass',
      if (plant.oldDamagePresent) 'Old damage',
      if (plant.possibleNonFawEvidence == true) 'Non-FAW sign',
      if (plant.uncertainEvidence == true) 'Uncertain sign',
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPositive
              ? const Color(0xFFB3261E).withValues(alpha: 0.35)
              : Colors.black12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppText(
                        'Plant ${plant.sequenceNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: _evidenceStateLabel(
                          evidence: evidence,
                          review: evidenceReview,
                          assessable: plant.assessable,
                        ),
                        icon: _evidenceStateIcon(
                          evidence: evidence,
                          review: evidenceReview,
                          assessable: plant.assessable,
                        ),
                      ),
                    ],
                  ),
                  if (resolveEvidenceFile != null) ...[
                    const SizedBox(height: 8),
                    _ReviewEvidence(
                      label: 'Plant ${plant.sequenceNumber} evidence',
                      bundle: evidence,
                      showPlantViews: true,
                      showLabel: false,
                      emptyEvidenceLabel:
                          evidencePolicy
                              .requiredViewsForObservation(
                                plant: plant,
                                vegetative: item.vegetative,
                              )
                              .isEmpty
                          ? 'No photo required'
                          : null,
                      resolveEvidenceFile: resolveEvidenceFile!,
                      thumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _statusLabel(plant.plantStatus),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isPositive
                          ? const Color(0xFFB3261E)
                          : isNegative
                          ? const Color(0xFF176B3A)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (plant.assessable)
                    if (raw.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final sign in raw)
                            _SymptomChip(label: sign, isPositive: isPositive),
                        ],
                      )
                    else
                      const AppText(
                        'No feeding signs observed',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      )
                  else
                    AppText(
                      'Not assessable: ${plant.notAssessableReason ?? "unspecified"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  key: Key('edit_plant_${plant.sequenceNumber}_button'),
                  tooltip: 'Review or correct Plant ${plant.sequenceNumber}',
                  onPressed: () => onEdit(plant.sequenceNumber),
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (plant.assessable && onMarkInsufficient != null)
                  IconButton(
                    key: Key('mark_plant_${plant.sequenceNumber}_insufficient'),
                    tooltip: AppWords.of(
                      context,
                    ).translate('Mark evidence insufficient'),
                    onPressed: () => onMarkInsufficient!(plant.sequenceNumber),
                    icon: const Icon(Icons.report_outlined),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  const _SymptomChip({required this.label, this.isPositive = true});

  final String label;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final color = isPositive
        ? const Color(0xFFB3261E)
        : const Color(0xFF176B3A);
    final bg = isPositive ? const Color(0xFFFDE8E8) : const Color(0xFFEAF6EE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ReviewEvidence extends StatelessWidget {
  const _ReviewEvidence({
    required this.label,
    required this.bundle,
    required this.resolveEvidenceFile,
    this.showPlantViews = false,
    this.showLabel = true,
    this.emptyEvidenceLabel,
    this.thumbnailBuilder,
    this.onOpenEvidence,
  });

  final String label;
  final EvidenceCaptureBundle? bundle;
  final Future<File> Function(String localUri) resolveEvidenceFile;
  final bool showPlantViews;
  final bool showLabel;
  final String? emptyEvidenceLabel;
  final Widget Function(EvidenceMediaRecord media)? thumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    final ready =
        bundle?.media
            .where(
              (media) =>
                  media.deletedAt == null &&
                  media.storageState == DatabaseCodes.evidenceStorageReady,
            )
            .toList(growable: false) ??
        const [];
    final waived = bundle?.waivedViewTypes ?? const <String>{};
    return Column(
      key: Key('review_evidence_${bundle?.session.scopeKey ?? label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
        ],
        if (showPlantViews)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildViewSlot(
                DatabaseCodes.evidenceViewWhorlOverview,
                'Overview',
                ready,
              ),
              _buildViewSlot(
                DatabaseCodes.evidenceViewCloseUp,
                'Close-up',
                ready,
              ),
            ],
          )
        else if (ready.isEmpty)
          Text(
            waived.isNotEmpty
                ? 'Manual fallback documented'
                : emptyEvidenceLabel ?? 'No accepted image',
            style: const TextStyle(fontSize: 13),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final media in ready)
                _ReviewEvidenceThumbnail(
                  key: ValueKey(media.id),
                  media: media,
                  resolveEvidenceFile: resolveEvidenceFile,
                  thumbnailBuilder: thumbnailBuilder,
                  scopeLabel: label,
                  onOpenEvidence: onOpenEvidence,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildViewSlot(
    String viewType,
    String viewLabel,
    List<EvidenceMediaRecord> ready,
  ) {
    EvidenceMediaRecord? media;
    for (final candidate in ready.reversed) {
      if (candidate.viewType == viewType) {
        media = candidate;
        break;
      }
    }
    if (media != null) {
      return _ReviewEvidenceThumbnail(
        key: ValueKey(media.id),
        media: media,
        resolveEvidenceFile: resolveEvidenceFile,
        thumbnailBuilder: thumbnailBuilder,
        scopeLabel: label,
        onOpenEvidence: onOpenEvidence,
      );
    }
    final waived = bundle?.waivedViewTypes.contains(viewType) == true;
    return Container(
      key: Key('missing_${bundle?.session.scopeKey}_$viewType'),
      width: 104,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(waived ? Icons.description_outlined : Icons.image_outlined),
          const SizedBox(height: 4),
          Text(viewLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            waived
                ? 'Fallback'
                : viewType == DatabaseCodes.evidenceViewCloseUp
                ? 'Not captured'
                : 'Missing',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ReviewEvidenceThumbnail extends StatefulWidget {
  const _ReviewEvidenceThumbnail({
    super.key,
    required this.media,
    required this.resolveEvidenceFile,
    this.thumbnailBuilder,
    required this.scopeLabel,
    this.onOpenEvidence,
  });

  final EvidenceMediaRecord media;
  final Future<File> Function(String localUri) resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? thumbnailBuilder;
  final String scopeLabel;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;

  @override
  State<_ReviewEvidenceThumbnail> createState() =>
      _ReviewEvidenceThumbnailState();
}

class _ReviewEvidenceThumbnailState extends State<_ReviewEvidenceThumbnail> {
  late Future<File> _file;

  @override
  void initState() {
    super.initState();
    _file = _resolve();
  }

  @override
  void didUpdateWidget(covariant _ReviewEvidenceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.localUri != widget.media.localUri ||
        oldWidget.media.thumbnailLocalUri != widget.media.thumbnailLocalUri) {
      _file = _resolve();
    }
  }

  Future<File> _resolve() => widget.resolveEvidenceFile(
    widget.media.thumbnailLocalUri ?? widget.media.localUri,
  );

  @override
  Widget build(BuildContext context) {
    final custom = widget.thumbnailBuilder;
    if (custom != null) {
      return _thumbnailFrame(custom(widget.media));
    }
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) => _thumbnailFrame(
        snapshot.hasData
            ? Image.file(
                snapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE6E6E6),
                  child: Icon(Icons.broken_image_outlined),
                ),
              )
            : const ColoredBox(
                color: Color(0xFFE6E6E6),
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }

  Widget _thumbnailFrame(Widget child) {
    return Semantics(
      button: widget.onOpenEvidence != null,
      label:
          '${widget.scopeLabel}, ${_viewLabel(widget.media.viewType)}. Open canonical evidence photo.',
      child: InkWell(
        key: Key('review_open_evidence_${widget.media.id}'),
        onTap: widget.onOpenEvidence == null
            ? null
            : () => widget.onOpenEvidence!(widget.media, widget.scopeLabel),
        child: SizedBox(
          width: 104,
          child: Column(
            children: [
              AspectRatio(aspectRatio: 4 / 3, child: child),
              const SizedBox(height: 3),
              Text(
                _viewLabel(widget.media.viewType),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PilotWorkloadCard extends StatelessWidget {
  const _PilotWorkloadCard({required this.metrics});

  final PilotWorkloadMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final storageMib = metrics.storageBytes / (1024 * 1024);
    return Card(
      key: const Key('pilot_workload_metrics'),
      elevation: 0,
      color: const Color(0xFFF3F8F4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Station 1 pilot workload',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            AppText(
              '${metrics.acceptedImageCount} accepted images · '
              '${metrics.retakeCount} retakes · '
              '${metrics.manualFallbackCount} manual fallbacks',
              style: const TextStyle(height: 1.35),
            ),
            AppText(
              '${metrics.manualFormUseCount} of 10 plant manual forms saved',
              style: const TextStyle(height: 1.35),
            ),
            AppText(
              '${metrics.guidedTapCount} guided capture taps recorded',
              style: const TextStyle(height: 1.35),
            ),
            AppText(
              'Private evidence storage: ${storageMib.toStringAsFixed(2)} MiB',
              style: const TextStyle(height: 1.35),
            ),
            const SizedBox(height: 6),
            const AppText(
              'Active screen time per plant:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (metrics.activeTimeByPlant.isEmpty)
              const AppText('Recorded when each plant is saved.')
            else
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final entry
                      in metrics.activeTimeByPlant.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key)))
                    AppText('P${entry.key}: ${_formatDuration(entry.value)}'),
                ],
              ),
            const SizedBox(height: 6),
            const AppText(
              'Pilot measurement only. It does not define an image requirement for Stations 2–5.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

EvidenceCaptureBundle? _bundleForScope(
  List<EvidenceCaptureBundle> bundles,
  String scopeType,
) {
  for (final bundle in bundles) {
    if (bundle.session.scopeType == scopeType) return bundle;
  }
  return null;
}

EvidenceCaptureBundle? _bundleForPlant(
  List<EvidenceCaptureBundle> bundles,
  int position,
) {
  for (final bundle in bundles) {
    if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
        bundle.session.plantPosition == position) {
      return bundle;
    }
  }
  return null;
}

String _evidenceStateLabel({
  required EvidenceCaptureBundle? evidence,
  required PlantEvidenceReview? review,
  bool assessable = true,
}) {
  if (!assessable) return 'Not assessable';
  if (evidence == null ||
      !evidence.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview)) {
    return 'Missing';
  }
  if (review?.isCurrent == true &&
      review?.status == DatabaseCodes.evidenceReviewInsufficient) {
    return 'Insufficient';
  }
  if (evidence.waivedViewTypes.contains(
    DatabaseCodes.evidenceViewWhorlOverview,
  )) {
    return 'Fallback';
  }
  if (review?.isCurrent == true &&
      review?.status == DatabaseCodes.evidenceReviewSufficient) {
    return 'Sufficient';
  }
  return 'Not reviewed';
}

ReviewPositionState _positionState({
  required Station1PlantRecord? saved,
  required EvidenceCaptureBundle? evidence,
  required PlantEvidenceReview? review,
}) {
  if (saved?.plant.assessable == false) {
    return ReviewPositionState.notAssessable;
  }
  return switch (_evidenceStateLabel(
    evidence: evidence,
    review: review,
    assessable: saved?.plant.assessable ?? true,
  )) {
    'Sufficient' => ReviewPositionState.confirmed,
    'Insufficient' => ReviewPositionState.insufficient,
    'Missing' => ReviewPositionState.missing,
    'Fallback' => ReviewPositionState.fallback,
    'Not assessable' => ReviewPositionState.notAssessable,
    _ => ReviewPositionState.notReviewed,
  };
}

int _reviewPriority(ReviewPositionState state) => switch (state) {
  ReviewPositionState.missing => 0,
  ReviewPositionState.insufficient => 1,
  ReviewPositionState.fallback => 2,
  ReviewPositionState.notReviewed => 3,
  ReviewPositionState.notAssessable => 4,
  ReviewPositionState.confirmed => 5,
};

IconData _evidenceStateIcon({
  required EvidenceCaptureBundle? evidence,
  required PlantEvidenceReview? review,
  bool assessable = true,
}) => switch (_evidenceStateLabel(
  evidence: evidence,
  review: review,
  assessable: assessable,
)) {
  'Sufficient' => Icons.check_circle_outline,
  'Insufficient' => Icons.report_outlined,
  'Missing' => Icons.image_not_supported_outlined,
  'Fallback' => Icons.description_outlined,
  'Not assessable' => Icons.block_outlined,
  _ => Icons.pending_outlined,
};

String _viewLabel(String? viewType) => switch (viewType) {
  DatabaseCodes.evidenceViewStationContext => 'Context',
  DatabaseCodes.evidenceViewWhorlOverview => 'Whorl overview',
  DatabaseCodes.evidenceViewCloseUp => 'Close-up',
  DatabaseCodes.evidenceViewDiagnosticDetail => 'Extra detail',
  _ => 'Evidence',
};

String _statusLabel(String status) => switch (status) {
  DatabaseCodes.plantNegative => 'No current FAW-consistent evidence',
  DatabaseCodes.plantCurrentPositive => 'Current FAW-consistent evidence',
  DatabaseCodes.plantOldDamageOnly => 'Old damage only',
  DatabaseCodes.plantPossibleNonFaw => 'Possible non-FAW evidence',
  DatabaseCodes.plantUncertain => 'Uncertain interpretation',
  DatabaseCodes.plantNotAssessable => 'Not assessable',
  _ => status,
};

String _reasonLabel(String? reason) => switch (reason) {
  DatabaseCodes.stationLocationServicesOff => 'phone location was off',
  DatabaseCodes.stationPermissionDenied => 'permission was denied',
  DatabaseCodes.stationPermissionBlocked => 'permission was blocked',
  DatabaseCodes.stationNoCurrentFix => 'no current GPS reading',
  DatabaseCodes.stationUnsafeToWait => 'unsafe or impractical to wait',
  DatabaseCodes.stationLocationDeviceError => 'phone or location error',
  DatabaseCodes.stationLocationOther => 'other recorded reason',
  _ => 'recorded reason',
};

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
}
