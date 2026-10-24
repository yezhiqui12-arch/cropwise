import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';

import '../providers/assessment_workspace_provider.dart';
import '../services/assessment_protocol_selector.dart';
import '../widgets/accessible_choice_field.dart';

class GrowthStageCorrectionScreen extends StatefulWidget {
  const GrowthStageCorrectionScreen({super.key});

  @override
  State<GrowthStageCorrectionScreen> createState() =>
      _GrowthStageCorrectionScreenState();
}

class _GrowthStageCorrectionScreenState
    extends State<GrowthStageCorrectionScreen> {
  String? _stage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stage ??= context
        .read<AssessmentWorkspaceProvider>()
        .currentAssessment
        ?.growthStage;
  }

  Future<void> _save() async {
    final stage = _stage;
    if (stage == null) return;
    try {
      await context.read<AssessmentWorkspaceProvider>().correctGrowthStage(
        stage,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('Growth stage could not be changed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssessmentWorkspaceProvider>();
    return Scaffold(
      appBar: AppBar(title: const AppText('Change Growth Stage')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: FilledButton(
              key: const Key('save_corrected_growth_stage'),
              onPressed: provider.isSaving ? null : _save,
              child: Text(provider.isSaving ? 'Saving…' : 'Save growth stage'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppText(
            'Choose the stage that best matches the maize now.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          AccessibleChoiceField<String>(
            key: const Key('correct_growth_stage_choice'),
            label: 'Growth stage',
            sheetTitle: 'Compare maize growth stages',
            value: _stage,
            leadingIcon: Icons.timeline_outlined,
            showImages: true,
            options: AssessmentProtocolSelector.growthStages
                .map(
                  (option) => AccessibleChoiceOption(
                    value: option.code,
                    label: option.label,
                    description: option.help,
                    assetPath: _stageAsset(option.code),
                    visualGroup: _stageVisualGroup(option.code),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _stage = value),
          ),
          const SizedBox(height: 12),
          const AppText(
            'If that stage is not supported yet, the assessment stays safely saved as a draft.',
          ),
        ],
      ),
    );
  }

  String _stageAsset(String stage) => switch (stage) {
    've' || 'v1' || 'v2' => 'assets/images/growth_stages/maize_emergence.jpg',
    'v3_v6' => 'assets/images/growth_stages/maize_young_vegetative.jpg',
    'v7_v12' => 'assets/images/growth_stages/maize_tall_vegetative.jpg',
    'vt_r2' => 'assets/images/growth_stages/maize_silks.jpg',
    _ => 'assets/images/growth_stages/maize_mature_kernels.jpg',
  };

  String _stageVisualGroup(String stage) => switch (stage) {
    've' || 'v1' || 'v2' => 'early_ve_v2',
    'v3_v6' => 'young_v3_v6',
    'v7_v12' => 'tall_v7_v12',
    'vt_r2' => 'reproductive_vt_r2',
    _ => 'ear_fill_r3_r6',
  };
}
