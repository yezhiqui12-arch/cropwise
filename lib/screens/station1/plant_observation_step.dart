import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../data/services/atomic_plant_save_service.dart';
import 'evidence_capture_panel.dart';

class PlantObservationStep extends StatefulWidget {
  const PlantObservationStep({
    super.key,
    required this.position,
    required this.savedCount,
    required this.stationId,
    required this.actorPersonId,
    required this.existing,
    required this.isSaving,
    required this.onSave,
    this.initialLeavesInspectedCount,
    this.onCancelEdit,
    this.evidence,
    this.resolveEvidenceFile,
    this.onCaptureEvidence,
    this.onInspectEvidence,
    this.onAcceptEvidence,
    this.onRetakeEvidence,
    this.onRemoveEvidence,
    this.onManualFallback,
  });

  final int position;
  final int savedCount;
  final String stationId;
  final String actorPersonId;
  final Station1PlantRecord? existing;
  final bool isSaving;
  final Future<void> Function(VegetativePlantSave input) onSave;
  final int? initialLeavesInspectedCount;
  final VoidCallback? onCancelEdit;
  final EvidenceCaptureBundle? evidence;
  final Future<File> Function(String localUri)? resolveEvidenceFile;
  final Future<void> Function(String viewType)? onCaptureEvidence;
  final Future<void> Function(EvidenceMediaRecord media)? onInspectEvidence;
  final Future<void> Function(EvidenceMediaRecord media)? onAcceptEvidence;
  final Future<void> Function(EvidenceMediaRecord media)? onRetakeEvidence;
  final Future<void> Function(EvidenceMediaRecord media)? onRemoveEvidence;
  final Future<void> Function(String viewType, String reasonCode, String? note)?
  onManualFallback;

  @override
  State<PlantObservationStep> createState() => _PlantObservationStepState();
}

