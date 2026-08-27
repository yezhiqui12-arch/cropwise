import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../data/services/stage_plant_save_service.dart';
import 'evidence_capture_panel.dart';

typedef CaptureEvidence = Future<void> Function(String viewType);
typedef InspectEvidence = Future<void> Function(EvidenceMediaRecord media);
typedef ChangeEvidence = Future<void> Function(EvidenceMediaRecord media);
typedef ManualEvidenceFallback =
    Future<void> Function(String viewType, String reasonCode, String? note);

class ReproductivePlantObservationStep extends StatefulWidget {
  const ReproductivePlantObservationStep({
    super.key,
    required this.position,
    required this.blockNumber,
    required this.stationNumber,
    required this.stationId,
    required this.actorPersonId,
    required this.existing,
    required this.isSaving,
    required this.onSave,
    required this.evidence,
    required this.resolveEvidenceFile,
    required this.onCaptureEvidence,
    required this.onInspectEvidence,
    required this.onAcceptEvidence,
    required this.onRetakeEvidence,
    required this.onRemoveEvidence,
    required this.onManualFallback,
  });

  final int position;
  final int blockNumber;
  final int stationNumber;
  final String stationId;
  final String actorPersonId;
  final StationPlantRecord? existing;
  final bool isSaving;
  final Future<void> Function(
    ReproductivePlantSave input,
    String evidenceReviewStatus,
  )
  onSave;
  final EvidenceCaptureBundle? evidence;
  final Future<File> Function(String localUri) resolveEvidenceFile;
  final CaptureEvidence onCaptureEvidence;
  final InspectEvidence onInspectEvidence;
  final ChangeEvidence onAcceptEvidence;
  final ChangeEvidence onRetakeEvidence;
  final ChangeEvidence onRemoveEvidence;
  final ManualEvidenceFallback onManualFallback;

  @override
  State<ReproductivePlantObservationStep> createState() =>
      _ReproductivePlantObservationStepState();
}

