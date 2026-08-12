import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/assessment_state.dart';
import '../providers/field_workspace_provider.dart';
import '../providers/wormwise_provider.dart';
import '../theme/app_colors.dart';

class GreetingSection extends StatelessWidget {
  const GreetingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final assessmentState = context.watch<WormWiseProvider>().currentState;
    final fieldName = context
        .watch<FieldWorkspaceProvider>()
        .activeWorkspace
        ?.field
        .name;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    final subtext = fieldName == null
        ? 'Set up a maize field to begin.'
        : assessmentState == AssessmentState.completed
        ? 'The latest assessment for $fieldName is complete.'
        : '$fieldName is your active field.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting!',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtext,
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