class _PlantObservationStepState extends State<PlantObservationStep>
    with WidgetsBindingObserver {
  bool? _assessable;
  int? _leavesInspected;
  bool _freshSignsAnswered = false;
  bool _noFreshSigns = false;
  bool _windowpanes = false;
  bool _scraping = false;
  bool _cutting = false;
  bool _frass = false;
  bool _whorlFeeding = false;
  bool? _larvaVisible;
  String? _larvalSize;
  String? _eggMassResponse;
  bool? _oldDamage;
  bool? _possibleNonFaw;
  bool? _uncertain;
  String? _plantStatus;
  String? _validationMessage;
  late final TextEditingController _notAssessableReason;
  late final TextEditingController _notes;
  final Stopwatch _activeTimer = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTimer.start();
    final existing = widget.existing;
    _notAssessableReason = TextEditingController(
      text: existing?.plant.notAssessableReason,
    );
    _notes = TextEditingController(text: existing?.plant.evaluatorNotes);
    _leavesInspected = widget.initialLeavesInspectedCount;
    if (existing != null) {
      _assessable = existing.plant.assessable;
      _leavesInspected = existing.vegetative.newestLeavesInspectedCount;
      _windowpanes = existing.vegetative.smallFreshWindowpanes;
      _scraping = existing.vegetative.scraping;
      _cutting = existing.vegetative.cuttingOrTearing;
      _frass = existing.vegetative.freshFrass;
      _whorlFeeding = existing.vegetative.whorlFeedingSign;
      _freshSignsAnswered = true;
      _noFreshSigns = !_hasFreshEvidence;
      _larvaVisible = existing.vegetative.larvaVisible;
      _larvalSize = existing.vegetative.larvalSize;
      _eggMassResponse = switch (existing.vegetative.eggMassVisible) {
        true => 'yes',
        false => 'no',
        null => 'not_collected',
      };
      _oldDamage = existing.plant.oldDamagePresent;
      _possibleNonFaw = existing.plant.possibleNonFawEvidence;
      _uncertain = existing.plant.uncertainEvidence;
      // Edits require a new, unpreselected evaluator interpretation.
      _plantStatus = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _activeTimer.start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _activeTimer.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeTimer.stop();
    _notAssessableReason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAssessable = _assessable == true;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('plant_observation_step'),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              Text(
                'BLOCK 1 · STATION 1 · ${widget.savedCount} OF 10 SAVED',
                style: const TextStyle(
                  color: Color(0xFF176B3A),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.existing == null
                    ? 'Plant ${widget.position} of 10'
                    : 'Edit Plant ${widget.position}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const _ReminderCard(),
              const SizedBox(height: 14),
              const _SectionTitle('Can this plant be assessed?'),
              _CompactChoices<bool>(
                keyBase: 'assessable',
                value: _assessable,
                choices: const {true: 'Assess plant', false: 'Cannot assess'},
                onChanged: (value) => setState(() {
                  _assessable = value;
                  _plantStatus = null;
                  _validationMessage = null;
                }),
              ),
              if (_assessable == false) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('not_assessable_reason_field'),
                  controller: _notAssessableReason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason (required)',
                    hintText: 'Missing, broken, or unsafe to reach',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (isAssessable) ...[
                const SizedBox(height: 18),
                if (widget.evidence != null) ...[
                  EvidenceCapturePanel(
                    title: 'Plant overview',
                    scopeLabel: 'Plant ${widget.position}',
                    instruction:
                        'Expose the whorl and keep the newest leaves in view.',
                    viewType: DatabaseCodes.evidenceViewWhorlOverview,
                    bundle: widget.evidence!,
                    resolveFile: widget.resolveEvidenceFile!,
                    onCapture: () => widget.onCaptureEvidence!(
                      DatabaseCodes.evidenceViewWhorlOverview,
                    ),
                    onInspect: widget.onInspectEvidence!,
                    onAccept: widget.onAcceptEvidence!,
                    onRetake: widget.onRetakeEvidence!,
                    onRemove: widget.onRemoveEvidence!,
                    onManualFallback: (reason, note) =>
                        widget.onManualFallback!(
                          DatabaseCodes.evidenceViewWhorlOverview,
                          reason,
                          note,
                        ),
                  ),
                  const SizedBox(height: 14),
                ],
                const _SectionTitle('Physical inspection'),
                const Text(
                  'Inspect the newest leaves emerging from the whorl.',
                  style: TextStyle(height: 1.35),
                ),
                const SizedBox(height: 8),
                _CompactChoices<int>(
                  keyBase: 'leaves_inspected',
                  value: _leavesInspected,
                  choices: const {3: '3 leaves', 4: '4 leaves'},
                  onChanged: (value) =>
                      setState(() => _leavesInspected = value),
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Fresh feeding signs'),
                const Text(
                  'Select every sign observed, or explicitly select none.',
                  style: TextStyle(height: 1.35),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SignChip(
                      key: const Key('fresh_windowpanes_field'),
                      label: 'Small fresh windowpanes',
                      selected: _windowpanes,
                      onSelected: (value) =>
                          _setFreshSign(_FreshSign.windowpanes, value),
                    ),
                    _SignChip(
                      key: const Key('fresh_scraping_field'),
                      label: 'Fresh scraping',
                      selected: _scraping,
                      onSelected: (value) =>
                          _setFreshSign(_FreshSign.scraping, value),
                    ),
                    _SignChip(
                      key: const Key('fresh_cutting_field'),
                      label: 'Fresh cutting or tearing',
                      selected: _cutting,
                      onSelected: (value) =>
                          _setFreshSign(_FreshSign.cutting, value),
                    ),
                    _SignChip(
                      key: const Key('fresh_frass_field'),
                      label: 'Fresh frass',
                      selected: _frass,
                      onSelected: (value) =>
                          _setFreshSign(_FreshSign.frass, value),
                    ),
                    _SignChip(
                      key: const Key('whorl_feeding_field'),
                      label: 'Whorl-feeding signs',
                      selected: _whorlFeeding,
                      onSelected: (value) =>
                          _setFreshSign(_FreshSign.whorlFeeding, value),
                    ),
                    _SignChip(
                      key: const Key('no_fresh_signs_field'),
                      label: 'No listed fresh feeding signs observed',
                      selected: _noFreshSigns,
                      onSelected: _setNoFreshSigns,
                    ),
                  ],
                ),
                const _ObservationHelp(),
                const SizedBox(height: 14),
                const _SectionTitle('Larva and egg mass'),
                _CompactChoices<bool>(
                  keyBase: 'visible_larva',
                  value: _larvaVisible,
                  choices: const {
                    true: 'Larva visible',
                    false: 'No larva seen',
                  },
                  onChanged: (value) => setState(() {
                    _larvaVisible = value;
                    _larvalSize = value ? null : 'none_seen';
                  }),
                ),
                if (_larvaVisible == true) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('larval_size_field'),
                    initialValue: _larvalSize == 'none_seen'
                        ? null
                        : _larvalSize,
                    decoration: const InputDecoration(
                      labelText: 'Broad larval-size group',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'small', child: Text('Small')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'large', child: Text('Large')),
                      DropdownMenuItem(
                        value: 'uncertain',
                        child: Text('Uncertain'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _larvalSize = value),
                  ),
                ],
                const SizedBox(height: 10),
                _CompactChoices<String>(
                  keyBase: 'egg_mass',
                  label: 'Egg mass if visible',
                  value: _eggMassResponse,
                  choices: const {
                    'yes': 'Yes',
                    'no': 'No',
                    'not_collected': 'Not collected',
                  },
                  onChanged: (value) =>
                      setState(() => _eggMassResponse = value),
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Other evidence'),
                _CompactChoices<bool>(
                  keyBase: 'old_damage',
                  label: 'Old damage present?',
                  value: _oldDamage,
                  choices: const {true: 'Yes', false: 'No'},
                  onChanged: (value) => setState(() => _oldDamage = value),
                ),
                const SizedBox(height: 10),
                _CompactChoices<bool>(
                  keyBase: 'possible_non_faw',
                  label: 'Possible non-FAW evidence?',
                  value: _possibleNonFaw,
                  choices: const {true: 'Yes', false: 'No'},
                  onChanged: (value) => setState(() => _possibleNonFaw = value),
                ),
                const SizedBox(height: 10),
                _CompactChoices<bool>(
                  keyBase: 'uncertain_evidence',
                  label: 'Uncertain evidence?',
                  value: _uncertain,
                  choices: const {true: 'Yes', false: 'No'},
                  onChanged: (value) => setState(() => _uncertain = value),
                ),
                const _InterpretationHelp(),
                if (widget.evidence != null && _needsCloseUp) ...[
                  const SizedBox(height: 14),
                  EvidenceCapturePanel(
                    title: 'Evidence close-up',
                    scopeLabel: 'Plant ${widget.position}',
                    instruction:
                        'Photograph the specific sign or organism that needs detail.',
                    viewType: DatabaseCodes.evidenceViewCloseUp,
                    bundle: widget.evidence!,
                    resolveFile: widget.resolveEvidenceFile!,
                    onCapture: () => widget.onCaptureEvidence!(
                      DatabaseCodes.evidenceViewCloseUp,
                    ),
                    onInspect: widget.onInspectEvidence!,
                    onAccept: widget.onAcceptEvidence!,
                    onRetake: widget.onRetakeEvidence!,
                    onRemove: widget.onRemoveEvidence!,
                    onManualFallback: (reason, note) =>
                        widget.onManualFallback!(
                          DatabaseCodes.evidenceViewCloseUp,
                          reason,
                          note,
                        ),
                  ),
                ],
                if (_hasMixedEvidence) ...[
                  const SizedBox(height: 12),
                  const Card(
                    key: Key('mixed_evidence_notice'),
                    elevation: 0,
                    color: Color(0xFFFFF3CD),
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Mixed evidence selected. Every raw answer will be kept. Confirm the primary interpretation; WormWise has not selected one.',
                        style: TextStyle(
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const _SectionTitle('Primary interpretation'),
                _CompactChoices<String>(
                  keyBase: 'plant_status',
                  value: _plantStatus,
                  choices: const {
                    DatabaseCodes.plantNegative: 'No current FAW evidence',
                    DatabaseCodes.plantCurrentPositive:
                        'Current FAW-consistent evidence',
                    DatabaseCodes.plantOldDamageOnly: 'Old damage only',
                    DatabaseCodes.plantPossibleNonFaw: 'Possible non-FAW',
                    DatabaseCodes.plantUncertain: 'Uncertain',
                  },
                  onChanged: (value) => setState(() => _plantStatus = value),
                ),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                key: const Key('plant_notes_expansion'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Add evaluator note (optional)'),
                children: [
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Evaluator note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_validationMessage != null) ...[
                  Text(
                    _validationMessage!,
                    key: const Key('plant_validation_message'),
                    style: const TextStyle(
                      color: Color(0xFF9D241F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: FilledButton(
                    key: const Key('save_plant_button'),
                    onPressed: widget.isSaving ? null : _save,
                    child: widget.isSaving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.position == 10 && widget.existing == null
                                ? 'Save Plant 10 and review'
                                : 'Save Plant ${widget.position}',
                          ),
                  ),
                ),
                if (widget.onCancelEdit != null)
                  TextButton(
                    onPressed: widget.isSaving ? null : widget.onCancelEdit,
                    child: const Text('Cancel edit'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasFreshEvidence =>
      _windowpanes || _scraping || _cutting || _frass || _whorlFeeding;

  bool get _hasMixedEvidence =>
      (_hasFreshEvidence &&
          (_possibleNonFaw == true ||
              _uncertain == true ||
              _oldDamage == true)) ||
      (_possibleNonFaw == true && _uncertain == true);

  bool get _needsCloseUp =>
      _hasFreshEvidence ||
      _larvaVisible == true ||
      _eggMassResponse == 'yes' ||
      _oldDamage == true ||
      _possibleNonFaw == true ||
      _uncertain == true;

  void _setFreshSign(_FreshSign sign, bool selected) {
    setState(() {
      switch (sign) {
        case _FreshSign.windowpanes:
          _windowpanes = selected;
        case _FreshSign.scraping:
          _scraping = selected;
        case _FreshSign.cutting:
          _cutting = selected;
        case _FreshSign.frass:
          _frass = selected;
        case _FreshSign.whorlFeeding:
          _whorlFeeding = selected;
      }
      if (selected) _noFreshSigns = false;
      _freshSignsAnswered = _hasFreshEvidence || _noFreshSigns;
    });
  }

  void _setNoFreshSigns(bool selected) {
    setState(() {
      _noFreshSigns = selected;
      if (selected) {
        _windowpanes = false;
        _scraping = false;
        _cutting = false;
        _frass = false;
        _whorlFeeding = false;
      }
      _freshSignsAnswered = selected || _hasFreshEvidence;
    });
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _validationMessage = error);
      return;
    }
    _activeTimer.stop();
    final assessable = _assessable!;
    final input = VegetativePlantSave(
      stationId: widget.stationId,
      plantPosition: widget.position,
      plantStatus: assessable
          ? _plantStatus!
          : DatabaseCodes.plantNotAssessable,
      assessable: assessable,
      notAssessableReason: assessable ? null : _notAssessableReason.text.trim(),
      newestLeavesInspectedCount: assessable ? _leavesInspected : null,
      smallFreshWindowpanes: assessable && _windowpanes,
      scraping: assessable && _scraping,
      cuttingOrTearing: assessable && _cutting,
      freshFrass: assessable && _frass,
      whorlFeedingSign: assessable && _whorlFeeding,
      larvaVisible: assessable && _larvaVisible == true,
      larvalSize: assessable
          ? (_larvaVisible == true ? _larvalSize! : 'none_seen')
          : 'none_seen',
      eggMassVisible: assessable
          ? switch (_eggMassResponse) {
              'yes' => true,
              'no' => false,
              _ => null,
            }
          : null,
      oldDamagePresent: assessable && _oldDamage == true,
      possibleNonFawEvidence: assessable ? _possibleNonFaw : null,
      uncertainEvidence: assessable ? _uncertain : null,
      evaluatorNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      actorPersonId: widget.actorPersonId,
      evidenceCaptureSessionId: widget.evidence?.session.id,
      requiredEvidenceViewTypes: assessable && widget.evidence != null
          ? const {
              DatabaseCodes.evidenceViewWhorlOverview,
              DatabaseCodes.evidenceViewCloseUp,
            }
          : const {},
      requireCameraPhaseAEvidence: widget.evidence != null,
      pilotActiveDurationMs: _activeTimer.elapsedMilliseconds,
    );

    try {
      await widget.onSave(input);
    } catch (error) {
      _activeTimer.start();
      if (!mounted) return;
      setState(() {
        _validationMessage =
            'Could not save this plant. Check the answers and try again. ${error.toString().replaceFirst('Bad state: ', '')}';
      });
    }
  }

  String? _validate() {
    if (_assessable == null) return 'Choose whether this plant is assessable.';
    if (_assessable == false) {
      if (_notAssessableReason.text.trim().isEmpty) {
        return 'Enter why this plant cannot be assessed.';
      }
      return null;
    }
    if (_leavesInspected != 3 && _leavesInspected != 4) {
      return 'Confirm inspection of the newest three or four leaves.';
    }
    final evidence = widget.evidence;
    if (evidence != null &&
        !evidence.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview)) {
      return 'Use the whorl/newest-leaves overview or document manual fallback.';
    }
    if (evidence != null &&
        !evidence.isViewSatisfied(DatabaseCodes.evidenceViewCloseUp)) {
      return 'Use the required closer whorl view or document manual fallback.';
    }
    if (!_freshSignsAnswered) {
      return 'Select each fresh feeding sign observed, or explicitly select no listed fresh signs.';
    }
    if (_larvaVisible == null) return 'Record whether a larva is visible.';
    if (_larvaVisible == true && _larvalSize == null) {
      return 'Choose the broad size group for the visible larva.';
    }
    if (_eggMassResponse == null) {
      return 'Record egg mass as yes, no, or not collected.';
    }
    if (_oldDamage == null) return 'Record whether old damage is present.';
    if (_possibleNonFaw == null) {
      return 'Answer whether possible non-FAW evidence is present.';
    }
    if (_uncertain == null) {
      return 'Answer whether uncertain evidence is present.';
    }
    if (_plantStatus == null) {
      return 'Confirm the primary interpretation. WormWise will not select it automatically.';
    }
    return null;
  }
}

enum _FreshSign { windowpanes, scraping, cutting, frass, whorlFeeding }

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      color: Color(0xFFEAF6EE),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Inspect this next consecutive plant: expose the whorl, check the newest 3 or 4 leaves, record what you see, then confirm your interpretation.',
          style: TextStyle(height: 1.35, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

class _SignChip extends StatelessWidget {
  const _SignChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: onSelected,
      showCheckmark: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
  );
}

class _CompactChoices<T> extends StatelessWidget {
  const _CompactChoices({
    required this.keyBase,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.label,
  });

  final String keyBase;
  final String? label;
  final T? value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null) ...[
        Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in choices.entries)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: ChoiceChip(
                key: Key('${keyBase}_${_choiceKey(entry.key)}'),
                selected: value == entry.key,
                label: Text(entry.value),
                onSelected: (_) => onChanged(entry.key),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
        ],
      ),
    ],
  );
}

String _choiceKey(Object? value) => switch (value) {
  true => 'yes',
  false => 'no',
  _ => '$value',
};

class _ObservationHelp extends StatelessWidget {
  const _ObservationHelp();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
    key: Key('fresh_signs_help'),
    tilePadding: EdgeInsets.zero,
    title: Text('What do these signs mean?'),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Use the approved field definitions for fresh windowpanes, scraping, cutting or tearing, frass, and general whorl-feeding signs. Select only what you physically observed; these raw signs do not by themselves prove pest identity.',
          style: TextStyle(height: 1.4),
        ),
      ),
    ],
  );
}

class _InterpretationHelp extends StatelessWidget {
  const _InterpretationHelp();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
    key: Key('other_evidence_help'),
    tilePadding: EdgeInsets.zero,
    title: Text('What does possible non-FAW or uncertain mean?'),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Keep these available when observations could have another cause or cannot be interpreted confidently. WormWise preserves them alongside all other raw observations.',
          style: TextStyle(height: 1.4),
        ),
      ),
    ],
  );
}
