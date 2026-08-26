import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../../services/station_evidence_policy.dart';

class PlantCaptureBoardStep extends StatefulWidget {
  const PlantCaptureBoardStep({
    super.key,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.isVeV2 = false,
    this.evidencePolicy = StationEvidencePolicy.cameraFirstOverviewConditional,
    required this.selectedPosition,
    required this.capturedPlantCount,
    required this.stationBundles,
    this.veV2Units = const [],
    required this.isSaving,
    required this.resolveFile,
    required this.onSelectPlant,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onCompleteStationCapture,
    required this.onCannotAssess,
    this.onSaveVeV2UnitException,
    this.onMarkAllHealthy,
    this.cvDiagnoses = const {},
  });

  final int blockNumber;
  final int stationNumber;
  final bool isVeV2;
  final StationEvidencePolicy evidencePolicy;
  final int selectedPosition;
  final int capturedPlantCount;
  final List<EvidenceCaptureBundle> stationBundles;
  final List<PlantingUnitObservationRecord> veV2Units;
  final bool isSaving;
  final Future<File> Function(String localUri) resolveFile;
  final ValueChanged<int> onSelectPlant;
  final Future<String?> Function(int position, String viewType) onCapture;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<bool> Function(EvidenceMediaRecord media) onAccept;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<bool> Function(
    int position,
    String viewType,
    String reason,
    String? note,
  )
  onManualFallback;
  final VoidCallback onCompleteStationCapture;
  final Future<void> Function(int position, String reason) onCannotAssess;
  final Future<void> Function(int position, String occupancy, String? reason)?
  onSaveVeV2UnitException;
  final VoidCallback? onMarkAllHealthy;
  final Map<int, PlantDiagnosisResult> cvDiagnoses;

  @override
  State<PlantCaptureBoardStep> createState() => _PlantCaptureBoardStepState();
}

class _PlantCaptureBoardStepState extends State<PlantCaptureBoardStep> {
  int? _expandedPosition;

  String get _primaryViewType => widget.isVeV2
      ? DatabaseCodes.evidenceViewWholeSeedling
      : DatabaseCodes.evidenceViewWhorlOverview;

  @override
  void initState() {
    super.initState();
    _expandedPosition = widget.selectedPosition;
  }

