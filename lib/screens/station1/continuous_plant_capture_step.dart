import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../../services/station_evidence_policy.dart';
import 'evidence_capture_panel.dart';

class ContinuousPlantCaptureStep extends StatefulWidget {
  const ContinuousPlantCaptureStep({
    super.key,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.evidencePolicy = StationEvidencePolicy.station1TwoView,
    required this.position,
    required this.capturedPlantCount,
    required this.initialLeavesInspectedCount,
    required this.bundle,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onLeavesInspected,
    required this.onCompletePlant,
    required this.onCannotAssess,
    this.onMarkAllHealthy,
    this.cvDiagnosis,
  });

  final int blockNumber;
  final int stationNumber;
  final StationEvidencePolicy evidencePolicy;
  final int position;
  final int capturedPlantCount;
  final int? initialLeavesInspectedCount;
  final EvidenceCaptureBundle bundle;
  final bool isSaving;
  final Future<File> Function(String localUri) resolveFile;
  final Future<String?> Function(String viewType) onCapture;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<bool> Function(EvidenceMediaRecord media) onAccept;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<bool> Function(String viewType, String reason, String? note)
  onManualFallback;
  final Future<void> Function(int newestLeavesInspectedCount) onLeavesInspected;
  final Future<void> Function(
    Duration activeDuration,
    int newestLeavesInspectedCount,
  )
  onCompletePlant;
  final Future<void> Function(String reason, Duration activeDuration)
  onCannotAssess;
  final VoidCallback? onMarkAllHealthy;
  final PlantDiagnosisResult? cvDiagnosis;

  @override
  State<ContinuousPlantCaptureStep> createState() =>
      _ContinuousPlantCaptureStepState();
}

