import 'package:flutter/material.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import '../../providers/scouting_workflow_state.dart';

class ResumeAssessmentStep extends StatefulWidget {
  const ResumeAssessmentStep({
    super.key,
    required this.isSaving,
    required this.onSubmit,
  });

  final bool isSaving;
  final Future<void> Function({
    required ResumeCondition condition,
    required bool safeToContinue,
    String? note,
  })
  onSubmit;

  @override
  State<ResumeAssessmentStep> createState() => _ResumeAssessmentStepState();
}

class _ResumeAssessmentStepState extends State<ResumeAssessmentStep> {
  ResumeCondition? _condition;
  bool? _safeToContinue;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsDecision = _condition == ResumeCondition.rainOrMajorDelay;
    return ListView(
      key: const Key('resume_assessment_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        const AppText(
          'RESUME ASSESSMENT',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        const AppText(
          'Did conditions change?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const AppText(
          'Check before adding observations. Previous answers and timestamps stay saved.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        RadioGroup<ResumeCondition>(
          groupValue: _condition,
          onChanged: (value) => setState(() {
            _condition = value;
            _safeToContinue = null;
          }),
          child: const Column(
            children: [
              RadioListTile(
                value: ResumeCondition.unchanged,
                title: AppText('No important change'),
              ),
              RadioListTile(
                value: ResumeCondition.rainOrMajorDelay,
                title: AppText('Rain, changed weather, or a major delay'),
              ),
              RadioListTile(
                value: ResumeCondition.treatmentOrFieldOperation,
                title: AppText('Treatment or another field operation'),
                subtitle: AppText(
                  'A new field-entry safety check will be required.',
                ),
              ),
            ],
          ),
        ),
        if (needsDecision) ...[
          const SizedBox(height: 12),
          const AppText(
            'Are observations still comparable and safe to continue?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          RadioGroup<bool>(
            groupValue: _safeToContinue,
            onChanged: (value) => setState(() => _safeToContinue = value),
            child: const Column(
              children: [
                RadioListTile(value: true, title: AppText('Yes, continue')),
                RadioListTile(value: false, title: AppText('No, pause here')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: AppWords.of(
              context,
            ).translate('Condition note (optional)'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton(
            key: const Key('submit_resume_check_button'),
            onPressed: _canSubmit && !widget.isSaving ? _submit : null,
            child: widget.isSaving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppText('Continue'),
          ),
        ),
      ],
    );
  }

  bool get _canSubmit =>
      _condition != null &&
      (_condition != ResumeCondition.rainOrMajorDelay ||
          _safeToContinue != null);

  Future<void> _submit() async {
    try {
      await widget.onSubmit(
        condition: _condition!,
        safeToContinue: _safeToContinue ?? true,
        note: _note.text,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }
}
