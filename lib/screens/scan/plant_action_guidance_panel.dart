import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/repositories/plant_action_repository.dart';
import '../../models/da_monitoring.dart';
import '../../models/guided_plant_details.dart';
import '../../models/plant_action_guidance.dart';
import '../../theme/app_colors.dart';
import 'scouting_ui.dart';

/// Shared comparison and action content for notices and plant details.
class PlantActionGuidancePanel extends StatefulWidget {
  const PlantActionGuidancePanel({
    super.key,
    required this.repository,
    required this.assessmentId,
    required this.blockRunId,
    required this.number,
    required this.loadDetails,
    required this.resolveFile,
    this.revision = '',
    this.atPlant = false,
    this.initiallyExpanded,
    this.guideIds,
    this.showHeading = true,
  });
  final PlantActionRepository repository;
  final String assessmentId, blockRunId, revision;
  final int number;
  final Future<GuidedPlantDetails> Function() loadDetails;
  final Future<File> Function(String uri) resolveFile;
  final bool atPlant;
  final bool? initiallyExpanded;
  final Set<String>? guideIds;
  final bool showHeading;
  @override
  State<PlantActionGuidancePanel> createState() =>
      _PlantActionGuidancePanelState();
}

class _PlantActionGuidancePanelState extends State<PlantActionGuidancePanel> {
  GuidedPlantDetails? _details;
  List<PlantActionGuide> _guides = [];
  Map<String, PlantActionRecord> _records = {};
  Set<String> _expanded = {};
  bool _saving = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlantActionGuidancePanel old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision ||
        old.number != widget.number ||
        old.blockRunId != widget.blockRunId ||
        old.assessmentId != widget.assessmentId ||
        old.repository.ownerId != widget.repository.ownerId) {
      _details = null;
      _guides = [];
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final assessment = widget.assessmentId;
    final block = widget.blockRunId;
    final number = widget.number;
    final repository = widget.repository;
    try {
      final details = await widget.loadDetails();
      if (details.snapshot.prepared.run.id != block ||
          details.snapshot.stationNumber != number ||
          details.photos.isEmpty) {
        return;
      }
      final finding = DaPlantFinding.fromModel(details.diagnosis)
          .withCorrections(
            details.monitoring?.plant(block, number),
            daPhotoSignature(details.photos),
          );
      final guides = PlantActionGuide.resolve(
        details.diagnosis,
        finding: finding,
      ).where((g) => widget.guideIds?.contains(g.id) ?? true).toList();
      final learned = await repository.learnedGuides();
      final records = await repository.load(assessment, block, number);
      if (!mounted || generation != _generation) return;
      final first = await repository.firstOffers(
        assessment,
        block,
        number,
        guides,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _details = details;
        _guides = guides;
        _records = records;
        _expanded = {
          for (final g in guides)
            if ((widget.initiallyExpanded ??
                    (first.contains(g.id) &&
                        !learned.contains(g.preferenceId))) &&
                !records.containsKey(g.id))
              g.id,
        };
      });
    } catch (_) {
      // A failed optional guide load never blocks capture or Save and next plant.
      if (!mounted || generation != _generation) return;
      setState(() {
        _details = null;
        _guides = [];
      });
    }
  }

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
    }
  }

  Future<void> _toggle(PlantActionGuide guide) async {
    if (_saving) return;
    if (!_expanded.contains(guide.id)) {
      setState(() => _expanded.add(guide.id));
      return;
    }
    final generation = _generation;
    setState(() => _saving = true);
    try {
      await widget.repository.rememberCollapsed(guide);
      if (mounted && generation == _generation) {
        setState(() => _expanded.remove(guide.id));
      }
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _imported =>
      !widget.atPlant ||
      _details!.photos.any((p) => p.captureSource != 'camera');
  Future<void> _record(PlantActionGuide guide, {bool undo = false}) async {
    if (_saving || _details == null) return;
    final generation = _generation;
    final assessment = widget.assessmentId;
    final block = widget.blockRunId;
    final number = widget.number;
    final repository = widget.repository;
    setState(() => _saving = true);
    try {
      await repository.record(
        assessment: assessment,
        block: block,
        number: number,
        guide: guide,
        signature: daPhotoSignature(_details!.photos),
        imported: _imported,
        undo: undo,
      );
      if (!undo) await repository.rememberCollapsed(guide);
      final records = await repository.load(assessment, block, number);
      if (mounted && generation == _generation) {
        setState(() {
          _records = records;
          if (!undo) _expanded.remove(guide.id);
        });
      }
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_details == null || _guides.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeading) ...[
            Row(
              children: [
                const Icon(
                  Icons.pan_tool_alt_outlined,
                  color: AppColors.primary,
                  size: 19,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Guided actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _imported ? 'When you inspect this plant' : 'At this plant',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _guides.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            ScoutingCard(child: _guide(_guides[i])),
          ],
        ],
      ),
    );
  }

  Widget _guide(PlantActionGuide guide) {
    final expanded = _expanded.contains(guide.id);
    final record = _records[guide.id];
    final previous =
        record != null &&
        record.signature != daPhotoSignature(_details!.photos);
    return Column(
      key: ValueKey('plant_action_${guide.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                guide.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              key: ValueKey('plant_action_toggle_${guide.id}'),
              onPressed: _saving ? null : () => _toggle(guide),
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(expanded ? 'Show less' : 'How'),
            ),
          ],
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          _comparison(guide),
          const SizedBox(height: 8),
          Text(
            guide.compareTip,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < guide.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guide.steps[i],
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: () => _sources(guide),
            child: const Text(
              'Photo credit and guidance',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ] else if (record == null)
          Text(
            guide.reminder,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        if (record == null) ...[
          const SizedBox(height: 10),
          const Text(
            'Record action (optional)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ValueKey('plant_action_record_${guide.id}'),
              onPressed: _saving ? null : () => _record(guide),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(guide.recordLabel),
            ),
          ),
        ] else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                previous
                    ? '${guide.recordedLabel} · earlier photos'
                    : guide.recordedLabel,
                key: ValueKey('plant_action_saved_${guide.id}'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                key: ValueKey('plant_action_undo_${guide.id}'),
                onPressed: _saving ? null : () => _record(guide, undo: true),
                child: const Text('Undo'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _comparison(PlantActionGuide guide) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _photo(
          'Your photo',
          _farmerPhoto(guide),
          () => _openPhoto(guide, false),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _photo(
          guide.reference.caption,
          Image.asset(
            guide.reference.asset,
            fit: BoxFit.contain,
            semanticLabel: guide.reference.caption,
          ),
          () => _openPhoto(guide, true),
        ),
      ),
    ],
  );
  Widget _photo(String title, Widget image, VoidCallback open) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: '$title. Tap to zoom.',
        button: true,
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 112,
              width: double.infinity,
              color: const Color(0xFFE3EBDD),
              child: image,
            ),
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ],
  );
  Future<File> _comparisonFile(PlantActionGuide guide) async {
    final classId = switch (guide.kind) {
      PlantActionKind.larva => 2,
      PlantActionKind.eggs => 3,
      PlantActionKind.inspectWhorl => 1,
      PlantActionKind.inspectDamage => 0,
    };
    final source = _details!.diagnosis?.detectionBoxes
        .where((box) => box.classId == classId)
        .firstOrNull
        ?.sourcePath;
    final photos = _details!.photos;
    final files = [
      for (final photo in photos) await widget.resolveFile(photo.localUri),
    ];
    if (source != null) {
      final basename = source.replaceAll('\\', '/').split('/').last;
      for (final file in files) {
        if (file.path == source ||
            file.path.replaceAll('\\', '/').split('/').last == basename) {
          return file;
        }
      }
    }
    return files.first;
  }

  Widget _farmerPhoto(PlantActionGuide guide) => FutureBuilder<File>(
    future: _comparisonFile(guide),
    builder: (_, state) => state.hasData
        ? Image.file(
            state.data!,
            fit: BoxFit.contain,
            semanticLabel: 'Your plant photo',
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.image_not_supported_outlined)),
          )
        : const Center(child: Icon(Icons.photo_outlined)),
  );
  Future<void> _openPhoto(
    PlantActionGuide guide,
    bool reference,
  ) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF162119),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      reference ? guide.reference.caption : 'Your photo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close photo',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: reference
                      ? Image.asset(guide.reference.asset, fit: BoxFit.contain)
                      : _farmerPhoto(guide),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                reference
                    ? '${guide.compareTip}\n\n${guide.reference.credit} · ${guide.reference.license}'
                    : 'Pinch to zoom.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _sources(PlantActionGuide guide) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Photo and guidance'),
      content: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(guide.reference.credit),
              const SizedBox(height: 8),
              Text(guide.reference.license),
              SelectableText(guide.reference.licenseUrl),
              const SizedBox(height: 8),
              SelectableText(guide.reference.sourceUrl),
              const SizedBox(height: 12),
              const Text(
                'FAO supports manual destruction of identified egg masses and young larvae. The tool-based handling steps are a practical app adaptation, not a quoted DA procedure.',
              ),
              SelectableText(PlantActionGuide.managementSource),
              const SizedBox(height: 8),
              const Text(
                'Reference photos are resized publisher images. Keep out of recently sprayed fields until the label allows re-entry. Ordinary gloves do not replace label requirements.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
