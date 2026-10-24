import '../../models/automatic_screening.dart';
import 'package:flutter/material.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../theme/app_colors.dart';
import 'field_workflow_components.dart';
import 'station_review_components.dart';

class StageStationReviewStep extends StatelessWidget {
  const StageStationReviewStep({
    super.key,
    required this.growthStage,
    this.blockNumber = 1,
    required this.snapshot,
    required this.evidenceReviews,
    required this.openingPlan,
    required this.openedEarSubsampleComplete,
    required this.isSaving,
    required this.onEditPlant,
    required this.onBeginOpenedEar,
    required this.onFailOpenedEar,
    required this.onConfirm,
  });

  final String growthStage;
  final int blockNumber;
  final StationSnapshot snapshot;
  final Map<int, PlantEvidenceReview> evidenceReviews;
  final List<EarOpeningSelectionRecord> openingPlan;
  final bool openedEarSubsampleComplete;
  final bool isSaving;
  final ValueChanged<int> onEditPlant;
  final ValueChanged<EarOpeningSelectionRecord> onBeginOpenedEar;
  final Future<void> Function(
    EarOpeningSelectionRecord selection,
    String reason,
  )
  onFailOpenedEar;
  final VoidCallback onConfirm;

  bool get _isLate => growthStage == 'r3_r6';

