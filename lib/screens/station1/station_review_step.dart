import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../services/evidence_capture_coordinator.dart';
import '../../services/station_evidence_policy.dart';
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
  });

  final Station1Snapshot snapshot;
  final int blockNumber;
  final int stationNumber;
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
    final capturedPositions = {
      for (final bundle in evidenceBundles)
        if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition != null &&
            bundle.session.completedAt != null &&
            bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview))
          bundle.session.plantPosition!,
    };
    final captureComplete = List<int>.generate(
      10,
      (index) => index + 1,
    ).every(capturedPositions.contains);
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
    final nextPosition = attentionPositions.firstOrNull;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('station_review_step'),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            children: [
              StationReviewHeader(
                stationNumber: stationNumber,
                confirmedCount: snapshot.plants.length,
                itemLabel: 'plants',
                needsAttentionCount: attentionPositions.length,
              ),
              const SizedBox(height: 14),
              StationReviewStatusStrip(
                states: states,
                itemLabel: 'Plant',
                onSelected: onEdit,
              ),
              const SizedBox(height: 14),
              if (onCompleteTestStation != null)
                ExpansionTile(
                  key: const Key('test_data_station_bypass_card'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                  title: const Text('TEST DATA shortcut'),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: FilledButton.icon(
                        key: const Key(
                          'complete_test_station_from_review_button',
                        ),
                        onPressed: isSaving ? null : onCompleteTestStation,
                        icon: const Icon(Icons.science_outlined),
                        label: Text('Complete test Station $stationNumber'),
                      ),
                    ),
                  ],
                ),
              const _AnalysisUnavailableBanner(),
              const SizedBox(height: 14),
              if (attentionPositions.isNotEmpty) ...[
                const _ReviewSectionLabel('NEEDS ATTENTION'),
                for (final position in attentionPositions)
                  if (savedByPosition[position] == null)
                    _PendingPlantReviewCard(
                      position: position,
                      evidence: _bundleForPlant(evidenceBundles, position),
                      evidenceReview: evidenceReviews[position],
                      resolveEvidenceFile: resolveEvidenceFile,
                      evidenceThumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                      onEdit: onEdit,
                      onMarkInsufficient: onMarkInsufficient,
                    )
                  else
                    _PlantReviewCard(
                      item: savedByPosition[position]!,
                      evidencePolicy: evidencePolicy,
                      evidence: _bundleForPlant(evidenceBundles, position),
                      evidenceReview: evidenceReviews[position],
                      resolveEvidenceFile: resolveEvidenceFile,
                      evidenceThumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                      onEdit: onEdit,
                      onMarkInsufficient: onMarkInsufficient,
                    ),
              ],
              if (readyPositions.isNotEmpty)
                ExpansionTile(
                  key: const Key('confirmed_plants_section'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                  title: Text('Confirmed plants · ${readyPositions.length}'),
                  subtitle: const Text('Open to review or correct'),
                  children: [
                    for (final position in readyPositions)
                      _PlantReviewCard(
                        item: savedByPosition[position]!,
                        evidencePolicy: evidencePolicy,
                        evidence: _bundleForPlant(evidenceBundles, position),
                        evidenceReview: evidenceReviews[position],
                        resolveEvidenceFile: resolveEvidenceFile,
                        evidenceThumbnailBuilder: evidenceThumbnailBuilder,
                        onOpenEvidence: onOpenEvidence,
                        onEdit: onEdit,
                        onMarkInsufficient: onMarkInsufficient,
                      ),
                  ],
                ),
              ExpansionTile(
                key: const Key('station_review_details'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                title: const Text('Station details'),
                subtitle: const Text('Location, context photo and workload'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      station.latitude == null
                          ? 'GPS unavailable: ${_reasonLabel(station.notLocatedReason)}'
                          : 'GPS saved · accuracy ${station.gpsAccuracyM!.toStringAsFixed(1)} m',
                    ),
                  ),
                  if (resolveEvidenceFile != null) ...[
                    const SizedBox(height: 12),
                    _ReviewEvidence(
                      label: 'Station context',
                      bundle: _bundleForScope(
                        evidenceBundles,
                        DatabaseCodes.evidenceScopeStationContext,
                      ),
                      resolveEvidenceFile: resolveEvidenceFile!,
                      thumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _PilotWorkloadCard(metrics: pilotWorkloadMetrics),
                ],
              ),
            ],
          ),
        ),
        if (onCompleteWithoutManualConfirmation != null && !stationReady)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('complete_without_manual_confirmation_button'),
                onPressed: !captureComplete || isSaving
                    ? null
                    : () => _confirmUnreviewedCompletion(context),
                child: const Text('Complete without manual confirmation'),
              ),
            ),
          ),
        StationReviewBottomBar(
          message: stationReady
              ? 'All 10 plants are confirmed.'
              : '${attentionPositions.length} plants still need attention.',
          actionLabel: stationReady
              ? 'Complete Station $stationNumber'
              : 'Review Plant $nextPosition',
          actionKey: stationReady
              ? const Key('confirm_station_review_button')
              : const Key('review_next_plant_button'),
          isSaving: isSaving,
          onPressed: stationReady ? onConfirm : () => onEdit(nextPosition!),
        ),
      ],
    );
  }

  Future<void> _confirmUnreviewedCompletion(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave observations unconfirmed?'),
        content: const Text(
          'Photos will be saved, but WormWise has no image model yet. No findings will be created for these plants.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_unreviewed_station_button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete station'),
          ),
        ],
      ),
    );
    if (accepted == true) onCompleteWithoutManualConfirmation?.call();
  }
}

