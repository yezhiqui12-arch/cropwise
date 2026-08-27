import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../data/services/stage_plant_save_service.dart';
import 'evidence_capture_panel.dart';

class LateSeasonSetupStep extends StatefulWidget {
  const LateSeasonSetupStep({
    super.key,
    required this.assessmentId,
    required this.evaluatorPersonId,
    required this.blockRunIds,
    required this.isSaving,
    required this.onSave,
  });

  final String assessmentId;
  final String evaluatorPersonId;
  final List<String> blockRunIds;
  final bool isSaving;
  final Future<void> Function(LateSeasonSetupInput input) onSave;

  @override
  State<LateSeasonSetupStep> createState() => _LateSeasonSetupStepState();
}

class _LateSeasonSetupStepState extends State<LateSeasonSetupStep> {
  String? _cropUse;
  bool? _harvestStarted;
  bool? _selectedEarsPartOfHarvest;
  String? _permission;
  String _designationRule = 'primary_or_uppermost_marketable_ear';
  String? _error;
  late final TextEditingController _maximum;
  late final TextEditingController _reason;
  late final TextEditingController _grantor;
  late final TextEditingController _remarks;

  @override
  void initState() {
    super.initState();
    _maximum = TextEditingController(text: '10');
    _reason = TextEditingController();
    _grantor = TextEditingController();
    _remarks = TextEditingController();
  }

  @override
  void dispose() {
    _maximum.dispose();
    _reason.dispose();
    _grantor.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('late_season_setup_step'),
    padding: const EdgeInsets.all(18),
    children: [
      const Text(
        'R3–R6 authorization and sampling plan',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Record this once before inspecting ears. External assessment continues even when opening permission is refused or unavailable.',
        style: TextStyle(height: 1.4),
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: const Key('late_crop_use'),
        initialValue: _cropUse,
        decoration: const InputDecoration(
          labelText: 'Crop use',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'grain', child: Text('Grain')),
          DropdownMenuItem(value: 'green_corn', child: Text('Green corn')),
          DropdownMenuItem(value: 'sweet_corn', child: Text('Sweet corn')),
          DropdownMenuItem(value: 'seed', child: Text('Seed')),
          DropdownMenuItem(value: 'silage', child: Text('Silage')),
          DropdownMenuItem(value: 'other', child: Text('Other')),
        ],
        onChanged: (value) => setState(() => _cropUse = value),
      ),
      const SizedBox(height: 14),
      _BinarySetupQuestion(
        label: 'Has commercial harvest started?',
        value: _harvestStarted,
        onChanged: (value) => setState(() => _harvestStarted = value),
      ),
      _BinarySetupQuestion(
        label: 'Are selected ears already part of harvest?',
        value: _selectedEarsPartOfHarvest,
        onChanged: (value) =>
            setState(() => _selectedEarsPartOfHarvest = value),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: const Key('late_opening_permission'),
        initialValue: _permission,
        decoration: const InputDecoration(
          labelText: 'Permission to open ears',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: DatabaseCodes.openingPermissionGranted,
            child: Text('Granted'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.openingPermissionRefused,
            child: Text('Refused'),
          ),
          DropdownMenuItem(
            value: DatabaseCodes.openingPermissionUnavailable,
            child: Text('Not available'),
          ),
        ],
        onChanged: (value) => setState(() {
          _permission = value;
          if (value != DatabaseCodes.openingPermissionGranted) {
            _maximum.text = '0';
          } else if (_maximum.text == '0') {
            _maximum.text = '10';
          }
        }),
      ),
      if (_permission == DatabaseCodes.openingPermissionGranted) ...[
        const SizedBox(height: 14),
        TextField(
          key: const Key('late_maximum_ears'),
          controller: _maximum,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Maximum ears permitted to open',
            helperText: 'The provisional standard sample is 2 per station.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('late_opening_reason'),
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Reason for opening',
            hintText: 'Severity documentation, expert validation, research…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('late_permission_grantor'),
          controller: _grantor,
          decoration: const InputDecoration(
            labelText: 'Person granting permission',
            border: OutlineInputBorder(),
          ),
        ),
      ],
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: const Key('late_ear_designation_rule'),
        initialValue: _designationRule,
        decoration: const InputDecoration(
          labelText: 'Designated-ear rule',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'primary_or_uppermost_marketable_ear',
            child: Text('Primary / uppermost marketable ear'),
          ),
          DropdownMenuItem(value: 'primary_ear', child: Text('Primary ear')),
          DropdownMenuItem(
            value: 'uppermost_ear',
            child: Text('Uppermost ear'),
          ),
        ],
        onChanged: (value) => setState(() => _designationRule = value!),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _remarks,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Authorization remarks (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      if (_permission != DatabaseCodes.openingPermissionGranted) ...[
        const SizedBox(height: 12),
        const Card(
          color: Color(0xFFFFF3CD),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Internal kernel condition will remain “not assessed”; it will never be stored as zero damage.',
            ),
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Color(0xFF9D241F))),
      ],
      const SizedBox(height: 18),
      FilledButton(
        key: const Key('save_late_season_setup'),
        onPressed: widget.isSaving ? null : _save,
        child: Text(
          widget.isSaving ? 'Saving…' : 'Lock authorization and plan',
        ),
      ),
    ],
  );

  Future<void> _save() async {
    final maximum = int.tryParse(_maximum.text.trim());
    if (_cropUse == null ||
        _harvestStarted == null ||
        _selectedEarsPartOfHarvest == null ||
        _permission == null) {
      setState(() => _error = 'Complete every authorization question.');
      return;
    }
    if (_permission == DatabaseCodes.openingPermissionGranted &&
        (maximum == null ||
            maximum <= 0 ||
            _reason.text.trim().isEmpty ||
            _grantor.text.trim().isEmpty)) {
      setState(
        () => _error =
            'Granted permission requires a positive maximum, reason, and grantor.',
      );
      return;
    }
    await widget.onSave(
      LateSeasonSetupInput(
        assessmentId: widget.assessmentId,
        cropUse: _cropUse!,
        commercialHarvestStarted: _harvestStarted!,
        selectedEarsPartOfHarvest: _selectedEarsPartOfHarvest!,
        openingPermission: _permission!,
        maximumEarsPermitted:
            _permission == DatabaseCodes.openingPermissionGranted
            ? maximum!
            : 0,
        openingReason: _permission == DatabaseCodes.openingPermissionGranted
            ? _reason.text.trim()
            : null,
        permissionGrantedBy:
            _permission == DatabaseCodes.openingPermissionGranted
            ? _grantor.text.trim()
            : null,
        evaluatorPersonId: widget.evaluatorPersonId,
        permissionRecordedAt: DateTime.now().toUtc(),
        earDesignationRule: _designationRule,
        remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        blockRunIds: widget.blockRunIds,
      ),
    );
  }
}

