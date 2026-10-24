import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../services/evidence_storage_service.dart';

/// Applies the same saved-evidence association rules everywhere plant media is
/// shown. A direct plant id is authoritative. Legacy position-only links are
/// accepted only when the capture session was explicitly plant-scoped.
bool assessmentEvidenceMatchesPlant({
  required AssessmentEvidenceEntry entry,
  required StationSnapshot station,
  required String plantObservationId,
  required int plantPosition,
}) {
  if (entry.plantObservationId == plantObservationId) return true;
  return entry.plantObservationId == null &&
      entry.scopeType == DatabaseCodes.evidenceScopePlant &&
      entry.stationId == station.station?.id &&
      entry.plantPosition == plantPosition;
}

List<AssessmentEvidenceEntry> assessmentEvidenceForPlant({
  required AssessmentHistoryDetail detail,
  required StationSnapshot station,
  required String plantObservationId,
  required int plantPosition,
  bool availableOnly = false,
}) => detail.evidence
    .where(
      (entry) =>
          (!availableOnly ||
              entry.media.storageState == DatabaseCodes.evidenceStorageReady) &&
          assessmentEvidenceMatchesPlant(
            entry: entry,
            station: station,
            plantObservationId: plantObservationId,
            plantPosition: plantPosition,
          ),
    )
    .toList(growable: false);

/// Renders only a saved local evidence file. Missing or unresolved files use a
/// neutral placeholder so a decorative crop image is never presented as proof.
class SavedEvidenceThumbnail extends StatefulWidget {
  const SavedEvidenceThumbnail({
    super.key,
    required this.entry,
    required this.storage,
    this.fit = BoxFit.cover,
    this.cacheWidth = 720,
  });

  final AssessmentEvidenceEntry entry;
  final EvidenceStorageService storage;
  final BoxFit fit;
  final int cacheWidth;

  @override
  State<SavedEvidenceThumbnail> createState() => _SavedEvidenceThumbnailState();
}

class _SavedEvidenceThumbnailState extends State<SavedEvidenceThumbnail> {
  late Future<File?> _file = _resolve();

  Future<File?> _resolve() async {
    final candidates = <String>{
      ?widget.entry.media.thumbnailLocalUri,
      widget.entry.media.localUri,
    };
    for (final uri in candidates) {
      try {
        final file = await widget.storage.resolve(uri);
        if (await file.exists()) return file;
      } on FileSystemException {
        // Try the full-size saved image when its thumbnail is unavailable.
      } on ArgumentError {
        // Invalid legacy paths remain read-only and render as unavailable.
      }
    }
    return null;
  }

  @override
  void didUpdateWidget(SavedEvidenceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storage != widget.storage ||
        oldWidget.entry.media.id != widget.entry.media.id ||
        oldWidget.entry.media.localUri != widget.entry.media.localUri ||
        oldWidget.entry.media.thumbnailLocalUri !=
            widget.entry.media.thumbnailLocalUri) {
      _file = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (snapshot.hasError || file == null) {
        return const _EvidencePlaceholder();
      }
      return Image.file(
        file,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        errorBuilder: (_, _, _) => const _EvidencePlaceholder(),
      );
    },
  );
}

class _EvidencePlaceholder extends StatelessWidget {
  const _EvidencePlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFE8EEE8),
    child: Center(
      child: Icon(
        Icons.photo_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