class _ReproductivePlantObservationStepState
    extends State<ReproductivePlantObservationStep> {
  bool? _assessable;
  bool _tassel = false;
  bool _earBase = false;
  bool _upperAxil = false;
  bool _lowerAxil = false;
  bool? _freshFeeding;
  bool? _frass;
  bool? _penetration;
  bool? _larva;
  int? _larvaCount;
  String? _larvalSize;
  bool? _possibleNonFaw;
  bool? _uncertain;
  String? _naturalEnemy;
  String? _classification;
  String? _evidenceReview;
  final Set<String> _causeTags = {};
  String? _error;
  late final TextEditingController _reason;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final observation = existing?.reproductive;
    _reason = TextEditingController(text: existing?.plant.notAssessableReason);
    _notes = TextEditingController(text: existing?.plant.evaluatorNotes);
    if (existing != null && observation != null) {
      _assessable = existing.plant.assessable;
      _tassel = observation.tasselExamined;
      _earBase = observation.earBaseExamined;
      _upperAxil = observation.upperAxilExamined;
      _lowerAxil = observation.lowerAxilExamined;
      _freshFeeding = observation.freshFeedingPresent;
      _frass = observation.frassPresent;
      _penetration = observation.earHuskPenetrationVisible;
      _larva = observation.larvaPresent;
      _larvaCount = observation.larvaCount;
      _larvalSize = observation.larvalSize;
      _possibleNonFaw = observation.possibleNonFawEvidence;
      _uncertain = observation.uncertainEvidence;
      _naturalEnemy = existing.plant.naturalEnemyQuickStatus;
      _classification = observation.classification;
      _causeTags.addAll(_decodeTags(observation.causeTagsJson));
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StageFormScaffold(
    title: 'VT–R2 · Plant ${widget.position} of 10',
    subtitle: 'Block ${widget.blockNumber} · Station ${widget.stationNumber}',
    isSaving: widget.isSaving,
    error: _error,
    onSave: _save,
    children: [
      const _ProtocolReminder(
        text:
            'Use the ladder route. Examine the tassel, developing ear base, and the axils immediately above and below the ear.',
      ),
      _StageChoice<bool>(
        label: 'Can this plant be assessed safely?',
        value: _assessable,
        choices: const {true: 'Assess plant', false: 'Cannot assess'},
        onChanged: (value) => setState(() {
          _assessable = value;
          _error = null;
        }),
      ),
      if (_assessable == false)
        TextField(
          key: const Key('vt_not_assessable_reason'),
          controller: _reason,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            border: OutlineInputBorder(),
          ),
        ),
      if (_assessable == true) ...[
        if (widget.evidence case final evidence?)
          EvidenceCapturePanel(
            title: 'Ear-region overview',
            scopeLabel: 'Plant ${widget.position}',
            instruction:
                'Keep the developing ear, ear base, and nearby upper and lower axils visible.',
            viewType: DatabaseCodes.evidenceViewEarRegionOverview,
            bundle: evidence,
            resolveFile: widget.resolveEvidenceFile,
            onCapture: () => widget.onCaptureEvidence(
              DatabaseCodes.evidenceViewEarRegionOverview,
            ),
            onInspect: widget.onInspectEvidence,
            onAccept: widget.onAcceptEvidence,
            onRetake: widget.onRetakeEvidence,
            onRemove: widget.onRemoveEvidence,
            onManualFallback: (reason, note) => widget.onManualFallback(
              DatabaseCodes.evidenceViewEarRegionOverview,
              reason,
              note,
            ),
          ),
        _EvidenceReviewChoice(
          value: _evidenceReview,
          onChanged: (value) => setState(() => _evidenceReview = value),
        ),
        const _StageHeading('Required target zones'),
        _CheckTile(
          key: const Key('vt_tassel_examined'),
          label: 'Tassel examined for fresh feeding',
          value: _tassel,
          onChanged: (value) => setState(() => _tassel = value),
        ),
        _CheckTile(
          key: const Key('vt_ear_base_examined'),
          label: 'Developing ear base examined',
          value: _earBase,
          onChanged: (value) => setState(() => _earBase = value),
        ),
        _CheckTile(
          key: const Key('vt_upper_axil_examined'),
          label: 'Axil immediately above the ear examined',
          value: _upperAxil,
          onChanged: (value) => setState(() => _upperAxil = value),
        ),
        _CheckTile(
          key: const Key('vt_lower_axil_examined'),
          label: 'Axil immediately below the ear examined',
          value: _lowerAxil,
          onChanged: (value) => setState(() => _lowerAxil = value),
        ),
        const _StageHeading('Observed evidence'),
        _YesNoQuestion(
          keyBase: 'vt_fresh_feeding',
          label: 'Fresh feeding present?',
          value: _freshFeeding,
          onChanged: (value) => setState(() => _freshFeeding = value),
        ),
        _YesNoQuestion(
          keyBase: 'vt_frass',
          label: 'Frass present?',
          value: _frass,
          onChanged: (value) => setState(() => _frass = value),
        ),
        _YesNoQuestion(
          keyBase: 'vt_penetration',
          label: 'Ear or husk penetration visible?',
          value: _penetration,
          onChanged: (value) => setState(() => _penetration = value),
        ),
        _YesNoQuestion(
          keyBase: 'vt_larva',
          label: 'Larva visible?',
          value: _larva,
          onChanged: (value) => setState(() {
            _larva = value;
            if (!value) {
              _larvaCount = null;
              _larvalSize = 'none_seen';
            }
          }),
        ),
        if (_larva == true) ...[
          TextFormField(
            key: const Key('vt_larva_count'),
            initialValue: _larvaCount?.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Larva count',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _larvaCount = int.tryParse(value),
          ),
          _LarvalSizeChoice(
            value: _larvalSize,
            onChanged: (value) => setState(() => _larvalSize = value),
          ),
        ],
        _YesNoQuestion(
          keyBase: 'vt_non_faw',
          label: 'Possible non-FAW symptom?',
          value: _possibleNonFaw,
          onChanged: (value) => setState(() => _possibleNonFaw = value),
        ),
        _YesNoQuestion(
          keyBase: 'vt_uncertain',
          label: 'Evidence uncertain?',
          value: _uncertain,
          onChanged: (value) => setState(() => _uncertain = value),
        ),
        _CauseTags(value: _causeTags, onChanged: () => setState(() {})),
        if (_needsCloseUp && widget.evidence != null)
          EvidenceCapturePanel(
            title: 'Target evidence close-up',
            scopeLabel: 'Plant ${widget.position}',
            instruction:
                'Photograph the fresh feeding, frass, larva, penetration, or ambiguous symptom.',
            viewType: DatabaseCodes.evidenceViewEarTargetCloseUp,
            bundle: widget.evidence!,
            resolveFile: widget.resolveEvidenceFile,
            onCapture: () => widget.onCaptureEvidence(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
            ),
            onInspect: widget.onInspectEvidence,
            onAccept: widget.onAcceptEvidence,
            onRetake: widget.onRetakeEvidence,
            onRemove: widget.onRemoveEvidence,
            onManualFallback: (reason, note) => widget.onManualFallback(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
              reason,
              note,
            ),
          ),
        const _StageHeading('Natural-enemy quick observation'),
        _NaturalEnemyChoice(
          value: _naturalEnemy,
          onChanged: (value) => setState(() => _naturalEnemy = value),
        ),
        const _StageHeading('Evaluator classification'),
        _StageChoice<String>(
          value: _classification,
          choices: const {
            DatabaseCodes.reproductiveInfested: 'Currently infested',
            DatabaseCodes.reproductiveNotInfested: 'Not currently infested',
            DatabaseCodes.reproductiveUncertain: 'Uncertain',
          },
          onChanged: (value) => setState(() => _classification = value),
        ),
      ],
      _NotesField(controller: _notes),
    ],
  );

  bool get _needsCloseUp =>
      _freshFeeding == true ||
      _frass == true ||
      _penetration == true ||
      _larva == true ||
      _possibleNonFaw == true ||
      _uncertain == true;

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final assessable = _assessable!;
    await widget.onSave(
      ReproductivePlantSave(
        stationId: widget.stationId,
        plantPosition: widget.position,
        assessable: assessable,
        notAssessableReason: assessable ? null : _reason.text.trim(),
        classification: assessable
            ? _classification!
            : DatabaseCodes.reproductiveNotAssessable,
        tasselExamined: assessable && _tassel,
        earBaseExamined: assessable && _earBase,
        upperAxilExamined: assessable && _upperAxil,
        lowerAxilExamined: assessable && _lowerAxil,
        freshFeedingPresent: assessable && _freshFeeding == true,
        frassPresent: assessable && _frass == true,
        earHuskPenetrationVisible: assessable && _penetration == true,
        larvaPresent: assessable && _larva == true,
        larvaCount: assessable && _larva == true ? _larvaCount : null,
        larvalSize: assessable && _larva == true ? _larvalSize! : 'none_seen',
        possibleNonFawEvidence: assessable ? _possibleNonFaw : null,
        uncertainEvidence: assessable ? _uncertain : null,
        naturalEnemyQuickStatus: assessable
            ? _naturalEnemy!
            : DatabaseCodes.naturalEnemyNotAssessable,
        causeTags: assessable ? _causeTags : const {},
        evaluatorNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        actorPersonId: widget.actorPersonId,
        evidenceCaptureSessionId: widget.evidence?.session.id,
        requiredEvidenceViewTypes: assessable
            ? const {DatabaseCodes.evidenceViewEarRegionOverview}
            : const {},
      ),
      _evidenceReview!,
    );
  }

  String? _validate() {
    if (_assessable == null) return 'Choose whether the plant is assessable.';
    if (_assessable == false) {
      return _reason.text.trim().isEmpty
          ? 'Enter why it cannot be assessed.'
          : null;
    }
    if (!(_tassel && _earBase && _upperAxil && _lowerAxil)) {
      return 'Confirm all four VT–R2 target zones.';
    }
    if (_freshFeeding == null ||
        _frass == null ||
        _penetration == null ||
        _larva == null ||
        _possibleNonFaw == null ||
        _uncertain == null) {
      return 'Complete every VT–R2 evidence question.';
    }
    if (_larva == true && (_larvaCount == null || _larvaCount! < 1)) {
      return 'Enter the visible larva count.';
    }
    if (_larva == true && _larvalSize == null) {
      return 'Select the larval-size group.';
    }
    if (_naturalEnemy == null) return 'Record the natural-enemy quick result.';
    if (_classification == null) return 'Confirm the evaluator classification.';
    if (_evidenceReview != DatabaseCodes.evidenceReviewSufficient) {
      return 'Explicitly confirm that the accepted evidence is sufficient.';
    }
    final positive = _larva == true || _freshFeeding == true;
    if (positive != (_classification == DatabaseCodes.reproductiveInfested)) {
      return 'Currently infested must match visible larva or fresh feeding.';
    }
    if (widget.evidence?.isViewSatisfied(
          DatabaseCodes.evidenceViewEarRegionOverview,
        ) !=
        true) {
      return 'Accept the required ear-region overview or document fallback.';
    }
    if (_needsCloseUp &&
        widget.evidence?.isViewSatisfied(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
            ) !=
            true) {
      return 'Positive or uncertain evidence requires a target close-up or documented fallback.';
    }
    return null;
  }
}

