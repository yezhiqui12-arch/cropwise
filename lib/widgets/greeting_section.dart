import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';
import '../data/local/database_codes.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';

class GreetingSection extends StatelessWidget {
  const GreetingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final assessment = context
        .watch<AssessmentWorkspaceProvider>()
        .currentAssessment;
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
        : assessment?.status == DatabaseCodes.completed
        ? 'The latest assessment for {field} is complete.'
        : '{field} is your active field.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          '$greeting!',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          subtext,
          arguments: {'field': fieldName ?? ''},
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
