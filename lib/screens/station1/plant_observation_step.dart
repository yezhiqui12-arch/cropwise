import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../data/repositories/station1_workflow_repository.dart';
import '../../data/services/atomic_plant_save_service.dart';

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
    this.onCancelEdit,
  });

  final int position;
  final int savedCount;
  final String stationId;
  final String actorPersonId;
  final Station1PlantRecord? existing;
  final bool isSaving;
  final Future<void> Function(VegetativePlantSave input) onSave;
  final VoidCallback? onCancelEdit;

  @override
  State<PlantObservationStep> createState() => _PlantObservationStepState();
}

class _PlantObservationStepState extends State<PlantObservationStep> {
  bool? _assessable;
  int? _leavesInspected;
  bool _windowpanes = false;
  bool _scraping = false;
  bool _cutting = false;
  bool _frass = false;
  bool _whorlFeeding = false;
  bool _larvaVisible = false;
  String? _larvalSize;
  String? _eggMassResponse;
  bool _oldDamage = false;
  bool? _possibleNonFaw;
  bool? _uncertain;
  String? _plantStatus;
  String? _validationMessage;
  late final TextEditingController _notAssessableReason;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _notAssessableReason = TextEditingController(
      text: existing?.plant.notAssessableReason,
    );
    _notes = TextEditingController(text: existing?.plant.evaluatorNotes);
    if (existing != null) {
      _assessable = existing.plant.assessable;
      _leavesInspected = existing.vegetative.newestLeavesInspectedCount;
      _windowpanes = existing.vegetative.smallFreshWindowpanes;
      _scraping = existing.vegetative.scraping;
      _cutting = existing.vegetative.cuttingOrTearing;
      _frass = existing.vegetative.freshFrass;
      _whorlFeeding = existing.vegetative.whorlFeedingSign;
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
      // The evaluator must actively reconfirm the primary interpretation.
      _plantStatus = null;
    }
  }

  @override
  void dispose() {
    _notAssessableReason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAssessable = _assessable == true;
    return ListView(
      key: const Key('plant_observation_step'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
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
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Record what you see first. Your primary interpretation is confirmed separately below.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Can this plant be assessed?'),
        RadioGroup<bool>(
          groupValue: _assessable,
          onChanged: (value) => setState(() {
            _assessable = value;
            _plantStatus = null;
            _validationMessage = null;
          }),
          child: const Column(
            children: [
              RadioListTile(value: true, title: Text('Yes, assess this plant')),
              RadioListTile(
                value: false,
                title: Text('No, record why it cannot be assessed'),
              ),
            ],
          ),
        ),
        if (_assessable == false) ...[
          TextField(
            key: const Key('not_assessable_reason_field'),
            controller: _notAssessableReason,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'For example: missing, broken, or unsafe to reach',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (isAssessable) ...[
          const SizedBox(height: 22),
          const _SectionTitle('Newest leaves inspected'),
          const Text(
            'Physically inspect the newest three or four leaves emerging from the whorl.',
            style: TextStyle(height: 1.4),
          ),
          RadioGroup<int>(
            groupValue: _leavesInspected,
            onChanged: (value) => setState(() => _leavesInspected = value),
            child: const Column(
              children: [
                RadioListTile(value: 3, title: Text('3 newest leaves')),
                RadioListTile(value: 4, title: Text('4 newest leaves')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionTitle('Fresh feeding observations'),
          const Text(
            'Select every sign observed. Unselected items are recorded as not seen.',
            style: TextStyle(height: 1.4),
          ),
          _Check(
            key: const Key('fresh_windowpanes_field'),
            label: 'Small fresh windowpanes',
            value: _windowpanes,
            onChanged: (value) => setState(() => _windowpanes = value),
          ),
          _Check(
            key: const Key('fresh_scraping_field'),
            label: 'Fresh scraping',
            value: _scraping,
            onChanged: (value) => setState(() => _scraping = value),
          ),
          _Check(
            key: const Key('fresh_cutting_field'),
            label: 'Fresh cutting or tearing',
            value: _cutting,
            onChanged: (value) => setState(() => _cutting = value),
          ),
          _Check(
            key: const Key('fresh_frass_field'),
            label: 'Fresh frass',
            value: _frass,
            onChanged: (value) => setState(() => _frass = value),
          ),
          _Check(
            key: const Key('whorl_feeding_field'),
            label: 'Whorl-feeding signs',
            value: _whorlFeeding,
            onChanged: (value) => setState(() => _whorlFeeding = value),
          ),
          const SizedBox(height: 14),
          const _SectionTitle('Larva and egg mass'),
          _Check(
            key: const Key('visible_larva_field'),
            label: 'Visible larva',
            value: _larvaVisible,
            onChanged: (value) => setState(() {
              _larvaVisible = value;
              _larvalSize = value ? null : 'none_seen';
            }),
          ),
          if (_larvaVisible)
            DropdownButtonFormField<String>(
              key: const Key('larval_size_field'),
              initialValue: _larvalSize == 'none_seen' ? null : _larvalSize,
              decoration: const InputDecoration(
                labelText: 'Broad larval-size group',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'small', child: Text('Small')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'large', child: Text('Large')),
                DropdownMenuItem(value: 'uncertain', child: Text('Uncertain')),
              ],
              onChanged: (value) => setState(() => _larvalSize = value),
            ),
          const SizedBox(height: 12),
          const Text(
            'Egg mass if visible',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          RadioGroup<String>(
            groupValue: _eggMassResponse,
            onChanged: (value) => setState(() => _eggMassResponse = value),
            child: const Column(
              children: [
                RadioListTile(
                  key: Key('egg_mass_yes'),
                  value: 'yes',
                  title: Text('Yes'),
                ),
                RadioListTile(
                  key: Key('egg_mass_no'),
                  value: 'no',
                  title: Text('No'),
                ),
                RadioListTile(
                  key: Key('egg_mass_not_collected'),
                  value: 'not_collected',
                  title: Text('Not collected'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionTitle('Other or older evidence'),
          _Check(
            key: const Key('old_damage_field'),
            label: 'Old damage only or old damage also present',
            value: _oldDamage,
            onChanged: (value) => setState(() => _oldDamage = value),
          ),
          const SizedBox(height: 10),
          _YesNoQuestion(
            keyBase: 'possible_non_faw',
            title: 'Possible non-FAW evidence present?',
            value: _possibleNonFaw,
            onChanged: (value) => setState(() => _possibleNonFaw = value),
          ),
          _YesNoQuestion(
            keyBase: 'uncertain_evidence',
            title: 'Uncertain evidence present?',
            value: _uncertain,
            onChanged: (value) => setState(() => _uncertain = value),
          ),
          if (_hasMixedEvidence) ...[
            const SizedBox(height: 12),
            const Card(
              key: Key('mixed_evidence_notice'),
              elevation: 0,
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Mixed observations selected. WormWise will preserve every raw answer. Confirm the primary interpretation below; no answer has been selected for you.',
                  style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Evaluator-confirmed primary interpretation'),
          const Text(
            'Choose the single interpretation that best represents this plant. This does not erase mixed or uncertain raw observations.',
            style: TextStyle(height: 1.4),
          ),
          RadioGroup<String>(
            groupValue: _plantStatus,
            onChanged: (value) => setState(() => _plantStatus = value),
            child: const Column(
              children: [
                RadioListTile(
                  value: DatabaseCodes.plantNegative,
                  title: Text('No current FAW-consistent evidence'),
                ),
                RadioListTile(
                  value: DatabaseCodes.plantCurrentPositive,
                  title: Text('Current FAW-consistent evidence'),
                ),
                RadioListTile(
                  value: DatabaseCodes.plantOldDamageOnly,
                  title: Text('Old damage only'),
                ),
                RadioListTile(
                  value: DatabaseCodes.plantPossibleNonFaw,
                  title: Text('Possible non-FAW evidence'),
                ),
                RadioListTile(
                  value: DatabaseCodes.plantUncertain,
                  title: Text('Uncertain interpretation'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Evaluator note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_validationMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _validationMessage!,
            key: const Key('plant_validation_message'),
            style: const TextStyle(
              color: Color(0xFF9D241F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 22),
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
        if (widget.onCancelEdit != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: OutlinedButton(
              onPressed: widget.isSaving ? null : widget.onCancelEdit,
              child: const Text('Cancel edit'),
            ),
          ),
        ],
      ],
    );
  }

  bool get _hasFreshEvidence =>
      _windowpanes || _scraping || _cutting || _frass || _whorlFeeding;

  bool get _hasMixedEvidence =>
      (_hasFreshEvidence &&
          (_possibleNonFaw == true || _uncertain == true || _oldDamage)) ||
      (_possibleNonFaw == true && _uncertain == true);

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _validationMessage = error);
      return;
    }

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
      larvaVisible: assessable && _larvaVisible,
      larvalSize: assessable
          ? (_larvaVisible ? _larvalSize! : 'none_seen')
          : 'none_seen',
      eggMassVisible: assessable
          ? switch (_eggMassResponse) {
              'yes' => true,
              'no' => false,
              _ => null,
            }
          : null,
      oldDamagePresent: assessable && _oldDamage,
      possibleNonFawEvidence: assessable ? _possibleNonFaw : null,
      uncertainEvidence: assessable ? _uncertain : null,
      evaluatorNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      actorPersonId: widget.actorPersonId,
    );

    try {
      await widget.onSave(input);
    } catch (error) {
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
    if (_larvaVisible && _larvalSize == null) {
      return 'Choose the broad size group for the visible larva.';
    }
    if (_eggMassResponse == null) {
      return 'Record egg mass as yes, no, or not collected.';
    }
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      onChanged: (next) => onChanged(next ?? false),
    );
  }
}

class _YesNoQuestion extends StatelessWidget {
  const _YesNoQuestion({
    required this.keyBase,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String keyBase;
  final String title;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          RadioGroup<bool>(
            groupValue: value,
            onChanged: onChanged,
            child: Row(
              children: [
                Expanded(
                  child: RadioListTile(
                    key: Key('${keyBase}_yes'),
                    value: true,
                    title: const Text('Yes'),
                  ),
                ),
                Expanded(
                  child: RadioListTile(
                    key: Key('${keyBase}_no'),
                    value: false,
                    title: const Text('No'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