class _AnalysisUnavailableBanner extends StatelessWidget {
  const _AnalysisUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('analysis_unavailable_banner'),
      elevation: 0,
      color: const Color(0xFFFFF5D9),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text(
          'Image analysis is not available yet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Manual confirmation is optional. Unreviewed photos do not become findings.',
        ),
        trailing: IconButton(
          key: const Key('analysis_unavailable_help'),
          tooltip: 'About unconfirmed photos',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About unconfirmed photos',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'WormWise does not yet have a validated image model. You may complete the station without manual confirmation, but those photos remain unreviewed and create no plant findings or FAW diagnosis.',
                      style: TextStyle(height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.help_outline),
        ),
      ),
    );
  }
}

class _ReviewSectionLabel extends StatelessWidget {
  const _ReviewSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF176B3A),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  );
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
                  child: Text(
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
              const Text(
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
                label: const Text('Mark evidence insufficient'),
              ),
              const SizedBox(height: 8),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                key: Key('manual_confirm_plant_${position}_button'),
                onPressed: () => onEdit(position),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text('Review Plant $position'),
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
                      Text(
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
                  if (_evidenceStateLabel(
                        evidence: evidence,
                        review: evidenceReview,
                        assessable: plant.assessable,
                      ) ==
                      'Not reviewed')
                    const Text(
                      'Needs confirmation',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
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
                      const Text(
                        'No feeding signs observed',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      )
                  else
                    Text(
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
                    tooltip: 'Mark evidence insufficient',
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
            const Text(
              'Station 1 pilot workload',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${metrics.acceptedImageCount} accepted images · '
              '${metrics.retakeCount} retakes · '
              '${metrics.manualFallbackCount} manual fallbacks',
              style: const TextStyle(height: 1.35),
            ),
            Text(
              '${metrics.manualFormUseCount} of 10 plant manual forms saved',
              style: const TextStyle(height: 1.35),
            ),
            Text(
              '${metrics.guidedTapCount} guided capture taps recorded',
              style: const TextStyle(height: 1.35),
            ),
            Text(
              'Private evidence storage: ${storageMib.toStringAsFixed(2)} MiB',
              style: const TextStyle(height: 1.35),
            ),
            const SizedBox(height: 6),
            const Text(
              'Active screen time per plant:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (metrics.activeTimeByPlant.isEmpty)
              const Text('Recorded when each plant is saved.')
            else
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final entry
                      in metrics.activeTimeByPlant.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key)))
                    Text('P${entry.key}: ${_formatDuration(entry.value)}'),
                ],
              ),
            const SizedBox(height: 6),
            const Text(
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