  @override
  Widget build(BuildContext context) {
    final plants = {
      for (final item in snapshot.plants) item.plant.sequenceNumber: item,
    };
    final completePlants = snapshot.plants.length == 10;
    final evidenceComplete = List.generate(10, (index) => index + 1).every((
      position,
    ) {
      final plant = plants[position];
      if (plant == null) return false;
      if (!plant.plant.assessable) return true;
      final review = evidenceReviews[position];
      return review?.isCurrent == true &&
          review?.status == DatabaseCodes.evidenceReviewSufficient;
    });
    final canConfirm =
        completePlants && evidenceComplete && openedEarSubsampleComplete;
    final states = {
      for (var position = 1; position <= 10; position++)
        position: _reviewState(
          plant: plants[position],
          evidenceReview: evidenceReviews[position],
        ),
    };
    final attentionPositions = [
      for (var position = 1; position <= 10; position++)
        if (states[position] != ReviewPositionState.confirmed &&
            states[position] != ReviewPositionState.notAssessable)
          position,
    ];
    final completedPositions = [
      for (var position = 1; position <= 10; position++)
        if (!attentionPositions.contains(position)) position,
    ];
    final activeOpeningSelections = openingPlan
        .where(
          (selection) =>
              selection.initiallySelected ||
              selection.selectionStatus == 'replacement_selected' ||
              selection.selectionStatus == 'opened' ||
              selection.selectionStatus == 'failed',
        )
        .toList();
    final unresolvedOpeningCount = activeOpeningSelections
        .where(
          (selection) =>
              selection.selectionStatus != 'opened' &&
              selection.selectionStatus != 'failed',
        )
        .length;
    final attentionCount = attentionPositions.length + unresolvedOpeningCount;

    final screeningMode = snapshot.plants.any(
      (p) => AutomaticScreening.parse(p.plant.wholePlantContextNote) != null,
    );
    final healthyCount = screeningMode
        ? snapshot.plants
              .where(
                (p) =>
                    AutomaticScreening.parse(
                      p.plant.wholePlantContextNote,
                    )?.status ==
                    AutomaticScreening.negativeStatus,
              )
              .length
        : _isLate
        ? snapshot.plants
              .where(
                (p) =>
                    p.ear?.externalClassification ==
                    DatabaseCodes.earExternalNegative,
              )
              .length
        : snapshot.plants
              .where(
                (p) =>
                    p.reproductive?.classification ==
                    DatabaseCodes.reproductiveNotInfested,
              )
              .length;

    final infestedCount = screeningMode
        ? snapshot.plants
              .where(
                (p) =>
                    AutomaticScreening.parse(
                      p.plant.wholePlantContextNote,
                    )?.positive ==
                    true,
              )
              .length
        : _isLate
        ? snapshot.plants
              .where(
                (p) =>
                    p.ear?.externalClassification ==
                    DatabaseCodes.earExternalActive,
              )
              .length
        : snapshot.plants
              .where(
                (p) =>
                    p.reproductive?.classification ==
                    DatabaseCodes.reproductiveInfested,
              )
              .length;

    final larvaeCount = snapshot.plants
        .where(
          (p) =>
              p.reproductive?.larvaPresent == true ||
              p.vegetativeOrNull?.larvaVisible == true,
        )
        .length;

    final frassCount = snapshot.plants
        .where(
          (p) =>
              p.reproductive?.frassPresent == true ||
              p.vegetativeOrNull?.freshFrass == true,
        )
        .length;

    final tasselSilkInfestedCount = snapshot.plants
        .where(
          (p) =>
              p.reproductive?.larvaPresent == true ||
              p.reproductive?.freshFeedingPresent == true ||
              p.reproductive?.frassPresent == true ||
              p.reproductive?.earHuskPenetrationVisible == true,
        )
        .length;

    final earDamageCount = snapshot.plants
        .where(
          (p) =>
              p.ear?.externalClassification == DatabaseCodes.earExternalActive,
        )
        .length;

    return FieldWorkflowShell(
      scrollKey: const Key('stage_station_review'),
      bottomBar: StationReviewBottomBar(
        message: canConfirm
            ? 'All stage-specific observations and evidence are complete.'
            : 'Review observations or complete station.',
        actionLabel: 'Complete Station ${snapshot.stationNumber}',
        actionKey: const Key('confirm_stage_station_review'),
        isSaving: isSaving,
        onPressed: canConfirm ? onConfirm : onConfirm,
      ),
      children: [
        StationReviewHeader(
          blockNumber: blockNumber,
          stageLabel: growthStageLabel(growthStage),
          stationNumber: snapshot.stationNumber,
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
          tasselSilkInfestedCount: tasselSilkInfestedCount,
          earDamageCount: earDamageCount,
          larvaeCount: larvaeCount,
          frassCount: frassCount,
        ),
        if (_isLate && activeOpeningSelections.isNotEmpty) ...[
          WorkflowSectionHeader(
            title: 'Opened-ear tasks',
            subtitle: unresolvedOpeningCount == 0
                ? 'Every selected ear is resolved.'
                : '$unresolvedOpeningCount selected ${unresolvedOpeningCount == 1 ? 'ear requires' : 'ears require'} action.',
          ),
          for (final selection in activeOpeningSelections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OpeningSelectionCard(
                selection: selection,
                plant: plants[selection.plantPosition],
                isSaving: isSaving,
                onOpen: () => onBeginOpenedEar(selection),
                onFail: () => _showFailureDialog(context, selection),
              ),
            ),
        ],
        const WorkflowSectionHeader(
          title: 'Plant assessments',
          subtitle: 'Tap any plant to inspect or correct.',
        ),
        for (var position = 1; position <= 10; position++)
          _buildStageCompactPlantTile(
            position: position,
            plant: plants[position],
            onTap: () => onEditPlant(position),
          ),
        const SizedBox(height: 14),
        StationDetailsFooterStrip(
          gpsAccuracyM: snapshot.station?.gpsAccuracyM,
          notLocatedReason: snapshot.station?.notLocatedReason,
        ),
      ],
    );
  }

