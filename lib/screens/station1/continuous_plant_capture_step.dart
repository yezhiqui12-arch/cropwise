import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import 'evidence_capture_panel.dart';

class ContinuousPlantCaptureStep extends StatefulWidget {
  const ContinuousPlantCaptureStep({
    super.key,
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
  });

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

  @override
  State<ContinuousPlantCaptureStep> createState() =>
      _ContinuousPlantCaptureStepState();
}

class _ContinuousPlantCaptureStepState extends State<ContinuousPlantCaptureStep>
    with WidgetsBindingObserver {
  final Stopwatch _activeTimer = Stopwatch();
  bool? _assessable;
  int? _leavesInspected;
  bool _detailRequested = false;
  String? _validationMessage;

  bool get _captureStarted =>
      widget.bundle.media.isNotEmpty ||
      widget.bundle.waivedViewTypes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTimer.start();
    if (_captureStarted) _assessable = true;
    _leavesInspected = widget.initialLeavesInspectedCount;
    _detailRequested = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewDiagnosticDetail,
    );
  }

  @override
  void didUpdateWidget(covariant ContinuousPlantCaptureStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _activeTimer
        ..reset()
        ..start();
      _assessable = _captureStarted ? true : null;
      _leavesInspected = widget.initialLeavesInspectedCount;
      _detailRequested = widget.bundle.isViewSatisfied(
        DatabaseCodes.evidenceViewDiagnosticDetail,
      );
      _validationMessage = null;
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
    final overviewReady = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewWhorlOverview,
    );
    final closeReady = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewCloseUp,
    );
    final detailReady = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewDiagnosticDetail,
    );
    final currentView = !overviewReady
        ? DatabaseCodes.evidenceViewWhorlOverview
        : !closeReady
        ? DatabaseCodes.evidenceViewCloseUp
        : _detailRequested && !detailReady
        ? DatabaseCodes.evidenceViewDiagnosticDetail
        : null;
    final currentViewNumber = !overviewReady
        ? 1
        : !closeReady
        ? 2
        : 3;

    return Column(
      children: [
        _CaptureProgressHeader(
          position: widget.position,
          capturedPlantCount: widget.capturedPlantCount,
          currentViewNumber: currentViewNumber,
          requiredViewsComplete: overviewReady && closeReady,
          onHelp: () => _showHelp(context),
        ),
        Expanded(
          child: ListView(
            key: const Key('continuous_plant_capture_step'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text(
                'Inspect the newest three or four leaves and the whorl. Do not skip this position based on damage.',
                style: TextStyle(height: 1.35, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (_assessable == null) _buildAssessabilityChoice(),
              if (_assessable == true) ...[
                _buildLeafConfirmation(),
                const SizedBox(height: 12),
                if (currentView != null)
                  _buildEvidencePanel(currentView)
                else
                  _buildRequiredViewsComplete(detailReady),
              ],
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

  Widget _buildAssessabilityChoice() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Can this plant position be assessed?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('capture_assessable_yes'),
                  label: const Text('Assess plant'),
                  selected: false,
                  onSelected: widget.isSaving
                      ? null
                      : (_) => setState(() {
                          _assessable = true;
                          _validationMessage = null;
                        }),
                ),
                ActionChip(
                  key: const Key('capture_cannot_assess'),
                  avatar: const Icon(Icons.report_outlined),
                  label: const Text('Cannot assess'),
                  onPressed: widget.isSaving ? null : _recordCannotAssess,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeafConfirmation() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Newest leaves physically inspected',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('capture_leaves_3'),
              label: const Text('3'),
              selected: _leavesInspected == 3,
              onSelected: widget.isSaving
                  ? null
                  : (_) => _recordLeavesInspected(3),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              key: const Key('capture_leaves_4'),
              label: const Text('4'),
              selected: _leavesInspected == 4,
              onSelected: widget.isSaving
                  ? null
                  : (_) => _recordLeavesInspected(4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidencePanel(String viewType) {
    final (title, instruction) = switch (viewType) {
      DatabaseCodes.evidenceViewWhorlOverview => (
        'Required view 1 · Overview',
        'Frame the whole whorl and newest three or four leaves.',
      ),
      DatabaseCodes.evidenceViewCloseUp => (
        'Required view 2 · Whorl detail',
        'Move closer to the whorl interior or inspected feeding surface.',
      ),
      _ => (
        'Conditional view · Extra detail',
        'Frame the larva, egg mass, ambiguous sign, or feature that needs detail.',
      ),
    };
    final captureAllowed = _leavesInspected == 3 || _leavesInspected == 4;
    return IgnorePointer(
      ignoring: !captureAllowed || widget.isSaving,
      child: Opacity(
        opacity: captureAllowed ? 1 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!captureAllowed)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Confirm whether three or four newest leaves were inspected before photographing.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (viewType == DatabaseCodes.evidenceViewCloseUp)
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
      ),
    );
  }

  Widget _buildRequiredViewsComplete(bool detailReady) {
    if (_detailRequested && detailReady) {
      return _FinishCaptureCard(
        message: 'The two required views and conditional detail are accepted.',
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
            const Text(
              'Both required views accepted',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add one extra detail only for a larva, egg mass, ambiguous feature, or something the required views do not show clearly.',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('add_conditional_detail'),
              onPressed: widget.isSaving
                  ? null
                  : () => setState(() => _detailRequested = true),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add conditional detail'),
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
    if (_leavesInspected != 3 && _leavesInspected != 4) {
      setState(() {
        _validationMessage =
            'Confirm whether three or four newest leaves were inspected.';
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
    final completesPlant =
        viewType == DatabaseCodes.evidenceViewDiagnosticDetail ||
        (viewType == DatabaseCodes.evidenceViewCloseUp && !_detailRequested);
    if (completesPlant) await _completePlant();
  }

  Future<void> _recordLeavesInspected(int count) async {
    final previous = _leavesInspected;
    setState(() {
      _leavesInspected = count;
      _validationMessage = null;
    });
    try {
      await widget.onLeavesInspected(count);
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
    final controller = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plant ${widget.position} cannot be assessed',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Keep this position in the sequence and record the reason.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('capture_not_assessable_reason'),
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Missing, broken, or unsafe to reach',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('save_capture_not_assessable'),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Save position and continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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
      builder: (context) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Station 1 capture help',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Use ten consecutive plant positions in one row and direction. Never replace a position because it looks healthy, damaged, inconvenient, or difficult to photograph.',
                style: TextStyle(height: 1.45),
              ),
              SizedBox(height: 10),
              Text(
                'Gently expose the whorl. Inspect the newest three or four emerging leaves, then take an overview and a closer whorl view. Stop if photography would be unsafe.',
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
    required this.position,
    required this.capturedPlantCount,
    required this.currentViewNumber,
    required this.requiredViewsComplete,
    required this.onHelp,
  });

  final int position;
  final int capturedPlantCount;
  final int currentViewNumber;
  final bool requiredViewsComplete;
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
                    'Block 1 · Station 1 · Plant $position/10',
                    key: const Key('capture_plant_progress'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    requiredViewsComplete
                        ? '$capturedPlantCount of 10 plants captured · Required views ready'
                        : '$capturedPlantCount of 10 plants captured · Required view $currentViewNumber of 2',
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
