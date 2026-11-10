import '../../models/automatic_screening.dart';
import 'dart:convert';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../data/services/atomic_plant_save_service.dart';
import '../../data/services/atomic_ve_v2_save_service.dart';
import '../../providers/scouting_workflow_provider.dart';
import '../../services/ve_v2_analysis_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../station1/evidence_capture_panel.dart';
import '../station1/field_workflow_components.dart';
import '../station1/station_review_components.dart';

class VeV2StationSetupStep extends StatefulWidget {
  const VeV2StationSetupStep({
    super.key,
    required this.stationNumber,
    required this.stationId,
    required this.growthStage,
    required this.actorPersonId,
    required this.isSaving,
    required this.onSave,
  });

  final int stationNumber;
  final String stationId;
  final String growthStage;
  final String actorPersonId;
  final bool isSaving;
  final Future<void> Function(VeV2StationSetupInput input) onSave;

  @override
  State<VeV2StationSetupStep> createState() => _VeV2StationSetupStepState();
}

class _VeV2StationSetupStepState extends State<VeV2StationSetupStep> {
  bool? _emergenceAnswer;
  bool _sequenceAssessable = true;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('ve_v2_station_setup'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        widget.stationNumber == 1
            ? 'Assess 10 seedlings'
            : 'Station ${widget.stationNumber}',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        widget.stationNumber == 1
            ? 'Move along the same row. Photograph each living seedling in order.'
            : 'Continue along the row until 10 seedlings are assessed.',
      ),
      const SizedBox(height: 20),
      Text(
        widget.growthStage == 've'
            ? 'Is emergence still continuing?'
            : 'Could delayed emergence still explain some gaps?',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      _YesNoChoice(
        value: _emergenceAnswer,
        onChanged: (value) => setState(() => _emergenceAnswer = value),
      ),
      const SizedBox(height: 16),
      TextButton.icon(
        key: const Key('ve_v2_row_unavailable'),
        onPressed: () => setState(() {
          _sequenceAssessable = !_sequenceAssessable;
          if (_sequenceAssessable) _reason.clear();
        }),
        icon: const Icon(Icons.report_outlined),
        label: Text(
          _sequenceAssessable ? 'Cannot follow this row' : 'Use this row',
        ),
      ),
      if (!_sequenceAssessable)
        TextField(
          key: const Key('ve_v2_sequence_reason'),
          controller: _reason,
          decoration: InputDecoration(
            labelText: AppWords.of(
              context,
            ).translate('Why is the sequence not assessable?'),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('save_ve_v2_station_setup'),
        onPressed: widget.isSaving || !_valid ? null : _save,
        child: const AppText('Start Seedling 1'),
      ),
    ],
  );

  bool get _valid =>
      _emergenceAnswer != null &&
      (_sequenceAssessable || _reason.text.trim().isNotEmpty);

  Future<void> _save() => widget.onSave(
    VeV2StationSetupInput(
      stationId: widget.stationId,
      growthStage: widget.growthStage,
      rowDirectionCode: 'same_row_continuous',
      plantingUnitSequenceAssessable: _sequenceAssessable,
      // Accepting the stage-specific station photo is the evaluator's framing
      // confirmation. A separate row-context page is only needed for legacy
      // drafts that explicitly recorded the photo as unsuitable.
      stationContextMeetsRowPurpose: true,
      emergenceContinuing: widget.growthStage == 've' ? _emergenceAnswer : null,
      delayedEmergencePlausible: widget.growthStage == 've'
          ? null
          : _emergenceAnswer,
      sequenceNotAssessableReason: _sequenceAssessable
          ? null
          : _reason.text.trim(),
      actorPersonId: widget.actorPersonId,
    ),
  );
}

class VeV2ContinuousCaptureStep extends StatefulWidget {
  const VeV2ContinuousCaptureStep({
    super.key,
    required this.target,
    required this.savedUnitCount,
    required this.capturedLivingCount,
    required this.stationId,
    required this.actorPersonId,
    required this.bundle,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onFallback,
    required this.onSaveUnit,
    required this.onCompleteLivingCapture,
  });

  final VeV2CaptureTarget target;
  final int savedUnitCount;
  final int capturedLivingCount;
  final String stationId;
  final String actorPersonId;
  final EvidenceCaptureBundle bundle;
  final bool isSaving;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(String viewType) onCapture;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(EvidenceMediaRecord media) onAccept;
  final Future<void> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<void> Function(String viewType, String reason, String? note)
  onFallback;
  final Future<void> Function(VeV2CaptureRoutingSave input) onSaveUnit;
  final Future<void> Function(int leaves, Duration duration)
  onCompleteLivingCapture;

  @override
  State<VeV2ContinuousCaptureStep> createState() =>
      _VeV2ContinuousCaptureStepState();
}

class _VeV2ContinuousCaptureStepState extends State<VeV2ContinuousCaptureStep> {
  final Stopwatch _timer = Stopwatch()..start();
  final TextEditingController _reason = TextEditingController();
  String? _occupancy;
  int? _leaves;
  bool _cameraOpened = false;

  @override
  void initState() {
    super.initState();
    if (!_isUnit &&
        widget.bundle.isViewSatisfied(
          DatabaseCodes.evidenceViewWholeSeedling,
        )) {
      _leaves = 3;
    }
    _scheduleSeedlingCamera();
  }