  Widget _buildStageCompactPlantTile({
    required int position,
    required StationPlantRecord? plant,
    required VoidCallback onTap,
  }) {
    if (plant == null) {
      return CompactPlantAuditTile(
        position: position,
        statusLabel: 'Not recorded',
        statusColor: const Color(0xFF7A4A00),
        statusBgColor: const Color(0xFFFFEBC4),
        symptomsSummary: 'Tap to record observation',
        isUnassessed: true,
        onTap: onTap,
      );
    }
    final screen = AutomaticScreening.parse(plant.plant.wholePlantContextNote);
    if (screen != null)
      return CompactPlantAuditTile(
        position: position,
        statusLabel: screen.label,
        statusColor: screen.positive
            ? AppColors.severeSeverityRing
            : AppColors.highContrastGreen,
        statusBgColor: screen.positive
            ? AppColors.severeSeverityBg
            : AppColors.primaryLight,
        symptomsSummary: '',
        onTap: onTap,
      );
    if (!plant.plant.assessable) {
      return CompactPlantAuditTile(
        position: position,
        statusLabel: 'Not assessable',
        statusColor: const Color(0xFF5A5A5A),
        statusBgColor: const Color(0xFFE8EAEB),
        symptomsSummary: plant.plant.notAssessableReason ?? 'Cannot assess',
        onTap: onTap,
      );
    }

    if (_isLate) {
      final ear = plant.ear;
      final isInfested =
          ear?.externalClassification == DatabaseCodes.earExternalActive;
      final isNegative =
          ear?.externalClassification == DatabaseCodes.earExternalNegative;

      final symptoms = <String>[
        if (ear?.larvaPresent == true) 'Ear larva',
        if (ear?.frassPresent == true) 'Silk/shank frass',
        if (ear?.entryHolePresent == true) 'Husk entry hole',
        if (ear?.silkDamagePresent == true) 'Silk feeding',
        if (ear?.huskDamagePresent == true) 'Husk damage',
      ];

      return CompactPlantAuditTile(
        position: position,
        statusLabel: isInfested
            ? 'FAW Infested Ear'
            : isNegative
            ? 'Clean Ear'
            : 'Recorded',
        statusColor: isInfested
            ? AppColors.severeSeverityRing
            : isNegative
            ? AppColors.highContrastGreen
            : const Color(0xFF24547A),
        statusBgColor: isInfested
            ? AppColors.severeSeverityBg
            : isNegative
            ? const Color(0xFFDDF1E2)
            : const Color(0xFFE3EDF7),
        symptomsSummary: symptoms.isNotEmpty
            ? symptoms.join(' · ')
            : 'Healthy ear · No feeding signs',
        onTap: onTap,
      );
    }

    final rep = plant.reproductive;
    final isInfested =
        rep?.classification == DatabaseCodes.reproductiveInfested;
    final isNegative =
        rep?.classification == DatabaseCodes.reproductiveNotInfested;

    final symptoms = <String>[
      if (rep?.larvaPresent == true) 'Larva: ${rep?.larvalSize}',
      if (rep?.frassPresent == true) 'Ear axil frass',
      if (rep?.freshFeedingPresent == true) 'Tassel/axil feeding',
      if (rep?.earHuskPenetrationVisible == true) 'Husk penetrated',
    ];

    return CompactPlantAuditTile(
      position: position,
      statusLabel: isInfested
          ? 'FAW Infested'
          : isNegative
          ? 'Clean'
          : 'Recorded',
      statusColor: isInfested
          ? AppColors.severeSeverityRing
          : isNegative
          ? AppColors.highContrastGreen
          : const Color(0xFF24547A),
      statusBgColor: isInfested
          ? AppColors.severeSeverityBg
          : isNegative
          ? const Color(0xFFDDF1E2)
          : const Color(0xFFE3EDF7),
      symptomsSummary: symptoms.isNotEmpty
          ? symptoms.join(' · ')
          : 'Healthy · No feeding signs',
      onTap: onTap,
    );
  }

