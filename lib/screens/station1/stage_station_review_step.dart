import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';

class StageStationReviewStep extends StatelessWidget {
  const StageStationReviewStep({
    super.key,
    required this.growthStage,
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
    return Column(
      children: [
        Material(
          color: const Color(0xFFF3F8F4),
          child: ListTile(
            title: Text(
              '${_isLate ? 'R3–R6' : 'VT–R2'} station review',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${snapshot.plants.length} of 10 plant positions confirmed',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('stage_station_review'),
            padding: const EdgeInsets.all(14),
            children: [
              for (var position = 1; position <= 10; position++) ...[
                _StagePlantReviewCard(
                  position: position,
                  growthStage: growthStage,
                  item: plants[position],
                  evidenceReview: evidenceReviews[position],
                  onEdit: () => onEditPlant(position),
                ),
                const SizedBox(height: 8),
              ],
              if (_isLate && openingPlan.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Preselected opened-ear subsample',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Selections were stored before external inspection. Failed selections retain their reason and activate the next predetermined replacement.',
                ),
                const SizedBox(height: 10),
                for (final selection in openingPlan)
                  if (selection.initiallySelected ||
                      selection.selectionStatus == 'replacement_selected' ||
                      selection.selectionStatus == 'opened' ||
                      selection.selectionStatus == 'failed')
                    _OpeningSelectionCard(
                      selection: selection,
                      plant: plants[selection.plantPosition],
                      isSaving: isSaving,
                      onOpen: () => onBeginOpenedEar(selection),
                      onFail: () => _showFailureDialog(context, selection),
                    ),
              ],
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!completePlants)
                  const Text('Complete all ten fixed plant positions.'),
                if (completePlants && !evidenceComplete)
                  const Text(
                    'Every assessable plant needs a current, sufficient evidence review.',
                  ),
                if (_isLate && !openedEarSubsampleComplete)
                  const Text(
                    'Complete or document failure for every active opened-ear selection.',
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('confirm_stage_station_review'),
                  onPressed: !canConfirm || isSaving ? null : onConfirm,
                  child: Text(
                    isSaving ? 'Saving…' : 'Confirm station and continue',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFailureDialog(
    BuildContext context,
    EarOpeningSelectionRecord selection,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Plant ${selection.plantPosition} cannot be opened'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Failure reason',
            hintText:
                'No ear, unsafe, already harvested, damaged during access…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Record and use replacement'),
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
        leading: CircleAvatar(child: Text('$position')),
        title: Text('Plant $position'),
        subtitle: Text(
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
            Text(
              'Plant ${selection.plantPosition} · $status',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (selection.replacesPlantPosition != null)
              Text('Replacement for Plant ${selection.replacesPlantPosition}'),
            if (selection.failureReason != null)
              Text('Failure: ${selection.failureReason}'),
            if (canAct) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: !earAvailable || isSaving ? null : onOpen,
                      child: const Text('Open selected ear'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving ? null : onFail,
                      child: const Text('Cannot open'),
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
