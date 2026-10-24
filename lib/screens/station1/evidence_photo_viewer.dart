import 'dart:io';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import 'model_detection_image.dart';

enum EvidencePhotoAction {
  usePhoto,
  retake,
  addCloseUp,
  addDiagnosticDetail,
  remove,
}

class EvidencePhotoViewer extends StatefulWidget {
  const EvidencePhotoViewer({
    super.key,
    required this.media,
    required this.scopeLabel,
    required this.resolveFile,
    this.allowActions = false,
    this.allowAddCloseUp = false,
    this.allowAddDiagnosticDetail = false,
    this.cvDiagnosis,
    this.transformationController,
    this.fieldName,
    this.stationLabel,
    this.photoIndex,
    this.photoCount,
    this.observationSummary,
    this.scoutingStyle = false,
  });

  final EvidenceMediaRecord media;
  final String scopeLabel;
  final Future<File> Function(String localUri) resolveFile;
  final bool allowActions;
  final bool allowAddCloseUp;
  final bool allowAddDiagnosticDetail;
  final PlantDiagnosisResult? cvDiagnosis;
  final TransformationController? transformationController;
  final String? fieldName;
  final String? stationLabel;
  final int? photoIndex;
  final int? photoCount;
  final String? observationSummary;
  final bool scoutingStyle;

  @override
  State<EvidencePhotoViewer> createState() => _EvidencePhotoViewerState();
}

class _EvidencePhotoViewerState extends State<EvidencePhotoViewer> {
  late Future<File> _file;
  late final TransformationController _transformationController;
  late final bool _ownsTransformationController;
  bool _showDetections = true;

  @override
  void initState() {
    super.initState();
    _file = widget.resolveFile(widget.media.localUri);
    _ownsTransformationController = widget.transformationController == null;
    _transformationController =
        widget.transformationController ?? TransformationController();
  }

  @override
  void dispose() {
    if (_ownsTransformationController) _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scoutingStyle && !widget.allowActions)
      return _buildScoutingViewer(context);
    if (!widget.allowActions) return _buildReadOnlyViewer(context);