  ReviewPositionState _reviewState({
    required StationPlantRecord? plant,
    required PlantEvidenceReview? evidenceReview,
  }) {
    if (plant == null) return ReviewPositionState.notReviewed;
    if (!plant.plant.assessable) return ReviewPositionState.notAssessable;
    if (evidenceReview?.status == DatabaseCodes.evidenceReviewInsufficient) {
      return ReviewPositionState.insufficient;
    }
    if (evidenceReview?.isCurrent == true &&
        evidenceReview?.status == DatabaseCodes.evidenceReviewSufficient) {
      return ReviewPositionState.confirmed;
    }
    return ReviewPositionState.notReviewed;
  }

  Future<void> _showFailureDialog(
    BuildContext context,
    EarOpeningSelectionRecord selection,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText('Plant ${selection.plantPosition} cannot be opened'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppWords.of(context).translate('Failure reason'),
            hintText: AppWords.of(context).translate(
              'No ear, unsafe, already harvested, damaged during access…',
            ),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const AppText('Record and use replacement'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason != null && reason.trim().isNotEmpty) {
      await onFailOpenedEar(selection, reason.trim());
    }
  }
}

class _StagePlantReviewCard extends StatelessWidget {
  const _StagePlantReviewCard({
    required this.position,
    required this.growthStage,
    required this.item,
    required this.evidenceReview,
    required this.onEdit,
  });
  final int position;
  final String growthStage;
  final StationPlantRecord? item;
  final PlantEvidenceReview? evidenceReview;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final record = item;
    final summary = record == null
        ? 'Observation required'
        : !record.plant.assessable
        ? 'Not assessable · ${record.plant.notAssessableReason}'
        : growthStage == 'vt_r2'
        ? _reproductiveSummary(record)
        : _earSummary(record);
    final reviewOkay =
        !((record?.plant.assessable) ?? false) ||
        (evidenceReview?.isCurrent == true &&
            evidenceReview?.status == DatabaseCodes.evidenceReviewSufficient);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: AppText('$position')),
        title: AppText('Plant $position'),
        subtitle: AppText(
          '$summary\nEvidence: ${reviewOkay ? 'ready' : 'review required'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.edit_outlined),
        onTap: onEdit,
      ),
    );
  }

  String _reproductiveSummary(StationPlantRecord record) {
    final observation = record.reproductive;
    if (observation == null) return 'VT–R2 observation required';
    final signs = <String>[
      if (observation.larvaPresent) 'larva',
      if (observation.freshFeedingPresent) 'fresh feeding',
      if (observation.frassPresent) 'frass',
      if (observation.earHuskPenetrationVisible) 'penetration',
    ];
    return '${observation.classification ?? 'unclassified'} · ${signs.isEmpty ? 'no listed signs' : signs.join(', ')}';
  }

  String _earSummary(StationPlantRecord record) {
    final ear = record.ear;
    if (ear == null) return 'External-ear observation required';
    return '${ear.externalClassification ?? 'unclassified'} · ${ear.opened ? 'opened-ear complete' : 'external only'}';
  }
}

class _OpeningSelectionCard extends StatelessWidget {
  const _OpeningSelectionCard({
    required this.selection,
    required this.plant,
    required this.isSaving,
    required this.onOpen,
    required this.onFail,
  });
  final EarOpeningSelectionRecord selection;
  final StationPlantRecord? plant;
  final bool isSaving;
  final VoidCallback onOpen;
  final VoidCallback onFail;

  @override
  Widget build(BuildContext context) {
    final status = selection.selectionStatus;
    final canAct = status == 'planned' || status == 'replacement_selected';
    final earAvailable = plant?.ear?.externallyAssessable == true;
    return Card(
      color: status == 'opened' ? const Color(0xFFEAF6EE) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              'Plant ${selection.plantPosition} · $status',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (selection.replacesPlantPosition != null)
              AppText(
                'Replacement for Plant ${selection.replacesPlantPosition}',
              ),
            if (selection.failureReason != null)
              AppText('Failure: ${selection.failureReason}'),
            if (canAct) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: !earAvailable || isSaving ? null : onOpen,
                      child: const AppText('Open selected ear'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving ? null : onFail,
                      child: const AppText('Cannot open'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