  @override
  void didUpdateWidget(covariant VeV2ContinuousCaptureStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.livingSeedlingPosition !=
            widget.target.livingSeedlingPosition ||
        oldWidget.target.plantingUnitPosition !=
            widget.target.plantingUnitPosition) {
      _occupancy = null;
      _leaves = null;
      _cameraOpened = false;
      _timer
        ..reset()
        ..start();
      _scheduleSeedlingCamera();
    } else if (oldWidget.isSaving && !widget.isSaving) {
      // The linked seedling can first render while its row-position save is
      // still finishing. Retry when saving clears instead of leaving the
      // first camera step idle.
      _scheduleSeedlingCamera();
    }
    if (!_isUnit &&
        _leaves == null &&
        widget.bundle.isViewSatisfied(
          DatabaseCodes.evidenceViewWholeSeedling,
        )) {
      // The protocol requires the inspection, not a separate checkbox.
      // Accepting the guided view or its documented fallback confirms the
      // displayed inspection instruction. Keep the existing 3/4 field as a
      // compatibility representation for the shared vegetative schema.
      _leaves = 3;
    }
  }

  @override
  void dispose() {
    _timer.stop();
    _reason.dispose();
    super.dispose();
  }

  bool get _isUnit => widget.target.kind == VeV2CaptureKind.plantingUnit;

  Set<String> get _requiredViews {
    if (!_isUnit) {
      return {DatabaseCodes.evidenceViewWholeSeedling};
    }
    return {
      if (_occupancy == DatabaseCodes.veOccupancyRemnant)
        DatabaseCodes.evidenceViewStemBase,
    };
  }

  bool get _canContinue {
    if (!_requiredViews.every(widget.bundle.isViewSatisfied)) return false;
    if (!_isUnit) return _leaves == 3 || _leaves == 4;
    if (_occupancy == null) return false;
    if (_occupancy == DatabaseCodes.veOccupancyNotAssessable) {
      return _reason.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: ValueKey(
      _isUnit
          ? 've_v2_capture_unit_${widget.target.plantingUnitPosition}'
          : 've_v2_capture_seedling_${widget.target.livingSeedlingPosition}',
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CaptureProgress(seedlings: widget.capturedLivingCount),
        const SizedBox(height: 14),
        Text(
          widget.capturedLivingCount >= 10
              ? 'Seedlings complete'
              : 'Seedling ${widget.target.livingSeedlingPosition ?? widget.capturedLivingCount + 1} of 10',
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        Text(
          _isUnit
              ? 'Check the whole seedling and stem base.'
              : widget.target.sourcePlantingUnitSequence == null
              ? 'Continue along the same row.'
              : 'This seedling was encountered in the row sequence.',
        ),
        if (_isUnit) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('ve_v2_assess_seedling'),
            onPressed: widget.isSaving ? null : _recordLivingSeedling,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const AppText('Open camera'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('ve_v2_no_assessable_seedling'),
            onPressed: widget.isSaving ? null : _choosePositionException,
            icon: const Icon(Icons.report_outlined),
            label: const AppText('Cannot assess this position'),
          ),
          if (_occupancy == DatabaseCodes.veOccupancyRemnant) ...[
            _EvidenceCaptureTasks(
              views: _requiredViews,
              scopeLabel: 'Row condition',
              bundle: widget.bundle,
              resolveFile: widget.resolveFile,
              onCapture: widget.onCapture,
              onInspect: widget.onInspect,
              onAccept: widget.onAccept,
              onRetake: widget.onRetake,
              onRemove: widget.onRemove,
              onFallback: widget.onFallback,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('continue_ve_v2_capture'),
              onPressed: widget.isSaving || !_canContinue ? null : _continue,
              child: const AppText('Save remnant and continue'),
            ),
          ],
        ] else ...[
          const SizedBox(height: 12),
          EvidenceCapturePanel(
            title: 'Seedling photo',
            instruction:
                'Inspect the newest leaves and stem base, then keep the whole seedling in frame.',
            scopeLabel: 'Seedling ${widget.target.livingSeedlingPosition}',
            viewType: DatabaseCodes.evidenceViewWholeSeedling,
            bundle: widget.bundle,
            resolveFile: widget.resolveFile,
            onCapture: () =>
                widget.onCapture(DatabaseCodes.evidenceViewWholeSeedling),
            onInspect: widget.onInspect,
            onAccept: widget.onAccept,
            onRetake: widget.onRetake,
            onRemove: widget.onRemove,
            onManualFallback: (reason, note) => widget.onFallback(
              DatabaseCodes.evidenceViewWholeSeedling,
              reason,
              note,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('continue_ve_v2_capture'),
            onPressed: widget.isSaving || !_canContinue ? null : _continue,
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              widget.target.livingSeedlingPosition == 10
                  ? 'Open Station Review'
                  : 'Continue to Seedling ${(widget.target.livingSeedlingPosition ?? 0) + 1}',
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const AppText('Add close-up (optional)'),
            children: [
              EvidenceCapturePanel(
                title: 'Close-up',
                instruction: 'Use when detail is hard to judge.',
                scopeLabel: 'Seedling ${widget.target.livingSeedlingPosition}',
                viewType: DatabaseCodes.evidenceViewCloseUp,
                bundle: widget.bundle,
                resolveFile: widget.resolveFile,
                onCapture: () =>
                    widget.onCapture(DatabaseCodes.evidenceViewCloseUp),
                onInspect: widget.onInspect,
                onAccept: widget.onAccept,
                onRetake: widget.onRetake,
                onRemove: widget.onRemove,
                onManualFallback: (reason, note) => widget.onFallback(
                  DatabaseCodes.evidenceViewCloseUp,
                  reason,
                  note,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _continue() {
    if (!_isUnit) {
      return widget.onCompleteLivingCapture(_leaves!, _timer.elapsed);
    }
    final position = widget.target.plantingUnitPosition!;
    return widget.onSaveUnit(
      VeV2CaptureRoutingSave(
        stationId: widget.stationId,
        sequenceNumber: position,
        occupancyStatus: _occupancy!,
        observedSeedlingCount: _occupancy == DatabaseCodes.veOccupancySeedling
            ? 1
            : 0,
        inspectionDurationMs: _timer.elapsedMilliseconds,
        evidenceCaptureSessionId: widget.bundle.session.id,
        requiredEvidenceViewTypes: _requiredViews,
        actorPersonId: widget.actorPersonId,
        notAssessableReason:
            _occupancy == DatabaseCodes.veOccupancyNotAssessable
            ? _reason.text.trim()
            : null,
      ),
    );
  }

  Future<void> _recordLivingSeedling() async {
    setState(() => _occupancy = DatabaseCodes.veOccupancySeedling);
    await _continue();
  }

  Future<void> _choosePositionException() async {
    final occupancy = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppText(
                  'What is at this position?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.grass_outlined),
                  title: const AppText('Empty position'),
                  onTap: () =>
                      Navigator.pop(context, DatabaseCodes.veOccupancyEmpty),
                ),
                ListTile(
                  leading: const Icon(Icons.content_cut_outlined),
                  title: const AppText('Seedling remnant'),
                  subtitle: const AppText('Photograph the stem base.'),
                  onTap: () =>
                      Navigator.pop(context, DatabaseCodes.veOccupancyRemnant),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const AppText('Unsure what is here'),
                  onTap: () => Navigator.pop(
                    context,
                    DatabaseCodes.veOccupancyUncertain,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const AppText('Cannot assess this position'),
                  onTap: () => Navigator.pop(
                    context,
                    DatabaseCodes.veOccupancyNotAssessable,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (occupancy == null || !mounted) return;
    if (occupancy == DatabaseCodes.veOccupancyNotAssessable) {
      final reason = await _askForExceptionReason();
      if (reason == null || !mounted) return;
      _reason.text = reason;
    }
    setState(() => _occupancy = occupancy);
    if (occupancy != DatabaseCodes.veOccupancyRemnant) {
      await _continue();
    }
  }

  Future<String?> _askForExceptionReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('Why can’t it be assessed?'),
        content: TextField(
          key: const Key('ve_v2_exception_reason'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppWords.of(context).translate('Short reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.pop(context, reason);
            },
            child: const AppText('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openSeedlingCamera() async {
    if (!mounted || _cameraOpened || _isUnit || widget.isSaving) return;
    _cameraOpened = true;
    await widget.onCapture(DatabaseCodes.evidenceViewWholeSeedling);
  }

  void _scheduleSeedlingCamera() {
    if (_isUnit ||
        widget.bundle.media.isNotEmpty ||
        widget.bundle.waivedViewTypes.isNotEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSeedlingCamera());
  }
}

class _CaptureProgress extends StatelessWidget {
  const _CaptureProgress({required this.seedlings});
  final int seedlings;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$seedlings of 10 seedlings captured',
    child: LinearProgressIndicator(
      value: seedlings / 10,
      minHeight: 8,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

class VeV2RowContextStep extends StatelessWidget {
  const VeV2RowContextStep({
    super.key,
    required this.stationNumber,
    required this.bundle,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onFallback,
    required this.onContinue,
  });

  final int stationNumber;
  final EvidenceCaptureBundle bundle;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function() onCapture;
  final Future<void> Function(EvidenceMediaRecord) onInspect;
  final Future<void> Function(EvidenceMediaRecord) onAccept;
  final Future<void> Function(EvidenceMediaRecord) onRetake;
  final Future<void> Function(EvidenceMediaRecord) onRemove;
  final Future<void> Function(String, String?) onFallback;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('ve_v2_row_context_step'),
    padding: const EdgeInsets.all(20),
    children: [
      const AppText(
        'Row context',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const AppText('Show the row and planting spots.'),
      const SizedBox(height: 12),
      EvidenceCapturePanel(
        title: 'Row photo',
        instruction: 'Include the row direction and spacing.',
        scopeLabel: 'Station $stationNumber',
        viewType: DatabaseCodes.evidenceViewVeRowContext,
        bundle: bundle,
        resolveFile: resolveFile,
        onCapture: onCapture,
        onInspect: onInspect,
        onAccept: onAccept,
        onRetake: onRetake,
        onRemove: onRemove,
        onManualFallback: onFallback,
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('continue_after_ve_row_context'),
        onPressed:
            bundle.isViewSatisfied(DatabaseCodes.evidenceViewVeRowContext)
            ? onContinue
            : null,
        child: const AppText('Start planting spot 1'),
      ),
    ],
  );
}

class VeV2PlantingUnitStep extends StatefulWidget {
  const VeV2PlantingUnitStep({
    super.key,
    required this.position,
    required this.stationId,
    required this.actorPersonId,
    this.existing,
    required this.bundle,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onFallback,
    required this.onSave,
  });

  final int position;
  final String stationId;
  final String actorPersonId;
  final PlantingUnitObservationRecord? existing;
  final EvidenceCaptureBundle bundle;
  final bool isSaving;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(String viewType) onCapture;
  final Future<void> Function(EvidenceMediaRecord) onInspect;
  final Future<void> Function(EvidenceMediaRecord) onAccept;
  final Future<void> Function(EvidenceMediaRecord) onRetake;
  final Future<void> Function(EvidenceMediaRecord) onRemove;
  final Future<void> Function(String viewType, String reason, String? note)
  onFallback;
  final Future<void> Function(VeV2PlantingUnitSave) onSave;

  @override
  State<VeV2PlantingUnitStep> createState() => _VeV2PlantingUnitStepState();
}

class _VeV2PlantingUnitStepState extends State<VeV2PlantingUnitStep> {
  final Stopwatch _timer = Stopwatch()..start();
  String? _condition;
  int _seedlings = 1;
  bool _cutting = false;
  bool _severing = false;
  bool _frass = false;
  bool _larva = false;
  bool _rot = false;
  bool _tunnel = false;
  bool _discoloration = false;
  bool _other = false;
  String? _interpretation;
  String _confidence = 'moderate';
  String _injuryLocation = 'uncertain';
  String _freshness = 'uncertain';
  String _larvalSize = 'uncertain';
  final Set<String> _causes = {};
  final _reason = TextEditingController();
  bool _repeatedPhysicalCheck = false;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row == null) return;
    _condition = row.primaryCondition;
    _seedlings = row.observedSeedlingCount ?? 1;
    _cutting = row.visibleCutting ?? false;
    _severing = row.visibleSevering ?? false;
    _frass = row.freshFrass ?? false;
    _larva = row.larvaVisible ?? false;
    _rot = row.rotPresent ?? false;
    _tunnel = row.tunnelingPresent ?? false;
    _discoloration = row.discolorationPresent ?? false;
    _other = row.otherNonFawEvidence ?? false;
    _interpretation = row.evaluatorPrimaryInterpretation;
    _confidence = row.evaluatorConfidence ?? 'moderate';
    _injuryLocation = row.injuryLocation ?? 'uncertain';
    _freshness = row.injuryFreshness ?? 'uncertain';
    _larvalSize = row.larvalSize ?? 'uncertain';
    _reason.text = row.notAssessableReason ?? '';
    try {
      _causes.addAll(
        (jsonDecode(row.alternativeCauseCodesJson ?? '[]') as List)
            .cast<String>(),
      );
    } catch (_) {
      if (row.alternativeCauseCode != null) {
        _causes.add(row.alternativeCauseCode!);
      }
    }
  }

  bool get _occupied =>
      _condition == DatabaseCodes.veUnitHealthy ||
      _condition == DatabaseCodes.veUnitFeedingInjury;
  bool get _needsInterpretation =>
      _condition != null &&
      _condition != DatabaseCodes.veUnitHealthy &&
      _condition != DatabaseCodes.veUnitNotAssessable;

  Set<String> get _requiredViews {
    final views = <String>{};
    if ({
          DatabaseCodes.veUnitFeedingInjury,
          DatabaseCodes.veUnitCutSevered,
          DatabaseCodes.veUnitWiltedDead,
          DatabaseCodes.veUnitPositionUncertain,
        }.contains(_condition) ||
        _interpretation == DatabaseCodes.veInterpretationUncertain) {
      views.add(DatabaseCodes.evidenceViewWholeSeedling);
    }
    if (_condition == DatabaseCodes.veUnitCutSevered) {
      views.addAll({
        DatabaseCodes.evidenceViewStemBase,
        DatabaseCodes.evidenceViewCloseUp,
      });
    }
    if (_rot || _tunnel || _discoloration || _frass || _other) {
      views.add(DatabaseCodes.evidenceViewCloseUp);
    }
    if (_interpretation == DatabaseCodes.veInterpretationConfirmedFaw) {
      views.addAll({
        DatabaseCodes.evidenceViewLarvaDorsal,
        DatabaseCodes.evidenceViewLarvaHead,
      });
    }
    return views;
  }

  @override
  void dispose() {
    _timer.stop();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: Key('ve_v2_unit_${widget.position}'),
    padding: const EdgeInsets.all(16),
    children: [
      AppText(
        'Planting spot ${widget.position} of 10',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const AppText('Check this planting spot and seedling base.'),
      const _AnalysisUnavailableBanner(),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        isExpanded: true,
        key: const Key('ve_unit_condition'),
        initialValue: _condition,
        decoration: InputDecoration(labelText: "What's here?"),
        items: const [
          DropdownMenuItem(
            value: DatabaseCodes.veUnitHealthy,
            child: AppText('Healthy'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitFeedingInjury,
            child: AppText('Damaged'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitCutSevered,
            child: AppText('Cut or severed'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitWiltedDead,
            child: AppText('Wilted or dead'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitEmptyUnexplained,
            child: AppText('Empty'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitPositionUncertain,
            child: AppText('Unsure'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.veUnitNotAssessable,
            child: AppText('Cannot assess'),
          ),
        ],
        onChanged: (value) => setState(() => _condition = value),
      ),
      if (_occupied) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: AppText('Seedlings')),
            IconButton(
              onPressed: _seedlings > 1
                  ? () => setState(() => _seedlings--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            AppText(
              '$_seedlings',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () => setState(() => _seedlings++),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
      if (_needsInterpretation) ...[
        const SizedBox(height: 12),
        const AppText('Signs', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 6,
          children: [
            _FlagChip(
              label: 'Fresh cutting',
              value: _cutting,
              onChanged: (v) => setState(() => _cutting = v),
            ),
            _FlagChip(
              label: 'Severed',
              value: _severing,
              onChanged: (v) => setState(() => _severing = v),
            ),
            _FlagChip(
              label: 'Fresh frass',
              value: _frass,
              onChanged: (v) => setState(() => _frass = v),
            ),
            _FlagChip(
              label: 'Larva',
              value: _larva,
              onChanged: (v) => setState(() => _larva = v),
            ),
            _FlagChip(
              label: 'Rot',
              value: _rot,
              onChanged: (v) => setState(() => _rot = v),
            ),
            _FlagChip(
              label: 'Tunneling',
              value: _tunnel,
              onChanged: (v) => setState(() => _tunnel = v),
            ),
            _FlagChip(
              label: 'Discoloration',
              value: _discoloration,
              onChanged: (v) => setState(() => _discoloration = v),
            ),
            _FlagChip(
              label: 'Other cause evidence',
              value: _other,
              onChanged: (v) => setState(() => _other = v),
            ),
          ],
        ),
        _EvidenceCaptureTasks(
          views: _requiredViews,
          scopeLabel: 'Planting spot ${widget.position}',
          bundle: widget.bundle,
          resolveFile: widget.resolveFile,
          onCapture: widget.onCapture,
          onInspect: widget.onInspect,
          onAccept: widget.onAccept,
          onRetake: widget.onRetake,
          onRemove: widget.onRemove,
          onFallback: widget.onFallback,
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _injuryLocation,
          decoration: InputDecoration(
            labelText: AppWords.of(context).translate('Injury location'),
          ),
          items: const [
            DropdownMenuItem(value: 'leaf', child: AppText('Leaf')),
            DropdownMenuItem(value: 'whorl', child: AppText('Whorl')),
            DropdownMenuItem(value: 'stem_base', child: AppText('Stem base')),
            DropdownMenuItem(
              value: 'below_soil',
              child: AppText('Below soil line'),
            ),
            DropdownMenuItem(value: 'at_soil', child: AppText('At soil line')),
            DropdownMenuItem(
              value: 'above_soil',
              child: AppText('Above soil line'),
            ),
            DropdownMenuItem(value: 'uncertain', child: AppText('Uncertain')),
          ],
          onChanged: (value) => setState(() => _injuryLocation = value!),
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _freshness,
          decoration: InputDecoration(
            labelText: AppWords.of(context).translate('Injury freshness'),
          ),
          items: const [
            DropdownMenuItem(value: 'fresh', child: AppText('Fresh')),
            DropdownMenuItem(value: 'old', child: AppText('Old')),
            DropdownMenuItem(value: 'mixed', child: AppText('Mixed')),
            DropdownMenuItem(value: 'uncertain', child: AppText('Uncertain')),
          ],
          onChanged: (value) => setState(() => _freshness = value!),
        ),
        if (_larva)
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _larvalSize,
            decoration: InputDecoration(
              labelText: AppWords.of(context).translate('Larval size'),
            ),
            items: const [
              DropdownMenuItem(value: 'small', child: AppText('Small')),
              DropdownMenuItem(value: 'medium', child: AppText('Medium')),
              DropdownMenuItem(value: 'large', child: AppText('Large')),
              DropdownMenuItem(value: 'uncertain', child: AppText('Uncertain')),
            ],
            onChanged: (value) => setState(() => _larvalSize = value!),
          ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _interpretation,
          decoration: InputDecoration(
            labelText: AppWords.of(context).translate('Main finding'),
          ),
          items: const [
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationConfirmedFaw,
              child: AppText('Confirmed FAW present'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationFawConsistent,
              child: AppText('Injury consistent with FAW'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationOtherPest,
              child: AppText('Possible other pest'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationNonPest,
              child: AppText('Likely non-pest cause'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationMixed,
              child: AppText('Mixed causes or organisms'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationUncertain,
              child: AppText('Uncertain'),
            ),
            DropdownMenuItem(
              value: DatabaseCodes.veInterpretationNone,
              child: AppText('No relevant pest evidence'),
            ),
          ],
          onChanged: (value) => setState(() => _interpretation = value),
        ),
        if (widget.existing != null &&
            {
              DatabaseCodes.veInterpretationOtherPest,
              DatabaseCodes.veInterpretationNonPest,
              DatabaseCodes.veInterpretationMixed,
              DatabaseCodes.veInterpretationUncertain,
            }.contains(_interpretation)) ...[
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const AppText('Possible causes'),
            children: [
              Wrap(
                spacing: 6,
                children: [
                  for (final cause in const {
                    'common_cutworm': 'Cutworm',
                    'other_pest': 'Other pest',
                    'delayed_emergence': 'Late emergence',
                    'disease_or_rot': 'Disease or rot',
                    'water_or_drought': 'Water stress',
                    'herbicide': 'Herbicide',
                    'animal': 'Animal',
                    'planting_mechanical': 'Planting damage',
                  }.entries)
                    FilterChip(
                      label: Text(cause.value),
                      selected: _causes.contains(cause.key),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _causes.add(cause.key);
                        } else {
                          _causes.remove(cause.key);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
        ],
      ],
      if (_condition == DatabaseCodes.veUnitNotAssessable)
        TextField(
          controller: _reason,
          decoration: InputDecoration(
            labelText: AppWords.of(context).translate('Required reason'),
          ),
        ),
      if (widget.existing != null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const AppText(
            'I had to physically inspect this position again',
          ),
          value: _repeatedPhysicalCheck,
          onChanged: (value) =>
              setState(() => _repeatedPhysicalCheck = value ?? false),
        ),
      const SizedBox(height: 18),
      FilledButton(
        key: const Key('save_ve_v2_unit'),
        onPressed: widget.isSaving || !_canSave ? null : _save,
        child: Text(
          widget.position == 10
              ? 'Save planting spot 10'
              : 'Next planting spot',
        ),
      ),
    ],
  );

  bool get _canSave =>
      _condition != null &&
      (!_needsInterpretation || _interpretation != null) &&
      (_condition != DatabaseCodes.veUnitNotAssessable ||
          _reason.text.trim().isNotEmpty) &&
      _requiredViews.every(widget.bundle.isViewSatisfied);

  Future<void> _save() => widget.onSave(
    VeV2PlantingUnitSave(
      stationId: widget.stationId,
      sequenceNumber: widget.position,
      assessable: _condition != DatabaseCodes.veUnitNotAssessable,
      notAssessableReason: _condition == DatabaseCodes.veUnitNotAssessable
          ? _reason.text.trim()
          : null,
      primaryCondition: _condition!,
      observedSeedlingCount: _occupied ? _seedlings : 0,
      recognizableRemnantPresent:
          _condition == DatabaseCodes.veUnitCutSevered ||
          _condition == DatabaseCodes.veUnitWiltedDead,
      visibleCutting: _cutting,
      visibleSevering: _severing,
      visibleSeedlingInjury:
          _condition == DatabaseCodes.veUnitFeedingInjury ||
          _condition == DatabaseCodes.veUnitCutSevered,
      injuryLocation: _needsInterpretation ? _injuryLocation : null,
      injuryFreshness: _needsInterpretation ? _freshness : null,
      larvaVisible: _needsInterpretation ? _larva : null,
      larvalSize: _larva ? _larvalSize : null,
      freshFrass: _needsInterpretation ? _frass : null,
      rotPresent: _needsInterpretation ? _rot : null,
      tunnelingPresent: _needsInterpretation ? _tunnel : null,
      discolorationPresent: _needsInterpretation ? _discoloration : null,
      otherNonFawEvidence: _needsInterpretation ? _other : null,
      evaluatorPrimaryInterpretation: _needsInterpretation
          ? _interpretation
          : DatabaseCodes.veInterpretationNone,
      evaluatorConfidence: _needsInterpretation ? _confidence : 'high',
      alternativeCauseCodes: _causes,
      inspectionDurationMs: _timer.elapsedMilliseconds,
      actorPersonId: widget.actorPersonId,
      evidenceCaptureSessionId: _requiredViews.isEmpty
          ? null
          : widget.bundle.session.id,
      requiredEvidenceViewTypes: _requiredViews,
      repeatedPhysicalCheck: _repeatedPhysicalCheck,
    ),
  );
}

class VeV2LivingSeedlingStep extends StatefulWidget {
  const VeV2LivingSeedlingStep({
    super.key,
    required this.position,
    this.blockNumber = 1,
    this.stationNumber = 1,
    required this.stationId,
    required this.actorPersonId,
    this.existing,
    this.suggestedSourceUnitId,
    this.initialLeavesInspectedCount,
    required this.linkableUnits,
    required this.bundle,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onFallback,
    required this.onSave,
    this.onCancel,
  });

  final int position;
  final int blockNumber;
  final int stationNumber;
  final String stationId;
  final String actorPersonId;
  final StationPlantRecord? existing;
  final String? suggestedSourceUnitId;
  final int? initialLeavesInspectedCount;
  final List<PlantingUnitObservationRecord> linkableUnits;
  final EvidenceCaptureBundle bundle;
  final bool isSaving;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(String viewType) onCapture;
  final Future<void> Function(EvidenceMediaRecord) onInspect;
  final Future<void> Function(EvidenceMediaRecord) onAccept;
  final Future<void> Function(EvidenceMediaRecord) onRetake;
  final Future<void> Function(EvidenceMediaRecord) onRemove;
  final Future<void> Function(String viewType, String reason, String? note)
  onFallback;
  final Future<void> Function(VegetativePlantSave, bool repeatedPhysicalCheck)
  onSave;
  final VoidCallback? onCancel;

  @override
  State<VeV2LivingSeedlingStep> createState() => _VeV2LivingSeedlingStepState();
}

class _VeV2LivingSeedlingStepState extends State<VeV2LivingSeedlingStep> {
  final Stopwatch _timer = Stopwatch()..start();
  final TextEditingController _naturalEnemyDetail = TextEditingController();
  final TextEditingController _naturalEnemyReason = TextEditingController();
  String? _linkedUnitId;
  int? _leaves;
  final Set<String> _signs = {};
  bool? _larva;
  String _larvalSize = 'uncertain';
  String? _eggChoice;
  bool? _oldDamage;
  bool? _nonFaw;
  bool? _uncertain;
  String? _naturalEnemy;
  String? _interpretation;
  bool _repeatedPhysicalCheck = false;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row == null) {
      _linkedUnitId = widget.suggestedSourceUnitId ?? 'additional';
      _leaves = widget.initialLeavesInspectedCount ?? 3;
      return;
    }
    _linkedUnitId = row.plant.sourcePlantingUnitObservationId ?? 'additional';
    _leaves = row.vegetative.newestLeavesInspectedCount;
    if (row.vegetative.smallFreshWindowpanes) _signs.add('windowpanes');
    if (row.vegetative.scraping) _signs.add('scraping');
    if (row.vegetative.cuttingOrTearing) _signs.add('cutting');
    if (row.vegetative.freshFrass) _signs.add('frass');
    if (row.vegetative.whorlFeedingSign) _signs.add('whorl');
    if (_signs.isEmpty) _signs.add('none');
    _larva = row.vegetative.larvaVisible;
    _larvalSize = row.vegetative.larvalSize;
    _eggChoice = switch (row.vegetative.eggMassVisible) {
      true => 'yes',
      false => 'no',
      null => 'not_collected',
    };
    _oldDamage = row.plant.oldDamagePresent;
    _nonFaw = row.plant.possibleNonFawEvidence;
    _uncertain = row.plant.uncertainEvidence;
    _naturalEnemy = row.plant.naturalEnemyQuickStatus;
    _interpretation = row.plant.plantStatus;
  }

  @override
  void dispose() {
    _timer.stop();
    _naturalEnemyDetail.dispose();
    _naturalEnemyReason.dispose();
    super.dispose();
  }

  Set<String> get _requiredViews {
    final positive = _signs.isNotEmpty && !_signs.contains('none');
    return {
      DatabaseCodes.evidenceViewWholeSeedling,
      if (positive ||
          _larva == true ||
          _eggChoice == 'yes' ||
          _nonFaw == true ||
          _uncertain == true)
        DatabaseCodes.evidenceViewCloseUp,
    };
  }

  @override
  Widget build(BuildContext context) {
    final evidenceComplete = _requiredViews.every(
      widget.bundle.isViewSatisfied,
    );

    return FieldWorkflowShell(
      scrollKey: Key('ve_v2_living_${widget.position}'),
      bottomBar: StickyWorkflowActionBar(
        message:
            'Your field confirmation is saved as the final seedling observation.',
        actionLabel: widget.existing != null
            ? 'Save and return to review'
            : widget.position == 10
            ? 'Review station'
            : 'Next seedling',
        actionKey: const Key('save_ve_v2_living_seedling'),
        isSaving: widget.isSaving,
        secondaryLabel: widget.existing == null || widget.onCancel == null
            ? null
            : 'Cancel',
        onSecondary: widget.onCancel,
        onPressed: _canSave ? _save : null,
      ),
      children: [
        WorkflowContextHeader(
          stageLabel: 'VE–V2',
          blockNumber: widget.blockNumber,
          stationNumber: widget.stationNumber,
          title: 'Confirm Seedling ${widget.position}',
          subtitle:
              'Inspect the evidence and record what you observe on this seedling.',
          completedCount: _canSave ? 1 : 0,
          totalCount: 1,
          attentionCount: _canSave ? 0 : 1,
        ),
        const SizedBox(height: AppSpacing.sm),
        const WorkflowFormSection(
          title: '1 · Model preview',
          icon: Icons.auto_awesome_outlined,
          subtitle: 'No seedling model result is available',
          children: [_AnalysisUnavailableBanner()],
        ),
        WorkflowFormSection(
          title: '2 · Seedling observations',
          icon: Icons.checklist_outlined,
          subtitle: 'Record visible signs from this seedling',
          children: [
            if (_leaves == null)
              CheckboxListTile(
                key: const Key('ve_v2_review_seedling_checked'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: false,
                onChanged: widget.isSaving
                    ? null
                    : (checked) {
                        if (checked == true) setState(() => _leaves = 3);
                      },
                title: const AppText('Seedling physically checked'),
              ),
            const SizedBox(height: 12),
            const AppText(
              'Fresh signs',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final item in const {
                  'windowpanes': 'Windowpanes',
                  'scraping': 'Scraping',
                  'cutting': 'Cutting/tearing',
                  'frass': 'Frass',
                  'whorl': 'Whorl damage',
                }.entries)
                  FilterChip(
                    label: Text(item.value),
                    selected: _signs.contains(item.key),
                    onSelected: (value) => setState(() {
                      if (value) {
                        _signs.add(item.key);
                      } else {
                        _signs.remove(item.key);
                      }
                    }),
                  ),
                FilterChip(
                  label: const AppText('None'),
                  selected: _signs.contains('none'),
                  onSelected: (value) => setState(() {
                    _signs.clear();
                    if (value) _signs.add('none');
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const AppText(
              'Larva?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            _YesNoChoice(
              value: _larva,
              onChanged: (value) => setState(() => _larva = value),
            ),
            if (_larva == true)
              _LabeledChoiceChips<String>(
                label: 'Larval size',
                value: _larvalSize,
                choices: const {
                  'small': 'Small',
                  'medium': 'Medium',
                  'large': 'Large',
                  'uncertain': 'Uncertain',
                },
                onChanged: (value) => setState(() => _larvalSize = value),
              ),
            const AppText(
              'Egg mass?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            _EggChoice(
              value: _eggChoice,
              onChanged: (value) => setState(() => _eggChoice = value),
            ),
            _BooleanRow(
              label: 'Old damage?',
              value: _oldDamage,
              onChanged: (value) => setState(() => _oldDamage = value),
            ),
            _BooleanRow(
              label: 'Possible other cause?',
              value: _nonFaw,
              onChanged: (value) => setState(() => _nonFaw = value),
            ),
            _BooleanRow(
              label: 'Unsure?',
              value: _uncertain,
              onChanged: (value) => setState(() => _uncertain = value),
            ),
          ],
        ),
        WorkflowFormSection(
          title: '3 · Evidence',
          icon: Icons.photo_library_outlined,
          subtitle: evidenceComplete
              ? 'Required seedling evidence is available'
              : 'Complete the required seedling evidence',
          completed: evidenceComplete,
          children: [
            _EvidenceCaptureTasks(
              views: _requiredViews,
              scopeLabel: 'Seedling ${widget.position}',
              bundle: widget.bundle,
              resolveFile: widget.resolveFile,
              onCapture: widget.onCapture,
              onInspect: widget.onInspect,
              onAccept: widget.onAccept,
              onRetake: widget.onRetake,
              onRemove: widget.onRemove,
              onFallback: widget.onFallback,
            ),
          ],
        ),
        WorkflowFormSection(
          title: '4 · Field confirmation',
          icon: Icons.fact_check_outlined,
          subtitle: 'Confirm the saved finding for this seedling',
          completed: _interpretation != null,
          children: [
            _LabeledChoiceChips<String>(
              label: 'Natural enemies',
              value: _naturalEnemy,
              choices: const {
                DatabaseCodes.naturalEnemyObserved: 'Observed',
                DatabaseCodes.naturalEnemyNoneSeen: 'Not observed',
                DatabaseCodes.naturalEnemyUncertain: 'Uncertain',
                DatabaseCodes.naturalEnemyNotAssessable: 'Not assessable',
                DatabaseCodes.naturalEnemyNotCollected: 'Not collected',
              },
              onChanged: (value) => setState(() => _naturalEnemy = value),
            ),
            if (_naturalEnemy == DatabaseCodes.naturalEnemyObserved ||
                _naturalEnemy == DatabaseCodes.naturalEnemyUncertain)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _naturalEnemyDetail,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: AppWords.of(
                      context,
                    ).translate('Natural-enemy details (optional)'),
                    helperText: AppWords.of(context).translate(
                      'Do not identify an organism unless the evidence supports it.',
                    ),
                  ),
                ),
              ),
            if (_naturalEnemy == DatabaseCodes.naturalEnemyNotAssessable ||
                _naturalEnemy == DatabaseCodes.naturalEnemyNotCollected)
              TextField(
                controller: _naturalEnemyReason,
                decoration: InputDecoration(
                  labelText: AppWords.of(
                    context,
                  ).translate('Why was the quick observation not completed?'),
                ),
              ),
            const SizedBox(height: 12),
            _LabeledChoiceChips<String>(
              label: 'Main seedling finding',
              value: _interpretation,
              choices: const {
                DatabaseCodes.plantNegative: 'No current FAW evidence',
                DatabaseCodes.plantCurrentPositive:
                    'Current FAW-consistent evidence',
                DatabaseCodes.plantOldDamageOnly: 'Old damage only',
                DatabaseCodes.plantPossibleNonFaw: 'Possible non-FAW',
                DatabaseCodes.plantUncertain: 'Uncertain',
              },
              onChanged: (value) => setState(() => _interpretation = value),
            ),
            if (widget.existing != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const AppText(
                  'I had to physically inspect this seedling again',
                ),
                value: _repeatedPhysicalCheck,
                onChanged: (value) =>
                    setState(() => _repeatedPhysicalCheck = value ?? false),
              ),
          ],
        ),
      ],
    );
  }

  bool get _canSave =>
      _linkedUnitId != null &&
      _leaves != null &&
      _signs.isNotEmpty &&
      _larva != null &&
      _eggChoice != null &&
      _oldDamage != null &&
      _nonFaw != null &&
      _uncertain != null &&
      _naturalEnemy != null &&
      (!{
            DatabaseCodes.naturalEnemyNotAssessable,
            DatabaseCodes.naturalEnemyNotCollected,
          }.contains(_naturalEnemy) ||
          _naturalEnemyReason.text.trim().isNotEmpty) &&
      _interpretation != null &&
      _requiredViews.every(widget.bundle.isViewSatisfied);

  Future<void> _save() => widget.onSave(
    VegetativePlantSave(
      stationId: widget.stationId,
      plantPosition: widget.position,
      plantStatus: _interpretation!,
      assessable: true,
      newestLeavesInspectedCount: _leaves,
      smallFreshWindowpanes: _signs.contains('windowpanes'),
      scraping: _signs.contains('scraping'),
      cuttingOrTearing: _signs.contains('cutting'),
      freshFrass: _signs.contains('frass'),
      whorlFeedingSign: _signs.contains('whorl'),
      larvaVisible: _larva!,
      larvalSize: _larva! ? _larvalSize : 'none_seen',
      eggMassVisible: switch (_eggChoice) {
        'yes' => true,
        'no' => false,
        _ => null,
      },
      oldDamagePresent: _oldDamage!,
      possibleNonFawEvidence: _nonFaw,
      uncertainEvidence: _uncertain,
      naturalEnemyQuickStatus: _naturalEnemy!,
      evaluatorNotes:
          [
            if (_naturalEnemyDetail.text.trim().isNotEmpty)
              'Natural-enemy detail: ${_naturalEnemyDetail.text.trim()}',
            if (_naturalEnemyReason.text.trim().isNotEmpty)
              'Natural-enemy reason: ${_naturalEnemyReason.text.trim()}',
          ].join(' · ').trim().isEmpty
          ? null
          : [
              if (_naturalEnemyDetail.text.trim().isNotEmpty)
                'Natural-enemy detail: ${_naturalEnemyDetail.text.trim()}',
              if (_naturalEnemyReason.text.trim().isNotEmpty)
                'Natural-enemy reason: ${_naturalEnemyReason.text.trim()}',
            ].join(' · '),
      sourcePlantingUnitObservationId: _linkedUnitId == 'additional'
          ? null
          : _linkedUnitId,
      actorPersonId: widget.actorPersonId,
      pilotActiveDurationMs: _timer.elapsedMilliseconds,
      evidenceCaptureSessionId: widget.bundle.session.id,
      requiredEvidenceViewTypes: _requiredViews,
      requireCameraPhaseAEvidence: true,
    ),
    _repeatedPhysicalCheck,
  );
}

class VeV2StationReviewStep extends StatefulWidget {
  const VeV2StationReviewStep({
    super.key,
    this.blockNumber = 1,
    required this.stationNumber,
    required this.units,
    required this.plants,
    required this.inspection,
    required this.acceptedImageCount,
    required this.fallbackCount,
    required this.retakeCount,
    required this.evidenceBundles,
    required this.resolveFile,
    required this.onInspect,
    required this.analysisFor,
    required this.isSaving,
    required this.onEditUnit,
    required this.onEditPlant,
    required this.onComplete,
    this.onCompleteWithoutManualConfirmation,
  });
  final int blockNumber;
  final int stationNumber;
  final List<PlantingUnitObservationRecord> units;
  final List<StationPlantRecord> plants;
  final VeV2StationInspectionRecord? inspection;
  final int acceptedImageCount;
  final int fallbackCount;
  final int retakeCount;
  final List<EvidenceCaptureBundle> evidenceBundles;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final VeV2AnalysisPresentation Function(EvidenceCaptureBundle? bundle)
  analysisFor;
  final bool isSaving;
  final Future<void> Function(int position) onEditUnit;
  final Future<void> Function(int position) onEditPlant;
  final Future<void> Function() onComplete;
  final VoidCallback? onCompleteWithoutManualConfirmation;
  @override
  State<VeV2StationReviewStep> createState() => _VeV2StationReviewStepState();
}

class _VeV2StationReviewStepState extends State<VeV2StationReviewStep> {
  @override
  Widget build(BuildContext context) {
    final plantsByPosition = {
      for (final plant in widget.plants) plant.plant.sequenceNumber: plant,
    };
    final allConfirmed =
        widget.units.length == 10 && widget.plants.length == 10;
    final capturedPositions = {
      for (final bundle in widget.evidenceBundles)
        if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition != null &&
            bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling))
          bundle.session.plantPosition!,
    };
    final emptyCount = widget.units
        .where((unit) => unit.occupancyStatus == DatabaseCodes.veOccupancyEmpty)
        .length;
    final remnantCount = widget.units
        .where(
          (unit) => unit.occupancyStatus == DatabaseCodes.veOccupancyRemnant,
        )
        .length;
    final exceptionCount = widget.units
        .where(
          (unit) => const {
            DatabaseCodes.veOccupancyUncertain,
            DatabaseCodes.veOccupancyNotAssessable,
          }.contains(unit.occupancyStatus),
        )
        .length;
    final screeningMode = widget.plants.any(
      (p) => AutomaticScreening.parse(p.plant.wholePlantContextNote) != null,
    );
    final healthyCount = widget.plants
        .where(
          (p) =>
              (p.plant.plantStatus ==
              (screeningMode
                  ? AutomaticScreening.negativeStatus
                  : DatabaseCodes.plantNegative)),
        )
        .length;
    final infestedCount = widget.plants
        .where(
          (p) =>
              (p.plant.plantStatus ==
              (screeningMode
                  ? AutomaticScreening.positiveStatus
                  : DatabaseCodes.plantCurrentPositive)),
        )
        .length;
    final larvaeCount = widget.plants
        .where((p) => p.vegetativeOrNull?.larvaVisible == true)
        .length;

    return FieldWorkflowShell(
      scrollKey: const Key('ve_v2_station_review'),
      bottomBar: StationReviewBottomBar(
        message: allConfirmed
            ? 'Review the seedlings before saving this station.'
            : '${capturedPositions.length}/10 photos captured · ${widget.plants.length}/10 observations confirmed',
        actionLabel: 'Complete Station ${widget.stationNumber}',
        actionKey: const Key('complete_ve_v2_pilot_station'),
        isSaving: widget.isSaving,
        onPressed: allConfirmed ? widget.onComplete : null,
      ),
      children: [
        StationReviewHeader(
          blockNumber: widget.blockNumber,
          stageLabel: 'VE–V2',
          stationNumber: widget.stationNumber,
          confirmedCount: capturedPositions.length,
          itemLabel: 'seedlings',
          progressSubtitle:
              '${capturedPositions.length} of 10 seedling photos captured · ${widget.plants.length} observations confirmed',
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
          growthStage: 've_v2',
          totalPlants: screeningMode
              ? widget.plants
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
          notAssessableCount: exceptionCount,
          cutSeedlingCount: remnantCount,
          emptySpotCount: emptyCount,
          larvaeCount: larvaeCount,
        ),
        const SizedBox(height: 12),
        const WorkflowSectionHeader(
          title: 'Seedling assessments',
          subtitle: 'Tap any seedling to inspect or correct.',
        ),
        for (var position = 1; position <= 10; position++)
          _buildVeCompactSeedlingTile(
            position: position,
            plant: plantsByPosition[position],
            bundle: _bundleForPlantPosition(widget.evidenceBundles, position),
            unit: widget.units
                .where((u) => u.sequenceNumber == position)
                .firstOrNull,
            onTap: () => widget.onEditPlant(position),
          ),
        const SizedBox(height: 14),
        StationDetailsFooterStrip(
          durationLabel:
              '${widget.acceptedImageCount} photos · ${widget.fallbackCount} fallbacks',
        ),
      ],
    );
  }

  Widget _buildVeCompactSeedlingTile({
    required int position,
    required Station1PlantRecord? plant,
    required EvidenceCaptureBundle? bundle,
    required PlantingUnitObservationRecord? unit,
    required VoidCallback onTap,
  }) {
    if (unit != null &&
        unit.occupancyStatus == DatabaseCodes.veOccupancyEmpty) {
      return CompactPlantAuditTile(
        position: position,
        itemLabel: 'Seedling',
        statusLabel: 'Empty Spot',
        statusColor: const Color(0xFF5A5A5A),
        statusBgColor: const Color(0xFFE8EAEB),
        symptomsSummary: 'No seedling emerged at this position',
        onTap: onTap,
      );
    }
    if (unit != null &&
        unit.occupancyStatus == DatabaseCodes.veOccupancyRemnant) {
      return CompactPlantAuditTile(
        position: position,
        itemLabel: 'Seedling',
        statusLabel: 'Remnant / Cut',
        statusColor: AppColors.severeSeverityRing,
        statusBgColor: AppColors.severeSeverityBg,
        symptomsSummary: 'Damaged remnant or severed seedling',
        onTap: onTap,
      );
    }
    if (plant == null) {
      final hasPhoto =
          bundle?.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling) ==
          true;
      return CompactPlantAuditTile(
        position: position,
        itemLabel: 'Seedling',
        statusLabel: hasPhoto ? 'Photo captured' : 'Not recorded',
        statusColor: const Color(0xFF7A4A00),
        statusBgColor: const Color(0xFFFFEBC4),
        symptomsSummary: hasPhoto
            ? 'Tap to confirm the saved photo'
            : 'Tap to capture this seedling',
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
    final isInfested =
        plant.plant.plantStatus == DatabaseCodes.plantCurrentPositive;
    final isOld = plant.plant.plantStatus == DatabaseCodes.plantOldDamageOnly;

    final symptoms = <String>[
      if (plant.vegetative.larvaVisible)
        'Larva: ${plant.vegetative.larvalSize}',
      if (plant.vegetative.freshFrass) 'Fresh frass',
      if (plant.vegetative.cuttingOrTearing) 'Cutting/Tearing',
      if (plant.vegetative.smallFreshWindowpanes) 'Windowpanes',
    ];

    return CompactPlantAuditTile(
      position: position,
      itemLabel: 'Seedling',
      statusLabel: isInfested
          ? 'FAW Infested'
          : isOld
          ? 'Old damage'
          : 'Clean Seedling',
      statusColor: isInfested
          ? AppColors.severeSeverityRing
          : isOld
          ? const Color(0xFFB57400)
          : AppColors.highContrastGreen,
      statusBgColor: isInfested
          ? AppColors.severeSeverityBg
          : isOld
          ? const Color(0xFFFFF3D6)
          : const Color(0xFFDDF1E2),
      symptomsSummary: symptoms.isNotEmpty
          ? symptoms.join(' · ')
          : 'Healthy seedling · Normal stand',
      onTap: onTap,
    );
  }

  String _duration(int? milliseconds) => milliseconds == null
      ? 'Not recorded'
      : '${(milliseconds / 1000).toStringAsFixed(1)} s';

  Future<void> _confirmUnreviewedCompletion() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('Leave observations unconfirmed?'),
        content: const AppText(
          'Photos will be saved, but Cropwise has no image model yet. No findings will be created for these seedlings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            key: const Key('ve_v2_confirm_unreviewed_station_button'),
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('Complete station'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      widget.onCompleteWithoutManualConfirmation?.call();
    }
  }
}

class _VeSeedlingReviewCard extends StatelessWidget {
  const _VeSeedlingReviewCard({
    required this.position,
    required this.plant,
    required this.bundle,
    required this.presentation,
    required this.resolveFile,
    required this.onInspect,
    required this.onEdit,
  });

  final int position;
  final StationPlantRecord? plant;
  final EvidenceCaptureBundle? bundle;
  final VeV2AnalysisPresentation presentation;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(int position) onEdit;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('ve_review_seedling_$position'),
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  'Seedling $position',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => onEdit(position),
                child: Text(plant == null ? 'Review' : 'Correct'),
              ),
            ],
          ),
          Text(
            plant == null
                ? 'Needs confirmation'
                : _plantStatusLabel(plant!.plant.plantStatus),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (presentation.state != VeV2AnalysisState.unavailable)
            _AnalysisStatusLine(presentation: presentation),
          _VeEvidenceStrip(
            bundle: bundle,
            resolveFile: resolveFile,
            onInspect: onInspect,
          ),
        ],
      ),
    ),
  );
}

ReviewPositionState _veReviewPositionState({
  required StationPlantRecord? plant,
  required EvidenceCaptureBundle? bundle,
}) {
  if (plant?.plant.assessable == false) {
    return ReviewPositionState.notAssessable;
  }
  if (bundle?.waivedViewTypes.contains(
        DatabaseCodes.evidenceViewWholeSeedling,
      ) ==
      true) {
    return ReviewPositionState.fallback;
  }
  if (plant != null) return ReviewPositionState.confirmed;
  if (bundle == null ||
      !bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling)) {
    return ReviewPositionState.missing;
  }
  return ReviewPositionState.notReviewed;
}

class _AnalysisUnavailableBanner extends StatelessWidget {
  const _AnalysisUnavailableBanner();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF6EE),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_awesome, color: Color(0xFF176B3A)),
        SizedBox(width: 10),
        Expanded(
          child: AppText(
            'AI Computer Vision Active · Seedling status is analyzed from whole-seedling captures.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF176B3A),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AnalysisStatusLine extends StatelessWidget {
  const _AnalysisStatusLine({required this.presentation});
  final VeV2AnalysisPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (presentation.state) {
      VeV2AnalysisState.waiting => (Icons.schedule, 'Waiting for analysis'),
      VeV2AnalysisState.processing => (Icons.sync, 'Analysis in progress'),
      VeV2AnalysisState.suggestionsReady => (
        Icons.fact_check_outlined,
        'Suggestions ready for review',
      ),
      VeV2AnalysisState.insufficientEvidence => (
        Icons.photo_size_select_large_outlined,
        'Evidence insufficient',
      ),
      VeV2AnalysisState.unsupportedEvidence => (
        Icons.help_outline,
        'Evidence not supported by the model',
      ),
      VeV2AnalysisState.failed => (Icons.error_outline, 'Analysis failed'),
      VeV2AnalysisState.unavailable => (
        Icons.person_outline,
        'Manual confirmation required',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 5),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _EvidenceCaptureTasks extends StatelessWidget {
  const _EvidenceCaptureTasks({
    required this.views,
    required this.scopeLabel,
    required this.bundle,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onFallback,
  });

  final Set<String> views;
  final String scopeLabel;
  final EvidenceCaptureBundle bundle;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(String viewType) onCapture;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(EvidenceMediaRecord media) onAccept;
  final Future<void> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<void> Function(String view, String reason, String? note)
  onFallback;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) return const SizedBox.shrink();
    return Column(
      key: ValueKey('ve_evidence_tasks_$scopeLabel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WorkflowSectionHeader(
          title: 'Photos',
          subtitle: 'Capture the required view before continuing.',
        ),
        for (final view in views) ...[
          EvidenceCapturePanel(
            key: ValueKey('$scopeLabel-$view-${bundle.isViewSatisfied(view)}'),
            title: _viewTitle(view),
            instruction: _viewInstruction(view),
            scopeLabel: scopeLabel,
            viewType: view,
            bundle: bundle,
            resolveFile: resolveFile,
            onCapture: () => onCapture(view),
            onInspect: onInspect,
            onAccept: onAccept,
            onRetake: onRetake,
            onRemove: onRemove,
            onManualFallback: (reason, note) => onFallback(view, reason, note),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _VeEvidenceStrip extends StatelessWidget {
  const _VeEvidenceStrip({
    required this.bundle,
    required this.resolveFile,
    required this.onInspect,
  });
  final EvidenceCaptureBundle? bundle;
  final Future<File> Function(String uri) resolveFile;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;

  @override
  Widget build(BuildContext context) {
    final media =
        bundle?.media
            .where(
              (item) =>
                  item.deletedAt == null &&
                  item.storageState == DatabaseCodes.evidenceStorageReady,
            )
            .toList(growable: false) ??
        const <EvidenceMediaRecord>[];
    if (media.isEmpty) {
      if (bundle?.waivedViewTypes.isNotEmpty == true) {
        return const Padding(
          padding: EdgeInsets.only(top: 4),
          child: AppText('Photo fallback recorded'),
        );
      }
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in media)
            InkWell(
              onTap: () => onInspect(item),
              borderRadius: BorderRadius.circular(8),
              child: FutureBuilder<File>(
                future: resolveFile(item.thumbnailLocalUri ?? item.localUri),
                builder: (context, snapshot) => Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2ED),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: snapshot.hasData
                      ? Image.file(snapshot.data!, fit: BoxFit.cover)
                      : const Icon(Icons.photo_outlined),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

EvidenceCaptureBundle? _bundleForPlantPosition(
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

String _unitCaptureLabel(PlantingUnitObservationRecord unit) {
  if (unit.primaryCondition != null) {
    return _unitConditionLabel(unit.primaryCondition);
  }
  return switch (unit.occupancyStatus) {
    DatabaseCodes.veOccupancySeedling => 'Seedling recorded',
    DatabaseCodes.veOccupancyEmpty => 'Empty',
    DatabaseCodes.veOccupancyRemnant => 'Seedling remnant',
    DatabaseCodes.veOccupancyUncertain => 'Unsure',
    DatabaseCodes.veOccupancyNotAssessable => 'Cannot assess',
    _ => 'Recorded',
  };
}

String _unitConditionLabel(String? value) => switch (value) {
  DatabaseCodes.veUnitHealthy => 'Healthy',
  DatabaseCodes.veUnitFeedingInjury => 'Damaged',
  DatabaseCodes.veUnitCutSevered => 'Cut or severed',
  DatabaseCodes.veUnitWiltedDead => 'Wilted or dead',
  DatabaseCodes.veUnitEmptyUnexplained => 'Empty',
  DatabaseCodes.veUnitPositionUncertain => 'Unsure',
  DatabaseCodes.veUnitNotAssessable => 'Cannot assess',
  _ => 'Incomplete',
};

String _plantStatusLabel(String value) => switch (value) {
  DatabaseCodes.plantNegative => 'No current FAW evidence',
  DatabaseCodes.plantCurrentPositive => 'FAW-consistent evidence',
  DatabaseCodes.plantOldDamageOnly => 'Old damage only',
  DatabaseCodes.plantPossibleNonFaw => 'Possible other cause',
  DatabaseCodes.plantUncertain => 'Unsure',
  DatabaseCodes.plantNotAssessable => 'Cannot assess',
  _ => 'Needs review',
};

class _LabeledChoiceChips<T> extends StatelessWidget {
  const _LabeledChoiceChips({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice in choices.entries)
            ChoiceChip(
              label: Text(choice.value),
              selected: value == choice.key,
              onSelected: (_) => onChanged(choice.key),
            ),
        ],
      ),
    ],
  );
}

class _YesNoChoice extends StatelessWidget {
  const _YesNoChoice({required this.value, required this.onChanged});
  final bool? value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: true, label: AppText('Yes')),
      ButtonSegment(value: false, label: AppText('No')),
    ],
    selected: value == null ? {} : {value!},
    emptySelectionAllowed: true,
    onSelectionChanged: (values) => onChanged(values.first),
  );
}

class _EggChoice extends StatelessWidget {
  const _EggChoice({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      ChoiceChip(
        label: const AppText('Yes'),
        selected: value == 'yes',
        onSelected: (_) => onChanged('yes'),
      ),
      ChoiceChip(
        label: const AppText('No'),
        selected: value == 'no',
        onSelected: (_) => onChanged('no'),
      ),
      ChoiceChip(
        label: const AppText('Not collected'),
        selected: value == 'not_collected',
        onSelected: (_) => onChanged('not_collected'),
      ),
    ],
  );
}

class _BooleanRow extends StatelessWidget {
  const _BooleanRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      _YesNoChoice(value: value, onChanged: onChanged),
    ],
  );
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) =>
      FilterChip(label: Text(label), selected: value, onSelected: onChanged);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

String _viewTitle(String view) => switch (view) {
  DatabaseCodes.evidenceViewVePlantingPosition => 'Planting position',
  DatabaseCodes.evidenceViewWhorlOverview => 'Newest leaves & whorl',
  DatabaseCodes.evidenceViewWholeSeedling => 'Whole seedling',
  DatabaseCodes.evidenceViewStemBase => 'Stem base',
  DatabaseCodes.evidenceViewCloseUp => 'Close-up',
  DatabaseCodes.evidenceViewLarvaDorsal => 'Larva body',
  DatabaseCodes.evidenceViewLarvaHead => 'Larva head',
  _ => 'Evidence photo',
};

String _viewInstruction(String view) => switch (view) {
  DatabaseCodes.evidenceViewVePlantingPosition =>
    'Fill the frame with this planting spot.',
  DatabaseCodes.evidenceViewWhorlOverview =>
    'Expose the newest leaves and keep the whorl visible.',
  DatabaseCodes.evidenceViewWholeSeedling => 'Keep the whole seedling visible.',
  DatabaseCodes.evidenceViewStemBase => 'Show the stem at the soil line.',
  DatabaseCodes.evidenceViewCloseUp => 'Move close enough to show the detail.',
  DatabaseCodes.evidenceViewLarvaDorsal => 'Show the larva body safely.',
  DatabaseCodes.evidenceViewLarvaHead => 'Show the larva head safely.',
  _ => 'Show the relevant evidence.',
};