class EarExternalObservationStep extends StatefulWidget {
  const EarExternalObservationStep({
    super.key,
    required this.position,
    required this.blockNumber,
    required this.stationNumber,
    required this.stationId,
    required this.actorPersonId,
    required this.designatedEarRule,
    required this.existing,
    required this.isSaving,
    required this.onSave,
    required this.evidence,
    required this.resolveEvidenceFile,
    required this.onCaptureEvidence,
    required this.onInspectEvidence,
    required this.onAcceptEvidence,
    required this.onRetakeEvidence,
    required this.onRemoveEvidence,
    required this.onManualFallback,
  });

  final int position;
  final int blockNumber;
  final int stationNumber;
  final String stationId;
  final String actorPersonId;
  final String designatedEarRule;
  final StationPlantRecord? existing;
  final bool isSaving;
  final Future<void> Function(
    EarExternalPlantSave input,
    String evidenceReviewStatus,
  )
  onSave;
  final EvidenceCaptureBundle? evidence;
  final Future<File> Function(String localUri) resolveEvidenceFile;
  final CaptureEvidence onCaptureEvidence;
  final InspectEvidence onInspectEvidence;
  final ChangeEvidence onAcceptEvidence;
  final ChangeEvidence onRetakeEvidence;
  final ChangeEvidence onRemoveEvidence;
  final ManualEvidenceFallback onManualFallback;

