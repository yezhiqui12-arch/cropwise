import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/local/database_codes.dart';
import '../providers/assessment_workspace_provider.dart';
import '../services/assessment_protocol_selector.dart';
import '../theme/app_colors.dart';

class AssessmentSessionScreen extends StatelessWidget {
  const AssessmentSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssessmentWorkspaceProvider>();
    final assessment = provider.currentAssessment;
    final fieldName = provider.fieldWorkspace?.field.name ?? 'Selected field';

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment Overview')),
      body: SafeArea(
        child: assessment == null
            ? const Center(child: Text('No unfinished assessment was found.'))
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Icon(
                    assessment.status == DatabaseCodes.inProgress
                        ? Icons.check_circle
                        : Icons.health_and_safety_outlined,
                    size: 68,
                    color: assessment.status == DatabaseCodes.inProgress
                        ? AppColors.primary
                        : const Color(0xFF9A6700),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    assessment.status == DatabaseCodes.inProgress
                        ? 'Assessment saved and started'
                        : 'Field entry needs another safety check',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assessment.status == DatabaseCodes.inProgress
                        ? 'The setup for $fieldName is stored in the offline database.'
                        : 'Do not enter $fieldName until the pesticide waiting period can be verified.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SummaryTile(
                    label: 'FIELD',
                    value: fieldName,
                    icon: Icons.agriculture_outlined,
                  ),
                  _SummaryTile(
                    label: 'GROWTH STAGE',
                    value: AssessmentProtocolSelector.growthStageLabel(
                      assessment.growthStage,
                    ),
                    icon: Icons.eco_outlined,
                  ),
                  _SummaryTile(
                    label: 'SCOUTING ROUTE',
                    value: AssessmentProtocolSelector.patternLabel(
                      assessment.scoutingPattern,
                    ),
                    icon: Icons.route_outlined,
                  ),
                  _SummaryTile(
                    label: 'OFFLINE STATUS',
                    value: assessment.status == DatabaseCodes.inProgress
                        ? 'In progress and saved locally'
                        : 'Safety blocked and saved locally',
                    icon: Icons.offline_pin_outlined,
                  ),
                  const SizedBox(height: 20),
                  if (assessment.status == DatabaseCodes.inProgress)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF90CAF9)),
                      ),
                      child: const Text(
                        'The next implementation will connect this saved assessment to Station 1, station GPS, and the ten-plant observation form. No assessment result has been calculated yet.',
                        style: TextStyle(height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (assessment.status == DatabaseCodes.safetyBlocked)
                    FilledButton.icon(
                      key: const Key('review_assessment_safety_button'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Return to Safety Setup'),
                    )
                  else
                    FilledButton(
                      key: const Key('close_assessment_overview_button'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Return to Home'),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