class _BinarySetupQuestion extends StatelessWidget {
  const _BinarySetupQuestion({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Yes'),
            selected: value == true,
            onSelected: (_) => onChanged(true),
          ),
          ChoiceChip(
            label: const Text('No'),
            selected: value == false,
            onSelected: (_) => onChanged(false),
          ),
        ],
      ),
    ],
  );
}

class OpenedEarEntryStep extends StatefulWidget {
  const OpenedEarEntryStep({
    super.key,
    required this.selection,
    required this.plant,
    required this.evidence,
    required this.actorPersonId,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onSave,
  });

  final EarOpeningSelectionRecord selection;
  final StationPlantRecord plant;
  final EvidenceCaptureBundle evidence;
  final String actorPersonId;
  final bool isSaving;
  final Future<File> Function(String localUri) resolveFile;
  final Future<void> Function(String viewType) onCapture;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(EvidenceMediaRecord media) onAccept;
  final Future<void> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<void> Function(String viewType, String reason, String? note)
  onManualFallback;
  final Future<void> Function(OpenedEarSave input) onSave;

  @override
  State<OpenedEarEntryStep> createState() => _OpenedEarEntryStepState();
}

class _OpenedEarEntryStepState extends State<OpenedEarEntryStep> {
  bool? _huskIntact;
  bool? _internalDamage;
  bool? _cobDamage;
  bool? _unclearKernels;
  bool? _earRot;
  String? _classification;
  String? _evidenceReview;
  String? _error;
  late final TextEditingController _totalKernels;
  late final TextEditingController _damagedKernels;
  late final TextEditingController _kernelMethod;
  late final TextEditingController _tipLength;
  late final TextEditingController _rotKernels;
  late final TextEditingController _rotType;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final ear = widget.plant.ear!;
    _huskIntact = ear.huskIntactBeforeOpening;
    _internalDamage = ear.internalDamagePresent;
    _cobDamage = ear.cobDamagePresent;
    _unclearKernels = ear.brokenMissingUnderdevelopedKernels;
    _earRot = ear.earRotPresent;
    _classification = ear.internalClassification;
    _totalKernels = TextEditingController(
      text: ear.totalKernelsCounted?.toString() ?? '',
    );
    _damagedKernels = TextEditingController(
      text: ear.damagedKernelsCounted?.toString() ?? '',
    );
    _kernelMethod = TextEditingController(text: ear.kernelCountMethod ?? '');
    _tipLength = TextEditingController(
      text: ear.earTipDamageLengthMm?.toString() ?? '',
    );
    _rotKernels = TextEditingController(
      text: ear.moldRotKernelsCounted?.toString() ?? '',
    );
    _rotType = TextEditingController(text: ear.earRotSuspectedType ?? '');
    _notes = TextEditingController(text: ear.notes ?? '');
  }

  @override
  void dispose() {
    _totalKernels.dispose();
    _damagedKernels.dispose();
    _kernelMethod.dispose();
    _tipLength.dispose();
    _rotKernels.dispose();
    _rotType.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: const Color(0xFFF3F8F4),
        child: ListTile(
          title: Text(
            'Opened ear · Plant ${widget.selection.plantPosition}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            widget.selection.initiallySelected
                ? 'Preselected before damage inspection'
                : 'Replacement for Plant ${widget.selection.replacesPlantPosition}',
          ),
        ),
      ),
      Expanded(
        child: ListView(
          key: const Key('opened_ear_entry_step'),
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Capture the intact ear before husk removal. Then open it, photograph one side, rotate it, and photograph the opposite side.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _OpenedEarEvidencePanel(
              title: '1 · Whole ear before opening',
              instruction: 'Show the entire designated ear with husk intact.',
              viewType: DatabaseCodes.evidenceViewWholeEarBeforeOpening,
              widget: widget,
            ),
            const SizedBox(height: 12),
            _OpenedEarEvidencePanel(
              title: '2 · Opened ear, first side',
              instruction: 'Show the full exposed kernel surface on one side.',
              viewType: DatabaseCodes.evidenceViewOpenedEarSideA,
              widget: widget,
            ),
            const SizedBox(height: 12),
            _OpenedEarEvidencePanel(
              title: '3 · Opened ear, opposite side',
              instruction:
                  'Rotate the ear and show the opposite kernel surface.',
              viewType: DatabaseCodes.evidenceViewOpenedEarSideB,
              widget: widget,
            ),
            const SizedBox(height: 18),
            _OpenedBool(
              label: 'Was the husk intact before opening?',
              value: _huskIntact,
              onChanged: (value) => setState(() => _huskIntact = value),
            ),
            _OpenedBool(
              label: 'Internal feeding damage present?',
              value: _internalDamage,
              onChanged: (value) => setState(() => _internalDamage = value),
            ),
            _OpenedBool(
              label: 'Cob damage present?',
              value: _cobDamage,
              onChanged: (value) => setState(() => _cobDamage = value),
            ),
            _OpenedBool(
              label:
                  'Broken, missing, or underdeveloped kernels with unclear cause?',
              value: _unclearKernels,
              onChanged: (value) => setState(() => _unclearKernels = value),
            ),
            const SizedBox(height: 12),
            const Text(
              'Kernel counts (optional; enter both only when the denominator is reliable)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('opened_damaged_kernels'),
                    controller: _damagedKernels,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Damaged',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('opened_total_kernels'),
                    controller: _totalKernels,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total assessable',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _kernelMethod,
              decoration: const InputDecoration(
                labelText:
                    'Kernel count method/reference (required with counts)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tipLength,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ear-tip damage length in mm (only with reference)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            _OpenedBool(
              label: 'Mold or rot present?',
              value: _earRot,
              onChanged: (value) => setState(() => _earRot = value),
            ),
            if (_earRot == true) ...[
              TextField(
                controller: _rotKernels,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mold/rot kernel count (if countable)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _rotType,
                decoration: const InputDecoration(
                  labelText: 'Suspected mold/rot type (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('opened_internal_classification'),
              initialValue: _classification,
              decoration: const InputDecoration(
                labelText: 'Internal classification',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: DatabaseCodes.earInternalConfirmedFaw,
                  child: Text('Confirmed FAW'),
                ),
                DropdownMenuItem(
                  value: DatabaseCodes.earInternalFawConsistent,
                  child: Text('FAW-consistent'),
                ),
                DropdownMenuItem(
                  value: DatabaseCodes.earInternalOtherPest,
                  child: Text('Other pest'),
                ),
                DropdownMenuItem(
                  value: DatabaseCodes.earInternalNonPest,
                  child: Text('Likely non-pest'),
                ),
                DropdownMenuItem(
                  value: DatabaseCodes.earInternalUncertain,
                  child: Text('Uncertain'),
                ),
              ],
              onChanged: (value) => setState(() => _classification = value),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('opened_evidence_review'),
              initialValue: _evidenceReview,
              decoration: const InputDecoration(
                labelText: 'Three-view evidence review',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: DatabaseCodes.evidenceReviewSufficient,
                  child: Text('Sufficient to confirm'),
                ),
                DropdownMenuItem(
                  value: DatabaseCodes.evidenceReviewInsufficient,
                  child: Text('Insufficient—retake needed'),
                ),
              ],
              onChanged: (value) => setState(() => _evidenceReview = value),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Opened-ear notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Color(0xFF9D241F))),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('save_opened_ear'),
                onPressed: widget.isSaving ? null : _save,
                child: Text(widget.isSaving ? 'Saving…' : 'Save opened ear'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _save() async {
    final total = _optionalInt(_totalKernels.text);
    final damaged = _optionalInt(_damagedKernels.text);
    if (_huskIntact == null ||
        _internalDamage == null ||
        _cobDamage == null ||
        _unclearKernels == null ||
        _earRot == null ||
        _classification == null) {
      setState(() => _error = 'Complete every opened-ear observation.');
      return;
    }
    if ((total == null) != (damaged == null) ||
        (total != null &&
            (total <= 0 ||
                damaged! < 0 ||
                damaged > total ||
                _kernelMethod.text.trim().isEmpty))) {
      setState(
        () => _error =
            'Enter both valid kernel counts and the count method, or leave all three blank.',
      );
      return;
    }
    if (_evidenceReview != DatabaseCodes.evidenceReviewSufficient) {
      setState(
        () =>
            _error = 'Confirm that all three opened-ear views are sufficient.',
      );
      return;
    }
    for (final view in const {
      DatabaseCodes.evidenceViewWholeEarBeforeOpening,
      DatabaseCodes.evidenceViewOpenedEarSideA,
      DatabaseCodes.evidenceViewOpenedEarSideB,
    }) {
      if (!widget.evidence.isViewSatisfied(view)) {
        setState(() => _error = 'Capture or document fallback for $view.');
        return;
      }
    }
    await widget.onSave(
      OpenedEarSave(
        earObservationId: widget.plant.ear!.id,
        selectionId: widget.selection.id,
        huskIntactBeforeOpening: _huskIntact!,
        internalDamagePresent: _internalDamage!,
        totalKernelsCounted: total,
        damagedKernelsCounted: damaged,
        kernelCountMethod: total == null ? null : _kernelMethod.text.trim(),
        earTipDamageLengthMm: double.tryParse(_tipLength.text.trim()),
        cobDamagePresent: _cobDamage!,
        brokenMissingUnderdevelopedKernels: _unclearKernels!,
        earRotPresent: _earRot!,
        moldRotKernelsCounted: _optionalInt(_rotKernels.text),
        earRotSuspectedType: _rotType.text.trim().isEmpty
            ? null
            : _rotType.text.trim(),
        internalClassification: _classification!,
        evidenceCaptureSessionId: widget.evidence.session.id,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        actorPersonId: widget.actorPersonId,
      ),
    );
  }

  int? _optionalInt(String value) =>
      value.trim().isEmpty ? null : int.tryParse(value.trim());
}

class _OpenedEarEvidencePanel extends StatelessWidget {
  const _OpenedEarEvidencePanel({
    required this.title,
    required this.instruction,
    required this.viewType,
    required this.widget,
  });
  final String title;
  final String instruction;
  final String viewType;
  final OpenedEarEntryStep widget;
  @override
  Widget build(BuildContext context) => EvidenceCapturePanel(
    title: title,
    scopeLabel: 'Plant ${widget.selection.plantPosition}',
    instruction: instruction,
    viewType: viewType,
    bundle: widget.evidence,
    resolveFile: widget.resolveFile,
    onCapture: () => widget.onCapture(viewType),
    onInspect: widget.onInspect,
    onAccept: widget.onAccept,
    onRetake: widget.onRetake,
    onRemove: widget.onRemove,
    onManualFallback: (reason, note) =>
        widget.onManualFallback(viewType, reason, note),
  );
}

class _OpenedBool extends StatelessWidget {
  const _OpenedBool({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Yes'),
            selected: value == true,
            onSelected: (_) => onChanged(true),
          ),
          ChoiceChip(
            label: const Text('No'),
            selected: value == false,
            onSelected: (_) => onChanged(false),
          ),
        ],
      ),
    ],
  );
}