class _ContinuousPlantCaptureStepState extends State<ContinuousPlantCaptureStep>
    with WidgetsBindingObserver {
  final Stopwatch _activeTimer = Stopwatch();
  int? _leavesInspected;
  bool _detailRequested = false;
  bool _cameraOpenedForPosition = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTimer.start();
    _leavesInspected = widget.initialLeavesInspectedCount;
    _detailRequested = widget.bundle.isViewSatisfied(
      widget.evidencePolicy == StationEvidencePolicy.station1TwoView
          ? DatabaseCodes.evidenceViewDiagnosticDetail
          : DatabaseCodes.evidenceViewCloseUp,
    );
    if (widget.bundle.media.isEmpty && widget.bundle.waivedViewTypes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPlantCamera());
    }
  }

  @override
  void didUpdateWidget(covariant ContinuousPlantCaptureStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _activeTimer
        ..reset()
        ..start();
      _leavesInspected = widget.initialLeavesInspectedCount;
      _detailRequested = widget.bundle.isViewSatisfied(
        widget.evidencePolicy == StationEvidencePolicy.station1TwoView
            ? DatabaseCodes.evidenceViewDiagnosticDetail
            : DatabaseCodes.evidenceViewCloseUp,
      );
      _cameraOpenedForPosition = false;
      _validationMessage = null;
      if (widget.bundle.media.isEmpty &&
          widget.bundle.waivedViewTypes.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openPlantCamera());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _activeTimer.start();
    } else {
      _activeTimer.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeTimer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesLegacyTwoView =
        widget.evidencePolicy == StationEvidencePolicy.station1TwoView;
    final overviewReady = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewWhorlOverview,
    );
    final closeReady = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewCloseUp,
    );
    final detailReady = widget.bundle.isViewSatisfied(
      usesLegacyTwoView
          ? DatabaseCodes.evidenceViewDiagnosticDetail
          : DatabaseCodes.evidenceViewCloseUp,
    );
    final currentView = !overviewReady
        ? DatabaseCodes.evidenceViewWhorlOverview
        : usesLegacyTwoView && !closeReady
        ? DatabaseCodes.evidenceViewCloseUp
        : _detailRequested && !detailReady
        ? usesLegacyTwoView
              ? DatabaseCodes.evidenceViewDiagnosticDetail
              : DatabaseCodes.evidenceViewCloseUp
        : null;
    final currentViewNumber = !overviewReady
        ? 1
        : !closeReady
        ? 2
        : 3;

    return Column(
      children: [
        _CaptureProgressHeader(
          blockNumber: widget.blockNumber,
          stationNumber: widget.stationNumber,
          position: widget.position,
          capturedPlantCount: widget.capturedPlantCount,
          currentViewNumber: currentViewNumber,
          requiredViewsComplete:
              overviewReady && (!usesLegacyTwoView || closeReady),
          requiredViewCount: usesLegacyTwoView ? 2 : 1,
          onHelp: () => _showHelp(context),
        ),
        Expanded(
          child: ListView(
            key: const Key('continuous_plant_capture_step'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text(
                'Inspect the newest leaves and whorl, then take the photo.',
                style: TextStyle(height: 1.35, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (widget.cvDiagnosis != null) ...[
                _CvDiagnosisCard(diagnosis: widget.cvDiagnosis!),
                const SizedBox(height: 8),
              ],
              if (currentView != null)
                _buildEvidencePanel(currentView)
              else
                _buildRequiredViewsComplete(
                  detailReady,
                  usesLegacyTwoView: usesLegacyTwoView,
                ),
              if (widget.onMarkAllHealthy != null && widget.position == 1) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('mark_all_healthy_button'),
                  onPressed: widget.isSaving ? null : widget.onMarkAllHealthy,
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF176B3A),
                  ),
                  label: const Text('All 10 Plants Clean (1-Tap Shortcut)'),
                ),
              ],
              TextButton.icon(
                key: const Key('capture_cannot_assess'),
                onPressed: widget.isSaving ? null : _recordCannotAssess,
                icon: const Icon(Icons.report_outlined),
                label: const Text('Cannot assess this position'),
              ),
              if (_validationMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _validationMessage!,
                  key: const Key('capture_validation_message'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEvidencePanel(String viewType) {
    final (title, instruction) = switch (viewType) {
      DatabaseCodes.evidenceViewWhorlOverview => (
        'Plant photo',
        'Keep the newest leaves and whorl clearly in the frame.',
      ),
      DatabaseCodes.evidenceViewCloseUp => (
        widget.evidencePolicy == StationEvidencePolicy.station1TwoView
            ? 'Required view 2 · Whorl detail'
            : 'Conditional close-up',
        'Move closer when damage, a larva, egg mass, non-FAW evidence, uncertainty, or inadequate overview detail needs it.',
      ),
      _ => (
        'Conditional view · Extra detail',
        'Frame the larva, egg mass, ambiguous sign, or feature that needs detail.',
      ),
    };
    return IgnorePointer(
      ignoring: widget.isSaving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (viewType == DatabaseCodes.evidenceViewCloseUp &&
              widget.evidencePolicy == StationEvidencePolicy.station1TwoView)
            CheckboxListTile(
              key: const Key('conditional_detail_requested'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _detailRequested,
              onChanged: widget.isSaving
                  ? null
                  : (value) =>
                        setState(() => _detailRequested = value ?? false),
              title: const Text('This plant needs one extra detail photo'),
              subtitle: const Text(
                'Use only for a larva, egg mass, or ambiguous feature.',
              ),
            ),
          EvidenceCapturePanel(
            title: title,
            scopeLabel: 'Plant ${widget.position}',
            instruction: instruction,
            viewType: viewType,
            bundle: widget.bundle,
            resolveFile: widget.resolveFile,
            onCapture: () => _captureAndMaybeAdvance(viewType),
            onInspect: _inspectAndMaybeAdvance,
            onAccept: _acceptAndMaybeAdvance,
            onRetake: _retakeAndMaybeAdvance,
            onRemove: widget.onRemove,
            onManualFallback: (reason, note) =>
                _fallbackAndMaybeAdvance(viewType, reason, note),
          ),
        ],
      ),
    );
  }

  Widget _buildRequiredViewsComplete(
    bool detailReady, {
    required bool usesLegacyTwoView,
  }) {
    if (_detailRequested && detailReady) {
      return _FinishCaptureCard(
        message: usesLegacyTwoView
            ? 'The two required views and conditional detail are accepted.'
            : 'The required overview and conditional close-up are accepted.',
        actionLabel: 'Finish Plant ${widget.position}',
        actionKey: const Key('finish_plant_capture'),
        isSaving: widget.isSaving,
        onPressed: _completePlant,
      );
    }
    return Card(
      key: const Key('conditional_detail_choice'),
      elevation: 0,
      color: const Color(0xFFEAF6EE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              usesLegacyTwoView
                  ? 'Both required views accepted'
                  : 'Required overview accepted',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a close-up only when damage, a larva, egg mass, non-FAW evidence, uncertainty, or inadequate overview detail needs it.',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('add_conditional_close_up'),
              onPressed: widget.isSaving
                  ? null
                  : () => setState(() => _detailRequested = true),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add close-up'),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton.icon(
                key: const Key('next_plant_after_capture'),
                onPressed: widget.isSaving ? null : _completePlant,
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  widget.position == 10
                      ? 'Open Station Review'
                      : 'Continue to Plant ${widget.position + 1}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completePlant() async {
    if (_leavesInspected != 3 &&
        _leavesInspected != 4 &&
        widget.bundle.isViewSatisfied(
          DatabaseCodes.evidenceViewWhorlOverview,
        )) {
      await _recordLeavesInspected(3);
    }
    if (_leavesInspected != 3 && _leavesInspected != 4) {
      setState(() {
        _validationMessage = 'Complete the guided plant photo or fallback.';
      });
      return;
    }
    _activeTimer.stop();
    try {
      await widget.onCompletePlant(_activeTimer.elapsed, _leavesInspected!);
    } catch (_) {
      _activeTimer.start();
    }
  }

  Future<void> _captureAndMaybeAdvance(String viewType) async {
    final acceptedView = await widget.onCapture(viewType);
    await _advanceAfterAcceptedView(acceptedView);
  }

  Future<void> _openPlantCamera() async {
    if (!mounted || _cameraOpenedForPosition || widget.isSaving) return;
    _cameraOpenedForPosition = true;
    await _captureAndMaybeAdvance(DatabaseCodes.evidenceViewWhorlOverview);
  }

  Future<void> _inspectAndMaybeAdvance(EvidenceMediaRecord media) async {
    final acceptedView = await widget.onInspect(media);
    await _advanceAfterAcceptedView(acceptedView);
  }

  Future<void> _acceptAndMaybeAdvance(EvidenceMediaRecord media) async {
    final accepted = await widget.onAccept(media);
    if (accepted) await _advanceAfterAcceptedView(media.viewType);
  }

  Future<void> _retakeAndMaybeAdvance(EvidenceMediaRecord media) async {
    final acceptedView = await widget.onRetake(media);
    await _advanceAfterAcceptedView(acceptedView);
  }

  Future<void> _fallbackAndMaybeAdvance(
    String viewType,
    String reason,
    String? note,
  ) async {
    final saved = await widget.onManualFallback(viewType, reason, note);
    if (saved) await _advanceAfterAcceptedView(viewType);
  }

  Future<void> _advanceAfterAcceptedView(String? viewType) async {
    if (!mounted || viewType == null) return;
    if (viewType == DatabaseCodes.evidenceViewWhorlOverview) {
      await _recordLeavesInspected(3);
      if (_leavesInspected != 3 && _leavesInspected != 4) return;
    }
    // Keep the evaluator on this plant after accepting evidence. The rebuilt
    // capture step presents the accepted photo, optional detail capture, and
    // an explicit Continue action instead of advancing automatically.
  }

  Future<void> _recordLeavesInspected(int? count) async {
    final previous = _leavesInspected;
    setState(() {
      _leavesInspected = count;
      _validationMessage = null;
    });
    try {
      if (count != null) await widget.onLeavesInspected(count);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leavesInspected = previous;
        _validationMessage =
            'The inspection confirmation was not saved. Try again.';
      });
    }
  }

  Future<void> _recordCannotAssess() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plant ${widget.position} cannot be assessed',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Choose a reason to continue.'),
              const SizedBox(height: 12),
              for (final reason in const [
                'Plant missing',
                'Unsafe to reach',
                'Required plant area cannot be inspected',
                'Other',
              ])
                ListTile(
                  minTileHeight: 52,
                  title: Text(reason),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, reason),
                ),
            ],
          ),
        ),
      ),
    );
    if (reason == null || !mounted) return;
    _activeTimer.stop();
    try {
      await widget.onCannotAssess(reason, _activeTimer.elapsed);
    } catch (_) {
      _activeTimer.start();
    }
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Station ${widget.stationNumber} capture help',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Use ten consecutive plant positions in one row and direction. Never replace a position because it looks healthy, damaged, inconvenient, or difficult to photograph.',
                style: TextStyle(height: 1.45),
              ),
              SizedBox(height: 10),
              Text(
                widget.evidencePolicy == StationEvidencePolicy.station1TwoView
                    ? 'Gently expose the whorl. Inspect the newest three or four emerging leaves, then take the two views required by this older Station 1 evidence record.'
                    : 'Gently expose the whorl. Inspect the newest three or four emerging leaves, then take one guided overview. Add a close-up only when relevant evidence or inadequate overview detail needs it. Stop if photography would be unsafe.',
                style: TextStyle(height: 1.45),
              ),
              SizedBox(height: 10),
              Text(
                'WormWise has no validated image model. Photographs support the record, but every plant still needs evaluator-completed observations in Station Review.',
                style: TextStyle(height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureProgressHeader extends StatelessWidget {
  const _CaptureProgressHeader({
    required this.blockNumber,
    required this.stationNumber,
    required this.position,
    required this.capturedPlantCount,
    required this.currentViewNumber,
    required this.requiredViewsComplete,
    required this.requiredViewCount,
    required this.onHelp,
  });

  final int blockNumber;
  final int stationNumber;
  final int position;
  final int capturedPlantCount;
  final int currentViewNumber;
  final bool requiredViewsComplete;
  final int requiredViewCount;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F8F4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Block $blockNumber · Station $stationNumber · Plant $position/10',
                    key: const Key('capture_plant_progress'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    requiredViewsComplete
                        ? '$capturedPlantCount of 10 plants captured · Required views ready'
                        : '$capturedPlantCount of 10 plants captured · Required view $currentViewNumber of $requiredViewCount',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: capturedPlantCount / 10),
                ],
              ),
            ),
            IconButton(
              key: const Key('capture_help_button'),
              tooltip: 'Station capture help',
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishCaptureCard extends StatelessWidget {
  const _FinishCaptureCard({
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.isSaving,
    required this.onPressed,
  });

  final String message;
  final String actionLabel;
  final Key actionKey;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFEAF6EE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton(
                key: actionKey,
                onPressed: isSaving ? null : onPressed,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CvDiagnosisCard extends StatelessWidget {
  const _CvDiagnosisCard({required this.diagnosis});

  final PlantDiagnosisResult diagnosis;

  @override
  Widget build(BuildContext context) {
    final isInfested = diagnosis.isInfested;
    final color = isInfested
        ? const Color(0xFFB3261E)
        : const Color(0xFF176B3A);
    final bgColor = isInfested
        ? const Color(0xFFFDE8E8)
        : const Color(0xFFEAF6EE);

    return Card(
      elevation: 0,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isInfested ? Icons.bug_report_outlined : Icons.verified_outlined,
              color: color,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AI: ${diagnosis.pestLabel}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${(diagnosis.confidenceScore * 100).toInt()}% conf',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isInfested
                        ? 'Damage grade: ${diagnosis.davisDamageGrade}/9 · FAW symptoms detected'
                        : 'No FAW damage detected on newest leaves.',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
