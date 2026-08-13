import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../services/evidence_capture_coordinator.dart';

class StationReviewStep extends StatelessWidget {
  const StationReviewStep({
    super.key,
    required this.snapshot,
    required this.isSaving,
    required this.onEdit,
    required this.onConfirm,
    this.evidenceBundles = const [],
    this.resolveEvidenceFile,
    this.evidenceThumbnailBuilder,
    this.onOpenEvidence,
    this.pilotWorkloadMetrics = PilotWorkloadMetrics.empty,
  });

  final Station1Snapshot snapshot;
  final bool isSaving;
  final ValueChanged<int> onEdit;
  final VoidCallback onConfirm;
  final List<EvidenceCaptureBundle> evidenceBundles;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? evidenceThumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;
  final PilotWorkloadMetrics pilotWorkloadMetrics;

  @override
  Widget build(BuildContext context) {
    final station = snapshot.station!;
    return ListView(
      key: const Key('station_review_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const Text(
          'BLOCK 1 · STATION 1 · 10 OF 10 PLANTS SAVED',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Review Station 1',
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
        for (final item in snapshot.plants)
          _PlantReviewCard(
            item: item,
            evidence: _bundleForPlant(
              evidenceBundles,
              item.plant.sequenceNumber,
            ),
            resolveEvidenceFile: resolveEvidenceFile,
            evidenceThumbnailBuilder: evidenceThumbnailBuilder,
            onOpenEvidence: onOpenEvidence,
            onEdit: onEdit,
          ),
        const SizedBox(height: 8),
        _PilotWorkloadCard(metrics: pilotWorkloadMetrics),
        const SizedBox(height: 18),
        const Card(
          elevation: 0,
          color: Color(0xFFEAF6EE),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Confirm only after checking all ten saved positions. Editing any plant later will require a new review confirmation.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('confirm_station_review_button'),
            onPressed: isSaving ? null : onConfirm,
            icon: const Icon(Icons.check_circle_outline),
            label: isSaving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm Station 1 review'),
          ),
        ),
      ],
    );
  }
}

class _PlantReviewCard extends StatelessWidget {
  const _PlantReviewCard({
    required this.item,
    required this.onEdit,
    this.evidence,
    this.resolveEvidenceFile,
    this.evidenceThumbnailBuilder,
    this.onOpenEvidence,
  });

  final Station1PlantRecord item;
  final ValueChanged<int> onEdit;
  final EvidenceCaptureBundle? evidence;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Widget Function(EvidenceMediaRecord media)? evidenceThumbnailBuilder;
  final Future<void> Function(EvidenceMediaRecord media, String scopeLabel)?
  onOpenEvidence;

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
                  if (resolveEvidenceFile != null) ...[
                    const SizedBox(height: 8),
                    _ReviewEvidence(
                      label: 'Plant ${plant.sequenceNumber} evidence',
                      bundle: evidence,
                      resolveEvidenceFile: resolveEvidenceFile!,
                      thumbnailBuilder: evidenceThumbnailBuilder,
                      onOpenEvidence: onOpenEvidence,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(_statusLabel(plant.plantStatus)),
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
            IconButton(
              key: Key('edit_plant_${plant.sequenceNumber}_button'),
              tooltip: 'Edit Plant ${plant.sequenceNumber}',
              onPressed: () => onEdit(plant.sequenceNumber),
              icon: const Icon(Icons.edit_outlined),
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
    this.thumbnailBuilder,
    this.onOpenEvidence,
  });

  final String label;
  final EvidenceCaptureBundle? bundle;
  final Future<File> Function(String localUri) resolveEvidenceFile;
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
        if (ready.isEmpty)
          Text(
            waived.isNotEmpty
                ? 'Manual fallback documented'
                : 'No accepted image',
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
          '${widget.scopeLabel}, ${_viewLabel(widget.media.viewType)}. Open original evidence photo.',
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

String _viewLabel(String? viewType) => switch (viewType) {
  DatabaseCodes.evidenceViewStationContext => 'Context',
  DatabaseCodes.evidenceViewWhorlOverview => 'Whorl overview',
  DatabaseCodes.evidenceViewCloseUp => 'Close-up',
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