  @override
  State<EarExternalObservationStep> createState() =>
      _EarExternalObservationStepState();
}

class _EarExternalObservationStepState
    extends State<EarExternalObservationStep> {
  bool? _earPresent;
  bool? _assessable;
  bool _tipExamined = false;
  bool _baseExamined = false;
  bool? _externalDamage;
  bool? _active;
  bool? _silkDamage;
  bool? _huskDamage;
  bool? _entryHole;
  bool? _frass;
  String? _frassFreshness;
  bool? _larva;
  String? _larvalSize;
  String? _feedingFreshness;
  bool? _moldRot;
  String? _classification;
  String? _naturalEnemy;
  String? _evidenceReview;
  final Set<String> _causeTags = {};
  String? _error;
  late final TextEditingController _reason;
  late final TextEditingController _identity;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final ear = existing?.ear;
    _reason = TextEditingController(text: existing?.plant.notAssessableReason);
    _identity = TextEditingController(text: ear?.designatedEarIdentity);
    _notes = TextEditingController(text: existing?.plant.evaluatorNotes);
    if (existing != null && ear != null) {
      _earPresent = ear.earPresent;
      _assessable = ear.externallyAssessable;
      _tipExamined = ear.exteriorEarTipExamined;
      _baseExamined = ear.baseShankSilkAxilsExamined;
      _externalDamage = ear.externalDamagePresent;
      _active = ear.activeInfestationPresent;
      _silkDamage = ear.silkDamagePresent;
      _huskDamage = ear.huskDamagePresent;
      _entryHole = ear.entryHolePresent;
      _frass = ear.frassPresent;
      _frassFreshness = ear.frassFreshness;
      _larva = ear.larvaPresent;
      _larvalSize = ear.larvalSize;
      _feedingFreshness = ear.feedingFreshness;
      _moldRot = ear.moldRotLikeSymptoms;
      _classification = ear.externalClassification;
      _naturalEnemy = existing.plant.naturalEnemyQuickStatus;
      _causeTags.addAll(_decodeTags(ear.causeTagsJson));
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _identity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StageFormScaffold(
    title: 'R3–R6 · Plant ${widget.position} of 10',
    subtitle: 'Block ${widget.blockNumber} · Station ${widget.stationNumber}',
    isSaving: widget.isSaving,
    error: _error,
    onSave: _save,
    children: [
      _ProtocolReminder(
        text:
            'Assess the same ear type throughout: ${widget.designatedEarRule}. Do not substitute another plant when the designated ear is absent.',
      ),
      _StageChoice<bool>(
        label: 'Is the designated ear present?',
        value: _earPresent,
        choices: const {true: 'Ear present', false: 'No designated ear'},
        onChanged: (value) => setState(() {
          _earPresent = value;
          _assessable = value ? null : false;
          if (!value) _reason.text = 'no_designated_ear';
        }),
      ),
      if (_earPresent == true)
        _StageChoice<bool>(
          label: 'Can the designated ear be assessed safely?',
          value: _assessable,
          choices: const {true: 'Assess ear', false: 'Cannot assess'},
          onChanged: (value) => setState(() => _assessable = value),
        ),
      if (_assessable == false)
        TextField(
          key: const Key('ear_not_assessable_reason'),
          controller: _reason,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
      if (_assessable == true) ...[
        TextField(
          key: const Key('designated_ear_identity'),
          controller: _identity,
          decoration: const InputDecoration(
            labelText: 'Designated-ear identity',
            hintText: 'Primary / uppermost marketable ear',
            border: OutlineInputBorder(),
          ),
        ),
        if (widget.evidence case final evidence?)
          EvidenceCapturePanel(
            title: 'Designated-ear overview',
            scopeLabel: 'Plant ${widget.position}',
            instruction:
                'Show the designated ear, silk, shank, ear base, and nearby axils.',
            viewType: DatabaseCodes.evidenceViewEarRegionOverview,
            bundle: evidence,
            resolveFile: widget.resolveEvidenceFile,
            onCapture: () => widget.onCaptureEvidence(
              DatabaseCodes.evidenceViewEarRegionOverview,
            ),
            onInspect: widget.onInspectEvidence,
            onAccept: widget.onAcceptEvidence,
            onRetake: widget.onRetakeEvidence,
            onRemove: widget.onRemoveEvidence,
            onManualFallback: (reason, note) => widget.onManualFallback(
              DatabaseCodes.evidenceViewEarRegionOverview,
              reason,
              note,
            ),
          ),
        _EvidenceReviewChoice(
          value: _evidenceReview,
          onChanged: (value) => setState(() => _evidenceReview = value),
        ),
        const _StageHeading('Required external inspection'),
        _CheckTile(
          key: const Key('ear_tip_examined'),
          label: 'Exterior and ear tip examined',
          value: _tipExamined,
          onChanged: (value) => setState(() => _tipExamined = value),
        ),
        _CheckTile(
          key: const Key('ear_base_examined'),
          label: 'Base, shank, silk, and nearby axils examined',
          value: _baseExamined,
          onChanged: (value) => setState(() => _baseExamined = value),
        ),
        const _StageHeading('External-ear evidence'),
        _YesNoQuestion(
          keyBase: 'ear_external_damage',
          label: 'External damage present?',
          value: _externalDamage,
          onChanged: (value) => setState(() => _externalDamage = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_active',
          label: 'Convincing active infestation?',
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_silk_damage',
          label: 'Silk feeding present?',
          value: _silkDamage,
          onChanged: (value) => setState(() => _silkDamage = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_husk_damage',
          label: 'Husk feeding present?',
          value: _huskDamage,
          onChanged: (value) => setState(() => _huskDamage = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_entry_hole',
          label: 'Entry or exit hole present?',
          value: _entryHole,
          onChanged: (value) => setState(() => _entryHole = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_frass',
          label: 'Frass present?',
          value: _frass,
          onChanged: (value) => setState(() => _frass = value),
        ),
        if (_frass == true)
          _FreshnessChoice(
            label: 'Frass freshness',
            value: _frassFreshness,
            onChanged: (value) => setState(() => _frassFreshness = value),
          ),
        _YesNoQuestion(
          keyBase: 'ear_larva',
          label: 'Live larva present?',
          value: _larva,
          onChanged: (value) => setState(() {
            _larva = value;
            if (!value) _larvalSize = 'none_seen';
          }),
        ),
        if (_larva == true)
          _LarvalSizeChoice(
            value: _larvalSize,
            onChanged: (value) => setState(() => _larvalSize = value),
          ),
        _FreshnessChoice(
          label: 'Feeding freshness',
          value: _feedingFreshness,
          onChanged: (value) => setState(() => _feedingFreshness = value),
        ),
        _YesNoQuestion(
          keyBase: 'ear_mold_rot',
          label: 'Mold or rot-like symptoms?',
          value: _moldRot,
          onChanged: (value) => setState(() => _moldRot = value),
        ),
        _CauseTags(value: _causeTags, onChanged: () => setState(() {})),
        if (_needsCloseUp && widget.evidence != null)
          EvidenceCapturePanel(
            title: 'External-ear evidence close-up',
            scopeLabel: 'Plant ${widget.position}',
            instruction:
                'Photograph the larva, frass, hole, feeding, mold, or ambiguous feature.',
            viewType: DatabaseCodes.evidenceViewEarTargetCloseUp,
            bundle: widget.evidence!,
            resolveFile: widget.resolveEvidenceFile,
            onCapture: () => widget.onCaptureEvidence(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
            ),
            onInspect: widget.onInspectEvidence,
            onAccept: widget.onAcceptEvidence,
            onRetake: widget.onRetakeEvidence,
            onRemove: widget.onRemoveEvidence,
            onManualFallback: (reason, note) => widget.onManualFallback(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
              reason,
              note,
            ),
          ),
        const _StageHeading('Natural-enemy quick observation'),
        _NaturalEnemyChoice(
          value: _naturalEnemy,
          onChanged: (value) => setState(() => _naturalEnemy = value),
        ),
        const _StageHeading('External-ear classification'),
        _StageChoice<String>(
          value: _classification,
          maxColumns: 1,
          choices: const {
            DatabaseCodes.earExternalActive: 'Active ear infestation',
            DatabaseCodes.earExternalDamaged: 'Externally damaged ear',
            DatabaseCodes.earExternalOldDamage: 'Old damage only',
            DatabaseCodes.earExternalOtherPest: 'Possible other pest',
            DatabaseCodes.earExternalNonPest: 'Likely non-pest damage',
            DatabaseCodes.earExternalMoldRot: 'Mold or rot present',
            DatabaseCodes.earExternalNegative: 'No relevant evidence',
            DatabaseCodes.earExternalUncertain: 'Uncertain',
          },
          onChanged: (value) => setState(() => _classification = value),
        ),
      ],
      _NotesField(controller: _notes),
    ],
  );

  bool get _needsCloseUp =>
      _externalDamage == true ||
      _active == true ||
      _frass == true ||
      _larva == true ||
      _entryHole == true ||
      _moldRot == true ||
      _classification == DatabaseCodes.earExternalUncertain;

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final assessable = _assessable == true;
    await widget.onSave(
      EarExternalPlantSave(
        stationId: widget.stationId,
        plantPosition: widget.position,
        earPresent: _earPresent,
        externallyAssessable: assessable,
        designatedEarIdentity: assessable ? _identity.text.trim() : null,
        exteriorEarTipExamined: assessable && _tipExamined,
        baseShankSilkAxilsExamined: assessable && _baseExamined,
        externalDamagePresent: assessable ? _externalDamage : null,
        activeInfestationPresent: assessable ? _active : null,
        silkDamagePresent: assessable ? _silkDamage : null,
        huskDamagePresent: assessable ? _huskDamage : null,
        entryHolePresent: assessable ? _entryHole : null,
        frassPresent: assessable ? _frass : null,
        frassFreshness: assessable && _frass == true ? _frassFreshness : null,
        larvaPresent: assessable ? _larva : null,
        larvalSize: assessable
            ? _larva == true
                  ? _larvalSize
                  : 'none_seen'
            : null,
        feedingFreshness: assessable ? _feedingFreshness : null,
        moldRotLikeSymptoms: assessable ? _moldRot : null,
        causeTags: assessable ? _causeTags : const {},
        externalClassification: assessable
            ? _classification!
            : DatabaseCodes.earExternalNotAssessable,
        naturalEnemyQuickStatus: assessable
            ? _naturalEnemy!
            : DatabaseCodes.naturalEnemyNotAssessable,
        notAssessableReason: assessable ? null : _reason.text.trim(),
        evaluatorNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        actorPersonId: widget.actorPersonId,
        evidenceCaptureSessionId: widget.evidence?.session.id,
        requiredEvidenceViewTypes: assessable
            ? const {DatabaseCodes.evidenceViewEarRegionOverview}
            : const {},
      ),
      _evidenceReview!,
    );
  }

  String? _validate() {
    if (_earPresent == null) return 'Record whether the designated ear exists.';
    if (_assessable == null) return 'Choose whether the ear is assessable.';
    if (_assessable == false) {
      return _reason.text.trim().isEmpty
          ? 'Enter the not-assessable reason.'
          : null;
    }
    if (_identity.text.trim().isEmpty) return 'Identify the designated ear.';
    if (!(_tipExamined && _baseExamined)) {
      return 'Complete both required external-ear target checks.';
    }
    if ([
      _externalDamage,
      _active,
      _silkDamage,
      _huskDamage,
      _entryHole,
      _frass,
      _larva,
      _moldRot,
    ].contains(null)) {
      return 'Complete every external-ear evidence question.';
    }
    if (_frass == true && _frassFreshness == null) {
      return 'Record frass freshness.';
    }
    if (_larva == true && _larvalSize == null) return 'Select larval size.';
    if (_feedingFreshness == null) return 'Record feeding freshness.';
    if (_classification == null) return 'Confirm the external classification.';
    if (_naturalEnemy == null) return 'Record the natural-enemy quick result.';
    if (_evidenceReview != DatabaseCodes.evidenceReviewSufficient) {
      return 'Explicitly confirm that the accepted evidence is sufficient.';
    }
    if (widget.evidence?.isViewSatisfied(
          DatabaseCodes.evidenceViewEarRegionOverview,
        ) !=
        true) {
      return 'Accept the designated-ear overview or document fallback.';
    }
    if (_needsCloseUp &&
        widget.evidence?.isViewSatisfied(
              DatabaseCodes.evidenceViewEarTargetCloseUp,
            ) !=
            true) {
      return 'Positive or uncertain evidence requires a close-up or documented fallback.';
    }
    return null;
  }
}

class _StageFormScaffold extends StatelessWidget {
  const _StageFormScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.isSaving,
    required this.error,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool isSaving;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: const Color(0xFFF3F8F4),
        child: ListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subtitle),
        ),
      ),
      Expanded(
        child: ListView.separated(
          key: const Key('stage_plant_observation_form'),
          padding: const EdgeInsets.all(16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) => children[index],
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
              if (error != null) ...[
                Text(error!, style: const TextStyle(color: Color(0xFF9D241F))),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('save_stage_plant'),
                onPressed: isSaving ? null : onSave,
                child: Text(isSaving ? 'Saving…' : 'Save plant'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ProtocolReminder extends StatelessWidget {
  const _ProtocolReminder({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFEAF6EE),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

class _StageHeading extends StatelessWidget {
  const _StageHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF176B3A),
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  );
}

class _StageChoice<T> extends StatelessWidget {
  const _StageChoice({
    this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.maxColumns = 2,
  });
  final String? label;
  final T? value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null) ...[
        Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in choices.entries)
            ChoiceChip(
              key: Key('choice_${entry.key}'),
              label: Text(entry.value),
              selected: value == entry.key,
              onSelected: (_) => onChanged(entry.key),
            ),
        ],
      ),
    ],
  );
}

class _YesNoQuestion extends StatelessWidget {
  const _YesNoQuestion({
    required this.keyBase,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String keyBase;
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => _StageChoice<bool>(
    label: label,
    value: value,
    choices: const {true: 'Yes', false: 'No'},
    onChanged: onChanged,
  );
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    onChanged: (next) => onChanged(next ?? false),
  );
}

class _LarvalSizeChoice extends StatelessWidget {
  const _LarvalSizeChoice({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => _StageChoice<String>(
    label: 'Larval-size group',
    value: value,
    choices: const {
      'small': 'Small (instars 1–2)',
      'medium': 'Medium (about instar 3)',
      'large': 'Large (instars 4–6)',
      'uncertain': 'Uncertain',
    },
    onChanged: onChanged,
  );
}

class _FreshnessChoice extends StatelessWidget {
  const _FreshnessChoice({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => _StageChoice<String>(
    label: label,
    value: value,
    choices: const {
      DatabaseCodes.evidenceFresh: 'Fresh',
      DatabaseCodes.evidenceOld: 'Old',
      DatabaseCodes.evidenceMixed: 'Mixed',
      DatabaseCodes.evidenceFreshnessUncertain: 'Uncertain',
    },
    onChanged: onChanged,
  );
}

class _NaturalEnemyChoice extends StatelessWidget {
  const _NaturalEnemyChoice({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => _StageChoice<String>(
    value: value,
    choices: const {
      DatabaseCodes.naturalEnemyNoneSeen: 'None observed',
      DatabaseCodes.naturalEnemyObserved: 'Observed',
      DatabaseCodes.naturalEnemyUncertain: 'Uncertain',
      DatabaseCodes.naturalEnemyNotAssessable: 'Not assessable',
    },
    onChanged: onChanged,
  );
}

class _EvidenceReviewChoice extends StatelessWidget {
  const _EvidenceReviewChoice({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => _StageChoice<String>(
    label: 'Evidence review',
    value: value,
    choices: const {
      DatabaseCodes.evidenceReviewSufficient: 'Sufficient to confirm',
      DatabaseCodes.evidenceReviewInsufficient: 'Insufficient—retake needed',
    },
    onChanged: onChanged,
  );
}

class _CauseTags extends StatelessWidget {
  const _CauseTags({required this.value, required this.onChanged});
  final Set<String> value;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Possible cause tags (select every applicable cause)',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in const {
            'faw': 'FAW-consistent',
            'corn_earworm': 'Corn earworm',
            'corn_borer': 'Corn borer',
            'disease': 'Disease',
            'animal': 'Animal',
            'mechanical': 'Mechanical',
            'other': 'Other',
            'uncertain': 'Uncertain',
          }.entries)
            FilterChip(
              label: Text(entry.value),
              selected: value.contains(entry.key),
              onSelected: (selected) {
                selected ? value.add(entry.key) : value.remove(entry.key);
                onChanged();
              },
            ),
        ],
      ),
    ],
  );
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: 3,
    decoration: const InputDecoration(
      labelText: 'Evaluator note (optional)',
      border: OutlineInputBorder(),
    ),
  );
}

Set<String> _decodeTags(String? value) {
  if (value == null || value.isEmpty) return {};
  try {
    final decoded = value.startsWith('[') ? value : '[]';
    return (jsonDecode(decoded) as List<dynamic>).whereType<String>().toSet();
  } catch (_) {
    return {};
  }
}
