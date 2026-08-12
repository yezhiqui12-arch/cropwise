import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/active_workspace_card.dart';
import '../widgets/greeting_section.dart';
import '../widgets/hero_assessment_card.dart';
import '../widgets/quick_tools_grid.dart';
import '../widgets/weather_conditions_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hasActiveField =
        context.watch<FieldWorkspaceProvider>().activeWorkspace != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Greeting
            const GreetingSection(),
            const SizedBox(height: 16),

            const ActiveWorkspaceCard(),
            const SizedBox(height: 16),

            if (hasActiveField) ...[
              // Hero Assessment Action Card
              const HeroAssessmentCard(),
              const SizedBox(height: 16),
            ],

            // Quick Tools Grid
            const QuickToolsGrid(),
            const SizedBox(height: 16),

            if (hasActiveField) ...[
              // Conditions During Assessment Weather Card
              const WeatherConditionsCard(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
