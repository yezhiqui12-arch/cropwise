import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../services/evidence_capture_coordinator.dart';
import '../../services/station_evidence_policy.dart';

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
    return ListView(
      key: const Key('station_review_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        Text(
          'BLOCK $blockNumber · STATION $stationNumber · ${snapshot.plants.length} OF 10 MANUALLY CONFIRMED',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Station Evidence Review',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          station.latitude == null
              ? 'Station GPS unavailable: ${_reasonLabel(station.notLocatedReason)}'
              : 'Station GPS saved · reported accuracy ${station.gpsAccuracyM!.toStringAsFixed(1)} m',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        const _AnalysisUnavailableBanner(),
        const SizedBox(height: 12),
        if (resolveEvidenceFile != null)
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
        if (resolveEvidenceFile != null) const SizedBox(height: 12),
        if (pendingPositions.isNotEmpty) ...[
          const _ReviewSectionLabel('NEEDS MANUAL CONFIRMATION'),
          for (final position in pendingPositions)
            _PendingPlantReviewCard(
              position: position,
              evidence: _bundleForPlant(evidenceBundles, position),
              evidenceReview: evidenceReviews[position],
              resolveEvidenceFile: resolveEvidenceFile,
              evidenceThumbnailBuilder: evidenceThumbnailBuilder,
              onOpenEvidence: onOpenEvidence,
              onEdit: onEdit,
              onMarkInsufficient: onMarkInsufficient,
            ),
        ],
        if (confirmedPositions.isNotEmpty) ...[
          const _ReviewSectionLabel('EVALUATOR CONFIRMED'),
          for (final position in confirmedPositions)
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
        const SizedBox(height: 8),
        if (evidencePolicy ==
            StationEvidencePolicy.cameraFirstOverviewConditional) ...[
          Card(
            key: const Key('camera_first_policy_banner'),
            elevation: 0,
            color: const Color(0xFFEAF6EE),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Camera-first policy: ${evidencePolicy.requirementsVersion}. Every assessable plant needs an overview; close-ups are conditional. No photograph creates an automated finding.',
                style: const TextStyle(height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _PilotWorkloadCard(metrics: pilotWorkloadMetrics),
        const SizedBox(height: 18),
        Card(
          elevation: 0,
          color: Color(0xFFEAF6EE),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              stationReady
                  ? 'All ten positions have evaluator-confirmed observations and current sufficient evidence reviews. Editing evidence or observations later requires a new Station $stationNumber review.'
                  : '${pendingPositions.length} structured confirmations and ${unresolvedEvidence.length} evidence reviews remain. Insufficient or missing evidence must be resolved separately.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (onCompleteTestStation != null) ...[
          Card(
            key: const Key('test_data_station_bypass_card'),
            elevation: 0,
            color: const Color(0xFFFFF3CD),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'TEST DATA shortcut',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Generate clearly synthetic confirmations for unfinished plants and complete this test station. Real farmer records are not changed.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: FilledButton.icon(
                      key: const Key(
                        'complete_test_station_from_review_button',
                      ),
                      onPressed: isSaving ? null : onCompleteTestStation,
                      icon: const Icon(Icons.science_outlined),
                      label: Text(
                        'Complete test Station $stationNumber (synthetic)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('confirm_station_review_button'),
            onPressed: isSaving || !stationReady ? null : onConfirm,
            icon: const Icon(Icons.check_circle_outline),
            label: isSaving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Complete Station $stationNumber review'),
          ),
        ),
      ],
    );
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
          'Automated analysis unavailable',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Confirm every plant manually. No image result has been generated.',
        ),
        trailing: IconButton(
          key: const Key('analysis_unavailable_help'),
          tooltip: 'Why manual confirmation is required',
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
                      'Why manual confirmation is required',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'WormWise does not yet have a validated image model. Photos support inspection and later review, but they do not establish plant observations or a FAW diagnosis. Complete the approved structured observations for each plant.',
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Plant $position',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
            if (resolveEvidenceFile != null) ...[
              const SizedBox(height: 10),
              _ReviewEvidence(
                label: 'Plant $position evidence',
                bundle: evidence,
                showPlantViews: true,
                resolveEvidenceFile: resolveEvidenceFile!,
                thumbnailBuilder: evidenceThumbnailBuilder,
                onOpenEvidence: onOpenEvidence,
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Structured observations incomplete · Automated analysis unavailable',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 10),
            if (onMarkInsufficient != null)
              OutlinedButton.icon(
                key: Key('mark_plant_${position}_insufficient'),
                onPressed: () => onMarkInsufficient!(position),
                icon: const Icon(Icons.report_outlined),
                label: const Text('Mark evidence insufficient'),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: FilledButton.icon(
                key: Key('manual_confirm_plant_${position}_button'),
                onPressed: () => onEdit(position),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review or correct plant'),
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
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 180),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5D9),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
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
    final raw = <String>[
      if (item.vegetative.smallFreshWindowpanes) 'windowpanes',
      if (item.vegetative.scraping) 'scraping',
      if (item.vegetative.cuttingOrTearing) 'cutting/tearing',
      if (item.vegetative.freshFrass) 'frass',
      if (item.vegetative.whorlFeedingSign) 'whorl signs',
      if (item.vegetative.larvaVisible) 'visible larva',
      if (item.vegetative.eggMassVisible == true) 'egg mass',
      if (plant.oldDamagePresent) 'old damage',
      if (plant.possibleNonFawEvidence == true) 'possible non-FAW',
      if (plant.uncertainEvidence == true) 'uncertain evidence',
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plant ${plant.sequenceNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
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
                  if (resolveEvidenceFile != null) ...[
                    const SizedBox(height: 8),
                    _ReviewEvidence(
                      label: 'Plant ${plant.sequenceNumber} evidence',
                      bundle: evidence,
                      showPlantViews: true,
                      emptyEvidenceLabel:
                          evidencePolicy
                              .requiredViewsForObservation(
                                plant: plant,
                                vegetative: item.vegetative,
                              )
                              .isEmpty
                          ? 'No plant image required by ${evidencePolicy.requirementsVersion}'
                          : null,
                      resolveEvidenceFile: resolveEvidenceFile!,
                      thumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(_statusLabel(plant.plantStatus)),
                  const SizedBox(height: 3),
                  const Text(
                    'Structured observations complete',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plant.assessable
                        ? (raw.isEmpty
                              ? 'No listed raw signs selected'
                              : raw.join(' · '))
                        : 'Not assessable: ${plant.notAssessableReason}',
                    style: const TextStyle(fontSize: 13, height: 1.35),
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

class _ReviewEvidence extends StatelessWidget {
  const _ReviewEvidence({
    required this.label,
    required this.bundle,
    required this.resolveEvidenceFile,
    this.showPlantViews = false,
    this.emptyEvidenceLabel,
    this.thumbnailBuilder,
    this.onOpenEvidence,
  });

  final String label;
  final EvidenceCaptureBundle? bundle;
  final Future<File> Function(String localUri) resolveEvidenceFile;
  final bool showPlantViews;
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
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