    final staged =
        widget.media.storageState == DatabaseCodes.evidenceStorageStaged;
    return Scaffold(
      appBar: AppBar(title: const AppText('Inspect canonical evidence')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.scopeLabel,
                    key: const Key('evidence_viewer_scope_label'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    evidenceViewLabel(widget.media.viewType),
                    key: const Key('evidence_viewer_view_label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  const AppText(
                    'Pinch to zoom and drag to inspect the stored evidence. The evaluator confirms framing and observations.',
                    style: TextStyle(height: 1.3),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<File>(
                future: _file,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const ColoredBox(
                      color: Colors.black,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData || !snapshot.data!.existsSync()) {
                    return const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: AppText(
                          'Canonical evidence is unavailable.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  }
                  final file = snapshot.data!;
                  final boxes = ModelDetectionImage.boxesForFile(
                    widget.cvDiagnosis,
                    file,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (boxes.isNotEmpty)
                        Material(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SegmentedButton<bool>(
                                    key: const Key('evidence_view_mode'),
                                    segments: const [
                                      ButtonSegment<bool>(
                                        value: false,
                                        icon: Icon(Icons.photo_outlined),
                                        label: AppText('Original'),
                                      ),
                                      ButtonSegment<bool>(
                                        value: true,
                                        icon: Icon(Icons.auto_awesome_outlined),
                                        label: AppText('AI detections'),
                                      ),
                                    ],
                                    selected: {_showDetections},
                                    showSelectedIcon: false,
                                    onSelectionChanged: (selection) {
                                      _transformationController.value =
                                          Matrix4.identity();
                                      setState(
                                        () => _showDetections = selection.first,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                AppText(
                                  '${boxes.length} ${boxes.length == 1 ? 'box' : 'boxes'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: ColoredBox(
                          color: Colors.black,
                          child: InteractiveViewer(
                            key: const Key('evidence_interactive_viewer'),
                            transformationController: _transformationController,
                            minScale: 1,
                            maxScale: 5,
                            boundaryMargin: EdgeInsets.zero,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.expand(
                              child: _showDetections && boxes.isNotEmpty
                                  ? ModelDetectionImage(
                                      file: file,
                                      boxes: boxes,
                                      fit: BoxFit.contain,
                                    )
                                  : Image.file(
                                      file,
                                      key: const Key(
                                        'evidence_canonical_image',
                                      ),
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: AppText(
                                          'Canonical evidence could not be decoded.',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (widget.allowActions)
              Material(
                elevation: 8,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (staged)
                        _ViewerButton(
                          key: const Key('viewer_use_photo'),
                          filled: true,
                          icon: Icons.check_circle_outline,
                          label: 'Use photo',
                          action: EvidencePhotoAction.usePhoto,
                        ),
                      if (staged) const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ViewerButton(
                              key: const Key('viewer_retake'),
                              icon: Icons.refresh,
                              label: 'Retake',
                              action: EvidencePhotoAction.retake,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ViewerButton(
                              key: const Key('viewer_remove'),
                              destructive: true,
                              icon: Icons.delete_outline,
                              label: 'Remove',
                              action: EvidencePhotoAction.remove,
                            ),
                          ),
                        ],
                      ),
                      if (widget.allowAddCloseUp) ...[
                        const SizedBox(height: 8),
                        _ViewerButton(
                          key: const Key('viewer_add_close_up'),
                          icon: Icons.add_a_photo_outlined,
                          label: 'Add close-up',
                          action: EvidencePhotoAction.addCloseUp,
                        ),
                      ],
                      if (widget.allowAddDiagnosticDetail) ...[
                        const SizedBox(height: 8),
                        _ViewerButton(
                          key: const Key('viewer_add_diagnostic_detail'),
                          icon: Icons.add_a_photo_outlined,
                          label: 'Add extra detail',
                          action: EvidencePhotoAction.addDiagnosticDetail,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoutingViewer(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF182018),
    appBar: AppBar(
      backgroundColor: const Color(0xFF182018),
      foregroundColor: Colors.white,
      title: AppText(
        widget.scopeLabel,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'Photo information',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: const Color(0xFF182018),
            showDragHandle: true,
            useSafeArea: true,
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      widget.scopeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReadOnlyMetadataGrid(media: widget.media),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<File>(
        future: _file,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done)
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          final file = state.data;
          if (file == null || !file.existsSync())
            return const Center(
              child: AppText(
                'Photo unavailable on this device.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          final boxes = ModelDetectionImage.boxesForFile(
            widget.cvDiagnosis,
            file,
          );
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  key: const Key('evidence_interactive_viewer'),
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 5,
                  boundaryMargin: EdgeInsets.zero,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox.expand(
                    child: ModelDetectionImage(
                      key: const Key('evidence_canonical_image'),
                      file: file,
                      boxes: _showDetections ? boxes : const [],
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (boxes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 10,
                          children: [
                            for (final mode in <(bool, String)>[
                              (false, 'Original'),
                              (true, 'Detections'),
                            ])
                              ChoiceChip(
                                key: Key('scout_photo_${mode.$1}'),
                                showCheckmark: false,
                                label: AppText(mode.$2),
                                selected: _showDetections == mode.$1,
                                onSelected: (_) =>
                                    setState(() => _showDetections = mode.$1),
                              ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            'Pinch to zoom',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('viewer_reset_view'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => _transformationController.value =
                              Matrix4.identity(),
                          icon: const Icon(Icons.center_focus_strong, size: 18),
                          label: const AppText(
                            'Reset view',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildReadOnlyViewer(BuildContext context) {
    const background = Color(0xFF07100F);
    const panel = Color(0xFF131D1C);
    const muted = Color(0xFFBBC8C5);
    final count = widget.photoCount;
    final index = widget.photoIndex;
    final hasPosition =
        count != null && count > 0 && index != null && index > 0;
    final title = hasPosition
        ? '${widget.scopeLabel} · Photo $index of $count'
        : widget.scopeLabel;
    final contextParts = <String>[
      if (widget.stationLabel?.trim().isNotEmpty ?? false)
        widget.stationLabel!.trim(),
      if (widget.fieldName?.trim().isNotEmpty ?? false)
        widget.fieldName!.trim(),
    ];

    return Scaffold(
      key: const Key('read_only_evidence_viewer'),
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        centerTitle: true,
        titleSpacing: 8,
        toolbarHeight: contextParts.isEmpty ? 60 : 74,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              key: const Key('evidence_viewer_scope_label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (contextParts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                contextParts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: FutureBuilder<File>(
                future: _file,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  }
                  if (!snapshot.hasData || !snapshot.data!.existsSync()) {
                    return const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white70,
                                size: 42,
                              ),
                              SizedBox(height: 12),
                              AppText(
                                'The stored evidence image is unavailable on this device.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return ColoredBox(
                    color: Colors.black,
                    child: InteractiveViewer(
                      key: const Key('evidence_interactive_viewer'),
                      transformationController: _transformationController,
                      minScale: 1,
                      maxScale: 5,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox.expand(
                        child: Image.file(
                          snapshot.data!,
                          key: const Key('evidence_canonical_image'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, _, _) => const Center(
                            child: AppText(
                              'The stored evidence image could not be decoded.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              flex: 4,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 9),
                    Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8D9B98),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  widget.scopeLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF273A36),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    widget.media.isCanonicalEvidence
                                        ? 'Canonical record'
                                        : 'Read-only record',
                                    style: const TextStyle(
                                      color: Color(0xFFD9E8E4),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              evidenceViewLabel(widget.media.viewType),
                              key: const Key('evidence_viewer_view_label'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (widget.observationSummary?.trim().isNotEmpty ??
                                false) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.observationSummary!.trim(),
                                style: const TextStyle(
                                  color: muted,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _ReadOnlyMetadataGrid(media: widget.media),
                            const SizedBox(height: 14),
                            const AppText(
                              'Pinch to zoom and drag to inspect this saved image. This viewer does not alter the evidence file.',
                              style: TextStyle(color: muted, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFF344340)),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                key: const Key('viewer_reset_view'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () =>
                                    _transformationController.value =
                                        Matrix4.identity(),
                                icon: const Icon(Icons.center_focus_strong),
                                label: const AppText('Reset view'),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                key: const Key('viewer_info'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: AppText(
                                          'Recorded evidence details are shown above.',
                                        ),
                                      ),
                                    ),
                                icon: const Icon(Icons.info_outline),
                                label: const AppText('Info'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyMetadataGrid extends StatelessWidget {
  const _ReadOnlyMetadataGrid({required this.media});

  final EvidenceMediaRecord media;

  @override
  Widget build(BuildContext context) {
    final capturedAt = media.capturedAt;
    final hasLocation = media.latitude != null && media.longitude != null;
    final source = switch (media.captureSource) {
      DatabaseCodes.evidenceCaptureSourceCamera => 'Camera capture',
      null || '' => 'Source not recorded',
      final value => _readableCode(value),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = <Widget>[
          _ReadOnlyMetadataTile(
            icon: Icons.calendar_today_outlined,
            label: capturedAt == null
                ? 'Capture time not recorded'
                : DateFormat.yMMMd().add_jm().format(capturedAt.toLocal()),
          ),
          _ReadOnlyMetadataTile(
            icon: Icons.location_on_outlined,
            label: hasLocation
                ? '${media.latitude!.toStringAsFixed(5)}, ${media.longitude!.toStringAsFixed(5)}'
                : 'Location not recorded',
          ),
          _ReadOnlyMetadataTile(icon: Icons.camera_alt_outlined, label: source),
          _ReadOnlyMetadataTile(
            icon: Icons.verified_outlined,
            label: media.storageState == DatabaseCodes.evidenceStorageMissing
                ? 'Stored file missing'
                : 'Saved evidence',
          ),
        ];
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < tiles.length; index++) ...[
                tiles[index],
                if (index < tiles.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        final tileWidth = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _ReadOnlyMetadataTile extends StatelessWidget {
  const _ReadOnlyMetadataTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFDCE9E5)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFDCE9E5), height: 1.25),
          ),
        ),
      ],
    ),
  );
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.action,
    this.filled = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final EvidencePhotoAction action;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56, minWidth: 112),
      child: filled
          ? FilledButton.icon(
              onPressed: () => Navigator.pop(context, action),
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              style: destructive
                  ? OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E),
                    )
                  : null,
              onPressed: () => Navigator.pop(context, action),
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

String evidenceViewLabel(String? viewType) => switch (viewType) {
  DatabaseCodes.evidenceViewStationContext => 'Station-context view',
  DatabaseCodes.evidenceViewWhorlOverview => 'Whorl and newest-leaves overview',
  DatabaseCodes.evidenceViewCloseUp => 'Required closer whorl view',
  DatabaseCodes.evidenceViewDiagnosticDetail => 'Conditional evidence detail',
  _ => 'Evidence view',
};

String _readableCode(String value) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'Not recorded';
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