  @override
  void didUpdateWidget(covariant PlantCaptureBoardStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPosition != widget.selectedPosition) {
      _expandedPosition = widget.selectedPosition;
    }
  }

  void _togglePlant(int position) {
    setState(() {
      if (_expandedPosition == position) {
        _expandedPosition = null; // Close card if already open!
      } else {
        _expandedPosition = position; // Open card!
        widget.onSelectPlant(position);
      }
    });
  }

  EvidenceCaptureBundle? _bundleFor(int position) {
    for (final b in widget.stationBundles) {
      if (b.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          b.session.plantPosition == position) {
        return b;
      }
    }
    return null;
  }

  bool _isPlantSatisfied(int position) {
    if (widget.isVeV2) {
      for (final unit in widget.veV2Units) {
        if (unit.sequenceNumber == position &&
            (unit.occupancyStatus == DatabaseCodes.veOccupancyEmpty ||
                unit.occupancyStatus ==
                    DatabaseCodes.veOccupancyNotAssessable)) {
          return true;
        }
      }
    }
    final bundle = _bundleFor(position);
    if (bundle == null) return false;
    if (bundle.session.completedAt != null) return true;
    final hasPrimary =
        bundle.isViewSatisfied(_primaryViewType) ||
        bundle.media.any(
          (m) =>
              m.viewType == _primaryViewType &&
              m.deletedAt == null &&
              (m.storageState == DatabaseCodes.evidenceStorageReady ||
                  m.storageState == DatabaseCodes.evidenceStorageStaged),
        );
    final hasWaived = bundle.waivedViewTypes.isNotEmpty;
    return hasPrimary || hasWaived;
  }

  int get _firstIncompletePosition {
    for (var pos = 1; pos <= 10; pos++) {
      if (!_isPlantSatisfied(pos)) return pos;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final allComplete = widget.capturedPlantCount >= 10;
    final activeTarget = _expandedPosition ?? _firstIncompletePosition;

    return Column(
      children: [
        _BoardHeader(
          blockNumber: widget.blockNumber,
          stationNumber: widget.stationNumber,
          isVeV2: widget.isVeV2,
          capturedCount: widget.capturedPlantCount,
          onMarkAllHealthy: widget.onMarkAllHealthy,
          isSaving: widget.isSaving,
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('continuous_plant_capture_step'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            itemCount: 10,
            itemBuilder: (context, index) {
              final position = index + 1;
              final bundle = _bundleFor(position);
              final isSelected = position == _expandedPosition;
              final isSatisfied = _isPlantSatisfied(position);
              final diagnosis = widget.cvDiagnoses[position];
              final unit = widget.veV2Units
                  .where((u) => u.sequenceNumber == position)
                  .firstOrNull;

              return _PlantTile(
                key: ValueKey('plant_tile_$position'),
                position: position,
                isVeV2: widget.isVeV2,
                unit: unit,
                isSelected: isSelected,
                isSatisfied: isSatisfied,
                bundle: bundle,
                diagnosis: diagnosis,
                isSaving: widget.isSaving,
                evidencePolicy: widget.evidencePolicy,
                resolveFile: widget.resolveFile,
                onTap: () => _togglePlant(position),
                onCapture: widget.onCapture,
                onInspect: widget.onInspect,
                onAccept: widget.onAccept,
                onRetake: widget.onRetake,
                onRemove: widget.onRemove,
                onManualFallback: widget.onManualFallback,
                onCannotAssess: () => _showCannotAssessDialog(position),
                onChoosePositionException:
                    widget.onSaveVeV2UnitException == null
                    ? null
                    : () => _showVeV2PositionExceptionDialog(position),
                onNextPlant: () {
                  final nextPos = position < 10 ? position + 1 : 1;
                  _togglePlant(nextPos);
                },
              );
            },
          ),
        ),
        _BoardBottomBar(
          allComplete: allComplete,
          isVeV2: widget.isVeV2,
          selectedPosition: activeTarget,
          isSaving: widget.isSaving,
          onAction: () {
            if (allComplete) {
              widget.onCompleteStationCapture();
            } else {
              final target = activeTarget;
              final bundle = _bundleFor(target);
              final hasPrimary =
                  bundle?.isViewSatisfied(_primaryViewType) ?? false;
              final viewType = hasPrimary
                  ? DatabaseCodes.evidenceViewCloseUp
                  : _primaryViewType;
              widget.onCapture(target, viewType);
            }
          },
        ),
      ],
    );
  }

  Future<void> _showVeV2PositionExceptionDialog(int position) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What is at Seedling Position $position?',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.grass_outlined),
                  title: const Text('Empty spot'),
                  subtitle: const Text('No emerged seedling at this spot.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancyEmpty,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.content_cut_outlined),
                  title: const Text('Seedling remnant'),
                  subtitle: const Text('Dead or cut seedling stem remnant.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancyRemnant,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Living seedling'),
                  subtitle: const Text('Living maize seedling present.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancySeedling,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted && widget.onSaveVeV2UnitException != null) {
      await widget.onSaveVeV2UnitException!(position, result, null);
    }
  }

  Future<void> _showCannotAssessDialog(int position) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cannot assess Plant $position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Document why this plant cannot be assessed (e.g. missing plant, animal damage, flooded spot).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Broken stem / Missing seedling',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(
                dialogContext,
                text.isEmpty ? 'Cannot assess plant' : text,
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason != null && mounted) {
      await widget.onCannotAssess(position, reason);
    }
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.blockNumber,
    required this.stationNumber,
    this.isVeV2 = false,
    required this.capturedCount,
    this.onMarkAllHealthy,
    required this.isSaving,
  });

  final int blockNumber;
  final int stationNumber;
  final bool isVeV2;
  final int capturedCount;
  final VoidCallback? onMarkAllHealthy;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF176B3A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'BLOCK $blockNumber · STATION $stationNumber',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                '$capturedCount/10 Captured',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: capturedCount >= 10
                      ? const Color(0xFF176B3A)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isVeV2 ? 'Capture Seedlings 1–10' : 'Capture Plants 1–10',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onMarkAllHealthy != null && capturedCount < 10)
                TextButton.icon(
                  key: const Key('mark_all_healthy_button'),
                  onPressed: isSaving ? null : onMarkAllHealthy,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text(
                    'All Clean',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlantTile extends StatelessWidget {
  const _PlantTile({
    super.key,
    required this.position,
    this.isVeV2 = false,
    this.unit,
    required this.isSelected,
    required this.isSatisfied,
    required this.bundle,
    this.diagnosis,
    required this.isSaving,
    required this.evidencePolicy,
    required this.resolveFile,
    required this.onTap,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onCannotAssess,
    this.onChoosePositionException,
    required this.onNextPlant,
  });

  final int position;
  final bool isVeV2;
  final PlantingUnitObservationRecord? unit;
  final bool isSelected;
  final bool isSatisfied;
  final EvidenceCaptureBundle? bundle;
  final PlantDiagnosisResult? diagnosis;
  final bool isSaving;
  final StationEvidencePolicy evidencePolicy;
  final Future<File> Function(String localUri) resolveFile;
  final VoidCallback onTap;
  final Future<String?> Function(int position, String viewType) onCapture;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<bool> Function(EvidenceMediaRecord media) onAccept;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<bool> Function(
    int position,
    String viewType,
    String reason,
    String? note,
  )
  onManualFallback;
  final VoidCallback onCannotAssess;
  final VoidCallback? onChoosePositionException;
  final VoidCallback onNextPlant;

  String get _primaryViewType => isVeV2
      ? DatabaseCodes.evidenceViewWholeSeedling
      : DatabaseCodes.evidenceViewWhorlOverview;

  String get _primaryViewLabel => isVeV2 ? 'Seedling' : 'Overview';

  EvidenceMediaRecord? _mediaFor(String viewType) {
    if (bundle == null) return null;
    for (final m in bundle!.media.reversed) {
      if (m.viewType == viewType &&
          m.deletedAt == null &&
          (m.storageState == DatabaseCodes.evidenceStorageReady ||
              m.storageState == DatabaseCodes.evidenceStorageStaged)) {
        return m;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final primaryMedia = _mediaFor(_primaryViewType);
    final closeUpMedia = _mediaFor(DatabaseCodes.evidenceViewCloseUp);
    final detailMedia = _mediaFor(DatabaseCodes.evidenceViewDiagnosticDetail);
    final hasPrimary =
        primaryMedia != null ||
        (bundle?.isViewSatisfied(_primaryViewType) ?? false);
    final hasCloseUp =
        closeUpMedia != null ||
        (bundle?.isViewSatisfied(DatabaseCodes.evidenceViewCloseUp) ?? false);
    final hasDetail =
        detailMedia != null ||
        (bundle?.isViewSatisfied(DatabaseCodes.evidenceViewDiagnosticDetail) ??
            false);
    final isWaived = (bundle?.waivedViewTypes.isNotEmpty) ?? false;
    final isEmptySpot = unit?.occupancyStatus == DatabaseCodes.veOccupancyEmpty;
    final isRemnant = unit?.occupancyStatus == DatabaseCodes.veOccupancyRemnant;

    final String statusSubtitle;
    if (isEmptySpot) {
      statusSubtitle = 'Empty spot documented';
    } else if (isRemnant) {
      statusSubtitle = 'Remnant documented';
    } else if (isWaived) {
      statusSubtitle = 'Manual fallback documented';
    } else if (hasPrimary && hasCloseUp && hasDetail) {
      statusSubtitle = '$_primaryViewLabel ✓ · Close-up ✓ · Detail ✓';
    } else if (hasPrimary && hasCloseUp) {
      statusSubtitle = '$_primaryViewLabel ✓ · Close-up ✓';
    } else if (hasPrimary) {
      statusSubtitle = '$_primaryViewLabel ✓ · Close-up optional';
    } else {
      statusSubtitle = '$_primaryViewLabel needed';
    }

    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isSatisfied
        ? const Color(0xFF176B3A).withValues(alpha: 0.3)
        : Colors.black12;

    final bgColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2)
        : isSatisfied
        ? const Color(0xFFF6FBF7)
        : Colors.white;

    final titleLabel = isVeV2 ? 'Seedling $position' : 'Plant $position';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
      ),
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: isSatisfied
                        ? const Color(0xFF176B3A)
                        : isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black12,
                    foregroundColor: isSatisfied || isSelected
                        ? Colors.white
                        : Colors.black54,
                    child: Text(
                      isSatisfied ? '✓' : '$position',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          statusSubtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSatisfied
                                ? const Color(0xFF176B3A)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            fontWeight: isSatisfied
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isSelected &&
                      (primaryMedia != null ||
                          closeUpMedia != null ||
                          detailMedia != null)) ...[
                    if (primaryMedia != null)
                      _MiniPhotoThumb(
                        media: primaryMedia,
                        resolveFile: resolveFile,
                      ),
                    if (closeUpMedia != null) ...[
                      const SizedBox(width: 4),
                      _MiniPhotoThumb(
                        media: closeUpMedia,
                        resolveFile: resolveFile,
                      ),
                    ],
                    if (detailMedia != null) ...[
                      const SizedBox(width: 4),
                      _MiniPhotoThumb(
                        media: detailMedia,
                        resolveFile: resolveFile,
                      ),
                    ],
                    const SizedBox(width: 8),
                  ],
                  if (diagnosis != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: diagnosis!.isInfested
                            ? const Color(0xFFFDE8E8)
                            : const Color(0xFFEAF6EE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        diagnosis!.isInfested ? 'Infested' : 'Clean',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: diagnosis!.isInfested
                              ? const Color(0xFFB3261E)
                              : const Color(0xFF176B3A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    isSelected
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.black45,
                    size: 18,
                  ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (primaryMedia != null)
                        _PhotoThumbnailCard(
                          media: primaryMedia,
                          label: _primaryViewLabel,
                          resolveFile: resolveFile,
                          onInspect: onInspect,
                          onRetake: onRetake,
                          onRemove: onRemove,
                        )
                      else
                        _AddPhotoCard(
                          label: isVeV2 ? 'Add Seedling' : 'Add Overview',
                          subtitle: 'Required',
                          icon: Icons.camera_alt,
                          isRequired: true,
                          onTap: () => onCapture(position, _primaryViewType),
                        ),
                      const SizedBox(width: 10),
                      if (closeUpMedia != null)
                        _PhotoThumbnailCard(
                          media: closeUpMedia,
                          label: 'Close-up',
                          resolveFile: resolveFile,
                          onInspect: onInspect,
                          onRetake: onRetake,
                          onRemove: onRemove,
                        )
                      else
                        _AddPhotoCard(
                          label: '+ Close-up',
                          subtitle: 'Optional',
                          icon: Icons.zoom_in,
                          isRequired: false,
                          onTap: () => onCapture(
                            position,
                            DatabaseCodes.evidenceViewCloseUp,
                          ),
                        ),
                      if (detailMedia != null) ...[
                        const SizedBox(width: 10),
                        _PhotoThumbnailCard(
                          media: detailMedia,
                          label: 'Detail',
                          resolveFile: resolveFile,
                          onInspect: onInspect,
                          onRetake: onRetake,
                          onRemove: onRemove,
                        ),
                      ] else if (hasCloseUp) ...[
                        const SizedBox(width: 10),
                        _AddPhotoCard(
                          label: '+ Detail',
                          subtitle: 'Optional',
                          icon: Icons.biotech,
                          isRequired: false,
                          onTap: () => onCapture(
                            position,
                            DatabaseCodes.evidenceViewDiagnosticDetail,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          key: const Key('capture_cannot_assess'),
                          onPressed: isSaving ? null : onCannotAssess,
                          icon: const Icon(Icons.report_outlined, size: 14),
                          label: const Text(
                            'Cannot assess',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (isVeV2 && onChoosePositionException != null) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            key: ValueKey('ve_spot_exception_$position'),
                            onPressed: isSaving
                                ? null
                                : onChoosePositionException,
                            icon: const Icon(Icons.more_horiz, size: 14),
                            label: Text(
                              isEmptySpot
                                  ? 'Empty'
                                  : isRemnant
                                  ? 'Remnant'
                                  : 'Spot status',
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isSatisfied && position < 10)
                      FilledButton.tonalIcon(
                        onPressed: onNextPlant,
                        icon: const Icon(Icons.arrow_forward, size: 13),
                        label: Text(
                          'Next (${isVeV2 ? "Seedling" : "Plant"} ${position + 1})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardBottomBar extends StatelessWidget {
  const _BoardBottomBar({
    required this.allComplete,
    this.isVeV2 = false,
    required this.selectedPosition,
    required this.isSaving,
    required this.onAction,
  });

  final bool allComplete;
  final bool isVeV2;
  final int selectedPosition;
  final bool isSaving;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final noun = isVeV2 ? 'Seedling' : 'Plant';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      color: Colors.transparent,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          key: const Key('finish_plant_capture'),
          onPressed: isSaving ? null : onAction,
          icon: Icon(
            allComplete ? Icons.fact_check_outlined : Icons.camera_alt_outlined,
          ),
          label: Text(
            allComplete
                ? 'Proceed to Station Review'
                : 'Capture $noun $selectedPosition',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _MiniPhotoThumb extends StatelessWidget {
  const _MiniPhotoThumb({required this.media, required this.resolveFile});

  final EvidenceMediaRecord media;
  final Future<File> Function(String localUri) resolveFile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 30,
        height: 30,
        child: FutureBuilder<File>(
          future: resolveFile(media.thumbnailLocalUri ?? media.localUri),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.file(snapshot.data!, fit: BoxFit.cover);
            }
            return const ColoredBox(color: Colors.black12);
          },
        ),
      ),
    );
  }
}

class _PhotoThumbnailCard extends StatefulWidget {
  const _PhotoThumbnailCard({
    required this.media,
    required this.label,
    required this.resolveFile,
    required this.onInspect,
    required this.onRetake,
    required this.onRemove,
  });

  final EvidenceMediaRecord media;
  final String label;
  final Future<File> Function(String localUri) resolveFile;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;

  @override
  State<_PhotoThumbnailCard> createState() => _PhotoThumbnailCardState();
}

class _PhotoThumbnailCardState extends State<_PhotoThumbnailCard> {
  late Future<File> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = widget.resolveFile(
      widget.media.thumbnailLocalUri ?? widget.media.localUri,
    );
  }

  @override
  void didUpdateWidget(covariant _PhotoThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.localUri != widget.media.localUri ||
        oldWidget.media.thumbnailLocalUri != widget.media.thumbnailLocalUri) {
      _fileFuture = widget.resolveFile(
        widget.media.thumbnailLocalUri ?? widget.media.localUri,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF176B3A), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<File>(
              future: _fileFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.file(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 24,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 24,
                    ),
                  );
                }
                return const ColoredBox(color: Color(0xFF2C2C2C));
              },
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => widget.onInspect(widget.media)),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MicroActionButton(
                    icon: Icons.refresh,
                    tooltip: 'Retake',
                    onTap: () => widget.onRetake(widget.media),
                  ),
                  const SizedBox(width: 3),
                  _MicroActionButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Remove',
                    onTap: () => widget.onRemove(widget.media),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                color: Colors.black.withValues(alpha: 0.75),
                child: Text(
                  '✓ ${widget.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicroActionButton extends StatelessWidget {
  const _MicroActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 13,
        color: Colors.white,
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
      ),
    );
  }
}

class _AddPhotoCard extends StatelessWidget {
  const _AddPhotoCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isRequired,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool isRequired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isRequired
        ? theme.colorScheme.primary.withValues(alpha: 0.5)
        : Colors.black26;
    final bgColor = isRequired
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
        : const Color(0xFFF9F9F9);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isRequired ? 1.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: isRequired ? theme.colorScheme.primary : Colors.black54,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isRequired
                      ? theme.colorScheme.primary
                      : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isRequired
                      ? theme.colorScheme.primary
                      : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
